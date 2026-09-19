"""
A plataforma de captação: a tela onde o Tel cola o link do OLX.

POR QUE EXISTE. O pedido do Tel, nas palavras dele: "a gente faz a captação
de imóveis diretamente com o proprietário, eu quero pegar esse anúncio dele no
olx e colocar no site da imobeasy.com já cadastrado". Hoje ele redigita tudo à
mão -- título, descrição, quartos, valor -- e sobe 16 fotos uma a uma. O
anúncio do proprietário já tem quase tudo isso escrito. Esta tela lê o anúncio,
mostra o que veio, PERGUNTA o que falta, e só então manda para o site.

O QUE ELA NÃO FAZ, e é decisão de arquitetura, não esquecimento:
  * **não escreve na tabela `imoveis`**. Ela cadastra no site; a varredura
    horária (`sincronizar_catalogo.py`, cron aos :17) traz o imóvel do site
    para o banco sozinha, em até uma hora. Dois caminhos de escrita para a
    mesma tabela é como se cria divergência que ninguém explica depois.
  * o rascunho mora em `captacoes`, tabela própria, nunca em `imoveis`.

ONDE ELA RODA. Porta 8090, processo separado do `servidor.py` (8080) -- se esta
tela travar numa leitura lenta do OLX, o publicador do Tel continua atendendo.
**Ler o OLX só funciona de um IP liberado:** medido em 02/09/2026, o servidor
(179.198.121.171) leva 403 do Cloudflare em `www`, `am` e `apigw`, e o Mac
passa no mesmo minuto. Baixar as fotos (`img.olx.com.br`) funciona nos dois.
Enquanto esse bloqueio durar, esta tela precisa rodar do Mac -- e quando a OLX
recusa, a tela DIZ isso, com essa explicação, em vez de "erro inesperado".

AUTENTICAÇÃO. Senha única em `CAPTACAO_SENHA`; sem ela o processo não sobe
(mesmo padrão de `servidor.py`, `db.py` e `enviar_zapi.py`). É ferramenta
interna de uma pessoa só -- não vale a pena tabela de usuário. A sessão é
cookie assinado do Flask.

    export $(cat .env | xargs) && .venv/bin/python captacao.py
"""
import hashlib
import hmac
import inspect
import json
import os
import re
import secrets
import threading
import time
from datetime import datetime

from flask import (Flask, abort, redirect, render_template, request, session,
                   url_for)

import db
import extrair_olx

# 8090 é a porta combinada, separada da 8080 do `servidor.py`. Configurável
# porque já se mediu (02/09/2026, no Mac) que outro processo pode estar
# sentado nela -- e o servidor de desenvolvimento do Flask morre com
# "Address already in use" numa mensagem que ninguém lê, se o log for para
# arquivo.
PORTA = int(os.environ.get("CAPTACAO_PORTA") or 8090)

# Os três módulos irmãos podem ainda não existir (estão sendo escritos em
# paralelo). O app SOBE mesmo assim e diz na tela o que está faltando -- uma
# tela que não abre não explica nada a ninguém.
try:
    import captacao_campos
except Exception:                                    # pragma: no cover
    captacao_campos = None
try:
    import captacao_fotos
except Exception:                                    # pragma: no cover
    captacao_fotos = None
try:
    import captacao_site
except Exception:                                    # pragma: no cover
    captacao_site = None


def _variavel_obrigatoria(nome):
    valor = os.environ.get(nome)
    if not valor:
        raise RuntimeError(
            f"{nome} não configurada no ambiente. Copie .env.example "
            "para .env, preencha o valor, e carregue no ambiente antes "
            "de rodar."
        )
    return valor


CAPTACAO_SENHA = _variavel_obrigatoria("CAPTACAO_SENHA")

# A chave que assina o cookie sai da própria senha quando `CAPTACAO_SECRET` não
# é dada. Duas razões: (1) chave sorteada a cada boot desloga o Tel a cada
# restart, e ele nem saberia por quê; (2) derivar da senha faz TROCAR A SENHA
# INVALIDAR as sessões abertas, que é exatamente o que se espera de uma troca
# de senha. Não é a senha em claro no cookie: é sha256 dela, e o cookie carrega
# só a assinatura.
CAPTACAO_SECRET = os.environ.get("CAPTACAO_SECRET") or hashlib.sha256(
    b"captacao-cookie|" + CAPTACAO_SENHA.encode("utf-8")).hexdigest()

# Onde as fotos baixadas ficam. Medido: ~87 KB por foto, ~1,3 MB por anúncio --
# cabe folgado nos 6,7 GB livres do servidor. Varrer Manaus inteira não caberia,
# mas isso é um anúncio por vez, a pedido do Tel.
PASTA_FOTOS = os.environ.get(
    "CAPTACAO_FOTOS_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "fotos_captacao"))

# Se a tela for servida por HTTPS, ligar. Fica desligado por padrão de
# propósito: com `Secure` ligado num acesso http o navegador descarta o cookie
# em SILÊNCIO e o login vira um loop sem mensagem -- o pior tipo de falha.
COOKIE_SEGURO = os.environ.get("CAPTACAO_COOKIE_SEGURO", "").lower() in ("1", "sim", "true")

app = Flask(__name__)
app.secret_key = CAPTACAO_SECRET
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=COOKIE_SEGURO,
    MAX_CONTENT_LENGTH=2 * 1024 * 1024,
)

STATUS_VALIDOS = ("rascunho", "pronto", "publicado", "erro")

# Rótulo em português de cada coluna de `imoveis`. Só é usado quando
# `captacao_campos.o_que_falta` não manda rótulo próprio -- o vocabulário de
# campo é dele, esta tabela é a rede de segurança para o campo que ele não
# rotular, para a tela nunca mostrar "area_util" cru para o Tel.
ROTULOS = {
    "tipo": "Tipo do imóvel",
    "status": "Situação",
    "condominio_nome": "Condomínio",
    "bairro": "Bairro",
    "logradouro": "Rua",
    "complemento": "Complemento",
    "area_util": "Área útil (m²)",
    "area_total": "Área total (m²)",
    "quartos": "Quartos",
    "suites": "Suítes",
    "banheiros": "Banheiros",
    "vagas": "Vagas descobertas",
    "vagas_cobertas": "Vagas cobertas",
    "sol": "Sol (manhã/tarde)",
    "andar": "Andar",
    "valor_venda": "Valor de venda",
    "valor_aluguel": "Valor do aluguel",
    "taxa_condominio": "Taxa de condomínio",
    "iptu": "IPTU",
    "mobilia": "Mobília",
    "descricao": "Descrição",
    "caracteristicas": "Características",
    "captado_por": "Captado por",
    "anotacoes": "Anotações da conversa com o proprietário",
}

