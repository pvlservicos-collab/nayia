"""A CAPTAÇÃO PELA OLX NO SITE NOVO (Pedro, 28/09/2026).

Pedro: "cola um link da olx e ele importa as fotos e todos os dados da olx
para a gente... vai carregar uma barrinha e colocar todos os dados que ele
conseguiu coletar em um espelho e as fotos, e aguardar o gatilho humano clicar
em cadastrar, mas quero que isso fique pré-cadastrado automaticamente".

POR QUE O ANÚNCIO CHEGA PELO NAVEGADOR. A OLX bloqueia o nosso servidor
(Cloudflare, 403 -- ver nay-publicador/extrair_olx.py). O bloqueio não é
contornado: quem lê o anúncio é o navegador de quem clica no botão "Enviar para
Imob Easy" (um favorito), na própria página da OLX, e ele manda para cá só o
anúncio. As FOTOS o servidor baixa -- o CDN de imagem da OLX não bloqueia.

AS ROTAS (todas atrás da senha do /admin):
  POST /admin/api/olx/importar      grava o PRÉ-CADASTRO: Rascunho, fora do site
                                    e da Nay, origem 'olx'. O mesmo anúncio duas
                                    vezes não vira dois imóveis (extras.olx_id).
  POST /admin/api/olx/<cod>/foto    baixa UMA foto; a tela chama uma a uma, e é
                                    assim que a barrinha anda de verdade
  GET  /admin/api/olx/importados    os pré-cadastros da OLX
  "Cadastrar" é a rota de sempre: PUT /admin/api/imoveis/<cod> {status: Disponível}.

A TRADUÇÃO do dado da OLX ("R$ 0", "5 ou mais", área que é terreno...) é a
`captacao_campos.py` do nay-publicador, copiada como está: foi medida em 217
anúncios em 02/09. Não mexer na cópia -- mexer lá e copiar de novo.
"""
import html
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

import psycopg2
import psycopg2.extras
import psycopg2.sql
from flask import Blueprint, jsonify, request

import captacao_campos as cc
from numeros import numero_br, valor_que_nao_existe
from imoveis_api import _admin_autenticado

olx_bp = Blueprint("olx", __name__)

WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
# A pasta é a /docker/nay-site-web/public/fotos-captacao do servidor: o nginx do
# site serve o que a API grava, e a foto fica pública como as do site antigo --
# a Nay manda foto por URL.
PASTA_FOTOS = os.environ.get("FOTOS_CAPTACAO_DIR", "/fotos")
URL_FOTOS = os.environ.get("FOTOS_CAPTACAO_URL", "https://imobeasy.online/fotos-captacao")
HOSTS_DE_FOTO = {"img.olx.com.br"}
FOTO_MAXIMA = 15 * 1024 * 1024
FOTO_MINIMA = 2_000
# o que o tradutor devolve e vira coluna do imóvel
COLUNAS_DO_TRADUTOR = ("tipo", "bairro", "logradouro", "area_util", "quartos", "suites",
                       "banheiros", "vagas", "vagas_cobertas", "valor_venda", "valor_aluguel",
                       "taxa_condominio", "iptu", "mobilia", "descricao", "caracteristicas")


def _sem_senha():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


def _conectar():
    if not WRITE_DATABASE_URL:
        raise RuntimeError("WRITE_DATABASE_URL não configurada")
    conn = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def _texto_do_anuncio(bruto):
    """A OLX manda a descrição em HTML simples: a quebra de linha vem como <br>
    e o acento pode vir como entidade. Sem isto o texto entrava no cadastro
    com "<br>" no meio (o primeiro importado, em 28/09)."""
    if not bruto:
        return bruto
    texto = re.sub(r"<br\s*/?>", "\n", str(bruto), flags=re.I)
    texto = html.unescape(re.sub(r"<[^>]+>", "", texto))
    texto = re.sub(r"[ \t]+\n", "\n", texto)
    return re.sub(r"\n{3,}", "\n\n", texto).strip()


# A linha que só pedia contato ("Contato para mais informações:", "chama no
# zap") fica sem sentido depois que o telefone sai -- e continua sendo um
# convite a falar direto com o dono.
_LINHA_DE_CONTATO = re.compile(
    r"^[ \t]*(contato|whats\s*app|zap|telefone|fone|celular|ligue|liga|chama)\b[^\n\d]*$", re.I | re.M)

# "Incluso no aluguel" com as MESMAS opções da tela (e do site antigo).
_INCLUSOS = (("Água", r"\b[aá]gua\b"), ("Energia", r"\b(energia|luz)\b"),
             ("Internet", r"\b(internet|wi-?fi)\b"), ("Taxa de Gás", r"\bg[aá]s\b"),
             ("Taxa de Condomínio", r"\bcondom[ií]nio\b"), ("IPTU", r"\biptu\b"))


def _incluso_no_texto(descricao):
    """O que o anúncio diz que o aluguel inclui -- SÓ com cabeçalho explícito
    ("Incluso no valor do aluguel:", "Inclusos no aluguel"), e o bloco é o resto
    dessa linha mais as linhas seguintes até a primeira em branco. "Não incluso"
    não conta. É texto livre: vira aviso para conferir no espelho."""
    linhas = (descricao or "").split("\n")
    for k, linha in enumerate(linhas):
        if (re.search(r"\binclus[oa]s?\b", linha, re.I) and re.search(r"alugu", linha, re.I)
                and not re.search(r"\bn[aã]o\s+(est[aá]\s+)?inclus", linha, re.I)):
            bloco = [linha.split(":", 1)[1] if ":" in linha else linha]
            for seguinte in linhas[k + 1:]:
                if not seguinte.strip():
                    break
                bloco.append(seguinte)
            texto = " ".join(bloco)
            return [nome for nome, padrao in _INCLUSOS if re.search(padrao, texto, re.I)]
    return []


def _lista(bruto):
    """"Piscina, Portaria, Piscina" -> ["Piscina", "Portaria"]"""
    itens = []
    for item in str(bruto or "").split(","):
        item = item.strip()
        if item and item not in itens:
            itens.append(item)
    return itens


def _dados_olx(anuncio, url):
    """O anúncio que o navegador mandou, no mesmo formato do
    extrair_olx.extrair() -- é o que o tradutor sabe ler."""
    anuncio = anuncio if isinstance(anuncio, dict) else {}
    props = {}
    for p in anuncio.get("properties") or []:
        if isinstance(p, dict) and p.get("name"):
            props[str(p["name"])] = p.get("value")
    local = anuncio.get("location") if isinstance(anuncio.get("location"), dict) else {}
    fotos = []
    for u in anuncio.get("images") or []:
        if isinstance(u, str) and u not in fotos:
            fotos.append(u)
    olx_id = str(anuncio.get("listId") or "").strip()
    if not olx_id:
        achado = re.search(r"-(\d{6,})(?:$|[/?#])", url)
        olx_id = achado.group(1) if achado else ""
    return {
        "olx_id": olx_id or None,
        "titulo": anuncio.get("subject"),
        "descricao": _texto_do_anuncio(anuncio.get("body")),
        "preco_texto": anuncio.get("priceValue"),
        "preco_rotulo": anuncio.get("priceLabel"),
        "bairro": local.get("neighbourhood"),
        "municipio": local.get("municipality"),
        "uf": local.get("uf"),
        "logradouro": local.get("address"),
        "cep": local.get("zipcode"),
        "campos": props,
        "fotos": fotos[:60],
    }


def _simples(v):
    if isinstance(v, datetime):
        return v.isoformat()
    try:
        from decimal import Decimal
        if isinstance(v, Decimal):
            return float(v)
    except Exception:  # noqa: BLE001
        pass
    return v


@olx_bp.route("/admin/api/olx/importar", methods=["POST"])
# o mesmo, pelo Cadastro rápido da aba Imóveis (09/10): debaixo de /admin/api/imoveis, que é o
# único caminho do admin que o CRM deixa passar pela aba Imóveis dele
@olx_bp.route("/admin/api/imoveis/olx/importar", methods=["POST"])
def olx_importar():
    if not _admin_autenticado():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    url = str(corpo.get("url") or "").strip()[:500]
    if not re.match(r"^https://([a-z0-9-]+\.)*olx\.com\.br/", url):
        return jsonify({"erro": "o link não é de um anúncio da OLX"}), 400
    d = _dados_olx(corpo.get("anuncio"), url)
    if not d["olx_id"] or not (d["titulo"] or d["descricao"]):
        return jsonify({"erro": "não veio anúncio: abra a página do imóvel na OLX e clique no botão de novo"}), 400
    resposta, status = _importar(d, url)
    return jsonify(resposta), status