# Fallback de obrigatoriedade, usado SÓ quando `o_que_falta` não disser quais
# são obrigatórios. Quem manda é o `captacao_campos`; isto evita que a tela
# jogue tudo no mesmo monte quando ele devolve só nomes.
OBRIGATORIOS_PADRAO = ("tipo", "bairro", "quartos", "banheiros",
                       "area_util", "valor_venda", "valor_aluguel")

# Os nomes REAIS, conferidos dentro de `captacao_site.credenciais()` em
# 02/09/2026 -- não são palpite. O primeiro palpite desta tela foi
# `IMOBEASY_USUARIO`, e estava errado: é `IMOBEASY_EMAIL`. A tela mostra esses
# nomes para o Tel exportar, então um nome errado aqui manda ele configurar a
# variável que ninguém lê.
VARIAVEIS_DO_SITE_PADRAO = ("IMOBEASY_EMAIL", "IMOBEASY_SENHA")

EXTENSOES_DE_FOTO = (".jpg", ".jpeg", ".png", ".webp")

# Campos que existem SÓ aqui e nunca vão para o site. `anotacoes` é o caso: o
# próprio formulário promete isso ao Tel ("fica guardado aqui na captação, não
# vai para o site") e `detalhe` já o tirava da lista de conferência -- faltava
# tirá-lo de mais dois lugares, e o efeito era um travamento SILENCIOSO.
# Medido em 02/09/2026: `pendencias_para_publicar` comparava TODA chave de
# `campos` com o mapa do formulário, então bastava o Tel escrever uma anotação
# para a publicação ficar bloqueada com "O formulário do site não tem onde pôr:
# Anotações da conversa com o proprietário". E `captacao_site.cadastrar` tem o
# MESMO portão do lado dele, então mandar a anotação junto derrubaria a
# publicação lá também. Campo nosso não é campo do site.
SO_NOSSOS = ("anotacoes",)

# Pergunta que o `captacao_campos` faz com um nome que NÃO é coluna nenhuma.
# `o_que_falta` cobra um obrigatório chamado `valor` -- que quer dizer "venda
# ou aluguel, um dos dois" --, mas ele só considera respondido quando
# `valor_venda` ou `valor_aluguel` estiver preenchido. A tela gravava a
# resposta em `campos["valor"]` e perguntava DE NOVO, para sempre: medido em
# 02/09/2026, o Tel responde "390000", salva, e a tela continua dizendo "Falta
# preencher: Valor de venda ou de aluguel". A captação nunca saía de rascunho e
# o botão de publicar nunca aparecia.
#
# A tela não pode adivinhar se 390.000 é venda ou aluguel -- então ela
# PERGUNTA as duas, que é o que o site também guarda em duas colunas.
PERGUNTAS_COMPOSTAS = {
    "valor": (("valor_venda", "Valor de venda"),
              ("valor_aluguel", "Valor do aluguel")),
}


# ---------------------------------------------------------------- segurança

# Senha única em porta aberta é adivinhável por laço. Sem freio, uma noite de
# tentativas acha qualquer senha curta -- e não haveria nem sinal de que
# aconteceu. Cinco erros do mesmo IP fecham por 5 minutos. Estado em memória:
# o processo é um só, e reiniciar liberar não é problema (reiniciar é coisa que
# o Tel faz, não o atacante).
_TENTATIVAS = {}
_TENTATIVAS_LOCK = threading.Lock()
LIMITE_TENTATIVAS = 5
CASTIGO_SEGUNDOS = 300


def _bloqueado_ate(ip, agora=None):
    agora = agora if agora is not None else time.time()
    with _TENTATIVAS_LOCK:
        _, ate = _TENTATIVAS.get(ip, (0, 0.0))
    return ate if ate > agora else 0.0


def _registrar_falha(ip, agora=None):
    agora = agora if agora is not None else time.time()
    with _TENTATIVAS_LOCK:
        falhas, ate = _TENTATIVAS.get(ip, (0, 0.0))
        # Castigo cumprido zera a conta. Sem isto o contador ficava em 5 para
        # sempre, e MESES depois um único erro de digitação do Tel valia outros
        # 5 minutos de porta fechada -- castigo de reincidente para quem errou
        # a senha uma vez. Medido em 02/09/2026. O freio é "5 erros seguidos",
        # e "seguidos" tem que valer também depois que o relógio corre.
        if ate and ate <= agora:
            falhas, ate = 0, 0.0
        falhas += 1
        if falhas >= LIMITE_TENTATIVAS:
            ate = agora + CASTIGO_SEGUNDOS
        _TENTATIVAS[ip] = (falhas, ate)


def _limpar_tentativas(ip):
    with _TENTATIVAS_LOCK:
        _TENTATIVAS.pop(ip, None)


def _logado():
    return session.get("entrou") is True


def _token_csrf():
    """Um token por sessão, conferido em TODO POST. O cookie é `SameSite=Lax`,
    o que já barra a maioria dos POST de outro site, mas 'a maioria' não é
    critério de porta: o padrão deste projeto é só deixar passar o que prova
    que pode."""
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(24)
    return session["csrf"]


@app.before_request
def _exigir_login_e_token():
    # A tela de entrar é a única sem sessão -- e ela tem freio próprio de
    # tentativa, senão seria a porta escancarada deste app.
    if request.endpoint in ("entrar", "static"):
        return None
    if not _logado():
        return redirect(url_for("entrar", voltar=request.path))
    if request.method == "POST":
        esperado = session.get("csrf") or ""
        recebido = request.form.get("csrf") or ""
        if not esperado or not hmac.compare_digest(esperado, recebido):
            # Falha FECHADO: token ausente é token errado.
            return _pagina_erro(
                "Sessão expirada",
                "A página estava aberta há muito tempo. Entre de novo e "
                "repita o que estava fazendo -- nada foi salvo.",
            ), 400
    return None


# ---------------------------------------------------------------- o banco

# ATENÇÃO: o DDL de `captacoes` e `captacao_fotos` é de outro arquivo (está
# sendo escrito em paralelo). O esquema ASSUMIDO aqui é este, e todo o SQL da
# tela mora nestas funções -- e os nomes são os do `captacao_schema.sql`,
# conferidos contra o banco em 02/09. `titulo` e `fotos_pasta` NÃO são
# colunas: o título sai de `dados_olx`, que é a prova de onde o dado veio, e
# a pasta sai do `olx_id`, que é o que a identifica. Guardar de novo o que já
# está guardado é a mesma cópia que diverge sozinha e este projeto já pagou
# por isso quatro vezes na gramática de comando.

_SQL_LISTAR = """
    SELECT id, link_olx, olx_id, status, codigo_no_site, erro,
           dados_olx->>'titulo' AS titulo,
           criado_em, atualizado_em
      FROM captacoes
     ORDER BY id DESC
     LIMIT 200
"""
_SQL_BUSCAR = """
    SELECT *, dados_olx->>'titulo' AS titulo FROM captacoes WHERE id = %s
"""
# Dedupe pela FUNÇÃO do esquema, não por `olx_id`: link que ainda não foi
# lido não tem id, e aí `WHERE olx_id = %s` não acha nada e abre um segundo
# rascunho do mesmo anúncio. `nay_chave_do_link` tira o id do próprio link, e
# quando não há id usa o endereço normalizado.
_SQL_POR_LINK = """
    SELECT c.*, c.dados_olx->>'titulo' AS titulo
      FROM nay_captacao_do_link(%s) c LIMIT 1
"""
_SQL_CRIAR = """
    INSERT INTO captacoes (link_olx, olx_id, status, dados_olx, campos)
    VALUES (%s, %s, 'rascunho', %s, %s)
    RETURNING id
"""
_SQL_SALVAR_CAMPOS = """
    UPDATE captacoes SET campos = %s, status = %s
     WHERE id = %s
"""
_SQL_MARCAR = """
    UPDATE captacoes SET status = %s, erro = %s, codigo_no_site = %s
     WHERE id = %s
"""
_SQL_FOTOS = """
    SELECT ordem, url_olx AS url, caminho, bytes, e_capa, baixada_em, erro
      FROM captacao_fotos WHERE captacao_id = %s ORDER BY ordem
"""
# O relatório do baixador inteiro, não só a URL: sem `caminho` e `bytes`,
# saber se a foto está no disco vira pergunta ao sistema de arquivos, e a
# resposta muda conforme a máquina. `ON CONFLICT` porque a retomada roda de
# novo sobre as mesmas fotos.
_SQL_GRAVAR_FOTO = """
    INSERT INTO captacao_fotos (captacao_id, ordem, url_olx, caminho, bytes,
                                e_capa, baixada_em, erro)
    VALUES (%s, %s, %s, %s, %s, %s,
            -- o carimbo sai do banco: foto com caminho foi baixada, foto sem
            -- caminho nao foi, e nao ha fuso do Python para errar no meio
            CASE WHEN %s IS NOT NULL THEN now() END, %s)
    ON CONFLICT (captacao_id, ordem) DO UPDATE
       SET url_olx = EXCLUDED.url_olx, caminho = EXCLUDED.caminho,
           bytes = EXCLUDED.bytes, e_capa = EXCLUDED.e_capa,
           baixada_em = EXCLUDED.baixada_em, erro = EXCLUDED.erro
"""


def _json(valor):
    """psycopg2 não sabe adaptar dict sozinho. Import tardio para o módulo
    continuar importável (e testável) numa máquina sem psycopg2."""
    from psycopg2.extras import Json
    return Json(valor)


def repo_listar(conn):
    with conn.cursor() as cur:
        cur.execute(_SQL_LISTAR)
        return list(cur.fetchall())


def repo_buscar(conn, captacao_id):
    with conn.cursor() as cur:
        cur.execute(_SQL_BUSCAR, (captacao_id,))
        return cur.fetchone()


def repo_por_link(conn, link):
    """Colar o mesmo link duas vezes não pode abrir dois rascunhos do mesmo
    imóvel -- ele preencheria um e publicaria o outro, vazio.

    A comparação é pela função `nay_captacao_do_link` do esquema, não por
    `olx_id`: o link que ele acabou de colar ainda não foi lido, então não tem
    id nenhum, e procurar por id não acharia nada. A função tira o número do
    próprio link -- e `www`/`am`, `?utm_source=...` e slug editado pelo
    proprietário são todos o mesmo anúncio."""
    if not link:
        return None
    with conn.cursor() as cur:
        cur.execute(_SQL_POR_LINK, (str(olx_id),))
        return cur.fetchone()


def repo_criar(conn, link, dados, campos, pasta):
    with conn.cursor() as cur:
        cur.execute(_SQL_CRIAR, (link, str(dados.get("olx_id") or "") or None,
                                 _json(dados),
                                 _json(campos)))
        novo = cur.fetchone()
        captacao_id = novo["id"] if isinstance(novo, dict) else novo[0]
        # Ordem comeca em 1, nao em 0: e a convencao de `imovel_fotos` (medido
        # -- 1.164 imoveis, ordem minima 1) e o esquema tem CHECK exigindo isso.
        # Aqui a foto ainda nao foi baixada: caminho/bytes vem depois.
        for indice, url in enumerate(dados.get("fotos") or []):
            cur.execute(_SQL_GRAVAR_FOTO, (captacao_id, indice + 1, url,
                                           None, None, indice == 0, None, None))
            # (caminho e bytes ficam nulos: a foto ainda nao foi baixada)
    conn.commit()
    return captacao_id


def repo_gravar_relatorio(conn, captacao_id, relatorio):
    """O que o baixador achou vira linha, em vez de morrer no ar.

    Sem isto, `caminho`, `bytes` e `baixada_em` nascem vazios e saber se a foto
    esta no disco vira pergunta ao sistema de arquivos -- resposta que muda
    conforme a maquina, e some quando a tela roda no servidor e o disco e outro.
    """
    if not relatorio:
        return
    with conn.cursor() as cur:
        for f in relatorio.get("fotos") or []:
            cur.execute(_SQL_GRAVAR_FOTO,
                        (captacao_id, f["ordem"], f["url"], f.get("arquivo"),
                         f.get("bytes"), bool(f.get("e_capa")),
                         f.get("arquivo"), None))
        for f in relatorio.get("falhas") or []:
            cur.execute(_SQL_GRAVAR_FOTO,
                        (captacao_id, f["ordem"], f["url"], None, None, False,
                         None, str(f.get("motivo"))[:400]))
    conn.commit()


def repo_salvar_campos(conn, captacao_id, campos, status):
    with conn.cursor() as cur:
        cur.execute(_SQL_SALVAR_CAMPOS, (_json(campos), status, captacao_id))
    conn.commit()


def repo_marcar(conn, captacao_id, status, erro=None, codigo_site=None):
    with conn.cursor() as cur:
        cur.execute(_SQL_MARCAR, (status, erro, codigo_site, captacao_id))
    conn.commit()


def repo_listar_fotos(conn, captacao_id):
    with conn.cursor() as cur:
        cur.execute(_SQL_FOTOS, (captacao_id,))
        return list(cur.fetchall())


# ------------------------------------------------- os módulos irmãos