def _importar(d, url, ensaio=False):
    """O pré-cadastro (Rascunho) de um anúncio da OLX já lido -- pelo favorito do navegador (olx_importar) ou pela base
    raspada (olx_do_link, 535). Devolve (resposta, status http). `ensaio`: traduz e responde, sem gravar nada."""
    campos = cc.traduzir(d)
    duvidas = cc.duvidas(d, campos)
    # O telefone do dono na descrição sai antes de gravar: no nosso anúncio ele
    # levaria o cliente direto ao proprietário. O aviso de conferir fica.
    if campos.get("descricao"):
        texto = re.sub(r"[ \t]+\n", "\n", cc._TELEFONE.sub("", campos["descricao"]))
        texto = _LINHA_DE_CONTATO.sub("", texto)
        campos["descricao"] = re.sub(r"\n{3,}", "\n\n", texto).strip() or None
        # o aviso do tradutor manda "tirar antes de publicar" -- aqui já saiu
        for duvida in duvidas:
            if duvida.get("campo") == "descricao" and "telefone" in str(duvida.get("aviso")):
                duvida["aviso"] = ("a descrição trazia telefone ou pedido de contato do proprietário -- "
                                   "tirei o que achei; confira se sobrou algum")

    # Os campos do site antigo que o anúncio traz (migração 157): as
    # características do CONDOMÍNIO separadas das do imóvel, como a OLX mostra
    # (a coluna `caracteristicas` continua com as duas, que é onde a Nay
    # procura), e o "incluso no aluguel" quando o texto diz com cabeçalho.
    extras_do_anuncio = {}
    condominio = _lista(d["campos"].get("re_complex_features"))
    if condominio:
        extras_do_anuncio["caracteristicas do condominio"] = ", ".join(condominio)
    incluso = _incluso_no_texto(campos.get("descricao"))
    if incluso:
        extras_do_anuncio["incluso no aluguel"] = ", ".join(incluso)
        duvidas.append({"campo": "incluso no aluguel",
                        "aviso": "o texto diz que o aluguel inclui " + ", ".join(incluso) +
                                 " -- marquei no campo Incluso no aluguel; confira"})

    if ensaio:
        return {"ensaio": True, "titulo": d["titulo"], "url": url, "campos": {k: _simples(v) for k, v in campos.items()},
                "falta": cc.o_que_falta(campos), "duvidas": duvidas, "fotos": d["fotos"]}, 200
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT codigo, status FROM imoveis WHERE origem = 'olx' AND extras->>'olx_id' = %s "
                        "ORDER BY codigo LIMIT 1", (d["olx_id"],))
            ja = cur.fetchone()
            if ja:
                codigo, novo, situacao = ja["codigo"], False, ja["status"]
            else:
                agora = datetime.now()
                extras = {"olx_id": d["olx_id"], "olx_url": url, "olx_titulo": str(d["titulo"] or "")[:300]}
                extras.update(extras_do_anuncio)
                cols = ["origem", "status", "disponivel", "publicado_no_site", "criado_em", "captado_em", "extras"]
                vals = ["olx", "Rascunho", False, False, agora, agora.strftime("%d/%m/%Y"), psycopg2.extras.Json(extras)]
                for c in COLUNAS_DO_TRADUTOR:
                    if campos.get(c) not in (None, "", []):
                        cols.append(c)
                        vals.append(campos[c])
                if d.get("municipio"):
                    cols.append("cidade")
                    vals.append(str(d["municipio"])[:80])
                if d.get("uf"):
                    cols.append("estado")
                    vals.append(str(d["uf"])[:30])
                if d.get("cep"):
                    cols.append("cep")
                    vals.append(str(d["cep"])[:12])
                cur.execute(psycopg2.sql.SQL(
                    "INSERT INTO imoveis (codigo, {}) VALUES (nextval('imoveis_crm_codigo_seq'), {}) RETURNING codigo"
                ).format(psycopg2.sql.SQL(", ").join(psycopg2.sql.Identifier(c) for c in cols),
                         psycopg2.sql.SQL(", ").join(psycopg2.sql.Placeholder() for _ in cols)), vals)
                codigo, novo, situacao = cur.fetchone()["codigo"], True, "Rascunho"
            cur.execute("SELECT count(*) AS n FROM imovel_fotos WHERE codigo = %s", (codigo,))
            fotos_ja = cur.fetchone()["n"]
        conn.commit()
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return {"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}, 500
    finally:
        conn.close()

    return {
        "codigo": codigo, "novo": novo, "situacao": situacao,
        "titulo": d["titulo"], "url": url,
        "campos": {k: _simples(v) for k, v in campos.items()},
        "falta": cc.o_que_falta(campos),
        "duvidas": duvidas,
        # foto só se ainda não tem: reimportar não baixa de novo
        "fotos": d["fotos"] if fotos_ja == 0 else [],
        "fotos_ja": fotos_ja,
    }, 200


# CADASTRAR IMÓVEL PELO LINK, NO CRM (535, Pedro 30/10/2026): "um botão lá em cima do contato, Cadastrar imóvel; se
# eu pegar o link da OLX da pessoa e colar lá, o nosso sistema já puxa todos os dados do imóvel, dá a pontuação ... e o
# sistema já vai baixar as fotos no automático da OLX" e "o ideal é já termos as fotos da OLX sem usar meu PC".
# O servidor NÃO abre a página do anúncio (a OLX responde 403 a ele), mas a base raspada (scrap_anuncio) tem o anúncio
# inteiro -- título, texto, preço, campos e as fotos -- e as fotos o servidor baixa (img.olx.com.br responde a ele).
# Anúncio fora da base: o favorito "Enviar para Imob Easy" no navegador grava pelo olx_importar e o link passa a achar.
_ID_DO_LINK = re.compile(r"(?:-|/)(\d{8,})(?=$|[/?#])")


def _anuncio_da_base(a):
    """Uma linha de scrap_anuncio no formato do anúncio aberto (o que o favorito manda e _dados_olx lê)."""
    dados = a.get("dados") or {}
    campos = dados.get("campos") if isinstance(dados.get("campos"), dict) else {}
    local = str(dados.get("local") or "")
    municipio = local.split(",")[0].strip() if "," in local else (local.strip() or "Manaus")
    return {
        "listId": a["olx_id"], "subject": a.get("titulo"), "body": a.get("descricao"),
        "priceValue": a.get("preco_texto"),
        "properties": [{"name": k, "value": v} for k, v in campos.items()],
        "location": {"neighbourhood": a.get("bairro"), "municipality": municipio, "uf": "AM", "zipcode": a.get("cep")},
        "images": [u for u in (a.get("fotos") or []) if u],
    }


@olx_bp.route("/admin/api/imoveis/olx/do-link", methods=["POST"])
def olx_do_link():
    if not _admin_autenticado():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    url = str(corpo.get("url") or "").strip()[:500]
    if not re.match(r"^https://([a-z0-9-]+\.)*olx\.com\.br/", url):
        return jsonify({"passo": "link", "erro": "esse link não é de um anúncio da OLX (começa com https:// e tem olx.com.br)"}), 400
    achado = _ID_DO_LINK.search(url.split("?")[0].split("#")[0])
    if not achado:
        return jsonify({"passo": "link", "erro": "não achei o número do anúncio no link (o fim do link da OLX tem um número grande)"}), 400
    olx_id = achado.group(1)
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("""SELECT olx_id, titulo, descricao, preco_texto, bairro, cep, fotos, dados, url, coletado_em
                             FROM scrap_anuncio WHERE olx_id = %s
                            ORDER BY (coalesce(descricao, '') <> '') DESC, coletado_em DESC LIMIT 1""", (int(olx_id),))
            # (a lista dos recentes, de 30/10, vem sem a descrição: a de prospecção, quando tem o mesmo anúncio, tem)
            base = cur.fetchone()
            cur.execute("SELECT codigo, status FROM imoveis WHERE extras->>'olx_id' = %s ORDER BY codigo LIMIT 1", (olx_id,))
            ja = cur.fetchone()
    finally:
        conn.close()
    if not base:
        if ja:
            return jsonify({"codigo": ja["codigo"], "novo": False, "situacao": ja["status"], "url": url, "olx_id": olx_id,
                            "fonte": "já cadastrado (sem o anúncio na base raspada)", "fotos": [], "falta": [], "duvidas": []})
        return jsonify({"passo": "anuncio", "olx_id": olx_id,
                        "erro": "esse anúncio não está na nossa base raspada da OLX (ela tem os anúncios das listas raspadas "
                                "até a última coleta). O servidor não consegue abrir a OLX sozinho: abra o anúncio no "
                                "navegador e clique no favorito \"Enviar para Imob Easy\"; depois cole o link aqui de novo."}), 404
    d = _dados_olx(_anuncio_da_base(base), base.get("url") or url)
    resposta, status = _importar(d, base.get("url") or url, ensaio=bool(corpo.get("ensaio")))
    if status == 200:
        resposta["olx_id"] = olx_id
        resposta["fonte"] = "base raspada da OLX, coletado em " + base["coletado_em"].strftime("%d/%m/%Y")
    else:
        resposta["passo"] = "cadastro"
    return jsonify(resposta), status


@olx_bp.route("/admin/api/imoveis/olx/<int:codigo>/estado")
def olx_estado(codigo):
    """O que a barra de cadastro do CRM mostra depois de cada passo: situação, fotos e a pontuação do cadastro (o que
    falta)."""
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("""SELECT i.codigo, i.status, i.disponivel, i.e_parceiro, i.publicado_no_site,
                                  i.extras->>'olx_url' AS olx_url, i.extras->>'parceiro_antigo' AS parceiro_antigo,
                                  (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
                                  p.pct, p.falta
                             FROM imoveis i LEFT JOIN vw_imovel_pontuacao p ON p.codigo = i.codigo
                            WHERE i.codigo = %s""", (codigo,))
            linha = cur.fetchone()
            if not linha:
                return jsonify({"erro": "imóvel não encontrado"}), 404
        conn.rollback()
        # o card de cliente vem de /api/imovel-card/<cod>?cliente=1 (a conexão de leitura; esta não lê a ficha)
        return jsonify({k: _simples(v) for k, v in linha.items()})
    finally:
        conn.close()


def _extensao(conteudo):
    if conteudo[:3] == b"\xff\xd8\xff":
        return "jpg"
    if conteudo[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if conteudo[:4] == b"RIFF" and conteudo[8:12] == b"WEBP":
        return "webp"
    return None


def _baixar(url, host_ok=None, exigir_tipo=True):
    """Só devolve foto de verdade. A OLX responde 404 COM UM JPEG DENTRO (um
    quadrado cinza) -- quem pega isso é o status, e o urllib já levanta erro
    para 404. O resto confere que veio imagem e inteira. `host_ok` diz de onde
    pode vir (padrão: o CDN da OLX); o armazém da Z-API nem sempre diz o tipo,
    e aí quem confere é a assinatura do arquivo."""
    host_ok = host_ok or (lambda h: h in HOSTS_DE_FOTO)
    pedido = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36",
        "Accept": "image/avif,image/webp,image/*,*/*;q=0.8"})
    with urllib.request.urlopen(pedido, timeout=25) as r:
        final = urllib.parse.urlparse(r.geturl())
        if r.status != 200 or final.scheme != "https" or not host_ok(final.hostname or ""):
            raise ValueError(f"resposta {r.status} de {final.hostname}")
        if exigir_tipo and not (r.headers.get_content_type() or "").startswith("image/"):
            raise ValueError("não veio imagem")
        conteudo = r.read(FOTO_MAXIMA + 1)
    if len(conteudo) > FOTO_MAXIMA or len(conteudo) < FOTO_MINIMA:
        raise ValueError(f"tamanho estranho ({len(conteudo)} bytes)")
    extensao = _extensao(conteudo)
    if not extensao:
        raise ValueError("o arquivo não é jpg, png nem webp")
    return conteudo, extensao