def _chamar_flexivel(func, **candidatos):
    """Passa só os argumentos que a função de fato aceita.

    Existe porque `captacao_campos` e `captacao_site` estão sendo escritos ao
    mesmo tempo que esta tela e a assinatura exata deles ainda não está
    fechada. Inspecionar a assinatura é melhor que `except TypeError`: aquele
    engoliria um TypeError vindo de DENTRO da função e o erro real sumiria.
    Quando as assinaturas assentarem, isto vira chamada direta."""
    try:
        params = inspect.signature(func).parameters
    except (TypeError, ValueError):                  # pragma: no cover
        return func(**candidatos)
    if any(p.kind is p.VAR_KEYWORD for p in params.values()):
        return func(**candidatos)
    return func(**{k: v for k, v in candidatos.items() if k in params})


def _traduzir(dados):
    if captacao_campos is None:
        return {}
    return _chamar_flexivel(captacao_campos.traduzir, dados_olx=dados,
                            dados=dados) or {}


def _normalizar_faltantes(bruto):
    """`o_que_falta` pode devolver lista de nome, lista de dict, ou dict
    nome->rótulo. A tela aceita as três e normaliza para
    [{nome, rotulo, obrigatorio}] -- porque quem escreve o outro lado ainda
    está escrevendo, e uma tela que quebra por causa do formato do vizinho não
    ajuda ninguém a descobrir nada."""
    itens = []
    if not bruto:
        return itens
    if isinstance(bruto, dict):
        bruto = [{"nome": k, "rotulo": v} for k, v in bruto.items()]
    for item in bruto:
        if isinstance(item, str):
            item = {"nome": item}
        if not isinstance(item, dict):
            continue
        nome = item.get("nome") or item.get("campo") or item.get("name")
        if not nome:
            continue
        obrigatorio = item.get("obrigatorio")
        if obrigatorio is None:
            obrigatorio = item.get("required")
        if obrigatorio is None:
            obrigatorio = nome in OBRIGATORIOS_PADRAO
        # Pergunta composta vira DUAS caixas com os nomes de coluna de verdade.
        # Sem isto a resposta ia para uma chave que `o_que_falta` não olha, e a
        # mesma pergunta voltava para sempre (ver PERGUNTAS_COMPOSTAS).
        subcampos = [{"nome": n, "rotulo": r}
                     for n, r in PERGUNTAS_COMPOSTAS.get(nome, ())]
        itens.append({
            "nome": nome,
            "rotulo": item.get("rotulo") or item.get("label") or _rotulo(nome),
            "obrigatorio": bool(obrigatorio),
            "ajuda": item.get("ajuda") or item.get("dica") or "",
            "subcampos": subcampos,
        })
    # Obrigatório em cima: é o que impede de publicar, então é o que ele
    # precisa ver primeiro no celular, sem rolar.
    itens.sort(key=lambda c: (not c["obrigatorio"], c["rotulo"]))
    return itens


def _rotulo(nome):
    return ROTULOS.get(nome) or nome.replace("_", " ").capitalize()


def _o_que_falta(campos):
    if captacao_campos is None:
        return []
    return _normalizar_faltantes(
        _chamar_flexivel(captacao_campos.o_que_falta, campos=campos))


def _duvidas(dados, campos, faltando):
    """As perguntas para o proprietário. Aceita lista de texto ou de dict.

    A chave que o `captacao_campos` usa de verdade é **`aviso`** -- conferida
    no módulo dele em 02/09/2026. Esta função procurava só `pergunta`/`texto`,
    e o resultado não era erro nenhum: era a lista voltar VAZIA e a tela
    simplesmente não mostrar as dúvidas, em silêncio. Chave de dicionário
    errada não estoura; ela apaga.
    """
    if captacao_campos is None or not hasattr(captacao_campos, "duvidas"):
        return [], False
    try:
        bruto = _chamar_flexivel(captacao_campos.duvidas, dados_olx=dados,
                                 dados=dados, campos=campos, faltando=faltando)
    except Exception:
        # As dúvidas são AJUDA, não portão -- e ajuda que quebra não pode levar
        # a página junto. Medido em 02/09/2026: `captacao_campos.duvidas`
        # compara `valor_venda < VENDA_MINIMA`, e o que esta tela grava vem do
        # formulário, ou seja TEXTO; a comparação estourava `TypeError` e a
        # captação passava a devolver 500 toda vez que fosse aberta, para
        # sempre, logo depois de o Tel responder o valor. A tela abre sem as
        # dúvidas e DIZ que elas faltaram -- calar seria pior.
        app.logger.exception("captacao_campos.duvidas estourou; a tela segue "
                             "sem as dúvidas")
        return [], True
    saida = []
    for item in (bruto or []):
        if isinstance(item, str):
            saida.append({"pergunta": item, "campo": None})
        elif isinstance(item, dict):
            pergunta = (item.get("aviso") or item.get("pergunta")
                        or item.get("texto") or item.get("duvida"))
            if pergunta:
                saida.append({"pergunta": pergunta,
                              "campo": item.get("campo") or item.get("nome")})
    return saida, False


# ---------------------------------------------------------------- o link

_HOSTS_OLX = re.compile(r"^(?:[a-z0-9-]+\.)*olx\.com\.br$", re.I)


def link_valido(bruto):
    """Só link do OLX entra. Sem esta parede, o campo de texto vira um
    buscador para qualquer endereço a partir da nossa máquina -- inclusive
    endereço interno da rede. O padrão do projeto é negar: só passa o que
    prova que é do OLX."""
    texto = (bruto or "").strip()
    if not texto or len(texto) > 2000:
        return None
    m = re.match(r"^(https?)://([^/\s?#]+)", texto, re.I)
    if not m:
        return None
    host = m.group(2).split("@")[-1].split(":")[0]
    if not _HOSTS_OLX.match(host):
        return None
    # Remonta a partir das PEÇAS, em vez de emendar por posição: fatiar com
    # `m.start()` depois de trocar `http` por `https` erraria o corte por um
    # caractere, porque a troca deixa a string mais longa que o `m` medido.
    #
    # `http` colado do celular vira `https` -- o extrator só sabe regionalizar
    # o endereço `https`, e mandar em claro o que existe cifrado não tem ganho.
    #
    # E o host em MINÚSCULA, que não é frescura: `extrair_olx._regionalizar`
    # troca `www.olx.com.br` por `am.olx.com.br` com uma regex sensível a
    # maiúscula, então um `https://WWW.OLX.COM.BR/...` colado do celular ia
    # buscar no host `www` -- que, segundo o cabeçalho do `extrair_olx`, devolve
    # 200 com a página ERRADA. Erro silencioso, do tipo pior.
    return "https://" + m.group(2).lower() + texto[m.end(2):]


# ---------------------------------------------------------------- telas

def _pagina_erro(titulo, detalhe, voltar="/"):
    # O token vai junto porque o cabeçalho de toda tela tem o botão "Sair", e
    # ele é um POST -- sem o token, sair a partir de uma tela de erro cairia
    # na própria parede de CSRF e mostraria outro erro em cima do primeiro.
    return render_template("captacao_erro.html", titulo=titulo,
                           detalhe=detalhe, voltar=voltar,
                           csrf=session.get("csrf", ""))


# O texto de cada erro de HTTP que esta tela consegue produzir. Sem isto o
# Flask devolve a página PADRÃO DO WERKZEUG, que é em INGLÊS ("Not Found -- The
# requested URL was not found on the server"): medido em 02/09/2026 ao abrir
# `/captacao/4242`, uma captação que não existe. O Tel lê essa tela no celular
# no meio de uma captação, e o projeto inteiro é em português -- página em
# inglês, sem dizer o que fazer, é a mesma falha de "erro inesperado".
ERROS_HTTP = {
    404: ("Essa página não existe",
          "Ou a captação foi apagada, ou o endereço veio errado. Volte para a "
          "lista e abra pela lista -- o número da captação é o `#` que aparece "
          "em cada linha."),
    405: ("Esse botão não vai aqui",
          "A página foi aberta de um jeito que esta tela não atende. Volte "
          "para a lista e repita pelo caminho normal."),
    413: ("O que você mandou é grande demais",
          "O formulário passou do limite de 2 MB. Se colou um texto enorme na "
          "descrição, corte um pedaço e salve em duas vezes."),
}


@app.errorhandler(Exception)
def _erro_interno(erro):
    """Mesma disciplina de `servidor.py`: o traceback vai para o log, nunca
    para a resposta. Já houve caso neste projeto de mensagem de erro carregando
    a DATABASE_URL inteira, com senha dentro."""
    from werkzeug.exceptions import HTTPException
    if isinstance(erro, HTTPException):
        codigo = erro.code or 500
        titulo, detalhe = ERROS_HTTP.get(codigo, (
            "Não deu para abrir essa página",
            "A tela recusou esse acesso. Volte para a lista e tente pelo "
            "caminho normal; se repetir, me chame com a hora que aconteceu."))
        return _pagina_erro(titulo, detalhe), codigo
    app.logger.exception("erro na tela de captação: %s %s",
                         request.method, request.path)
    return _pagina_erro(
        "Deu erro aqui dentro",
        "Alguma coisa quebrou do lado do servidor. O detalhe ficou no log. "
        "Tente de novo; se repetir, me chame com a hora que aconteceu.",
    ), 500


@app.route("/entrar", methods=["GET", "POST"])
def entrar():
    voltar = request.values.get("voltar") or "/"
    if not voltar.startswith("/") or voltar.startswith("//"):
        voltar = "/"                      # nunca redirecionar para fora
    if request.method == "GET":
        return render_template("captacao_entrar.html", erro=None, voltar=voltar)

    ip = request.remote_addr or "?"
    ate = _bloqueado_ate(ip)
    if ate:
        faltam = int(ate - time.time()) // 60 + 1
        return render_template(
            "captacao_entrar.html", voltar=voltar,
            erro=f"Muitas tentativas erradas. Espere {faltam} min e tente de novo."
        ), 429

    enviada = request.form.get("senha") or ""
    if hmac.compare_digest(enviada, CAPTACAO_SENHA):
        _limpar_tentativas(ip)
        session.clear()
        session["entrou"] = True
        _token_csrf()
        return redirect(voltar)
    _registrar_falha(ip)
    return render_template("captacao_entrar.html", voltar=voltar,
                           erro="Senha errada."), 401


@app.route("/sair", methods=["POST"])
def sair():
    session.clear()
    return redirect(url_for("entrar"))


@app.route("/")
def inicio():
    conn = db.conectar()
    try:
        captacoes = repo_listar(conn)
    finally:
        conn.close()
    return render_template("captacao_lista.html", captacoes=captacoes,
                           csrf=_token_csrf(), faltando=_modulos_faltando(),
                           mensagem=request.args.get("msg"))


def _modulos_faltando():
    """O que ainda não existe no disco. A tela diz -- em vez de fingir que
    está tudo pronto e falhar mais tarde, num lugar mais difícil de entender."""
    faltam = []
    if captacao_campos is None:
        faltam.append("captacao_campos.py (traduzir os campos do OLX para os nossos)")
    if captacao_fotos is None:
        faltam.append("captacao_fotos.py (baixar as fotos)")
    if captacao_site is None:
        faltam.append("captacao_site.py (cadastrar no admin da Imob Easy)")
    return faltam


@app.route("/captar", methods=["POST"])
def captar():
    link = link_valido(request.form.get("link"))
    if not link:
        return _pagina_erro(
            "Esse link não serve",
            "Cole o endereço completo de um anúncio do OLX, começando com "
            "https:// e no domínio olx.com.br. Exemplo: "
            "https://www.olx.com.br/regiao-de-manaus/imoveis/casa-...-1526572128",
        ), 400

    try:
        dados = extrair_olx.do_link(link)
    except extrair_olx.OlxBloqueado:
        # Mensagem HONESTA: isto não é bug, é a OLX recusando este IP. Medido
        # em 02/09/2026 -- 403 do servidor, 200 do Mac, no mesmo minuto.
        return _pagina_erro(
            "A OLX recusou a leitura deste IP",
            "Não é erro do sistema: a OLX (Cloudflare) bloqueou as requisições "
            "que saem desta máquina e devolveu 403. O que fazer: rodar esta "
            "tela do Mac, que hoje passa, ou esperar o bloqueio expirar -- ele "
            "costuma cair sozinho. As FOTOS não estão bloqueadas em lugar "
            "nenhum; só a leitura da página do anúncio.",
        ), 502
    except Exception:
        app.logger.exception("falha ao ler o anúncio do OLX: %s", link)
        return _pagina_erro(
            "Não consegui ler esse anúncio",
            "O link abriu, mas não achei os dados do anúncio dentro da página. "
            "Isso acontece quando o anúncio saiu do ar, ou quando a OLX mudou "
            "o formato da página. Confira o link no navegador; se ele abrir "
            "normal, o formato mudou e o extrator precisa de ajuste.",
        ), 502

    conn = db.conectar()
    try:
        ja = repo_por_link(conn, link)
        if ja:
            return redirect(url_for("detalhe", captacao_id=ja["id"],
                                    msg="Esse anúncio já tinha sido captado -- "
                                        "abri o rascunho que já existia."))
        campos = _traduzir(dados)
        pasta = os.path.join(PASTA_FOTOS, _nome_de_pasta(dados.get("olx_id")))
        captacao_id = repo_criar(conn, link, dados, campos, pasta)
    finally:
        conn.close()

    # O relatório do baixador vira linha: sem isso, `caminho` e `bytes`
    # nascem vazios e saber se a foto está no disco vira pergunta ao sistema de
    # arquivos -- resposta que muda de máquina para máquina.
    repo_gravar_relatorio(conn, captacao_id,
                          _baixar_fotos(dados.get("fotos") or [], pasta))
    return redirect(url_for("detalhe", captacao_id=captacao_id))