@olx_bp.route("/admin/api/olx/<int:codigo>/foto", methods=["POST"])
@olx_bp.route("/admin/api/imoveis/olx/<int:codigo>/foto", methods=["POST"])   # Cadastro rápido (09/10)
def olx_foto(codigo):
    if not _admin_autenticado():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    url = str(corpo.get("url") or "").strip()
    try:
        ordem = int(corpo.get("ordem"))
    except (TypeError, ValueError):
        return jsonify({"erro": "ordem inválida"}), 400
    alvo = urllib.parse.urlparse(url)
    if alvo.scheme != "https" or alvo.hostname not in HOSTS_DE_FOTO or not 1 <= ordem <= 60:
        return jsonify({"erro": "só foto do anúncio da OLX (img.olx.com.br)"}), 400

    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT origem FROM imoveis WHERE codigo = %s", (codigo,))
            linha = cur.fetchone()
            if not linha or linha["origem"] != "olx":
                return jsonify({"erro": "este imóvel não é um pré-cadastro da OLX"}), 404
            cur.execute("SELECT url FROM imovel_fotos WHERE codigo = %s AND ordem = %s", (codigo, ordem))
            ja = cur.fetchone()
            if ja:   # retomada: a foto já veio numa rodada anterior
                return jsonify({"ok": True, "url": ja["url"], "ja": True})
        conn.rollback()   # não segurar transação aberta durante o download
        try:
            conteudo, extensao = _baixar(url)
        except (urllib.error.URLError, ValueError, TimeoutError, OSError) as exc:
            return jsonify({"ok": False, "erro": f"não baixou: {exc}"[:200]}), 502
        pasta = os.path.join(PASTA_FOTOS, "olx", str(codigo))
        os.makedirs(pasta, exist_ok=True)
        nome = f"{ordem:02d}.{extensao}"
        temporario = os.path.join(pasta, nome + ".parcial")
        with open(temporario, "wb") as f:
            f.write(conteudo)
        os.replace(temporario, os.path.join(pasta, nome))   # ou existe inteiro, ou não existe
        publica = f"{URL_FOTOS}/olx/{codigo}/{nome}"
        with conn.cursor() as cur:
            cur.execute("INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (%s, %s, %s, %s)",
                        (codigo, ordem, publica, ordem == 1))
        conn.commit()
        return jsonify({"ok": True, "url": publica})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@olx_bp.route("/admin/api/olx/<int:codigo>/foto", methods=["DELETE"])
def olx_foto_apagar(codigo):
    """Tira uma foto do pré-cadastro antes de ele virar anúncio.

    Pedido do Tel (30/09/2026): "coloca um X na imagem para clicar nele e
    apagar caso não queira que suba essa imagem". A OLX traz foto de planta,
    de fachada repetida e foto ruim; quem separa é o olho de quem cadastra.

    Some a linha E o arquivo: foto que ninguém quis não fica ocupando disco.
    A CAPA NÃO PRECISA SER PROMOVIDA -- `buscar_fotos` ordena por `ordem`, não
    por `e_capa`, então a próxima da fila já vira a primeira sozinha. (E a role
    do site não tem UPDATE em `imovel_fotos`, só INSERT e DELETE.)
    """
    if not _admin_autenticado():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    url = str(corpo.get("url") or "").strip()
    if not url:
        return jsonify({"erro": "sem url"}), 400

    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT origem FROM imoveis WHERE codigo = %s", (codigo,))
            linha = cur.fetchone()
            if not linha or linha["origem"] != "olx":
                return jsonify({"erro": "este imóvel não é um pré-cadastro da OLX"}), 404
            cur.execute("DELETE FROM imovel_fotos WHERE codigo = %s AND url = %s", (codigo, url))
            apagou = cur.rowcount
            cur.execute("SELECT count(*) AS n FROM imovel_fotos WHERE codigo = %s", (codigo,))
            restam = cur.fetchone()["n"]
        conn.commit()

        # O ARQUIVO DEPOIS DO COMMIT, e só o que está dentro da pasta deste
        # imóvel: a url vem do navegador, e caminho vindo de fora nunca escolhe
        # o que apagar. Se falhar, a linha já se foi e a foto não aparece mais.
        prefixo = f"{URL_FOTOS}/olx/{codigo}/"
        if url.startswith(prefixo):
            nome = os.path.basename(url[len(prefixo):])
            caminho = os.path.join(PASTA_FOTOS, "olx", str(codigo), nome)
            pasta = os.path.realpath(os.path.join(PASTA_FOTOS, "olx", str(codigo)))
            if nome and os.path.realpath(caminho).startswith(pasta + os.sep):
                try:
                    os.remove(caminho)
                except OSError:
                    pass   # sem arquivo é o mesmo resultado que o pedido queria

        return jsonify({"ok": True, "apagou": apagou, "restam": restam})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@olx_bp.route("/admin/api/olx/importados")