def _nome_de_pasta(olx_id):
    """O `olx_id` vira NOME DE PASTA, e nome de pasta vindo de fora precisa de
    coleira. Ele sai do JSON da página da OLX (`listId`), que hoje é um número
    -- mas `os.path.join(PASTA_FOTOS, "../../../tmp/x")` escreve em `/tmp`, e o
    join com um caminho ABSOLUTO joga fora a pasta base inteira. Medido em
    02/09/2026. Aqui vale a lista do que PODE, não a do que não pode."""
    limpo = re.sub(r"[^A-Za-z0-9_-]", "", str(olx_id or ""))[:64]
    return limpo or "sem-id"


def _pasta_da_linha(linha):
    """A pasta das fotos sai do `olx_id`, que e o que identifica o anuncio --
    nao de uma coluna. Guardar de novo o que ja esta guardado e a copia que
    diverge sozinha."""
    return os.path.join(PASTA_FOTOS, _nome_de_pasta((linha or {}).get("olx_id")))


def _baixar_fotos(urls, pasta):
    """Baixa as fotos e devolve o relatório de `captacao_fotos.baixar`
    ({"pasta", "fotos", "falhas"}) -- ou None se não deu para tentar.

    Baixar foto NÃO pode derrubar a captação: se falhar aqui, o rascunho já
    existe com as URLs guardadas e a tela de publicar avisa que as fotos não
    estão no disco. Perder o texto do anúncio por causa de uma foto seria o
    pior dos dois mundos.

    É seguro chamar de novo: `baixar` reconhece o que já está em disco
    (`estado: "ja_estava"`, sem ir à rede) e retenta só o que faltou. É por
    isso que a publicação chama outra vez em vez de guardar caminho de arquivo
    em coluna nenhuma -- o disco é a verdade, e ele pode ter sido limpo.
    """
    if captacao_fotos is None or not urls:
        return None
    try:
        os.makedirs(pasta, exist_ok=True)
        return captacao_fotos.baixar(urls, pasta)
    except Exception:
        app.logger.exception("falha ao baixar fotos para %s", pasta)
        return None


def _fotos_em_disco(pasta):
    """Quantas fotos já estão gravadas. Olha o disco em vez de guardar o
    caminho numa coluna: a pasta pode ter sido limpa, e uma coluna dizendo que
    a foto existe faria a publicação tentar subir arquivo que não está lá."""
    if not pasta or not os.path.isdir(pasta):
        return []
    try:
        return sorted(n for n in os.listdir(pasta)
                      if n.lower().endswith(EXTENSOES_DE_FOTO))
    except OSError:                                  # pragma: no cover
        return []


def _carregar(conn, captacao_id):
    linha = repo_buscar(conn, captacao_id)
    if not linha:
        abort(404)
    return linha


def _campos_de(linha):
    bruto = linha.get("campos")
    if isinstance(bruto, str):
        try:
            bruto = json.loads(bruto)
        except ValueError:
            bruto = {}
    return dict(bruto or {})


def _dados_de(linha):
    bruto = linha.get("dados_olx")
    if isinstance(bruto, str):
        try:
            bruto = json.loads(bruto)
        except ValueError:
            bruto = {}
    return dict(bruto or {})


@app.route("/captacao/<int:captacao_id>")
def detalhe(captacao_id):
    conn = db.conectar()
    try:
        linha = _carregar(conn, captacao_id)
        fotos = repo_listar_fotos(conn, captacao_id)
    finally:
        conn.close()

    dados = _dados_de(linha)
    campos = _campos_de(linha)
    faltando = _o_que_falta(campos)
    urls_das_fotos = [f["url"] for f in (fotos or [])] or list(dados.get("fotos") or [])
    # `captacao_campos.traduzir` devolve a forma INTEIRA, com `None` no campo
    # que o anúncio não trouxe -- e `None` num `value=` de input vira a palavra
    # "None" escrita dentro da caixa, que o Tel salvaria como se fosse o valor.
    # Campo sem valor não é "preenchido": ele já está na lista do que falta.
    preenchidos = [{"nome": n, "rotulo": _rotulo(n), "valor": v}
                   for n, v in sorted(campos.items())
                   if n not in SO_NOSSOS and v is not None and v != ""]
    duvidas, duvidas_falharam = _duvidas(dados, campos, faltando)
    avisos = avisos_da_captacao(linha, urls_das_fotos)
    if duvidas_falharam:
        avisos.append("Não consegui montar a lista do que perguntar ao "
                      "proprietário -- o módulo que a monta quebrou com o que "
                      "está salvo aqui. O resto da tela funciona, e o detalhe "
                      "ficou no log. Me chame com o número desta captação.")
    return render_template(
        "captacao_detalhe.html", c=linha, dados=dados, campos=campos,
        faltando=faltando, preenchidos=preenchidos, duvidas=duvidas,
        fotos=fotos or [{"ordem": i, "url": u}
                        for i, u in enumerate(dados.get("fotos") or [])],
        pendencias=pendencias_para_publicar(linha, campos, faltando, urls_das_fotos),
        avisos=avisos,
        csrf=_token_csrf(), mensagem=request.args.get("msg"),
    )


def _nomes_editaveis(campos, faltando):
    """Os nomes de campo que ESTA TELA de fato desenhou -- e só eles são aceitos
    de volta no POST.

    O padrão do projeto é negar: só passa o que prova que pode. Antes daqui, o
    nome vinha cru do formulário e virava chave do dicionário: medido em
    02/09/2026, um POST com `campo_` (nome vazio) e `campo_../../etc` gravou as
    chaves `''` e `'../../etc'` dentro de `campos`. Não é só sujeira -- chave que
    o mapa do site não conhece BLOQUEIA a publicação para sempre, com um rótulo
    que não quer dizer nada.
    """
    nomes = set(campos) | set(SO_NOSSOS)
    for campo in faltando:
        if campo.get("subcampos"):
            nomes.update(s["nome"] for s in campo["subcampos"])
        else:
            nomes.add(campo["nome"])
    return nomes


@app.route("/captacao/<int:captacao_id>", methods=["POST"])
def salvar(captacao_id):
    conn = db.conectar()
    try:
        linha = _carregar(conn, captacao_id)
        campos = _campos_de(linha)
        antes = _o_que_falta(campos)
        aceitos = _nomes_editaveis(campos, antes)
        respondidos = set()
        # `.to_dict(flat=False)` e NÃO `.items()`: o mesmo nome pode chegar duas
        # vezes (o campo aparece em "Falta preencher" e em "Já preenchido"), e
        # `.items()` entrega só a PRIMEIRA ocorrência -- que é a caixa vazia.
        # Medido em 02/09/2026: salvar assim APAGAVA o valor que já estava lá.
        # Vale a última resposta com conteúdo; só apaga se todas vierem vazias.
        for chave, valores in request.form.to_dict(flat=False).items():
            if not chave.startswith("campo_"):
                continue
            nome = chave[len("campo_"):]
            if nome not in aceitos:
                app.logger.warning("campo desconhecido ignorado no POST: %r",
                                   nome)
                continue
            cheios = [(v or "").strip() for v in valores if (v or "").strip()]
            if cheios:
                campos[nome] = cheios[-1]
                respondidos.add(nome)
            else:
                # Campo esvaziado some do dicionário. Guardar "" seria dizer
                # que a resposta é vazia -- e ausente não é zero, que é a
                # armadilha medida no dado do OLX (fazenda de R$ 1.500).
                campos.pop(nome, None)
        faltando = _o_que_falta(campos)
        status = ("pronto" if not [c for c in faltando if c["obrigatorio"]]
                  else "rascunho")
        if linha.get("status") == "publicado":
            status = "publicado"      # já foi para o site; não volta a rascunho
        repo_salvar_campos(conn, captacao_id, campos, status)
    finally:
        conn.close()

    # Portão que FALA: se o Tel respondeu uma pergunta e ela continua sendo
    # cobrada, quem está errado somos nós -- e ele precisa saber disso agora, em
    # vez de digitar a mesma resposta a noite inteira. Foi exatamente o que a
    # pergunta `valor` fazia até 02/09/2026, sem uma linha de aviso.
    teimosos = sorted({c["rotulo"] for c in faltando
                       if c["nome"] in respondidos
                       or any(s["nome"] in respondidos
                              for s in c.get("subcampos") or ())})
    recado = "Salvei o que você preencheu."
    if teimosos:
        recado += (" MAS continuo cobrando " + ", ".join(teimosos)
                   + " mesmo depois da sua resposta -- isso é defeito nosso,"
                     " não seu. Me chame em vez de responder de novo.")
    return redirect(url_for("detalhe", captacao_id=captacao_id, msg=recado))


def variaveis_do_site():
    return tuple(getattr(captacao_site, "VARIAVEIS_NECESSARIAS", None)
                 or VARIAVEIS_DO_SITE_PADRAO)


def _mapa_do_site():
    return getattr(captacao_site, "MAPA_PROVISORIO", None)


def campos_para_o_site(campos):
    """O que vai no formulário do admin -- sem os campos que são só nossos.

    Os dois lados precisam concordar: se `anotacoes` entrar aqui,
    `captacao_site.cadastrar` recusa o cadastro inteiro ("não sei em que campo
    do formulário colocar"), porque lá também é portão fechado.

    `None` também sai, e por isso: `captacao_campos.traduzir` devolve a forma
    INTEIRA, com `None` no que o anúncio não trouxe -- então TODA captação
    nasce com a chave `caracteristicas`, que o mapa do formulário não tem.
    O `cadastrar` pula valor `None` na hora de montar o POST, mas confere as
    CHAVES antes disso -- então a chave vazia sozinha derrubava o cadastro.
    Medido em 02/09/2026: a pendência "O formulário do site não tem onde pôr:
    Características" aparecia em toda captação, sem ninguém ter escrito nada
    ali. Chave sem valor não é dado a mandar; é campo que ficou em branco.
    """
    return {n: v for n, v in campos.items()
            if n not in SO_NOSSOS and v is not None and v != ""}


def pendencias_para_publicar(linha, campos, faltando, fotos_urls=()):
    """O que ainda IMPEDE de mandar para o site. Cada item é um portão fechado.

    Existe para a tela poder dizer a VERDADE em vez de mostrar um botão que
    finge. Hoje nenhum item aqui é hipotético: a credencial do admin da Imob
    Easy não existe em lugar nenhum, e o mapa do formulário nunca foi
    conferido contra o admin de verdade -- e `captacao_site.cadastrar` recusa
    postar nas duas situações, porque o Rails DESCARTA EM SILÊNCIO o parâmetro
    que não conhece e o imóvel nasceria vazio, sem erro nenhum.
    """
    itens = []
    if captacao_site is None:
        itens.append("O módulo `captacao_site.py` ainda não existe -- é ele que "
                     "faz login no admin e preenche o cadastro.")
    for var in variaveis_do_site():
        if not os.environ.get(var):
            itens.append(f"A variável de ambiente `{var}` não está configurada: "
                         "é a credencial do admin da Imob Easy, e ela ainda "
                         "não foi levantada com o Tel.")

    mapa = _mapa_do_site()
    if mapa is not None and not getattr(mapa, "confirmado", False):
        itens.append("O mapa do formulário do admin nunca foi conferido contra "
                     "o admin de verdade -- ninguém abriu a tela de cadastro "
                     "logado ainda, então o nome real de cada campo é palpite. "
                     "Publicar assim gravaria o imóvel com os campos vazios e "
                     "SEM ERRO NENHUM.")
    if mapa is not None and getattr(mapa, "campos", None):
        desconhecidos = sorted(c for c in campos_para_o_site(campos)
                               if c not in mapa.campos)
        if desconhecidos:
            itens.append("O formulário do site não tem onde pôr: "
                         + ", ".join(_rotulo(c) for c in desconhecidos)
                         + ". O Rails jogaria fora sem avisar.")

    obrigatorios = [c["rotulo"] for c in faltando if c["obrigatorio"]]
    if obrigatorios:
        itens.append("Falta preencher: " + ", ".join(obrigatorios) + ".")

    if captacao_fotos is None:
        itens.append("O módulo `captacao_fotos.py` ainda não existe -- as fotos "
                     "não foram baixadas para o disco.")
    elif fotos_urls and not _fotos_em_disco(_pasta_da_linha(linha)):
        itens.append(
            f"Nenhuma das {len(fotos_urls)} fotos está no disco ainda. Baixar "
            "foto funciona até do servidor (só a leitura da página do OLX "
            "depende de IP liberado), então isto costuma ser pasta apagada.")
    return itens


def avisos_da_captacao(linha, fotos_urls=()):
    """Coisas que NÃO impedem de publicar, mas que ele precisa ver.

    Foto que faltou é o caso: bloquear a publicação inteira porque 2 de 16
    fotos não baixaram deixaria o imóvel fora do site por causa de uma URL
    morta. Avisar deixa a escolha com ele, que é quem sabe se aquela foto
    importa.
    """
    avisos = []
    if captacao_fotos is None or not fotos_urls:
        return avisos
    em_disco = len(_fotos_em_disco(_pasta_da_linha(linha)))
    if em_disco and em_disco < len(fotos_urls):
        avisos.append(f"{em_disco} das {len(fotos_urls)} fotos estão no disco. "
                      "Ao publicar eu tento baixar as que faltam de novo; se "
                      "não vierem, o imóvel vai com as que tiver.")
    return avisos