def olx_importados():
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT i.codigo, i.status, i.tipo, i.bairro, i.quartos, i.area_util,
                       i.valor_aluguel, i.valor_venda, i.criado_em,
                       i.extras->>'olx_titulo' AS titulo, i.extras->>'olx_url' AS olx_url,
                       (i.proprietario_id IS NOT NULL) AS tem_proprietario,
                       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
                       (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo
                         ORDER BY f.e_capa DESC, f.ordem LIMIT 1) AS capa
                  FROM imoveis i
                 WHERE i.origem = 'olx'
                 ORDER BY i.criado_em DESC
                 LIMIT 200""")
            linhas = [{k: _simples(v) for k, v in l.items()} for l in cur.fetchall()]
        return jsonify({"itens": linhas})
    finally:
        conn.close()

# =====================================================================
# O CADASTRO PELA CONVERSA DA CAPTAÇÃO (28/09, migração 164)
#
# Pedro: "precisa pedir as informações certinhas do imóvel para recadastrar
# qualquer coisa, ou se ele mandar um imóvel novo, cadastrar o imóvel novo dele".
# A Nay monta a ficha na conversa (captacao_ficha, no banco); aqui:
#   POST /api/fotos-captacao/whatsapp   o n8n manda a foto que o dono enviou
#                                       (senha de máquina: CAPTACAO_FOTO_SEGREDO)
#   GET  /admin/api/captacao/cadastros  as fichas, para o painel
#   POST /admin/api/captacao/cadastros/<id>/aplicar    imóvel disponível: aplica
#        no catálogo e põe no site e na Nay; imóvel novo: cria o pré-cadastro
#        (Rascunho), ligado ao dono, com as fotos
#   POST /admin/api/captacao/cadastros/<id>/descartar
# =====================================================================
import hmac

CAPTACAO_FOTO_SEGREDO = os.environ.get("CAPTACAO_FOTO_SEGREDO", "")
# os 4 níveis de mobília (344, 11/10): sem nada, só climatizado, com modulados e ar (o antigo semi), mobiliado
_MOBILIA = (("semi", "com modulados e ar"), ("modulad", "com modulados e ar"), ("planejad", "com modulados e ar"),
            ("so ar", "só climatizado"), ("só ar", "só climatizado"), ("climatiz", "só climatizado"))
_INCLUSO_CHIPS = (("Água", r"[aá]gua"), ("Energia", r"energia|\bluz\b"), ("Internet", r"internet|wi-?fi"),
                  ("Taxa de Gás", r"\bg[aá]s\b"), ("Taxa de Condomínio", r"condom[ií]nio"), ("IPTU", r"iptu"))


def _host_do_whatsapp(host):
    """O armazém de mídia da Z-API (Backblaze, e a própria Z-API)."""
    return bool(re.search(r"(^|\.)(backblazeb2\.com|z-api\.io|amazonaws\.com)$", host or ""))


def _mobilia_do_dono(texto):
    t = str(texto or "").lower()
    if not t or re.search(r"\bn[aã]o\b|\bsem\b|nao sabe", t):
        return None
    for chave, valor in _MOBILIA:
        if chave in t:
            return valor
    return "mobiliado" if "mobiliad" in t else None


def _incluso_do_dono(texto):
    t = str(texto or "")
    if not t or re.search(r"^\s*(n[aã]o|nada|nenhum|nao sabe)\b", t, re.I):
        return None
    itens = [nome for nome, padrao in _INCLUSO_CHIPS if re.search(padrao, t, re.I)]
    return ", ".join(itens) or None


def _foto_do_corretor_da_busca(conn, telefone, url, mid):
    """476b: baixa para fotos-captacao/whatsapp-busca/<8 dígitos>/ e registra (a Nay dos corretores põe no pré-cadastro)."""
    try:
        conteudo, extensao = _baixar(url, host_ok=_host_do_whatsapp, exigir_tipo=False)
    except (urllib.error.URLError, ValueError, TimeoutError, OSError) as exc:
        return jsonify({"ok": False, "erro": f"não baixou: {exc}"[:200]}), 502
    pasta_tel = telefone[-8:]
    pasta = os.path.join(PASTA_FOTOS, "whatsapp-busca", pasta_tel)
    os.makedirs(pasta, exist_ok=True)
    nome = re.sub(r"[^A-Za-z0-9_-]", "", mid or datetime.now().strftime("%H%M%S%f"))[:60] + "." + extensao
    temporario = os.path.join(pasta, nome + ".parcial")
    with open(temporario, "wb") as f:
        f.write(conteudo)
    os.replace(temporario, os.path.join(pasta, nome))
    publica = f"{URL_FOTOS}/whatsapp-busca/{pasta_tel}/{nome}"
    with conn.cursor() as cur:
        cur.execute("SELECT busca_corretor_foto_guardar(%s, %s, %s) AS ok", (telefone, publica, mid or nome))
    conn.commit()
    return jsonify({"ok": True, "url": publica, "busca": True})


@olx_bp.route("/api/fotos-captacao/whatsapp", methods=["POST"])
def captacao_foto_whatsapp():
    if not CAPTACAO_FOTO_SEGREDO or not hmac.compare_digest(
            request.headers.get("x-captacao-segredo", ""), CAPTACAO_FOTO_SEGREDO):
        return jsonify({"erro": "sem permissão"}), 401
    corpo = request.get_json(silent=True) or {}
    telefone = re.sub(r"\D", "", str(corpo.get("telefone") or ""))
    url = str(corpo.get("midia_url") or "").strip()
    mid = str(corpo.get("message_id") or "").strip()[:120]
    alvo = urllib.parse.urlparse(url)
    if len(telefone) < 10 or alvo.scheme != "https" or not _host_do_whatsapp(alvo.hostname):
        return jsonify({"ok": False, "erro": "foto de fora"}), 400
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            # só dono que é da campanha; a ficha aberta mais recente -- ou uma nova
            # do imóvel da campanha (ele mandou a foto antes de a ficha abrir)
            cur.execute("SELECT id, codigo FROM captacao_leads WHERE telefone_chave = nay_fone_chave(%s) "
                        "ORDER BY id DESC LIMIT 1", (telefone,))
            lead = cur.fetchone()
            if not lead:
                # 476b (Pedro, 22/10): a foto do CORRETOR que oferece imóvel para uma busca de cliente
                cur.execute("SELECT busca_corretor_e(%s) AS e", (telefone,))
                if (cur.fetchone() or {}).get("e"):
                    conn.commit()
                    return _foto_do_corretor_da_busca(conn, telefone, url, mid)
                return jsonify({"ok": False, "erro": "não é da campanha"}), 200
            # a mesma trava da captacao_ficha (165): foto e resposta juntas não abrem duas fichas
            cur.execute("SELECT pg_advisory_xact_lock(hashtext('captacao_ficha'), %s)", (int(lead["id"]),))
            cur.execute("SELECT id, dados FROM captacao_cadastro WHERE lead_id = %s AND estado IN ('coletando', 'pronto') "
                        "ORDER BY (estado = 'coletando') DESC, atualizado_em DESC LIMIT 1", (lead["id"],))
            ficha = cur.fetchone()
            if not ficha:
                cur.execute("INSERT INTO captacao_cadastro (lead_id, tipo, codigo) VALUES (%s, 'atualizar', %s) RETURNING id, dados",
                            (lead["id"], int(lead["codigo"]) if str(lead["codigo"] or "").isdigit() else None))
                ficha = cur.fetchone()
            if mid and mid in ((ficha["dados"] or {}).get("_fotos_ids") or []):
                conn.commit()
                return jsonify({"ok": True, "ja": True})
        conn.commit()
        try:
            conteudo, extensao = _baixar(url, host_ok=_host_do_whatsapp, exigir_tipo=False)
        except (urllib.error.URLError, ValueError, TimeoutError, OSError) as exc:
            return jsonify({"ok": False, "erro": f"não baixou: {exc}"[:200]}), 502
        pasta = os.path.join(PASTA_FOTOS, "whatsapp", str(ficha["id"]))
        os.makedirs(pasta, exist_ok=True)
        nome = (mid or datetime.now().strftime("%H%M%S%f"))
        nome = re.sub(r"[^A-Za-z0-9_-]", "", nome)[:60] + "." + extensao
        temporario = os.path.join(pasta, nome + ".parcial")
        with open(temporario, "wb") as f:
            f.write(conteudo)
        os.replace(temporario, os.path.join(pasta, nome))
        publica = f"{URL_FOTOS}/whatsapp/{ficha['id']}/{nome}"
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE captacao_cadastro
                   SET fotos = fotos || to_jsonb(%s::text),
                       dados = jsonb_set(dados, '{_fotos_ids}', coalesce(dados->'_fotos_ids', '[]'::jsonb) || to_jsonb(%s::text)),
                       atualizado_em = now()
                 WHERE id = %s""", (publica, mid or nome, ficha["id"]))
        conn.commit()
        return jsonify({"ok": True, "url": publica, "ficha": ficha["id"]})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@olx_bp.route("/admin/api/captacao/cadastros")