@app.route("/captacao/<int:captacao_id>/publicar", methods=["POST"])
def publicar(captacao_id):
    """Manda para o admin da Imob Easy: login, cadastro, fotos, conferência.

    A ORDEM importa e é a do `captacao_site`: `entrar` devolve a sessão logada,
    e `cadastrar` RECEBE essa sessão -- ele não faz login sozinho. Passar
    credencial no lugar da sessão foi o primeiro erro desta tela, e teria
    virado um "o site não aceitou" que não explicava nada.

    E de propósito NÃO escrevemos em `imoveis`: a varredura horária traz o
    imóvel do site para o banco da Nay sozinha, aos :17 de cada hora.
    """
    codigo = None
    conn = db.conectar()
    try:
        linha = _carregar(conn, captacao_id)
        # Portão contra o CLIQUE DUPLO, e ele fecha ANTES de qualquer chamada.
        # O botão some da tela quando a captação vira `publicado`, mas isso não
        # é proteção nenhuma: o cadastro no site demora, a página ainda está com
        # o botão na frente do Tel, e o segundo clique (ou o "voltar" do
        # navegador, ou o reenvio do formulário) manda o mesmo POST de novo.
        # Medido em 02/09/2026: dois POST seguidos = `cadastrar` chamado DUAS
        # vezes = dois imóveis iguais no site, sem desfazer -- e a varredura
        # horária traz os dois para a tabela `imoveis`. É o mesmo buraco que o
        # `postar_agora` do publicador já tem documentado no CLAUDE.md.
        if linha.get("status") == "publicado":
            return _pagina_erro(
                "Esta captação já está no site",
                ("Ela foi cadastrada"
                 + (f" com o código {linha['codigo_no_site']}" if linha.get("codigo_no_site") else "")
                 + " e eu não mandei de novo, senão o mesmo imóvel apareceria "
                   "duas vezes no site e não há como desfazer. Se o cadastro de "
                   "lá estiver errado, corrija no admin da Imob Easy."),
                voltar=url_for("detalhe", captacao_id=captacao_id),
            ), 409
        campos = _campos_de(linha)
        faltando = _o_que_falta(campos)
        urls = [f["url"] for f in repo_listar_fotos(conn, captacao_id)]
        pendencias = pendencias_para_publicar(linha, campos, faltando, urls)
        if pendencias:
            # NÃO chama o site. Falha fechado: sem a certeza de que dá para
            # publicar, não se tenta -- e a tela lista o que falta, item a
            # item, em vez de um "erro ao publicar" que não ensina nada.
            return render_template(
                "captacao_erro.html",
                titulo="Ainda não dá para publicar",
                detalhe="Estas coisas precisam existir antes -- nenhuma delas "
                        "foi tentada e nada foi enviado ao site:",
                itens=pendencias, csrf=session.get("csrf", ""),
                voltar=url_for("detalhe", captacao_id=captacao_id),
            ), 409

        # Chamada de novo de propósito: é idempotente (o que já está em disco
        # não vai à rede) e retenta o que faltou, então a lista que sai daqui
        # é a verdade do disco AGORA, na ordem do anúncio -- com a capa em
        # primeiro lugar, que é o que o site espera.
        relatorio = _baixar_fotos(urls, _pasta_da_linha(linha))
        repo_gravar_relatorio(conn, captacao_id, relatorio)
        arquivos = [f["arquivo"] for f in (relatorio or {}).get("fotos", [])]

        try:
            sessao = captacao_site.entrar()
            # `campos_para_o_site`, não `campos`: a anotação da conversa com o
            # proprietário é nossa e o formulário do admin não tem onde pôr.
            resultado = captacao_site.cadastrar(sessao,
                                                campos_para_o_site(campos),
                                                fotos=arquivos)
            codigo = (resultado or {}).get("codigo")
            if codigo and hasattr(captacao_site, "conferir"):
                # Ler de volta o que o site gravou. O Rails responde 200 com o
                # formulário redesenhado quando a validação reprova, e isso
                # PARECE ter dado certo -- conferir é o que separa os dois.
                captacao_site.conferir(sessao, codigo,
                                       enviado=campos_para_o_site(campos))
        except Exception as erro:
            # A mensagem de `FalhaNaCaptacao` é escrita para o Tel ler e diz em
            # que passo parou; ela pode ir para a tela. Qualquer OUTRA exceção
            # é interna e só o log a vê -- já houve neste projeto mensagem de
            # erro carregando a DATABASE_URL inteira, com senha dentro.
            app.logger.exception("falha ao cadastrar no site: captação %s",
                                 captacao_id)
            familia = getattr(captacao_site, "FalhaNaCaptacao", ())
            se_explica = isinstance(erro, familia) if familia else False
            recado = str(erro) if se_explica else (
                "O detalhe ficou no log. Nada indica que o imóvel foi criado, "
                "mas confira no admin antes de tentar de novo.")
            # `codigo_site` vai junto de propósito: o UPDATE grava a coluna
            # SEMPRE, e passar None aqui APAGAVA o código de um imóvel que está
            # no site -- medido em 02/09/2026. Perder o código é perder o único
            # ponteiro para o anúncio que se quer corrigir.
            repo_marcar(conn, captacao_id, "erro", erro=recado[:500],
                        codigo_site=linha.get("codigo_no_site"))
            return _pagina_erro(
                "Não deu para cadastrar no site",
                recado + " Marquei esta captação como erro; os dados e as "
                "fotos continuam salvos aqui.",
                voltar=url_for("detalhe", captacao_id=captacao_id),
            ), 502

        repo_marcar(conn, captacao_id, "publicado", codigo_site=codigo)
    finally:
        conn.close()

    return redirect(url_for(
        "detalhe", captacao_id=captacao_id,
        msg=("Cadastrado no site" + (f" com o código {codigo}." if codigo else ".")
             + " A varredura traz para o banco da Nay em até uma hora.")))


@app.template_filter("quando")
def _quando(valor):
    if not valor:
        return ""
    if isinstance(valor, datetime):
        return valor.strftime("%d/%m %H:%M")
    return str(valor)


if __name__ == "__main__":
    # debug=False deliberado: o debugger do Flask expõe traceback e permite
    # execução de código pela própria resposta HTTP.
    app.run(host="0.0.0.0", port=PORTA, debug=False, threaded=True)