def captacao_cadastros():
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT c.id, c.tipo, c.codigo, c.dados, c.fotos, c.estado, c.criado_em, c.atualizado_em,
                       l.id AS lead_id, l.nome, l.tratamento, l.telefone, l.situacao, l.valor_locacao_pedido,
                       l.situacao = 'disponivel' AS disponivel,
                       i.tipo AS imovel_tipo, i.bairro AS imovel_bairro, i.condominio_nome AS imovel_condominio,
                       i.status AS imovel_status, i.valor_aluguel AS imovel_aluguel
                  FROM captacao_cadastro c
                  JOIN captacao_leads l ON l.id = c.lead_id
                  LEFT JOIN imoveis i ON i.codigo = c.codigo
                 WHERE c.estado IN ('coletando', 'pronto')
                 ORDER BY (c.estado = 'pronto') DESC, c.atualizado_em DESC
                 LIMIT 200""")
            itens = [{k: _simples(v) for k, v in l.items()} for l in cur.fetchall()]
        return jsonify({"itens": itens})
    finally:
        conn.close()


@olx_bp.route("/admin/api/captacao/cadastros/<int:fid>/descartar", methods=["POST"])
def captacao_cadastro_descartar(fid):
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE captacao_cadastro SET estado = 'descartado', atualizado_em = now() "
                        "WHERE id = %s AND estado IN ('coletando', 'pronto') RETURNING id", (fid,))
            ok = cur.fetchone() is not None
        conn.commit()
        return jsonify({"ok": ok})
    finally:
        conn.close()


@olx_bp.route("/admin/api/captacao/cadastros/<int:fid>/aplicar", methods=["POST"])
# Cadastro rápido (09/10): "Criar o imóvel com esta ficha", pela aba Imóveis do site e do CRM
@olx_bp.route("/admin/api/imoveis/da-ficha/<int:fid>", methods=["POST"])
def captacao_cadastro_aplicar(fid):
    """Imóvel da campanha DISPONÍVEL: grava no catálogo o que o dono disse e
    põe no site e na Nay (a regra de 27/09: Disponível = no ar), travado contra
    o site antigo. Imóvel NOVO: cria o pré-cadastro (Rascunho), ligado ao dono,
    com as fotos -- o humano confere no editor e escolhe a situação."""
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT c.*, l.proprietario_id, l.valor_locacao_pedido, l.situacao AS lead_situacao "
                        "FROM captacao_cadastro c JOIN captacao_leads l ON l.id = c.lead_id "
                        "WHERE c.id = %s AND c.estado IN ('coletando', 'pronto') FOR UPDATE OF c", (fid,))
            c = cur.fetchone()
            if not c:
                return jsonify({"erro": "ficha não encontrada ou já aplicada"}), 404
            # a foto de um imóvel alugado também abre ficha (o dono mandou antes de
            # dizer a situação); "Aplicar" poria no ar um imóvel que não está vago
            if c["tipo"] == "atualizar" and c["lead_situacao"] != "disponivel":
                return jsonify({"erro": "o dono não disse que o imóvel está disponível -- não dá para pôr no ar"}), 400
            d = c["dados"] or {}
            numeros = {"quartos": d.get("quartos"), "suites": d.get("suites"), "banheiros": d.get("banheiros"),
                       "vagas": d.get("vagas"), "area_util": d.get("area"),
                       "taxa_condominio": d.get("condominio_valor"), "iptu": d.get("iptu")}
            valor = d.get("valor")
            mobilia = _mobilia_do_dono(d.get("mobilia"))
            incluso = _incluso_do_dono(d.get("incluso"))

            if c["tipo"] == "atualizar":
                if not c["codigo"]:
                    return jsonify({"erro": "esta ficha não tem o código do imóvel -- crie como imóvel novo"}), 400
                sets = [psycopg2.sql.SQL("{0} = coalesce(captacao_numero(%s)::{1}, {0})").format(
                            psycopg2.sql.Identifier(col),
                            psycopg2.sql.SQL("int" if col in ("quartos", "suites", "banheiros", "vagas") else "numeric"))
                        for col in numeros]
                valores = list(numeros.values())
                sets.append(psycopg2.sql.SQL("valor_aluguel = coalesce(captacao_numero(%s), valor_aluguel)"))
                valores.append(valor or c.get("valor_locacao_pedido"))
                if mobilia:
                    sets.append(psycopg2.sql.SQL("mobilia = %s"))
                    valores.append(mobilia)
                if incluso:
                    sets.append(psycopg2.sql.SQL("extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('incluso no aluguel', %s::text)"))
                    valores.append(incluso)
                sets.append(psycopg2.sql.SQL(
                    "status = 'Disponível', disponivel = true, publicado_no_site = NOT coalesce(e_parceiro, false), "
                    "travado = true, travado_motivo = %s, travado_em = now()"))
                valores.append("captação: o dono disse disponível (ficha %s)" % fid)
                cur.execute(psycopg2.sql.SQL("UPDATE imoveis SET {} WHERE codigo = %s RETURNING codigo").format(
                    psycopg2.sql.SQL(", ").join(sets)), valores + [c["codigo"]])
                if not cur.fetchone():
                    return jsonify({"erro": "o imóvel %s não está no catálogo" % c["codigo"]}), 404
                codigo = c["codigo"]
            else:
                negocio = str(d.get("negocio") or "").lower()
                vende = "vend" in negocio or "amb" in negocio
                aluga = not ("vend" in negocio and "amb" not in negocio)
                tipo = str(d.get("tipo") or "").strip().capitalize() or None
                cur.execute("""
                    INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, criado_em, captado_em,
                                         tipo, bairro, condominio_nome, quartos, suites, banheiros, vagas, area_util,
                                         taxa_condominio, iptu, valor_aluguel, valor_venda, mobilia, descricao,
                                         proprietario_id, extras)
                    VALUES (nextval('imoveis_crm_codigo_seq'), 'captacao', 'Rascunho', false, false, now(),
                            to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM/YYYY'),
                            %s, %s, %s, captacao_numero(%s)::int, captacao_numero(%s)::int, captacao_numero(%s)::int,
                            captacao_numero(%s)::int, captacao_numero(%s), captacao_numero(%s), captacao_numero(%s),
                            CASE WHEN %s THEN captacao_numero(%s) END, CASE WHEN %s THEN captacao_numero(%s) END,
                            %s, %s, %s, %s::jsonb)
                    RETURNING codigo""",
                    (tipo, d.get("bairro"), d.get("condominio"), numeros["quartos"], numeros["suites"],
                     numeros["banheiros"], numeros["vagas"], numeros["area_util"], numeros["taxa_condominio"],
                     numeros["iptu"], aluga, valor, vende, valor, mobilia,
                     "O dono contou na captação: " + str(d.get("detalhes") or "").strip() if d.get("detalhes") else None,
                     c["proprietario_id"],
                     psycopg2.extras.Json({k: v for k, v in {"incluso no aluguel": incluso,
                                                            "captacao_ficha": str(fid)}.items() if v})))
                codigo = cur.fetchone()["codigo"]
                if c["proprietario_id"]:   # a Nay acha o dono pelo imovel_privado (162)
                    cur.execute("INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (%s, %s) "
                                "ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id",
                                (codigo, c["proprietario_id"]))

            # as fotos que ele mandou, depois das que o imóvel já tinha
            fotos = [f for f in (c["fotos"] or []) if isinstance(f, str)]
            if fotos:
                cur.execute("SELECT coalesce(max(ordem), 0) AS m, count(*) AS n FROM imovel_fotos WHERE codigo = %s", (codigo,))
                base = cur.fetchone()
                for k, url in enumerate(fotos, 1):
                    cur.execute("INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (%s, %s, %s, %s)",
                                (codigo, base["m"] + k, url, base["n"] == 0 and k == 1))
            cur.execute("UPDATE captacao_cadastro SET estado = 'aplicado', codigo = %s, aplicado_em = now(), "
                        "aplicado_por = 'painel', atualizado_em = now() WHERE id = %s", (codigo, fid))
        conn.commit()
        return jsonify({"ok": True, "codigo": codigo, "tipo": c["tipo"], "fotos": len(fotos)})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


# =====================================================================
# O CARD DO PROPRIETÁRIO NO CRM (Pedro, 29/09/2026): "o imóvel do cara já deve
# aparecer lá, e dar opção de atualizar, e embaixo cadastrar imóvel -- o
# sistema já puxa as fotos e informações, o resto nós preenchemos".
#
#   POST /api/captacao/crm/imovel   {captacao_id, codigo?}
#        com codigo: o imóvel DELE recebe o que a ficha da conversa tem, SÓ nos
#        campos vazios; a situação não muda (quem põe no ar é o humano, no
#        editor). sem codigo: pré-cadastro novo (Rascunho 9xxx), ligado ao
#        dono, com a ficha de imóvel novo se houver.
#   POST /api/captacao/crm/imovel/<codigo>/foto   os bytes de UMA foto (o CRM
#        guarda as fotos da conversa e manda uma por vez; X-Foto-Id evita a
#        mesma foto duas vezes).
# Senha de máquina: a mesma CAPTACAO_FOTO_SEGREDO das fotos da captação.
# =====================================================================
URL_ADMIN = os.environ.get("ADMIN_URL", "https://imobeasy.online/admin")


def _maquina_ok():
    return bool(CAPTACAO_FOTO_SEGREDO) and hmac.compare_digest(
        request.headers.get("x-captacao-segredo", ""), CAPTACAO_FOTO_SEGREDO)


def _codigos_do_dono(cur, lead):
    """Os imóveis do dono: o da campanha, os de imoveis_prop e os ligados ao
    proprietario_id (a mesma regra de crm_captacao_imoveis_do_dono, 181)."""
    cods = set()
    if str(lead["codigo"] or "").strip().isdigit():
        cods.add(int(str(lead["codigo"]).strip()))
    for x in lead["imoveis_prop"] if isinstance(lead["imoveis_prop"], list) else []:
        c = str((x or {}).get("codigo") or "").strip()
        if c.isdigit():
            cods.add(int(c))
    if lead["proprietario_id"]:
        cur.execute("SELECT codigo FROM imoveis WHERE proprietario_id = %s "
                    "UNION SELECT codigo FROM imovel_privado WHERE proprietario_id = %s",
                    (lead["proprietario_id"], lead["proprietario_id"]))
        cods.update(int(r["codigo"]) for r in cur.fetchall())
    return cods


# 246 (Pedro, 01/10/2026): "uma opção de alterar os dados do imóvel dele lá pelo
# card, e uma opção de cadastrar novo imóvel que abre um popup... esse popup vai
# ter encima uma porcentagem que vai se preenchendo conforme eu vou adicionando
# informações". O popup manda `dados` com o que a pessoa preencheu olhando os
# valores de hoje -- então aqui o que ela escreveu SUBSTITUI o que estava, ao
# contrário da ficha da conversa (que só preenche campo vazio).
# A situação NÃO entra na lista: quem põe no ar é o humano, no editor.
CAMPOS_DO_POPUP = {
    "tipo": ("tipo", "texto"), "bairro": ("bairro", "texto"),
    "condominio": ("condominio_nome", "texto"), "condoId": ("condo_id", "int"),
    "logradouro": ("logradouro", "texto"), "numero": ("numero", "texto"),
    "complemento": ("complemento", "texto"), "cidade": ("cidade", "texto"),
    "estado": ("estado", "texto"),
    "quartos": ("quartos", "int"), "suites": ("suites", "int"),
    "banheiros": ("banheiros", "int"), "vagas": ("vagas", "int"),
    "vagasCobertas": ("vagas_cobertas", "int"),
    "areaUtil": ("area_util", "numero"), "areaTotal": ("area_total", "numero"),
    "andar": ("andar", "texto"), "sol": ("sol", "texto"), "mobilia": ("mobilia", "texto"),
    "taxaCondominio": ("taxa_condominio", "numero"), "iptu": ("iptu", "numero"),
    "aluguel": ("valor_aluguel", "numero"), "venda": ("valor_venda", "numero"),
    "descricao": ("descricao", "texto"),
    "caracteristicas": ("caracteristicas", "lista"),
}


def _valor_do_popup(bruto, forma):
    """None = "não mexe"; "" (texto vazio) e [] = apagar o que estava."""
    if bruto is None:
        return None, False
    if forma == "lista":
        if not isinstance(bruto, list):
            return None, False
        itens = [str(x).strip() for x in bruto if str(x or "").strip()]
        return itens, True
    if forma in ("int", "numero"):
        t = str(bruto).strip()
        if t == "":
            return None, True            # apaga
        try:
            # 03/10: a leitura é a do numeros.py. Aqui se tirava TODO ponto: certo para "750.000", mas a
            # área 88.5 que o próprio popup mostra virava 885 a cada salvar (o popup manda todos os campos).
            return (int(float(t)) if forma == "int" else numero_br(t)), True
        except (TypeError, ValueError):
            return None, False
    t = str(bruto).strip()
    return (t or None), True


def _aplicar_dados_do_popup(cur, codigo, dados):
    """Grava os campos que o popup mandou. Devolve os nomes que entraram."""
    if not isinstance(dados, dict):
        return []
    sets, valores, entraram = [], [], []
    for chave, (coluna, forma) in CAMPOS_DO_POPUP.items():
        if chave not in dados:
            continue
        valor, vale = _valor_do_popup(dados.get(chave), forma)
        if not vale:
            continue
        # venda de R$ 750 ou aluguel de R$ 90 é dedo que escorregou: o que estava no cadastro fica
        if forma == "numero" and valor_que_nao_existe(coluna, valor):
            continue
        tipo_sql = {"int": "int", "numero": "numeric", "lista": "text[]"}.get(forma, "text")
        sets.append(psycopg2.sql.SQL("{} = %s::" + tipo_sql).format(psycopg2.sql.Identifier(coluna)))
        valores.append(valor)
        entraram.append(coluna)
    incluso = str(dados.get("inclusoNoAluguel") or "").strip()
    if incluso:
        sets.append(psycopg2.sql.SQL(
            "extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('incluso no aluguel', %s::text)"))
        valores.append(incluso)
        entraram.append("incluso no aluguel")
    # Fino acabamento (Pedro, 20/10): Sim / Não; vazio no popup = não mexe (o pendente do Checklist rápido continua)
    fino = str(dados.get("finoAcabamento") or "").strip()
    if fino in ("Sim", "Não"):
        sets.append(psycopg2.sql.SQL(
            "extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('fino acabamento', %s::text)"))
        valores.append(fino)
        entraram.append("fino acabamento")
    if not sets:
        return []
    cur.execute(psycopg2.sql.SQL("UPDATE imoveis SET {} WHERE codigo = %s").format(
        psycopg2.sql.SQL(", ").join(sets)), valores + [codigo])
    # o condomínio escolhido na lista também liga o imóvel ao cadastro dele
    if "condo_id" in entraram:
        cur.execute("UPDATE imoveis SET condominio_nome = coalesce(nullif(btrim(condominio_nome), ''), "
                    "(SELECT nome FROM condominios WHERE id = imoveis.condo_id)) WHERE codigo = %s", (codigo,))
    return entraram


@olx_bp.route("/api/captacao/crm/imovel", methods=["POST"])
def captacao_crm_imovel():
    if not _maquina_ok():
        return jsonify({"erro": "sem permissão"}), 401
    corpo = request.get_json(silent=True) or {}
    try:
        lead_id = int(corpo.get("captacao_id"))
    except (TypeError, ValueError):
        return jsonify({"erro": "captacao_id inválido"}), 400
    codigo = int(corpo["codigo"]) if str(corpo.get("codigo") or "").strip().isdigit() else None
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM captacao_leads WHERE id = %s", (lead_id,))
            lead = cur.fetchone()
            if not lead:
                return jsonify({"erro": "proprietário não encontrado na captação"}), 404
            cur.execute("SELECT id, tipo, codigo, dados FROM captacao_cadastro WHERE lead_id = %s "
                        "AND estado IN ('coletando', 'pronto') ORDER BY (estado = 'pronto') DESC, atualizado_em DESC "
                        "LIMIT 1 FOR UPDATE", (lead_id,))
            ficha = cur.fetchone()
            # a ficha só vale para o imóvel de que ela fala: a de 'atualizar' para
            # o código dela (ou o da campanha), a de 'novo' para o cadastro novo
            if ficha and codigo is not None:
                ficha_serve = ficha["tipo"] == "atualizar" and (ficha["codigo"] or codigo) == codigo
            else:
                ficha_serve = bool(ficha) and ficha["tipo"] != "atualizar"
            d = (ficha["dados"] or {}) if ficha_serve else {}
            numeros = {"quartos": d.get("quartos"), "suites": d.get("suites"), "banheiros": d.get("banheiros"),
                       "vagas": d.get("vagas"), "area_util": d.get("area"),
                       "taxa_condominio": d.get("condominio_valor"), "iptu": d.get("iptu")}
            negocio = str(d.get("negocio") or "").lower()
            vende = "vend" in negocio or "amb" in negocio
            aluga = not ("vend" in negocio and "amb" not in negocio)
            valor = d.get("valor") or (lead["valor_locacao_pedido"] if codigo is not None else None)
            mobilia = _mobilia_do_dono(d.get("mobilia"))
            incluso = _incluso_do_dono(d.get("incluso"))

            if codigo is not None:
                puxado = False
                if codigo not in _codigos_do_dono(cur, lead):
                    # 246: dá para PUXAR um pré-cadastro (Rascunho -- é onde a OLX
                    # deixa o que foi capturado) e ligá-lo a este dono. Imóvel que
                    # já está no ar, de outra pessoa, continua barrado.
                    cur.execute("SELECT status, proprietario_id FROM imoveis WHERE codigo = %s FOR UPDATE", (codigo,))
                    alvo = cur.fetchone()
                    if not alvo:
                        return jsonify({"erro": "o imóvel %s não está no catálogo" % codigo}), 404
                    if (alvo["status"] or "") != "Rascunho" or alvo["proprietario_id"]:
                        return jsonify({"erro": "o imóvel %s não é deste proprietário" % codigo}), 403
                    puxado = True
                sets = [psycopg2.sql.SQL("{0} = coalesce({0}, captacao_numero(%s)::{1})").format(
                            psycopg2.sql.Identifier(col),
                            psycopg2.sql.SQL("int" if col in ("quartos", "suites", "banheiros", "vagas") else "numeric"))
                        for col in numeros]
                valores = list(numeros.values())
                sets.append(psycopg2.sql.SQL("valor_aluguel = coalesce(valor_aluguel, CASE WHEN %s THEN captacao_numero(%s) END)"))
                valores += [aluga, valor]
                sets.append(psycopg2.sql.SQL("valor_venda = coalesce(valor_venda, CASE WHEN %s THEN captacao_numero(%s) END)"))
                valores += [vende, valor]
                sets.append(psycopg2.sql.SQL("mobilia = coalesce(nullif(mobilia, ''), %s)"))
                valores.append(mobilia)
                sets.append(psycopg2.sql.SQL("proprietario_id = coalesce(proprietario_id, %s)"))
                valores.append(lead["proprietario_id"])
                if incluso:
                    sets.append(psycopg2.sql.SQL(
                        "extras = CASE WHEN coalesce(extras, '{}'::jsonb) ? 'incluso no aluguel' THEN extras "
                        "ELSE coalesce(extras, '{}'::jsonb) || jsonb_build_object('incluso no aluguel', %s::text) END"))
                    valores.append(incluso)
                cur.execute(psycopg2.sql.SQL("UPDATE imoveis SET {} WHERE codigo = %s RETURNING codigo").format(
                    psycopg2.sql.SQL(", ").join(sets)), valores + [codigo])
                if not cur.fetchone():
                    return jsonify({"erro": "o imóvel %s não está no catálogo" % codigo}), 404
                final = codigo
                if puxado and lead["proprietario_id"]:
                    cur.execute("INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (%s, %s) "
                                "ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id",
                                (final, lead["proprietario_id"]))
            else:
                tipo = str(d.get("tipo") or "").strip().capitalize() or None
                cur.execute("""
                    INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, criado_em, captado_em,
                                         tipo, bairro, condominio_nome, quartos, suites, banheiros, vagas, area_util,
                                         taxa_condominio, iptu, valor_aluguel, valor_venda, mobilia, descricao,
                                         proprietario_id, extras)
                    VALUES (nextval('imoveis_crm_codigo_seq'), 'captacao', 'Rascunho', false, false, now(),
                            to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM/YYYY'),
                            %s, %s, %s, captacao_numero(%s)::int, captacao_numero(%s)::int, captacao_numero(%s)::int,
                            captacao_numero(%s)::int, captacao_numero(%s), captacao_numero(%s), captacao_numero(%s),
                            CASE WHEN %s THEN captacao_numero(%s) END, CASE WHEN %s THEN captacao_numero(%s) END,
                            %s, %s, %s, %s::jsonb)
                    RETURNING codigo""",
                    (tipo, d.get("bairro"), d.get("condominio"), numeros["quartos"], numeros["suites"],
                     numeros["banheiros"], numeros["vagas"], numeros["area_util"], numeros["taxa_condominio"],
                     numeros["iptu"], aluga, valor, vende, valor, mobilia,
                     "O dono contou na captação: " + str(d.get("detalhes") or "").strip() if d.get("detalhes") else None,
                     lead["proprietario_id"],
                     psycopg2.extras.Json({k: v for k, v in {"incluso no aluguel": incluso,
                                                            "captacao_lead": str(lead_id),
                                                            "captacao_ficha": str(ficha["id"]) if ficha_serve else None,
                                                            "cadastrado_pelo": "crm"}.items() if v})))
                final = cur.fetchone()["codigo"]
                if lead["proprietario_id"]:   # a Nay acha o dono pelo imovel_privado (162)
                    cur.execute("INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (%s, %s) "
                                "ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id",
                                (final, lead["proprietario_id"]))
            # 246: o que a pessoa preencheu no popup entra por cima
            campos = _aplicar_dados_do_popup(cur, final, corpo.get("dados"))
            if ficha_serve:
                cur.execute("UPDATE captacao_cadastro SET estado = 'aplicado', codigo = %s, aplicado_em = now(), "
                            "aplicado_por = 'crm', atualizado_em = now() WHERE id = %s", (final, ficha["id"]))
            cur.execute("SELECT nai_imovel_pontos(%s) AS p", (final,))
            pontos = cur.fetchone()["p"]
        conn.commit()
        return jsonify({"ok": True, "codigo": final, "novo": codigo is None, "usou_ficha": ficha_serve,
                        "campos": campos, "pontuacao": pontos,
                        "editor": "%s/imovel-editar.html?codigo=%s" % (URL_ADMIN, final)})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@olx_bp.route("/api/captacao/crm/imovel/<int:codigo>/foto", methods=["POST"])
def captacao_crm_foto(codigo):
    if not _maquina_ok():
        return jsonify({"erro": "sem permissão"}), 401
    conteudo = request.get_data(cache=False)
    if len(conteudo) > FOTO_MAXIMA or len(conteudo) < FOTO_MINIMA:
        return jsonify({"ok": False, "erro": "tamanho estranho (%s bytes)" % len(conteudo)}), 400
    extensao = _extensao(conteudo)
    if not extensao:
        return jsonify({"ok": False, "erro": "o arquivo não é jpg, png nem webp"}), 400
    chave = re.sub(r"[^A-Za-z0-9_-]", "", request.headers.get("x-foto-id", ""))[:60] \
        or datetime.now().strftime("%Y%m%d%H%M%S%f")
    nome = chave + "." + extensao
    publica = f"{URL_FOTOS}/crm/{codigo}/{nome}"
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM imoveis WHERE codigo = %s", (codigo,))
            if not cur.fetchone():
                return jsonify({"ok": False, "erro": "imóvel não encontrado"}), 404
            cur.execute("SELECT url FROM imovel_fotos WHERE codigo = %s AND url = %s", (codigo, publica))
            if cur.fetchone():
                return jsonify({"ok": True, "url": publica, "ja": True})
        conn.rollback()   # não segurar transação durante a gravação do arquivo
        pasta = os.path.join(PASTA_FOTOS, "crm", str(codigo))
        os.makedirs(pasta, exist_ok=True)
        temporario = os.path.join(pasta, nome + ".parcial")
        with open(temporario, "wb") as f:
            f.write(conteudo)
        os.replace(temporario, os.path.join(pasta, nome))
        with conn.cursor() as cur:
            cur.execute("SELECT pg_advisory_xact_lock(hashtext('imovel_fotos'), %s)", (codigo,))
            cur.execute("SELECT coalesce(max(ordem), 0) AS m, count(*) AS n FROM imovel_fotos WHERE codigo = %s", (codigo,))
            base = cur.fetchone()
            cur.execute("INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (%s, %s, %s, %s)",
                        (codigo, base["m"] + 1, publica, base["n"] == 0))
        conn.commit()
        return jsonify({"ok": True, "url": publica})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


# =====================================================================
# IMÓVEIS DA OLX BOT (02/10/2026, migração 260)
#
# Pedro: "o grok vai enviar nome de corretor, número dele, link do imóvel, dados
# do imóvel completo para nosso cadastro, e esses imóveis vão vir para uma nova
# aba no site... ao lado de Captação OLX, Imóveis da OLX Bot... para aprovação
# manual humana".
#
# O bot entrega pelo CRM (/api/public/imovel-cadastro) e o envio fica em
# privado.olx_bot_imovel. Aqui é o lado de quem aprova, com a senha do painel:
#   GET  /admin/api/olx-bot                   os envios (pendentes na frente)
#   POST /admin/api/olx-bot/<id>/aprovar      vira PRÉ-CADASTRO: Rascunho, fora
#        do site e da Nay, com origem 'olx' -- cai na lista "Pré-cadastrados da
#        OLX", onde já existem o espelho, o dono e o botão Cadastrar. Aprovar
#        não publica nada: quem publica continua sendo o Cadastrar.
#   POST /admin/api/olx-bot/<id>/descartar    com o motivo, que o bot recebe se
#        mandar o mesmo anúncio de novo
#
# As fotos e o proprietário quem grava é a própria tela, depois do aprovar,
# pelas rotas que a Captação OLX já usa (api/olx/<cod>/foto e PUT api/imoveis).
# =====================================================================
_TIPO_DA_FAMILIA = {"apartamento": "Apartamento", "casa": "Casa", "terreno": "Lote", "comercial": "Sala/Andar"}


def _numero_do_bot(v):
    """990000, "990000", "R$ 990.000,00" e "2.500" viram número; o resto, None."""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    t = re.sub(r"[^0-9.,]", "", str(v))
    if not t:
        return None
    if re.fullmatch(r"\d+(\.\d{1,2})?", t):
        return float(t)
    if re.fullmatch(r"(\d{1,3}(\.\d{3})+|\d+)(,\d{1,2})?", t):
        return float(t.replace(".", "").replace(",", "."))
    return None


def _inteiro_do_bot(v):
    n = _numero_do_bot(v)
    return int(n) if n is not None and 0 <= n < 1000 else None


def _lista_do_bot(v):
    if isinstance(v, str):
        v = re.split(r"[,;\n]", v)
    if not isinstance(v, list):
        return []
    vistos, saida = set(), []
    for item in v:
        t = str(item or "").strip()[:80]
        if t and t.lower() not in vistos:
            vistos.add(t.lower())
            saida.append(t)
    return saida[:60]


def _texto_do_bot(v, limite):
    t = str(v or "").strip()
    return t[:limite] or None


def _colunas_do_bot(cur, d):
    """Os dados que o bot mandou, nas colunas do catálogo. Só o que veio."""
    col = {}
    familia = None
    tipo = _texto_do_bot(d.get("tipo"), 60)
    if tipo:
        cur.execute("SELECT tipo FROM imoveis WHERE nay_sem_acento(lower(tipo)) = nay_sem_acento(lower(%s)) LIMIT 1", (tipo,))
        achado = cur.fetchone()
        if achado:
            col["tipo"] = achado["tipo"]
        else:
            cur.execute("SELECT crm_anuncio_familia(%s) AS f", (tipo,))
            familia = cur.fetchone()["f"]
    condominio = _texto_do_bot(d.get("condominio_nome"), 120)
    if familia:
        col["tipo"] = _TIPO_DA_FAMILIA[familia]
        if condominio and familia == "casa":
            col["tipo"] = "Casa de condomínio"
        if condominio and familia == "terreno":
            col["tipo"] = "Lote em Condomínio"
    if condominio:
        col["condominio_nome"] = condominio
        cur.execute("SELECT id, nome FROM condominios WHERE nay_sem_acento(lower(nome)) = nay_sem_acento(lower(%s)) LIMIT 2",
                    (condominio,))
        iguais = cur.fetchall()
        if len(iguais) == 1:
            col["condo_id"], col["condominio_nome"] = iguais[0]["id"], iguais[0]["nome"]
    bairro = _texto_do_bot(d.get("bairro"), 80)
    if bairro:
        # o nome do bairro como o catálogo escreve ("ponta negra" -> "Ponta Negra").
        # Pelos imóveis e só tirando acento: o papel do site não lê a bairro_normal
        # nem a bairro_area (que a nay_normalizar_lugar consulta) -- no ensaio a
        # aprovação parava aqui com "permission denied for table bairro_area".
        cur.execute("SELECT bairro FROM imoveis WHERE coalesce(bairro, '') <> '' "
                    "AND nay_sem_acento(lower(btrim(bairro))) = nay_sem_acento(lower(btrim(%s))) "
                    "GROUP BY bairro ORDER BY count(*) DESC LIMIT 1", (bairro,))
        achado = cur.fetchone()
        col["bairro"] = achado["bairro"] if achado else bairro
    for chave, coluna, limite in (("endereco", "logradouro", 160), ("numero", "numero", 20), ("complemento", "complemento", 80),
                                  ("cep", "cep", 12), ("cidade", "cidade", 80), ("uf", "estado", 30), ("andar", "andar", 20)):
        t = _texto_do_bot(d.get(chave), limite)
        if t:
            col[coluna] = t
    for chave, coluna in (("area_m2", "area_util"), ("area_total_m2", "area_total"),
                          ("valor_condominio", "taxa_condominio"), ("iptu", "iptu")):
        n = _numero_do_bot(d.get(chave))
        if n is not None and n > 0:
            col[coluna] = n
    for chave in ("quartos", "suites", "banheiros", "vagas"):
        n = _inteiro_do_bot(d.get(chave))
        if n is not None:
            col[chave] = n
    # o preço: os dois campos próprios mandam; "preco" sozinho vai pela finalidade
    venda, aluguel = _numero_do_bot(d.get("preco_venda")), _numero_do_bot(d.get("preco_aluguel"))
    preco = _numero_do_bot(d.get("preco"))
    finalidade = str(d.get("finalidade") or "").lower()
    if preco and not venda and not aluguel:
        if "alug" in finalidade or "loca" in finalidade:
            aluguel = preco
        elif "vend" in finalidade or "compra" in finalidade:
            venda = preco
        elif preco < 30000:      # sem finalidade: até 30 mil é aluguel, acima é venda
            aluguel = preco
        else:
            venda = preco
    if venda and venda > 0:
        col["valor_venda"] = venda
    if aluguel and aluguel > 0:
        col["valor_aluguel"] = aluguel
    mobilia = str(d.get("mobilia") or "").lower()
    if "semi" in mobilia or "modulad" in mobilia:
        col["mobilia"] = "com modulados e ar"
    elif mobilia.startswith("mobiliad"):
        col["mobilia"] = "mobiliado"
    elif "climatiz" in mobilia or "ar-cond" in mobilia or "ar cond" in mobilia:
        col["mobilia"] = "só climatizado"
    # "sem mobília" é o campo vazio, como no resto do catálogo
    do_condominio = _lista_do_bot(d.get("caracteristicas_condominio"))
    todas = _lista_do_bot(d.get("caracteristicas"))
    ja_tem = {x.lower() for x in todas}
    for c in do_condominio:
        if c.lower() not in ja_tem:
            todas.append(c)
    if todas:
        col["caracteristicas"] = todas
    descricao = _texto_do_bot(d.get("descricao"), 6000)
    if descricao:
        # o telefone do dono sai da descrição, como na Captação OLX: no nosso
        # anúncio ele levaria o cliente direto ao proprietário
        texto = re.sub(r"[ \t]+\n", "\n", cc._TELEFONE.sub("", descricao))
        texto = _LINHA_DE_CONTATO.sub("", texto)
        texto = re.sub(r"\n{3,}", "\n\n", texto).strip()
        if texto:
            col["descricao"] = texto
    return col, do_condominio


def _envio_do_bot(l):
    d = {k: _simples(v) for k, v in l.items()}
    cand = (d.get("candidatos") or {}).get("candidatos") or []
    d["candidatos"] = [{"id_imovel": c.get("id_imovel"), "score": c.get("score"), "confianca": c.get("confianca"),
                        "bateu": c.get("campos_que_bateram"), "status": (c.get("dados") or {}).get("status"),
                        "titulo": (c.get("dados") or {}).get("titulo")} for c in cand[:3]]
    return d


@olx_bp.route("/admin/api/olx-bot")
def olx_bot_lista():
    if not _admin_autenticado():
        return _sem_senha()
    estado = str(request.args.get("estado") or "pendente")
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT estado, count(*) AS n FROM privado.olx_bot_imovel GROUP BY 1")
            contagem = {l["estado"]: l["n"] for l in cur.fetchall()}
            cur.execute("""
                SELECT id, estado, link, portal, id_anuncio, corretor_nome, corretor_telefone,
                       proprietario_nome, proprietario_telefone, autorizacao_como, dados, fotos,
                       candidatos, envios, recebido_em, atualizado_em, codigo, decidido_por, decidido_em, motivo
                  FROM privado.olx_bot_imovel
                 WHERE %s = 'todos' OR estado = %s
                 ORDER BY (estado = 'pendente') DESC, coalesce(decidido_em, recebido_em) DESC
                 LIMIT 200""", (estado, estado))
            itens = [_envio_do_bot(l) for l in cur.fetchall()]
        return jsonify({"itens": itens, "contagem": contagem})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@olx_bp.route("/admin/api/olx-bot/<int:eid>/aprovar", methods=["POST"])
@olx_bp.route("/admin/api/imoveis/olx-bot/<int:eid>/aprovar", methods=["POST"])   # Aprovar imóveis (419): o CRM só deixa passar /admin/api/imoveis/*
def olx_bot_aprovar(eid):
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM privado.olx_bot_imovel WHERE id = %s FOR UPDATE", (eid,))
            e = cur.fetchone()
            if not e:
                return jsonify({"erro": "envio não encontrado"}), 404
            if e["estado"] != "pendente":
                return jsonify({"erro": "este envio já foi %s" % e["estado"], "codigo": e["codigo"]}), 409
            d = e["dados"] or {}
            # o mesmo anúncio já importado à mão pela Captação OLX: não vira dois imóveis
            ja = None
            if e["id_anuncio"]:
                cur.execute("SELECT codigo FROM imoveis WHERE origem = 'olx' AND extras->>'olx_id' = %s ORDER BY codigo LIMIT 1",
                            (e["id_anuncio"],))
                ja = cur.fetchone()
            if ja:
                codigo, novo = ja["codigo"], False
            else:
                col, do_condominio = _colunas_do_bot(cur, d)
                agora = datetime.now()
                extras = {"olx_id": e["id_anuncio"], "olx_url": e["link"],
                          "olx_titulo": str(d.get("titulo") or "")[:300] or None,
                          "cadastrado_pelo": "grokbot", "olx_bot_envio": str(eid),
                          "captado por": e["corretor_nome"],
                          "caracteristicas do condominio": ", ".join(do_condominio) or None,
                          "observacoes do bot": _texto_do_bot(d.get("observacoes"), 1000)}
                extras = {k: v for k, v in extras.items() if v}
                cols = ["origem", "status", "disponivel", "publicado_no_site", "criado_em", "captado_em", "extras"]
                vals = ["olx", "Rascunho", False, False, agora, agora.strftime("%d/%m/%Y"), psycopg2.extras.Json(extras)]
                for c, v in col.items():
                    cols.append(c)
                    vals.append(v)
                cur.execute(psycopg2.sql.SQL(
                    "INSERT INTO imoveis (codigo, {}) VALUES (nextval('imoveis_crm_codigo_seq'), {}) RETURNING codigo"
                ).format(psycopg2.sql.SQL(", ").join(psycopg2.sql.Identifier(c) for c in cols),
                         psycopg2.sql.SQL(", ").join(psycopg2.sql.Placeholder() for _ in cols)), vals)
                codigo, novo = cur.fetchone()["codigo"], True
            # a próxima consulta do bot por este anúncio bate por link (258)
            cur.execute("INSERT INTO imovel_anuncio (codigo, portal, id_anuncio, link, link_normal, registrado_por) "
                        "SELECT %s, %s, %s, %s, crm_anuncio_link_normal(%s), 'painel (OLX Bot)' "
                        "WHERE NOT EXISTS (SELECT 1 FROM imovel_anuncio WHERE link_normal = crm_anuncio_link_normal(%s))",
                        (codigo, e["portal"] or "olx", e["id_anuncio"], e["link"], e["link"], e["link"]))
            cur.execute("UPDATE privado.olx_bot_imovel SET estado = 'aprovado', codigo = %s, decidido_por = 'painel', "
                        "decidido_em = now(), atualizado_em = now() WHERE id = %s", (codigo, eid))
            cur.execute("SELECT count(*) AS n FROM imovel_fotos WHERE codigo = %s", (codigo,))
            fotos_ja = cur.fetchone()["n"]
        conn.commit()
        return jsonify({"ok": True, "codigo": codigo, "novo": novo,
                        "fotos": list(e["fotos"] or []) if fotos_ja == 0 else [],
                        "proprietario": {"nome": e["proprietario_nome"], "telefone": e["proprietario_telefone"]},
                        "editor": "%s/imovel-editar.html?codigo=%s" % (URL_ADMIN, codigo)})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@olx_bp.route("/admin/api/olx-bot/<int:eid>/descartar", methods=["POST"])
def olx_bot_descartar(eid):
    if not _admin_autenticado():
        return _sem_senha()
    motivo = str((request.get_json(silent=True) or {}).get("motivo") or "").strip()[:300] or None
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE privado.olx_bot_imovel SET estado = 'descartado', motivo = %s, decidido_por = 'painel', "
                        "decidido_em = now(), atualizado_em = now() WHERE id = %s AND estado = 'pendente' RETURNING id",
                        (motivo, eid))
            if not cur.fetchone():
                conn.rollback()
                return jsonify({"erro": "envio não encontrado ou já decidido"}), 409
        conn.commit()
        return jsonify({"ok": True})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


# ── ANUNCIAR NA OLX pelo editar imóvel (Pedro, 16/10/2026: "cria um botão lá nos imóveis em editar imóveis, anunciar
# na OLX, ele cria um popup de anúncio manualmente"; migração 396). O popup lê o anúncio que o sistema monta, a pessoa
# mexe no título, descrição, preço, CEP e fotos, e pede; o serviço nay-olx publica pela API da OLX em segundos e o popup
# acompanha o pedido. Atrás da senha do painel.
def _quem_pediu():
    a = request.authorization
    return (a.username if a and a.username else "painel")[:80]


@olx_bp.route("/admin/api/imoveis/<int:codigo>/olx", methods=["GET"])
def olx_anuncio_rascunho(codigo):
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT site_olx_anuncio_rascunho(%s) AS r", (codigo,))
            return jsonify((cur.fetchone() or {}).get("r") or {})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@olx_bp.route("/admin/api/imoveis/<int:codigo>/olx", methods=["POST"])
def olx_anuncio_pedir(codigo):
    if not _admin_autenticado():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    negocio = str(corpo.get("negocio") or "")
    campos = {k: corpo.get(k) for k in ("subject", "body", "price", "zipcode", "images") if corpo.get(k) is not None}
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT site_olx_anuncio_pedir(%s, %s, %s::jsonb, %s) AS id",
                        (codigo, negocio, psycopg2.extras.Json(campos), _quem_pediu()))
            pid = (cur.fetchone() or {}).get("id")
        conn.commit()
        return jsonify({"ok": True, "pedido": pid})
    except psycopg2.Error as exc:
        conn.rollback()
        msg = (getattr(exc.diag, "message_primary", None) or str(exc)).strip()
        return jsonify({"ok": False, "erro": msg[:300]}), 400
    finally:
        conn.close()


@olx_bp.route("/admin/api/olx/pedido/<int:pid>", methods=["GET"])
def olx_anuncio_pedido(pid):
    if not _admin_autenticado():
        return _sem_senha()
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT site_olx_anuncio_pedido(%s) AS r", (pid,))
            r = (cur.fetchone() or {}).get("r")
        return (jsonify(r), 200) if r else (jsonify({"erro": "pedido não encontrado"}), 404)
    finally:
        conn.close()
