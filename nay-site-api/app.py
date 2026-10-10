"""API somente-leitura que alimenta o site estatico imob-easy com dados
reais do naydb.

Conecta com a role `nay_site_leitura`: SELECT liberado coluna a coluna,
so nas 4 tabelas que o site precisa (imoveis, imovel_fotos, condominios,
corretores) -- nada de mensagens, pendencias, proprietarios, telefone de
corretor. Mesmo com um bug de query aqui, o Postgres recusa fisicamente
ler o que nao foi liberado (testado antes do deploy).

Nunca escreve. `default_transaction_read_only=on` esta fixado na propria
role, nao so em codigo.
"""
import os
import re
from datetime import datetime, date
from decimal import Decimal
from zoneinfo import ZoneInfo

import psycopg2
import psycopg2.extras
import psycopg2.sql
from flask import Flask, Response, jsonify, request

DATABASE_URL = os.environ["DATABASE_URL"]
FUSO = ZoneInfo("America/Manaus")
HEARTBEAT_DIR = os.environ.get("HEARTBEAT_DIR", "/heartbeats")
CRONS = {
    "disparar_grade": ("Grade de postagem", 15),
    "disparar_lembretes": ("Lembretes de retorno", 15),
    "entregar_pendentes": ("Entrega do que ficou de mandar", 15),
    "ciclo_pendencias": ("Ciclo de pendências", 15),
}
# Role separada para o item unico + edicao (admin/imoveis-editar.html).
# So essa role tem UPDATE, e so nas colunas de negocio -- sem chave, sem
# vinculo de condominio, sem bookkeeping do sistema. Testado antes do
# deploy: UPDATE em codigo, DELETE, e escrita em outra tabela sao todos
# recusados pelo Postgres nessa role.
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
# Role nay_leitura (a mesma do nay-painel): SELECT em todas as tabelas,
# read-only forçado no banco. Reaproveitada aqui só pro navegador de
# tabelas -- nenhuma outra rota desse arquivo usa ela.
TABELAS_DATABASE_URL = os.environ.get("TABELAS_DATABASE_URL")
# Role dedicada, CRUD completo mas só na tabela site_proximos_passos --
# conteúdo do próprio site (o quadro "Próximos passos" do Início), não
# dado de negócio. Nenhum outro grant foi dado a ela.
CONTEUDO_DATABASE_URL = os.environ.get("CONTEUDO_DATABASE_URL")
# Role dedicada, SELECT/INSERT/DELETE só em site_listas (sem UPDATE --
# lista é um retrato imutável do momento em que foi criada).
LISTAS_DATABASE_URL = os.environ.get("LISTAS_DATABASE_URL")

app = Flask(__name__)

# Campos que o formulario de edicao pode gravar. Uma lista fixa aqui, e nao
# "o que o cliente mandar" -- mesmo que o front-end mande um campo a mais
# por engano ou bug, ele e ignorado antes de qualquer coisa chegar perto de
# SQL. Cada um marcado como sincronizado pelo site (a proxima varredura
# horaria pode sobrescrever) ou interno (o site nunca fornece isso, nunca
# sobrescrito por automacao -- ver Arquivos/25-guia.md).
CAMPOS_EDITAVEIS = {
    # sincronizados pelo site -- editar aqui e temporario se o site tiver
    # outro valor na proxima varredura
    "tipo": {"tipo": "texto", "sincronizado": True},
    "bairro": {"tipo": "texto", "sincronizado": True},
    "cidade": {"tipo": "texto", "sincronizado": True},
    "estado": {"tipo": "texto", "sincronizado": True},
    "logradouro": {"tipo": "texto", "sincronizado": True},
    "numero": {"tipo": "texto", "sincronizado": True},
    "complemento": {"tipo": "texto", "sincronizado": True},
    "cep": {"tipo": "texto", "sincronizado": True},
    "area_util": {"tipo": "numero", "sincronizado": True},
    "area_total": {"tipo": "numero", "sincronizado": True},
    "quartos": {"tipo": "inteiro", "sincronizado": True},
    "suites": {"tipo": "inteiro", "sincronizado": True},
    "banheiros": {"tipo": "inteiro", "sincronizado": True},
    "vagas": {"tipo": "inteiro", "sincronizado": True},
    "vagas_cobertas": {"tipo": "inteiro", "sincronizado": True},
    "sol": {"tipo": "texto", "sincronizado": True},
    "andar": {"tipo": "texto", "sincronizado": True},
    "valor_venda": {"tipo": "numero", "sincronizado": True},
    "valor_aluguel": {"tipo": "numero", "sincronizado": True},
    "taxa_condominio": {"tipo": "numero", "sincronizado": True},
    "iptu": {"tipo": "numero", "sincronizado": True},
    "mobilia": {"tipo": "texto", "sincronizado": True},
    "descricao": {"tipo": "texto", "sincronizado": True},
    "caracteristicas": {"tipo": "lista", "sincronizado": True},
    "publicado_no_site": {"tipo": "booleano", "sincronizado": True},
    # internos -- o site nunca toca, nunca sobrescrito pela varredura
    "disponivel": {"tipo": "booleano", "sincronizado": False},
    "bloqueado": {"tipo": "booleano", "sincronizado": False},
    "motivo_bloqueio": {"tipo": "texto", "sincronizado": False},
    # do site antigo, que o cadastro novo nao mostrava (28/09); captado_em e
    # "dd/mm/aaaa", como o site antigo escrevia
    "captado_por": {"tipo": "texto", "sincronizado": False},
    "captado_em": {"tipo": "texto", "sincronizado": False},
}

# OS CAMPOS DO SITE ANTIGO QUE O NOVO NAO TINHA (Pedro, 28/09: "ponha todos os
# campos do site antigo mas sem ser obrigatorio"). Moram em `imoveis.extras`,
# com o MESMO nome de chave da raspagem do site antigo -- a Nay ja le "incluso
# no aluguel" e "aceita financiamento" de la (migracao 157). O tipo diz como o
# valor e gravado: do jeito que o site antigo escrevia ("115 m2", "Sim").
EXTRAS_EDITAVEIS = {
    "salas": "inteiro",
    "andares": "inteiro",
    "elevadores": "inteiro",
    "lances de escada": "inteiro",
    "area construida": "m2",
    "tamanho do terreno": "m2",
    "frente": "m",
    "fundo": "m",
    "pe direito": "m",
    "tipo de cobertura": "texto",
    "incluso no aluguel": "texto",
    "garantia de aluguel": "texto",
    "aceita financiamento": "simnao",
    "permuta": "texto",
    "indicado por": "texto",
    "inspecionado por": "texto",
    # quais das `caracteristicas` são do CONDOMÍNIO (Pedro, 28/09: "na OLX fica
    # bem divididinho, quero assim"). A coluna continua com todas -- é nela que
    # a Nay procura "tem piscina?" --; esta chave só diz em que grupo cada uma
    # aparece. Sem ela, a tela separa por palavra (portaria, salão de festas...).
    "caracteristicas do condominio": "lista_texto",
}

# A UNIDADE e a LOCACAO ATUAL nunca saem pela rota aberta: so por
# /admin/api/imoveis/<codigo>/privado, que confere a senha (migracao 157).
# O numero do apartamento em `imovel_privado` e o que a Nay usa no endereco
# interno (motoboy); o locatario fica no schema `privado`, fora do public.
PRIVADO_UNIDADE = ("torre", "unidade", "bloco", "casa", "lote")
PRIVADO_FICHA = ("locatario_nome", "locatario_contato", "observacao_aluguel", "observacoes")
_SEM_VENCIMENTO = object()  # "o corpo nao falou do vencimento" (None apaga)

# O PROPRIETARIO DO IMOVEL (migracao 162). Pedro, 28/09: "a ultima etapa da
# captacao pela OLX, ja que a OLX nao da esses dados". Mora em `proprietarios`
# (a tabela do admin antigo) e o imovel aponta para ele em
# imoveis.proprietario_id E imovel_privado.proprietario_id -- e por este que a
# Nay acha o dono para pedir a visita (nai_proprietario_do_imovel).
PROPRIETARIO_CAMPOS = ("nome", "telefone", "email", "documento", "tratamento")


@app.after_request
def cors(resp):
    # Sem cookie/sessao -- CORS aberto e seguro aqui. Faltavam os headers
    # de preflight (Allow-Methods/Allow-Headers): o navegador manda um
    # OPTIONS antes de qualquer POST/PUT/DELETE com corpo JSON, e sem
    # esses dois o navegador bloqueia a requisição de verdade ANTES dela
    # sair -- por isso nenhum curl/node de teste pegava esse bug (eles
    # não fazem esse preflight).
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    # Cache SO na vitrine publica (lista de imoveis do site). Todo o resto
    # e tela de trabalho: com cache de 60s, depois de salvar a tela lia o
    # valor antigo e parecia que a mudanca tinha voltado (revisao 11/09).
    if request.method == "GET" and request.path == "/api/imoveis":
        resp.headers["Cache-Control"] = "public, max-age=60"
    elif "Cache-Control" not in resp.headers:
        # 06/10 (Pedro, "otimiza o /imoveis"): a rota que já disse quanto tempo pode guardar é respeitada
        # (imoveis-para-enviar 2 min, mapa/bairros 1 h, imoveis/opcoes 5 min). Este else apagava isso com
        # no-store, e o /imoveis baixava 220 KB da API a cada abertura. Quem não diz nada continua no-store.
        resp.headers["Cache-Control"] = "no-store"
    return resp


# A SENHA DO /admin PARA GRAVAR IMOVEL (28/09/2026). O PUT e o POST de
# /api/imoveis nao pediam senha nenhuma: qualquer um na internet mudava preco,
# descricao, tirava do site ou publicava -- e isso muda o que a Nay oferece. O
# editor passou a gravar pelo proprio dominio (imobeasy.online/admin/api/...),
# atras da senha do /admin, e esta e a mesma conferencia dos outros modulos
# (o hash do basicauth do Traefik, aqui dentro, porque este processo tambem
# atende api.imobeasy.online, que nao tem senha).
try:
    from passlib.context import CryptContext as _CryptContext
    _CTX_ADMIN = _CryptContext(schemes=["apr_md5_crypt", "bcrypt", "sha256_crypt"])
except Exception:  # noqa: BLE001
    _CTX_ADMIN = None


def senha_do_admin_confere():
    import base64
    import hmac
    # O PAINEL DE IMOVEIS DENTRO DO CRM (Pedro, 30/09/2026): o CRM serve a aba
    # de imoveis do site por um proxy dele, que confere o login do CRM e manda
    # este segredo de maquina no lugar da senha do /admin. O segredo SO abre as
    # rotas de IMOVEIS: treino, regras e o resto do admin continuam pedindo a
    # senha de gente. Segredo vazio = porta fechada.
    segredo = os.environ.get("CRM_PAINEL_SEGREDO", "")
    veio = request.headers.get("X-Painel-Crm", "")
    if (segredo and veio and request.path.startswith("/admin/api/imoveis")
            and hmac.compare_digest(veio, segredo)):
        return True
    htpasswd = os.environ.get("ADMIN_HTPASSWD", "")
    if ":" not in htpasswd or _CTX_ADMIN is None:
        return False
    usuario_ok, hash_ok = htpasswd.split(":", 1)
    cab = request.headers.get("Authorization", "")
    if not cab.startswith("Basic "):
        return False
    try:
        usuario, senha = base64.b64decode(cab[6:]).decode("utf-8").split(":", 1)
    except Exception:  # noqa: BLE001
        return False
    if not hmac.compare_digest(usuario, usuario_ok):
        return False
    try:
        return _CTX_ADMIN.verify(senha, hash_ok)
    except Exception:  # noqa: BLE001
        return False


def _sem_senha():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


def _inteiro(v, padrao):
    """Numero da query string; lixo ("NaN", "abc") vira o padrao em vez de erro 500."""
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return padrao


def conectar():
    conn = psycopg2.connect(DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def conectar_escrita():
    if not WRITE_DATABASE_URL:
        raise RuntimeError("WRITE_DATABASE_URL não configurada")
    conn = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def todas_linhas(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def conectar_listas():
    if not LISTAS_DATABASE_URL:
        raise RuntimeError("LISTAS_DATABASE_URL não configurada")
    conn = psycopg2.connect(LISTAS_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def conectar_conteudo():
    if not CONTEUDO_DATABASE_URL:
        raise RuntimeError("CONTEUDO_DATABASE_URL não configurada")
    conn = psycopg2.connect(CONTEUDO_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def conectar_tabelas():
    if not TABELAS_DATABASE_URL:
        raise RuntimeError("TABELAS_DATABASE_URL não configurada")
    conn = psycopg2.connect(TABELAS_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def mascarar_email(email):
    email = str(email or "")
    if "@" not in email:
        return email
    local, dominio = email.split("@", 1)
    if len(local) <= 2:
        return "••@" + dominio
    return local[:2] + "•••@" + dominio


def mascarar_cpf(cpf):
    digitos = re.sub(r"\D", "", str(cpf or ""))
    if len(digitos) < 6:
        return cpf
    return digitos[:3] + ".***.**-" + digitos[-2:]


COLUNAS_OCULTAS = ("senha", "password", "token", "secret", "client_token")


def mascarar_valor(coluna, valor):
    """Política genérica pro navegador de tabelas: mascara o que parece
    identificador pessoal pelo NOME da coluna (funciona em qualquer uma
    das 42 tabelas sem precisar conhecer cada uma), trunca texto longo,
    nunca deixa passar coluna que pareça credencial."""
    if valor is None:
        return None
    nome = coluna.lower()
    if any(p in nome for p in COLUNAS_OCULTAS):
        return "[oculto]"
    if nome == "telefone" or nome.endswith("_telefone"):
        return mascarar_telefone(valor)
    if "email" in nome:
        return mascarar_email(valor)
    if "cpf" in nome:
        return mascarar_cpf(valor)
    if isinstance(valor, str) and len(valor) > 200:
        return valor[:200] + "…"
    return valor


def serializar_valor(valor):
    if isinstance(valor, Decimal):
        return float(valor)
    if isinstance(valor, (datetime, date)):
        return valor.isoformat()
    return valor


def mascarar_telefone(tel):
    """Nunca manda o telefone inteiro pro navegador -- mascara já no
    servidor, não só na tela. '5592841234567' -> '5592••••567'."""
    tel = str(tel or "")
    if len(tel) <= 6:
        return tel
    return tel[:4] + "••••" + tel[-3:]


def formatar_reais(valor):
    if valor is None:
        return None
    inteiro = int(valor)
    texto = f"{inteiro:,}".replace(",", ".")
    centavos = f"{valor:.2f}".split(".")[1]
    return f"R$ {texto},{centavos}"


def formatar_endereco(row):
    partes = []
    if row.get("logradouro"):
        rua = row["logradouro"]
        if row.get("numero"):
            rua += f", {row['numero']}"
        partes.append(rua)
    endereco = " - ".join(partes) if partes else ""
    if row.get("bairro"):
        endereco = f"{endereco} - {row['bairro']}" if endereco else row["bairro"]
    return endereco or "Endereço não informado"


def formatar_quartos(row):
    q = row.get("quartos")
    if q is None:
        return "—"
    if row.get("suites"):
        plural = "suíte" if row["suites"] == 1 else "suítes"
        return f"{q} ({row['suites']} {plural})"
    return str(q)


def imovel_para_cartao(row, fotos_por_codigo):
    fotos = fotos_por_codigo.get(row["codigo"], [])
    capa = next((f["url"] for f in fotos if f["e_capa"]), None) or (fotos[0]["url"] if fotos else None)

    venda = row.get("valor_venda")
    aluguel = row.get("valor_aluguel")
    if venda:
        rotulo, preco = "Venda:", formatar_reais(venda)
    elif aluguel:
        rotulo, preco = "Aluguel:", formatar_reais(aluguel)
    else:
        rotulo, preco = "Valor:", "Consulte"

    return {
        "codigo": row["codigo"],
        "nome": row.get("condominio_nome") or row.get("tipo") or "Imóvel",
        "endereco": formatar_endereco(row),
        "complemento": row.get("complemento"),
        "area": f"{row['area_util']:.0f} m2" if row.get("area_util") else "—",
        "quartos": formatar_quartos(row),
        "banheiros": str(row["banheiros"]) if row.get("banheiros") is not None else "—",
        "garagem": str(row["vagas"]) if row.get("vagas") is not None else "—",
        "rotuloPreco": rotulo,
        "preco": preco,
        # URL absoluta de foto real (CDN do imobeasy.com) quando existe;
        # None quando o imóvel não tem foto cadastrada -- o site cai no
        # placeholder local nesse caso.
        "foto": capa,
        "pontos": len(fotos) or 1,
        "parceiro": bool(row.get("e_parceiro")),
    }


def buscar_fotos(conn, codigos):
    if not codigos:
        return {}
    linhas = todas_linhas(conn, """
        SELECT codigo, url, e_capa FROM imovel_fotos
        WHERE codigo = ANY(%s) ORDER BY codigo, ordem NULLS LAST
    """, (list(codigos),))
    por_codigo = {}
    for l in linhas:
        por_codigo.setdefault(l["codigo"], []).append(l)
    return por_codigo


@app.route("/api/imoveis")
def api_imoveis():
    finalidade = request.args.get("finalidade")  # venda | aluguel | None
    limit = min(int(request.args.get("limit", 60)), 200)
    apenas_publicados = request.args.get("todos") != "1"

    condicoes = []
    if apenas_publicados:
        condicoes.append("publicado_no_site = true AND disponivel = true")
    if finalidade == "venda":
        condicoes.append("valor_venda IS NOT NULL")
    elif finalidade == "aluguel":
        condicoes.append("valor_aluguel IS NOT NULL")
    # 05/10 (Pedro): os filtros de comprar/alugar eram só desenho. Cada um é opcional; sem nenhum,
    # a rota responde como sempre respondeu (a home e os destaques dependem disso).
    a, params = request.args, []
    bairros = [b.strip()[:60] for b in a.getlist("bairros") + a.getlist("bairro") if b and b.strip()][:20]
    if bairros:
        condicoes.append("nay_sem_acento(lower(coalesce(bairro, ''))) LIKE ANY "
                         "(SELECT '%%' || nay_sem_acento(lower(x)) || '%%' FROM unnest(%s::text[]) x)")
        params.append(bairros)
    tipo = str(a.get("tipo") or "").strip()[:60]
    if tipo and tipo != "Todos":
        condicoes.append("tipo = %s")
        params.append(tipo)
    condominio = str(a.get("condominio") or "").strip()[:80]
    if condominio:
        condicoes.append("nay_sem_acento(lower(coalesce(condominio_nome, ''))) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'")
        params.append(condominio)
    for nome, coluna in (("quartos", "quartos"), ("garagem", "vagas"), ("banheiros", "banheiros")):
        pedido = str(a.get(nome) or "").strip()
        n = re.sub(r"\D", "", pedido)[:2]
        if n:   # "4+" e o campo de banheiros são "a partir de"; 1, 2 e 3 são exatos
            condicoes.append(coluna + (" >= %s" if pedido.endswith("+") or nome == "banheiros" else " = %s"))
            params.append(int(n))
    valor = {"venda": "valor_venda", "aluguel": "valor_aluguel"}.get(finalidade, "coalesce(valor_venda, valor_aluguel)")
    for nome, sinal in (("valor_min", ">="), ("valor_max", "<=")):
        n = re.sub(r"\D", "", str(a.get(nome) or ""))[:12]
        if n:
            condicoes.append(valor + " " + sinal + " %s")
            params.append(int(n))
    where = ("WHERE " + " AND ".join(condicoes)) if condicoes else ""
    paginado = bool(a.get("pagina"))
    if paginado:
        limit = max(1, min(int(a.get("por") or 24), 60))
    salto = (max(1, int(a.get("pagina") or 1)) - 1) * limit if paginado else 0

    conn = conectar()
    try:
        linhas = todas_linhas(conn, f"""
            SELECT codigo, tipo, condominio_nome, bairro, logradouro, numero,
                   complemento, area_util, quartos, suites, banheiros, vagas,
                   valor_venda, valor_aluguel, e_parceiro, count(*) OVER () AS total
            FROM imoveis
            {where}
            ORDER BY criado_em DESC, codigo DESC
            LIMIT %s OFFSET %s
        """, tuple(params + [limit, salto]))
        fotos = buscar_fotos(conn, [l["codigo"] for l in linhas])
        itens = [imovel_para_cartao(l, fotos) for l in linhas]
        if paginado:
            total = linhas[0]["total"] if linhas else 0
            if not linhas and salto:   # página além do fim: o total ainda precisa vir certo
                total = todas_linhas(conn, f"SELECT count(*) AS n FROM imoveis {where}", tuple(params))[0]["n"]
            return jsonify({"total": total, "itens": itens})
        return jsonify(itens)
    finally:
        conn.close()


@app.route("/api/bairros")
def api_bairros():
    """Os bairros que tem imovel no ar, para a busca da home (Tel, 15/09:
    "quando a pessoa clica no bairro desce a lista com todos os bairros
    cadastrados, e conforme ela for digitando vai ficando so os que
    correspondem"). A lista e curta: o site baixa uma vez e filtra na tela,
    sem ir ao servidor a cada tecla.

    `?todos=1` traz tambem bairro de imovel fora do ar -- serve para o admin.
    """
    apenas_publicados = request.args.get("todos") != "1"
    condicoes = ["coalesce(btrim(bairro), '') <> ''"]
    if apenas_publicados:
        condicoes.append("publicado_no_site = true AND disponivel = true")
    where = "WHERE " + " AND ".join(condicoes)

    conn = conectar()
    try:
        linhas = todas_linhas(conn, f"""
            SELECT btrim(bairro) AS bairro,
                   count(*) AS imoveis,
                   count(*) FILTER (WHERE valor_venda IS NOT NULL) AS venda,
                   count(*) FILTER (WHERE valor_aluguel IS NOT NULL) AS aluguel
              FROM imoveis
              {where}
             GROUP BY btrim(bairro)
             ORDER BY btrim(bairro)
        """)
        return jsonify([dict(l) for l in linhas])
    finally:
        conn.close()


@app.route("/api/tipos")
def api_tipos():
    """Os tipos de imóvel que têm imóvel no ar, para o filtro de comprar/alugar e
    da home (05/10): a lista vem do banco, então só aparece tipo que existe."""
    conn = conectar()
    try:
        return jsonify([dict(l) for l in todas_linhas(conn, """
            SELECT btrim(tipo) AS tipo, count(*) AS imoveis,
                   count(*) FILTER (WHERE valor_venda IS NOT NULL) AS venda,
                   count(*) FILTER (WHERE valor_aluguel IS NOT NULL) AS aluguel
              FROM imoveis
             WHERE publicado_no_site = true AND disponivel = true AND coalesce(btrim(tipo), '') <> ''
             GROUP BY btrim(tipo) ORDER BY count(*) DESC, btrim(tipo)""")])
    finally:
        conn.close()


# ==========================================================================
# PAINEL DA NAY DE LOCAÇÃO (Tel, 15/09/2026): métricas de resposta e acesso à
# configuração dela -- prompt e regras. O que for salvo aqui vale na mensagem
# seguinte, porque o fluxo do n8n lê o prompt e a configuração do banco.
#
# Role própria (`nay_site_nai`): lê as views do painel, lê `nai_config` e
# `nai_prompt`, muda SÓ `nai_config.valor` e chama `nai_salvar_prompt`. Ela não
# enxerga mensagem de corretor nem telefone de ninguém.
# ==========================================================================
NAI_DATABASE_URL = os.environ.get("NAI_DATABASE_URL", "")

# Chaves que o painel pode mudar. Fora desta lista, o pedido é recusado -- é a
# mesma ideia do portão fechado do resto do projeto: só passa o que é esperado.
NAI_CHAVES_EDITAVEIS = {
    "modo", "pausada", "envio_simulado", "numeros_teste", "telefone_teste_destino",
    "janela_inicio", "janela_fim", "escala_sem_parar", "regra_publico",
    "tel_telefone", "aviso_motoboy_min", "dados_primeiro_lembrete_min",
    # a frase que ela diz ao proprietário na PRIMEIRA mensagem (Tel, 15/09):
    # editável porque é a cara da empresa com quem nunca falou com este número.
    "apresentacao_proprietario",
}


# As chaves da CAMPANHA DE CAPTAÇÃO que a aba pode mudar (Tel, 15/09). Ficam de
# fora, de propósito, os telefones (do Tel, de teste, do relatório) e o chat do
# Telegram: são endereço de gente, e trocar um deles por engano manda a campanha
# inteira para o lugar errado. Os carimbos `_cron_*` também não se editam --
# quem os escreve é o próprio cron, e são eles que mostram se ele está vivo.
CAPTACAO_CHAVES_EDITAVEIS = {
    "captacao_pausada", "resposta_pausada", "modo_teste",
    "limite_dia", "minutos_entre_disparos", "jitter_max_segundos",
    "janela_inicio", "janela_fim", "janela_inicio_fds", "janela_fim_fds",
    "pausa_inicio", "pausa_fim",
    "max_followup", "horas_primeiro_followup",
    "rampa_inicio", "rampa_passo", "rampa_maximo", "limite_api_dia", "limite_total_dia",
    "disjuntor_resposta_min", "disjuntor_sem_entrega",
}
# O VALOR tambem e conferido (28/09): "Nao" em captacao_pausada nao e "nao" --
# o fluxo lia como NAO pausado e a tela, como pausado.
CAPTACAO_VALORES = {"captacao_pausada": {"sim", "nao"}, "resposta_pausada": {"sim", "nao"},
                    "modo_teste": {"sim", "nao"}}
CAPTACAO_HORAS = {"janela_inicio", "janela_fim", "janela_inicio_fds", "janela_fim_fds", "pausa_inicio", "pausa_fim"}


def conectar_nai():
    if not NAI_DATABASE_URL:
        raise RuntimeError("NAI_DATABASE_URL não configurada")
    conn = psycopg2.connect(NAI_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


@app.route("/api/nai/estado")
def api_nai_estado():
    """Tudo o que a tela mostra de uma vez: configuração, prompts, métricas,
    o que a esteira de conferência fez e as últimas respostas."""
    conn = conectar_nai()
    try:
        config = todas_linhas(conn, """
            SELECT chave, valor, descricao FROM nai_config ORDER BY chave
        """)
        prompts = todas_linhas(conn, """
            SELECT papel, versao, length(texto) AS caracteres, atualizado_em, atualizado_por
              FROM nai_prompt ORDER BY papel
        """)
        return jsonify({
            "config": [dict(l, editavel=(l["chave"] in NAI_CHAVES_EDITAVEIS)) for l in config],
            "prompts": [dict(l) for l in prompts],
            "metricas": [dict(l) for l in todas_linhas(conn, "SELECT * FROM vw_nai_metricas_dia LIMIT 30")],
            "conferencias": [dict(l) for l in todas_linhas(conn, "SELECT * FROM vw_nai_conferencia_resumo")],
            "turnos": [dict(l) for l in todas_linhas(conn, "SELECT * FROM vw_nai_ultimos_turnos LIMIT 40")],
            # Por imóvel (Tel, 15/09): quantas vezes cada um foi oferecido e
            # quantas visitas saíram dele. Vem ordenado pelo mais movimentado,
            # que é como ele vai ler a tabela.
            "imoveis": [dict(l) for l in todas_linhas(conn, """
                SELECT * FROM vw_nai_metricas_imovel
                 ORDER BY vezes_mandado DESC, visitas_pedidas DESC, fotos_enviadas DESC
                 LIMIT 200
            """)],
        })
    finally:
        conn.close()


@app.route("/api/nai/config", methods=["PUT"])
def api_nai_config_salvar():
    dados = request.get_json(silent=True) or {}
    chave = str(dados.get("chave") or "").strip()
    valor = dados.get("valor")
    if chave not in NAI_CHAVES_EDITAVEIS:
        return jsonify({"ok": False, "erro": "essa configuração não é editável pelo painel"}), 400
    if valor is None:
        return jsonify({"ok": False, "erro": "valor é obrigatório"}), 400

    conn = conectar_nai()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE nai_config SET valor = %s WHERE chave = %s RETURNING chave, valor",
                        (str(valor).strip(), chave))
            linha = cur.fetchone()
        conn.commit()
        if not linha:
            return jsonify({"ok": False, "erro": "configuração não encontrada"}), 404
        return jsonify({"ok": True, "chave": linha["chave"], "valor": linha["valor"]})
    finally:
        conn.close()


@app.route("/api/nai/prompt/<papel>", methods=["GET", "PUT"])
def api_nai_prompt(papel):
    papel = (papel or "").strip().lower()
    # "captacao" entrou em 15/09: o prompt da campanha com proprietários passou a
    # morar na mesma tabela, com a mesma trava de versão e o mesmo histórico.
    if papel not in ("corretor", "proprietario", "motoboy", "captacao"):
        return jsonify({"ok": False, "erro": "papel desconhecido"}), 404

    conn = conectar_nai()
    try:
        if request.method == "GET":
            linhas = todas_linhas(conn, """
                SELECT papel, texto, versao, atualizado_em, atualizado_por
                  FROM nai_prompt WHERE papel = %s
            """, (papel,))
            if not linhas:
                return jsonify({"ok": False, "erro": "prompt não cadastrado"}), 404
            return jsonify(dict(linhas[0]))

        dados = request.get_json(silent=True) or {}
        texto = dados.get("texto") or ""
        versao = dados.get("versao")
        por = str(dados.get("por") or "painel")[:60]
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM nai_salvar_prompt(%s, %s, %s, %s)",
                        (papel, texto, versao, por))
            r = cur.fetchone()
        conn.commit()
        if not r["ok"]:
            # 409: alguém salvou antes; a tela mostra o motivo e a versão atual
            return jsonify({"ok": False, "erro": r["motivo"], "versao": r["versao"]}), 409
        return jsonify({"ok": True, "versao": r["versao"]})
    finally:
        conn.close()


# ==========================================================================
# FILA E BOTÃO DE PAUSA (Tel, 15/09/2026): "um botão de pausa e play e fila de
# mensagens lá para eu ver e poder parar manualmente lá no site".
#
# A pausa é a mesma chave que o comando PARAR ATENDIMENTO do WhatsApp mexe --
# um lugar só, para o site e o WhatsApp nunca discordarem sobre se ela está
# atendendo.
# ==========================================================================
@app.route("/api/nai/fila")
def api_nai_fila():
    """O que está na fila dos dois lados, e o que a porta decidiu para quem
    escreveu nas últimas 48h."""
    conn = conectar_nai()
    try:
        resumo = todas_linhas(conn, "SELECT * FROM vw_nai_fila_resumo")
        estado = todas_linhas(conn, """
            SELECT
              (SELECT valor FROM nai_config WHERE chave = 'pausada')       AS pausada,
              (SELECT valor FROM nai_config WHERE chave = 'modo')          AS modo,
              (SELECT valor FROM nai_config WHERE chave = 'regra_publico') AS regra_publico,
              (SELECT valor FROM nai_config WHERE chave = 'regra_publico_desde') AS regra_desde,
              (SELECT valor FROM nai_config WHERE chave = 'envio_simulado') AS envio_simulado
        """)
        return jsonify({
            "resumo": dict(resumo[0]) if resumo else {},
            "estado": dict(estado[0]) if estado else {},
            "fila": [dict(l) for l in todas_linhas(conn, "SELECT * FROM vw_nai_fila LIMIT 80")],
            "porta": [dict(l) for l in todas_linhas(conn, "SELECT * FROM vw_nai_porta LIMIT 40")],
        })
    finally:
        conn.close()


@app.route("/api/nai/envios")
def api_nai_envios():
    """Tudo que saiu pelo número da Nay de Locação, dizendo quem mandou."""
    conn = conectar_nai()
    try:
        r = todas_linhas(conn, "SELECT * FROM vw_nai_envios_resumo")
        return jsonify({
            "resumo": dict(r[0]) if r else {},
            "envios": [dict(l) for l in todas_linhas(conn,
                "SELECT * FROM vw_nai_envios LIMIT 120")],
        })
    finally:
        conn.close()


@app.route("/api/nai/captacao/envios")
def api_captacao_envios():
    """O mesmo, do número da captação."""
    conn = conectar_nai()
    try:
        r = todas_linhas(conn, "SELECT * FROM vw_captacao_envios_resumo")
        return jsonify({
            "resumo": dict(r[0]) if r else {},
            "envios": [dict(l) for l in todas_linhas(conn,
                "SELECT * FROM vw_captacao_envios LIMIT 120")],
        })
    finally:
        conn.close()


@app.route("/api/nai/pausa", methods=["PUT"])
def api_nai_pausa():
    """Para ou volta a atender. Corpo: {"pausar": true} ou {"pausar": false}."""
    dados = request.get_json(silent=True) or {}
    if "pausar" not in dados:
        return jsonify({"ok": False, "erro": "diga pausar: true ou false"}), 400
    valor = "sim" if dados.get("pausar") else "nao"
    conn = conectar_nai()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE nai_config SET valor = %s WHERE chave = 'pausada' RETURNING valor",
                (valor,))
            r = cur.fetchone()
        conn.commit()
        if not r:
            return jsonify({"ok": False, "erro": "chave de pausa não encontrada"}), 404
        return jsonify({
            "ok": True,
            "pausada": r["valor"],
            # o que dizer na tela: o que acontece com as mensagens enquanto parada
            "nota": ("Parada. As mensagens continuam chegando e ficam guardadas; "
                     "ela não responde ninguém até você dar play.")
                    if valor == "sim" else "Voltou a atender.",
        })
    finally:
        conn.close()


# ==========================================================================
# ABA DA NAY DE CAPTAÇÃO (Tel, 15/09/2026): "lá no nay locação cria outra tab
# em cima no mesmo menu, nay captação, e põe as coisas de captação lá".
#
# Só leitura do funil e das conversas, mais as regras da campanha. Nenhuma
# rota daqui escreve em lead nenhum: a campanha segue como está, o painel olha.
# ==========================================================================
@app.route("/api/nai/captacao")
def api_captacao_estado():
    """O funil, o dia a dia, as últimas conversas, o que foi captado e as regras."""
    conn = conectar_nai()
    try:
        resumo = todas_linhas(conn, "SELECT * FROM vw_captacao_resumo")
        config = todas_linhas(conn, """
            SELECT chave, valor, nota AS descricao FROM captacao_config ORDER BY chave
        """)
        return jsonify({
            "resumo": dict(resumo[0]) if resumo else {},
            "dias": [dict(l) for l in todas_linhas(conn, "SELECT * FROM vw_captacao_dia LIMIT 30")],
            "conversas": [dict(l) for l in todas_linhas(conn,
                "SELECT * FROM vw_captacao_conversas LIMIT 60")],
            "captados": [dict(l) for l in todas_linhas(conn,
                "SELECT * FROM vw_captacao_outros_imoveis LIMIT 40")],
            "config": [dict(l, editavel=(l["chave"] in CAPTACAO_CHAVES_EDITAVEIS))
                       for l in config],
        })
    finally:
        conn.close()


@app.route("/api/nai/captacao/conversas")
def api_captacao_conversas():
    """As conversas da captação INTEIRAS, balão a balão (Tel, 15/09/2026).

    A aba Conversas mostra só a última fala de cada lado, e era por isso que
    ele não achava o que procurava. Aqui vem o thread completo, com a triagem
    e o rascunho da mensagem ao lado. Só leitura: nada daqui envia mensagem.
    """
    conn = conectar_nai()
    try:
        leads = todas_linhas(conn, """
            SELECT * FROM vw_captacao_thread_leads
             ORDER BY prioridade NULLS LAST, ordem, ultima_em DESC NULLS LAST
        """)
        # Uma consulta só para as 775 mensagens, agrupadas aqui. Uma consulta
        # por conversa seriam 89 idas ao banco para montar uma tela.
        por_lead = {}
        for m in todas_linhas(conn, """
            SELECT * FROM vw_captacao_thread_msgs ORDER BY lead_id, id
        """):
            por_lead.setdefault(m["lead_id"], []).append(dict(m))
        return jsonify({
            "conversas": [dict(l, mensagens=por_lead.get(l["id"], []))
                          for l in leads],
        })
    finally:
        conn.close()


@app.route("/api/nai/captacao/config", methods=["PUT"])
def api_captacao_config_salvar():
    """Muda UMA regra da campanha. Chave fora da lista é recusada."""
    dados = request.get_json(silent=True) or {}
    chave = str(dados.get("chave") or "")
    valor = dados.get("valor")
    if chave not in CAPTACAO_CHAVES_EDITAVEIS:
        return jsonify({"ok": False, "erro": "essa regra não é editável por aqui"}), 400
    if valor is None or str(valor).strip() == "":
        return jsonify({"ok": False, "erro": "valor vazio"}), 400
    valor = str(valor).strip()
    if chave in CAPTACAO_VALORES:
        valor = valor.lower()
        if valor not in CAPTACAO_VALORES[chave]:
            return jsonify({"ok": False, "erro": "use sim ou nao"}), 400
    elif chave in CAPTACAO_HORAS:
        if not re.fullmatch(r"\d{2}:\d{2}", valor):
            return jsonify({"ok": False, "erro": "hora no formato 09:00"}), 400
    elif not valor.isdigit():
        return jsonify({"ok": False, "erro": "valor precisa ser número"}), 400
    conn = conectar_nai()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE captacao_config SET valor = %s WHERE chave = %s RETURNING chave, valor",
                (str(valor).strip(), chave))
            r = cur.fetchone()
        conn.commit()
        if not r:
            return jsonify({"ok": False, "erro": "regra não encontrada"}), 404
        return jsonify({"ok": True, "chave": r["chave"], "valor": r["valor"]})
    finally:
        conn.close()


@app.route("/api/condominios")
def api_condominios():
    """Lista de condominios. Antes cortava em 300 (os 61 ultimos em ordem
    alfabetica nunca apareciam) e so contava imovel disponivel com condo_id.
    Agora: ?q= (sem acento), ?page=&per=, e conta os imoveis ligados pelo id
    OU pelo mesmo nome, de todas as origens (vw_imoveis_todos)."""
    q = str(request.args.get("q") or "").strip()[:80]
    per = max(1, min(int(request.args.get("per") or 0) or 5000, 5000))
    page = max(1, int(request.args.get("page") or 1))
    conn = conectar()
    try:
        cond, params = "", []
        if q:
            cond = "WHERE nay_sem_acento(lower(c.nome || ' ' || coalesce(c.bairro, ''))) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'"
            params.append(q)
        linhas = todas_linhas(conn, """
            WITH v AS (SELECT codigo, condo_id, status, lower(nay_sem_acento(condominio)) AS cn
                         FROM vw_imoveis_todos WHERE status <> 'Excluído'),
                 cn AS (SELECT id, lower(nay_sem_acento(nome)) AS nn FROM condominios),
                 lig AS (SELECT cn.id, v.codigo, v.status FROM cn JOIN v ON v.condo_id = cn.id
                         UNION
                         SELECT cn.id, v.codigo, v.status FROM cn JOIN v ON v.condo_id IS NULL AND v.cn = cn.nn),
                 cont AS (SELECT c.id,
                                 count(lig.codigo) AS imoveis,
                                 count(lig.codigo) FILTER (WHERE lig.status = 'Disponível') AS disponiveis
                            FROM condominios c LEFT JOIN lig ON lig.id = c.id
                           GROUP BY c.id)
            SELECT c.id, c.nome, c.bairro, cont.imoveis, cont.disponiveis, count(*) OVER () AS total
            FROM condominios c JOIN cont ON cont.id = c.id
            """ + cond + """
            ORDER BY c.nome
            LIMIT %s OFFSET %s
        """, tuple(params + [per, (page - 1) * per]))
        return jsonify([{
            "id": l["id"],
            "total": l["total"],
            "disponiveis": l["disponiveis"],
            "bairro": l["bairro"],
            "nome": l["nome"],
            "endereco": l["bairro"] or "—",
            "imoveis": l["imoveis"],
            # sem dado real de "alerta"/"em revisão" no banco -- sempre falso,
            # não inventamos sinalização que o banco não tem.
            "alerta": False,
            "olho": False,
        } for l in linhas])
    finally:
        conn.close()


@app.route("/api/condominios/aba")
def api_condominios_aba():
    """A ABA CONDOMÍNIOS de Todos os imóveis (Pedro, 30/09/2026: "põe a aba
    condomínios listando tudo, também com as características que pegamos do site
    antigo"). Cada condomínio do cadastro, mais as fichas sem cadastro (migração
    210), com:
      * os imóveis ligados pelo id OU pelo nome (o mesmo de /api/condominios), ou
        pelos `nomes_no_imovel` da ficha;
      * a ficha (ano, construtora, torres, andares, lazer...), quando existe;
      * `antigo`: as características do condomínio lidas dos anúncios do site
        antigo (imovel_ficha), com quantos imóveis dele citam cada uma.
    Sem dado pessoal."""
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            WITH v AS (SELECT codigo, condo_id, status, lower(nay_sem_acento(condominio)) AS cn
                         FROM vw_imoveis_todos WHERE status <> 'Excluído'),
                 base AS (SELECT 'c' || c.id AS chave, c.id AS condo_id, c.nome, c.bairro, f.id AS ficha_id
                            FROM condominios c LEFT JOIN condominio_ficha f ON f.condominio_id = c.id
                          UNION ALL
                          SELECT 'f' || f.id, NULL, f.nome, f.bairro, f.id
                            FROM condominio_ficha f
                           WHERE f.condominio_id IS NULL OR NOT EXISTS (SELECT 1 FROM condominios c WHERE c.id = f.condominio_id)),
                 nomes AS (SELECT b.chave, lower(nay_sem_acento(b.nome)) AS cn FROM base b
                           UNION
                           SELECT b.chave, lower(nay_sem_acento(x)) FROM base b
                             JOIN condominio_ficha f ON f.id = b.ficha_id, unnest(f.nomes_no_imovel) x),
                 lig AS (SELECT b.chave, v.codigo, v.status FROM base b JOIN v ON v.condo_id = b.condo_id
                         UNION
                         SELECT n.chave, v.codigo, v.status FROM nomes n JOIN v ON v.condo_id IS NULL AND v.cn = n.cn),
                 cont AS (SELECT chave, count(*) AS imoveis,
                                 count(*) FILTER (WHERE status = 'Disponível') AS disponiveis
                            FROM lig GROUP BY chave),
                 carac AS (SELECT lig.chave, x AS item, count(DISTINCT lig.codigo) AS n
                             FROM lig JOIN imovel_ficha fi ON fi.codigo = lig.codigo,
                                  unnest(fi.caracteristicas_condominio) x
                            GROUP BY 1, 2),
                 antigo AS (SELECT chave, json_agg(json_build_object('item', item, 'n', n) ORDER BY n DESC, item) AS lista
                              FROM carac GROUP BY chave)
            SELECT b.chave, b.condo_id, b.nome, b.bairro,
                   coalesce(cont.imoveis, 0) AS imoveis, coalesce(cont.disponiveis, 0) AS disponiveis,
                   antigo.lista AS antigo,
                   CASE WHEN f.id IS NOT NULL THEN json_build_object(
                     'tipo', f.tipo, 'endereco', f.endereco, 'ano', f.ano_lancamento, 'construtora', f.construtora,
                     'revestimento', f.revestimento, 'torres', f.torres, 'andares', f.andares,
                     'aptos_por_andar', f.aptos_por_andar, 'elevador', f.elevador, 'unidades', f.unidades,
                     'lazer', f.lazer, 'fonte', f.fonte) END AS ficha
              FROM base b
              LEFT JOIN cont ON cont.chave = b.chave
              LEFT JOIN antigo ON antigo.chave = b.chave
              LEFT JOIN condominio_ficha f ON f.id = b.ficha_id
             ORDER BY (f.id IS NULL), lower(nay_sem_acento(b.nome))
        """)
        return jsonify([{
            "chave": l["chave"], "id": l["condo_id"], "nome": l["nome"], "bairro": l["bairro"],
            "imoveis": l["imoveis"], "disponiveis": l["disponiveis"],
            "antigo": l["antigo"] or [], "ficha": l["ficha"],
        } for l in linhas]), 200, {"Cache-Control": "public, max-age=120"}
    finally:
        conn.close()


# =====================================================================
# O CADASTRO DE CONDOMÍNIO (Pedro, 08/10/2026, migração 322)
#
# "quero uma aba nova adicionar condomínio ... e lá na lista quando se digita um
# nome desça a lista filtrando letra a letra em todos os filtros dos
# condomínios, quero o cadastro de condomínio no site normal aba imóveis e no
# crm também" e "todo condomínio vai ter endereço fixo".
#
#   GET  /api/condominios/nomes               todos, só id/nome/bairro: é o que os
#        campos de condomínio leem UMA vez para filtrar na tela, letra a letra
#   GET  /admin/api/imoveis/condominios       todos, com a ficha (para a aba)
#   POST /admin/api/imoveis/condominios       cria   } site_condominio_salvar:
#   PUT  /admin/api/imoveis/condominios/<id>  edita  } o que veio VALE, vazio apaga
#
# As rotas de escrita ficam debaixo de /admin/api/imoveis de propósito: é o único
# pedaço do admin que a aba Imóveis do CRM deixa passar (crm/src/lib/painelDoSite.ts).
# =====================================================================
CAMPOS_DO_CONDOMINIO = ("nome", "tipo", "bairro", "logradouro", "numero", "cidade", "estado", "cep", "torres",
                        "andares", "aptos_por_andar", "elevador", "unidades", "construtora", "revestimento",
                        "ano_lancamento")


@app.route("/api/condominios/nomes")
def api_condominios_nomes():
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT id, nome, bairro FROM condominios ORDER BY lower(nay_sem_acento(nome)), id")
        return jsonify([{"id": l["id"], "nome": l["nome"], "bairro": l["bairro"]} for l in linhas]), 200, {
            # sem guardar: o condomínio que acabou de ser cadastrado tem de aparecer no campo seguinte
            "Cache-Control": "no-cache"}
    finally:
        conn.close()


@app.route("/admin/api/imoveis/condominios")
def api_condominios_cadastro():
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            -- pelo id OU pelo nome (09/10): 3.765 imóveis estão ligados só pelo nome, e a tela dizia "nenhum
            -- imóvel ligado" para quase todo condomínio. Contado UMA vez, não por condomínio (por linha passava de 5 s).
            WITH n AS (SELECT condo_id, CASE WHEN condo_id IS NULL THEN lower(nay_sem_acento(btrim(condominio_nome))) END AS nn
                         FROM imoveis),
                 por_id AS (SELECT condo_id, count(*) AS q FROM n WHERE condo_id IS NOT NULL GROUP BY 1),
                 por_nome AS (SELECT nn, count(*) AS q FROM n WHERE nn IS NOT NULL GROUP BY 1)
            SELECT c.id, c.nome, c.bairro, f.tipo, f.logradouro, f.numero, f.cidade, f.estado, f.cep, f.endereco,
                   f.torres, f.andares, f.aptos_por_andar, f.elevador, f.unidades, f.construtora, f.revestimento,
                   f.ano_lancamento, f.lazer, f.fonte, f.atualizado_em,
                   coalesce(pi.q, 0) + coalesce(pn.q, 0) AS imoveis
              FROM condominios c LEFT JOIN condominio_ficha f ON f.condominio_id = c.id
              LEFT JOIN por_id pi ON pi.condo_id = c.id
              LEFT JOIN por_nome pn ON pn.nn = lower(nay_sem_acento(btrim(c.nome)))
             ORDER BY lower(nay_sem_acento(c.nome)), c.id""")
        return jsonify({"itens": [{
            "id": l["id"], "nome": l["nome"], "bairro": l["bairro"], "tipo": l["tipo"] or "apartamentos",
            "logradouro": l["logradouro"], "numero": l["numero"], "cidade": l["cidade"], "estado": l["estado"],
            "cep": l["cep"], "endereco": l["endereco"], "torres": l["torres"], "andares": l["andares"],
            "aptos_por_andar": l["aptos_por_andar"], "elevador": l["elevador"], "unidades": l["unidades"],
            "construtora": l["construtora"], "revestimento": l["revestimento"], "ano_lancamento": l["ano_lancamento"],
            "lazer": list(l["lazer"] or []), "fonte": l["fonte"], "imoveis": l["imoveis"],
            "atualizado": l["atualizado_em"].isoformat() if l["atualizado_em"] else None,
        } for l in linhas], "total": len(linhas)})
    finally:
        conn.close()


@app.route("/admin/api/imoveis/condominios", methods=["POST"])
@app.route("/admin/api/imoveis/condominios/<int:cid>", methods=["PUT"])
def api_condominio_salvar(cid=None):
    if not senha_do_admin_confere():
        return _sem_senha()
    corpo = request.get_json(silent=True)
    if not isinstance(corpo, dict):
        return jsonify({"ok": False, "motivo": "faltaram os dados do condomínio"}), 400
    dados = {k: ("" if corpo[k] is None else str(corpo[k]))[:300] for k in CAMPOS_DO_CONDOMINIO if k in corpo}
    if isinstance(corpo.get("lazer"), list):
        dados["lazer"] = [str(x)[:80] for x in corpo["lazer"] if str(x or "").strip()][:80]
    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT site_condominio_salvar(%s, %s) AS r", (cid, psycopg2.extras.Json(dados)))
            r = cur.fetchone()["r"] or {}
        conn.commit()
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"ok": False, "motivo": str(exc).strip().splitlines()[0][:200]}), 400
    finally:
        conn.close()
    if not r.get("ok"):
        # nome repetido devolve o id do que já existe: a tela oferece abrir aquele
        return jsonify(r), (409 if r.get("id") else 400)
    return jsonify(r)


@app.route("/api/anuncios")
def api_anuncios():
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            SELECT codigo, condominio_nome, valor_venda, valor_aluguel,
                   publicado_no_site
            FROM imoveis
            ORDER BY criado_em DESC
            LIMIT 100
        """)
        saida = []
        for l in linhas:
            if l["valor_venda"]:
                tipo, valor = "Venda", f"Venda: {formatar_reais(l['valor_venda'])}"
            elif l["valor_aluguel"]:
                tipo, valor = "Aluguel", f"Aluguel: {formatar_reais(l['valor_aluguel'])}"
            else:
                tipo, valor = "—", "Consulte"
            saida.append({
                "destaque": False,
                "status": "Publicado" if l["publicado_no_site"] else "Rascunho",
                "codigo": str(l["codigo"]),
                "referencia": l["condominio_nome"] or "—",
                "tipo": tipo,
                # não existe característica "aceita financiamento" mapeada
                # no banco -- "—" em vez de chutar Sim/Não.
                "financia": "—",
                "valor": valor,
            })
        return jsonify(saida)
    finally:
        conn.close()


@app.route("/api/imoveis-admin")
def api_imoveis_admin():
    """Formato de tabela (admin/imoveis.html) -- diferente do cartão público.

    De propósito sem coluna de proprietário: a tabela `proprietarios` tem
    telefone e e-mail reais, e essa tela do site não tem login. Ver
    conversa/README para a decisão de não ligar isso ainda.
    """
    limit = min(int(request.args.get("limit", 100)), 300)
    de, ate = periodo_da_query()
    tipo = request.args.get("tipo")  # "casa" | "apartamento" | None (todos)

    condicoes = []
    params = []
    if de:
        condicoes.append("ct.vencimento >= %s")
        params.append(de)
    if ate:
        condicoes.append("ct.vencimento <= %s")
        params.append(ate)
    if tipo == "casa":
        condicoes.append("i.tipo ILIKE 'Casa%%'")
    elif tipo == "apartamento":
        condicoes.append("(i.tipo ILIKE 'Apartamento%%' OR i.tipo IN ('Cobertura', 'Flat'))")
    junta_contrato = "JOIN" if (de or ate) else "LEFT JOIN"
    where = ("WHERE " + " AND ".join(condicoes)) if condicoes else ""
    params.append(limit)

    conn = conectar()
    try:
        linhas = todas_linhas(conn, f"""
            SELECT i.codigo, i.condominio_nome, i.bairro, i.logradouro, i.numero,
                   i.valor_venda, i.valor_aluguel, i.disponivel, i.publicado_no_site,
                   ct.vencimento AS contrato_vencimento
            FROM imoveis i
            {junta_contrato} contratos_locacao ct ON ct.codigo = i.codigo::text
            {where}
            ORDER BY i.criado_em DESC
            LIMIT %s
        """, params)
        saida = []
        for l in linhas:
            if not l["disponivel"]:
                status = "Indisponível"
            elif not l["publicado_no_site"]:
                status = "Rascunho"
            else:
                status = "Disponível"

            if l["valor_venda"]:
                valor = f"Venda: {formatar_reais(l['valor_venda'])}"
            elif l["valor_aluguel"]:
                valor = f"Aluguel: {formatar_reais(l['valor_aluguel'])}"
            else:
                valor = "Consulte"

            saida.append({
                "codigo": str(l["codigo"]),
                "status": status,
                "financia": "—",
                "valor": valor,
                "condominio": l["condominio_nome"] or "",
                "endereco": formatar_endereco(l),
                "proprietario": "",
                "vencimento": l["contrato_vencimento"].isoformat() if l.get("contrato_vencimento") else None,
            })
        return jsonify(saida)
    finally:
        conn.close()


@app.route("/api/imoveis/<int:codigo>")
def api_imovel_detalhe(codigo):
    """Todos os campos do imóvel para a tela de edição -- via role de
    escrita porque ela já tem SELECT nesses campos a mais (descrição,
    IPTU, mobília, campos internos) que a role pública de listagem não
    precisa e por isso não tem."""
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, """
            SELECT codigo, tipo, status, condo_id, condominio_nome, bairro, cidade,
                   estado, logradouro, numero, complemento, cep, area_util,
                   area_total, quartos, suites, banheiros, vagas,
                   vagas_cobertas, sol, andar, valor_venda, valor_aluguel,
                   taxa_condominio, iptu, mobilia, descricao, caracteristicas,
                   publicado_no_site, disponivel, bloqueado, motivo_bloqueio,
                   e_parceiro, criado_em, sincronizado_em, captado_por, captado_em,
                   extras
            FROM imoveis WHERE codigo = %s
        """, (codigo,))
        if not linhas:
            return jsonify({"erro": "não encontrado"}), 404
        item = linhas[0]
        for campo in ("valor_venda", "valor_aluguel", "taxa_condominio", "iptu", "area_util", "area_total"):
            if item.get(campo) is not None:
                item[campo] = float(item[campo])
        for campo in ("criado_em", "sincronizado_em"):
            if item.get(campo) is not None:
                item[campo] = item[campo].isoformat()
        # So as chaves da lista: o extras da raspagem tambem guarda torre e
        # apartamento, e esta rota responde sem senha.
        extras = item.get("extras") or {}
        item["extras"] = {k: extras[k] for k in EXTRAS_EDITAVEIS if extras.get(k) not in (None, "")}
        item["campos_editaveis"] = CAMPOS_EDITAVEIS
        item["extras_editaveis"] = EXTRAS_EDITAVEIS
        return jsonify(item)
    finally:
        conn.close()


def _card_do_imovel(conn, codigo):
    """O card + as fotos de um imovel, do jeito que a Nay manda.

    Reusa `nai_card_do_imovel` e `nai_imagens_do_envio` -- as MESMAS funcoes do
    envio de verdade. Escrever um card novo aqui daria dois cards diferentes
    para o mesmo imovel, e o do CRM envelheceria calado.

    A COLAGEM FICA DE FORA. A metadinha de 4 fotos e so dos grupos desde 14/09
    (pedido do Tel); num envio de um para um vao as fotos soltas.
    """
    linhas = todas_linhas(conn, "SELECT texto_pronto, qtd_fotos FROM nai_card_do_imovel(%s)", (codigo,))
    if not linhas or not linhas[0]["texto_pronto"]:
        return None
    card = linhas[0]

    fotos = todas_linhas(conn, "SELECT url, e_colagem FROM nai_imagens_do_envio(%s)", (codigo,))
    urls = [f["url"] for f in fotos if f["url"] and not f["e_colagem"]]
    # A metadinha vai SEPARADA, so para quem mostra o post dos grupos (admin ›
    # Grupos, 03/10): um envio de um para um continua usando so `fotos`.
    colagem = todas_linhas(conn, "SELECT url FROM imovel_colagem WHERE codigo = %s", (codigo,))

    resumo = todas_linhas(conn, """
        SELECT codigo, status, tipo, condominio, bairro, endereco, quartos, suites,
               banheiros, vagas, area_total, valor_venda, valor_aluguel, financia,
               e_parceiro, publicado_no_site, fotos AS total_fotos, capa,
               proprietario_nome
          FROM vw_imoveis_todos WHERE codigo = %s
    """, (codigo,))
    r = dict(resumo[0]) if resumo else {"codigo": codigo}
    for campo in ("valor_venda", "valor_aluguel", "area_total"):
        if r.get(campo) is not None:
            r[campo] = float(r[campo])

    return {
        "codigo": codigo,
        "card": card["texto_pronto"],
        "qtd_fotos": int(card["qtd_fotos"] or 0),
        "fotos": urls,
        "colagem": (colagem[0]["url"] or None) if colagem else None,
        "imovel": r,
        # A parede do parceiro NAO bloqueia aqui: quem manda e uma pessoa, nao a
        # Nay. Mas a bandeira vai junto, em cima, para a tela avisar antes.
        "e_parceiro": bool(r.get("e_parceiro")),
        "no_site": bool(r.get("publicado_no_site")),
    }


@app.route("/api/imovel-card/<int:codigo>")
def api_imovel_card(codigo):
    """O card pronto de um imovel, para o CRM mandar numa conversa.

    Tel, 27/09/2026: "se alguem quiser buscar imoveis para la e ja enviar para
    uma conversa ele pode so referenciar /codigo que ja vai as fotos e o card do
    imovel para o contato".
    """
    conn = conectar_tabelas()
    try:
        d = _card_do_imovel(conn, codigo)
        if not d:
            return jsonify({"erro": "imovel nao encontrado"}), 404
        return jsonify(d)
    finally:
        conn.close()


@app.route("/api/mensagem-imovel")
def api_mensagem_imovel():
    """De qual imovel fala a mensagem que a pessoa MARCOU no WhatsApp?

    Tel, 27/09/2026: "se alguem marcar uma mensagem de um imovel disparado no
    grupo vai aparecer encima da mensagem um popup com o imovel".

    A Z-API so manda o `referenceMessageId` -- o id da mensagem marcada, sem o
    conteudo dela. Quem sabe de qual imovel aquela mensagem era e a CAIXA DE
    SAIDA: `nai_saida` guarda o `message_id` de cada envio junto com o `codigo`
    do imovel. E o caminho exato, sem adivinhar por texto.

    Se a caixa de saida nao souber (mensagem antiga, ou de fora do fluxo), cai
    no texto da mensagem em `mensagens` e procura o codigo ali. Nao achando
    nada, devolve 404 -- a tela entao nao mostra popup, em vez de mostrar o
    imovel errado.
    """
    mid = str(request.args.get("id") or "").strip()[:80]
    if not mid:
        return jsonify({"erro": "falta o id da mensagem"}), 400

    conn = conectar_tabelas()
    try:
        linhas = todas_linhas(conn, """
            SELECT codigo FROM nai_saida
             WHERE message_id = %s AND codigo IS NOT NULL
             ORDER BY criado_em DESC LIMIT 1
        """, (mid,))
        codigo = linhas[0]["codigo"] if linhas else None

        if codigo is None:
            # O texto da mensagem, procurando "Codigo: NNNN" ou codigo solto.
            linhas = todas_linhas(conn, """
                SELECT (regexp_match(texto, 'C(?:o|ó)digo:?\\s*([0-9]{3,5})', 'i'))[1] AS cod
                  FROM mensagens WHERE message_id = %s AND texto IS NOT NULL
                 ORDER BY criada_em DESC LIMIT 1
            """, (mid,))
            if linhas and linhas[0]["cod"]:
                codigo = int(linhas[0]["cod"])

        if codigo is None:
            return jsonify({"erro": "nao sei de qual imovel essa mensagem fala"}), 404

        d = _card_do_imovel(conn, int(codigo))
        if not d:
            return jsonify({"erro": "imovel nao encontrado", "codigo": codigo}), 404
        return jsonify(d)
    finally:
        conn.close()


@app.route("/api/imoveis/<int:codigo>/fotos")
def api_imovel_fotos(codigo):
    """As fotos de um imovel, na ordem, a capa primeiro. E o que a gaveta da
    tela de Imoveis abre quando alguem clica na linha -- antes nao havia de
    onde tirar isso: `/api/imoveis/<codigo>` traz os campos do imovel e nao
    as fotos."""
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            SELECT url, coalesce(e_capa, false) AS e_capa, e_fachada
              FROM imovel_fotos
             WHERE codigo = %s AND coalesce(url, '') <> ''
             -- sem `id` no desempate: a role do site tem SELECT coluna por
             -- coluna em imovel_fotos e `id` nao esta entre elas (de proposito).
             ORDER BY e_capa DESC, ordem NULLS LAST, url
        """, (codigo,))
        return jsonify({"codigo": codigo, "total": len(linhas),
                        "fotos": [{"url": l["url"], "capa": l["e_capa"], "fachada": l["e_fachada"]}
                                  for l in linhas]})
    finally:
        conn.close()


# O NÚMERO DO FORMULÁRIO, lido de um jeito só (numeros.py, 03/10/2026): "750.000" é 750000, e venda
# abaixo de R$ 10 mil ou aluguel abaixo de R$ 100 é erro de digitação, não valor.
from numeros import numero_br as _numero_br, valor_que_nao_existe as _valor_que_nao_existe  # noqa: E402


@app.route("/api/imoveis/<int:codigo>", methods=["PUT"])
@app.route("/admin/api/imoveis/<int:codigo>", methods=["PUT"])
def api_imovel_salvar(codigo):
    if not senha_do_admin_confere():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    sets = []
    valores = []
    erros = []

    # CONDOMINIO: escolhido na lista (etiqueta), grava o id; o nome sai da
    # tabela condominios -- nunca o texto que veio do navegador.
    if "condo_id" in corpo:
        cid = corpo.get("condo_id")
        if cid in (None, ""):
            sets.append(psycopg2.sql.SQL("condo_id = NULL"))
        else:
            try:
                cid = int(cid)
            except (TypeError, ValueError):
                return jsonify({"erro": "validação", "detalhes": ["condo_id: valor inválido"]}), 400
            sets.append(psycopg2.sql.SQL("condo_id = %s"))
            valores.append(cid)
            sets.append(psycopg2.sql.SQL("condominio_nome = (SELECT nome FROM condominios WHERE id = %s)"))
            valores.append(cid)

    # A SITUAÇÃO (28/09, Pedro: "o status do imóvel nem tá dando pra editar
    # direito"). Ela manda em duas outras coisas, pela regra do Tel de 27/09:
    # nosso e Disponível fica no site e na Nay; qualquer outra situação sai dos
    # dois. Sem isso, marcar "Alugado" deixava a Nay oferecendo o imóvel.
    # `publicado_no_site` mandado junto, de propósito, vale mais que a regra.
    status_novo = None
    if "status" in corpo:
        status_novo = str(corpo.get("status") or "").strip()
        if status_novo not in STATUS_EDITAVEIS:
            return jsonify({"erro": "validação", "detalhes": ["status: use " + ", ".join(STATUS_EDITAVEIS)]}), 400
        sets.append(psycopg2.sql.SQL("status = %s"))
        valores.append(status_novo)
        sets.append(psycopg2.sql.SQL("disponivel = %s"))
        valores.append(status_novo == "Disponível")
        if "publicado_no_site" not in corpo:
            sets.append(psycopg2.sql.SQL("publicado_no_site = (%s AND NOT coalesce(e_parceiro, false))"))
            valores.append(status_novo == "Disponível")

    # A TRAVA (28/09, Pedro: "a não ser que o Tel tenha mudado em uma data
    # posterior"): o que se decide à mão aqui -- situação ou "no site" -- a
    # leitura diária do site antigo não desfaz. Sem ela, o imóvel posto
    # Disponível no admin novo e que não está no .com saía do ar na manhã
    # seguinte (sincronizar_catalogo.py despublica o que não acha lá).
    if status_novo is not None or "publicado_no_site" in corpo:
        sets.append(psycopg2.sql.SQL("travado = true, travado_motivo = %s, travado_em = now()"))
        valores.append("mudado à mão no admin novo")

    for campo, valor in corpo.items():
        regra = CAMPOS_EDITAVEIS.get(campo)
        if not regra:
            continue  # ignora silenciosamente qualquer campo fora da lista
        if campo == "disponivel" and status_novo is not None:
            continue  # quem decide é a situação, logo acima

        if valor is None:
            sets.append(psycopg2.sql.SQL("{} = %s").format(psycopg2.sql.Identifier(campo)))
            valores.append(None)
            continue

        try:
            if regra["tipo"] == "numero":
                numero = _numero_br(valor)
                absurdo = _valor_que_nao_existe(campo, numero)
                if absurdo:
                    erros.append(absurdo)
                    continue
                valores.append(numero)
            elif regra["tipo"] == "inteiro":
                valores.append(int(valor))
            elif regra["tipo"] == "booleano":
                valores.append(bool(valor))
            elif regra["tipo"] == "lista":
                if not isinstance(valor, list):
                    raise ValueError
                valores.append([str(v) for v in valor])
            else:  # texto
                valores.append(str(valor))
        except (TypeError, ValueError):
            erros.append(f"{campo}: valor inválido")
            continue

        sets.append(psycopg2.sql.SQL("{} = %s").format(psycopg2.sql.Identifier(campo)))

    # os campos do site antigo (extras) e a parte privada (unidade, locacao)
    apagar, gravar = _extras_do_corpo(corpo, erros)
    if apagar or gravar:
        sets.append(psycopg2.sql.SQL("extras = (coalesce(extras, '{}'::jsonb) - %s::text[]) || %s::jsonb"))
        valores.append(apagar)
        valores.append(psycopg2.extras.Json(gravar))
    unidade, ficha, vencimento = _privado_do_corpo(corpo, erros)
    dono, dono_novo = _proprietario_do_corpo(corpo)

    if erros:
        return jsonify({"erro": "validação", "detalhes": erros}), 400
    if not sets and not unidade and not ficha and vencimento is _SEM_VENCIMENTO and dono is None:
        return jsonify({"erro": "nenhum campo editável enviado"}), 400

    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            if sets:
                query = psycopg2.sql.SQL("UPDATE imoveis SET {} WHERE codigo = %s").format(
                    psycopg2.sql.SQL(", ").join(sets)
                )
                cur.execute(query, valores + [codigo])
                existe = cur.rowcount > 0
            else:
                cur.execute("SELECT 1 FROM imoveis WHERE codigo = %s", (codigo,))
                existe = cur.fetchone() is not None
            if not existe:
                conn.rollback()
                return jsonify({"erro": "não encontrado"}), 404
            _gravar_privado(cur, codigo, unidade, ficha, vencimento)
            pid = _gravar_proprietario(cur, codigo, dono, dono_novo)
            _guardar_no_condominio(cur, codigo, corpo, gravar)
        conn.commit()
        resposta = {"status": "salvo", "codigo": codigo, "proprietario_id": pid}
        if dono is not None:   # o dono como ficou gravado (pode ter ligado a quem já era dono)
            resposta["proprietario"] = _proprietario_do_imovel(conn, codigo)
        return jsonify(resposta)
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


def _extra_normalizado(tipo, valor):
    """O valor do jeito que o site antigo gravava no extras; None apaga a chave."""
    if valor is None:
        return None
    txt = str(valor).strip()
    if not txt:
        return None
    if tipo == "inteiro":
        return str(int(float(txt.replace(",", "."))))
    if tipo in ("m2", "m"):
        achado = re.search(r"\d+(?:[.,]\d+)?", txt)
        if not achado:
            raise ValueError
        n = float(achado.group(0).replace(",", "."))
        return ("%.2f" % n).rstrip("0").rstrip(".") + (" m2" if tipo == "m2" else " m")
    if tipo == "simnao":
        baixo = txt.lower()
        if baixo in ("sim", "s", "true", "1"):
            return "Sim"
        if baixo in ("não", "nao", "n", "false", "0"):
            return "Não"
        raise ValueError
    if tipo == "lista_texto":   # "A, B, A" -> "A, B" (o jeito do site antigo)
        itens = []
        for item in re.split(r"[,\n]", txt):
            item = item.strip()
            if item and item not in itens:
                itens.append(item)
        return ", ".join(itens)[:2000] or None
    return txt[:500]


def _extras_do_corpo(corpo, erros):
    """(chaves a apagar, chaves a gravar) de corpo["extras"]. Chave fora de
    EXTRAS_EDITAVEIS e ignorada, igual aos campos de coluna."""
    apagar, gravar = [], {}
    extras = corpo.get("extras")
    if not isinstance(extras, dict):
        return apagar, gravar
    for chave, valor in extras.items():
        tipo = EXTRAS_EDITAVEIS.get(chave)
        if not tipo:
            continue
        try:
            v = _extra_normalizado(tipo, valor)
        except (TypeError, ValueError):
            erros.append(f"{chave}: valor inválido")
            continue
        if v is None:
            apagar.append(chave)
        else:
            gravar[chave] = v
    return apagar, gravar


def _privado_do_corpo(corpo, erros):
    """(unidade, ficha, vencimento) de corpo["privado"]. O vencimento volta
    _SEM_VENCIMENTO quando o corpo nao fala dele; None apaga."""
    unidade, ficha, vencimento = {}, {}, _SEM_VENCIMENTO
    privado = corpo.get("privado")
    if not isinstance(privado, dict):
        return unidade, ficha, vencimento
    for campo, valor in privado.items():
        if campo in PRIVADO_UNIDADE or campo in PRIVADO_FICHA:
            limite = 4000 if campo == "observacoes" else 300
            txt = None if valor is None else (str(valor).strip()[:limite] or None)
            (unidade if campo in PRIVADO_UNIDADE else ficha)[campo] = txt
        elif campo == "vencimento":
            if valor in (None, ""):
                vencimento = None
            else:
                try:
                    vencimento = date.fromisoformat(str(valor)[:10])
                except ValueError:
                    erros.append("vencimento: data inválida")
    return unidade, ficha, vencimento


def _gravar_privado(cur, codigo, unidade, ficha, vencimento):
    """A unidade em imovel_privado, o locatario em privado.imovel_ficha e o
    vencimento em contratos_locacao (de onde sai a lista por vencimento)."""
    for tabela, campos, extra in (("imovel_privado", unidade, None),
                                  ("imovel_ficha", ficha, "atualizado_em = now()")):
        if not campos:
            continue
        cols = list(campos)
        alvo = (psycopg2.sql.Identifier("privado", tabela) if tabela == "imovel_ficha"
                else psycopg2.sql.Identifier(tabela))
        sets = [psycopg2.sql.SQL("{0} = EXCLUDED.{0}").format(psycopg2.sql.Identifier(c)) for c in cols]
        if extra:
            sets.append(psycopg2.sql.SQL(extra))
        cur.execute(psycopg2.sql.SQL(
            "INSERT INTO {t} (codigo, {c}) VALUES (%s, {v}) ON CONFLICT (codigo) DO UPDATE SET {s}"
        ).format(t=alvo,
                 c=psycopg2.sql.SQL(", ").join(psycopg2.sql.Identifier(c) for c in cols),
                 v=psycopg2.sql.SQL(", ").join(psycopg2.sql.Placeholder() for _ in cols),
                 s=psycopg2.sql.SQL(", ").join(sets)),
            [codigo] + [campos[c] for c in cols])
    if vencimento is not _SEM_VENCIMENTO:
        cur.execute("UPDATE contratos_locacao SET vencimento = %s WHERE codigo = %s", (vencimento, str(codigo)))
        if cur.rowcount == 0 and vencimento is not None:
            cur.execute("INSERT INTO contratos_locacao (codigo, vencimento) VALUES (%s, %s)", (str(codigo), vencimento))


def _telefone_formatado(txt):
    """O formato do cadastro: (92) 99999-9999. Outro jeito (dois números,
    estrangeiro) fica como veio -- a Nay pega o primeiro telefone do campo."""
    digitos = re.sub(r"\D", "", txt)
    if digitos.startswith("55") and len(digitos) in (12, 13):
        digitos = digitos[2:]
    if len(digitos) == 11:
        return f"({digitos[:2]}) {digitos[2:7]}-{digitos[7:]}"
    if len(digitos) == 10:
        return f"({digitos[:2]}) {digitos[2:6]}-{digitos[6:]}"
    return txt


def _documento_formatado(txt):
    digitos = re.sub(r"\D", "", txt)
    if len(digitos) == 11:
        return f"{digitos[:3]}.{digitos[3:6]}.{digitos[6:9]}-{digitos[9:]}"
    if len(digitos) == 14:
        return f"{digitos[:2]}.{digitos[2:5]}.{digitos[5:8]}/{digitos[8:12]}-{digitos[12:]}"
    return txt


def _proprietario_do_corpo(corpo):
    """(dados, novo) de corpo["proprietario"]. `novo` = corpo["proprietario_novo"]:
    "é outra pessoa" -- não mexe no dono de hoje, cadastra ou acha outro."""
    p = corpo.get("proprietario")
    if not isinstance(p, dict):
        return None, False
    dados = {}
    for campo in PROPRIETARIO_CAMPOS:
        if campo in p:
            v = p.get(campo)
            v = None if v is None else (str(v).strip()[:300] or None)
            if v and campo == "telefone":
                v = _telefone_formatado(v)
            if v and campo == "documento":
                v = _documento_formatado(v)
            dados[campo] = v
    return dados, bool(corpo.get("proprietario_novo"))


def _gravar_proprietario(cur, codigo, dados, novo):
    """Grava o dono do imóvel e liga os dois lugares. Devolve o id (ou None).

    * o imóvel já tem dono e não é "outra pessoa": atualiza os dados DELE (valem
      para todos os imóveis dele);
    * senão procura quem já é dono de outro imóvel -- pelo CPF/CNPJ, ou pelo
      telefone (8 últimos dígitos), e só se achar UM: ligar o imóvel à pessoa
      errada não tem volta; na dúvida, cadastra outro;
    * não achou: cadastra, com id da faixa 900001+ (migração 162)."""
    if dados is None:
        return None
    cur.execute("SELECT coalesce(p.proprietario_id, i.proprietario_id) AS id FROM imoveis i "
                "LEFT JOIN imovel_privado p ON p.codigo = i.codigo WHERE i.codigo = %s", (codigo,))
    pid = None if novo else (cur.fetchone() or {}).get("id")
    if pid is not None:
        if dados:
            cur.execute(psycopg2.sql.SQL("UPDATE proprietarios SET {} WHERE id = %s").format(
                psycopg2.sql.SQL(", ").join(psycopg2.sql.SQL("{} = %s").format(psycopg2.sql.Identifier(c)) for c in dados)),
                list(dados.values()) + [pid])
    else:
        preenchidos = {c: v for c, v in dados.items() if v}
        if not preenchidos:
            return None
        documento = re.sub(r"\D", "", preenchidos.get("documento") or "")
        telefone = re.sub(r"\D", "", preenchidos.get("telefone") or "")
        if len(documento) >= 11:
            cur.execute(r"SELECT id FROM proprietarios WHERE regexp_replace(coalesce(documento, ''), '\D', '', 'g') = %s LIMIT 2",
                        (documento,))
            achados = cur.fetchall()
            pid = achados[0]["id"] if len(achados) == 1 else None
        if pid is None and len(telefone) >= 8:
            cur.execute(r"SELECT id FROM proprietarios WHERE regexp_replace(coalesce(telefone, ''), '\D', '', 'g') LIKE %s LIMIT 2",
                        ("%" + telefone[-8:] + "%",))
            achados = cur.fetchall()
            pid = achados[0]["id"] if len(achados) == 1 else None
        if pid is None:
            cur.execute("SELECT nextval('proprietarios_site_id_seq') AS id")
            pid = cur.fetchone()["id"]
            cols = list(preenchidos)
            cur.execute(psycopg2.sql.SQL("INSERT INTO proprietarios (id, {}) VALUES (%s, {})").format(
                psycopg2.sql.SQL(", ").join(psycopg2.sql.Identifier(c) for c in cols),
                psycopg2.sql.SQL(", ").join(psycopg2.sql.Placeholder() for _ in cols)),
                [pid] + [preenchidos[c] for c in cols])
        else:
            # já era dono de outro imóvel: completa o que o cadastro dele não tinha
            cur.execute(psycopg2.sql.SQL("UPDATE proprietarios SET {} WHERE id = %s").format(
                psycopg2.sql.SQL(", ").join(
                    psycopg2.sql.SQL("{0} = coalesce(NULLIF(btrim({0}), ''), %s)").format(psycopg2.sql.Identifier(c))
                    for c in preenchidos)),
                list(preenchidos.values()) + [pid])
    # os dois lugares apontam para ele (a Nay lê o imovel_privado)
    cur.execute("UPDATE imoveis SET proprietario_id = %s WHERE codigo = %s", (pid, codigo))
    cur.execute("INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (%s, %s) "
                "ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id", (codigo, pid))
    return pid


def _proprietario_do_imovel(conn, codigo):
    dono = todas_linhas(conn, """
        SELECT pr.id, pr.nome, pr.telefone, pr.email, pr.documento, pr.tratamento
          FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo
          JOIN proprietarios pr ON pr.id = coalesce(p.proprietario_id, i.proprietario_id)
         WHERE i.codigo = %s""", (codigo,))
    if not dono:
        return None
    dono = dict(dono[0])
    outros = todas_linhas(conn, """
        SELECT codigo FROM imoveis WHERE proprietario_id = %s AND codigo <> %s
        UNION SELECT codigo FROM imovel_privado WHERE proprietario_id = %s AND codigo <> %s
        ORDER BY 1 LIMIT 40""", (dono["id"], codigo, dono["id"], codigo))
    dono["outros_imoveis"] = [o["codigo"] for o in outros]
    return dono


# =====================================================================
# CADASTRO PENDENTE (Pedro, 01/10/2026): "cria a ferramenta completa de cadastro
# de imóveis importando tudo direitinho, e lá em imóveis cria uma aba CADASTRO
# PENDENTE e põe lá esses para cadastro por humano".
#
#   GET  /admin/api/imoveis/cadastro-pendente   a lista, com o motivo de cada um
#        (migração 248): Rascunho, bloqueado, no ar sem foto, faltando campo
#        essencial, foto em link que vai expirar, e a ficha que o dono ditou na
#        conversa e ninguém cadastrou.
#   POST /admin/api/imoveis/<codigo>/importar   "importa tudo direitinho": baixa
#        para o nosso servidor a foto que mora num link de fora (a da Z-API
#        expira e nem passa na conferência do envio), e puxa a ficha da
#        conversa, o condomínio, o endereço dele e o proprietário -- só em campo
#        VAZIO. A situação do imóvel não é tocada: publicar é decisão de gente.
# Atrás da senha do /admin (e do segredo do painel do CRM, como as outras rotas
# de /admin/api/imoveis).
# =====================================================================
PASTA_IMPORTADO = os.environ.get("FOTOS_CAPTACAO_PASTA", "/fotos")
URL_IMPORTADO = os.environ.get("FOTOS_CAPTACAO_URL", "https://imobeasy.online/fotos-captacao")


@app.route("/admin/api/imoveis/cadastro-pendente")
def api_cadastro_pendente():
    if not senha_do_admin_confere():
        return jsonify({"erro": "sem permissao"}), 401
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT * FROM nai_cadastro_pendente()")
        # 332: "O que a IA supõe que é" -- o palpite de cada item (nay-captacao/captacao/palpite.py). Sem a tabela
        # (migração ainda não aplicada) a fila abre igual, só sem a categoria.
        palpites = {}
        try:
            conn.rollback()
            for p in todas_linhas(conn, "SELECT fonte, item, categoria, porque FROM cadastro_rapido_palpite"):
                palpites[(p["fonte"], int(p["item"]))] = {"categoria": p["categoria"], "porque": p["porque"]}
        except Exception:  # noqa: BLE001
            conn.rollback()
    finally:
        conn.close()
    itens = [{
        "fonte": l["fonte"], "codigo": l["codigo"], "fichaId": l["ficha_id"],
        "titulo": l["titulo"], "tipo": l["tipo"], "bairro": l["bairro"], "condominio": l["condominio"],
        "origem": l["origem"], "status": l["status"], "pct": l["pct"],
        "falta": list(l["falta"] or []), "motivos": list(l["motivos"] or []),
        "fotos": l["fotos"], "fotosDeFora": l["fotos_de_fora"], "dono": l["dono"],
        "quando": l["atualizado"].isoformat() if l["atualizado"] else None,
        "dados": l["dados"] or None,
        "palpite": palpites.get(("ficha", int(l["ficha_id"])) if l["fonte"] == "ficha" else ("imovel", int(l["codigo"] or 0))),
    } for l in linhas if l["status"] != STATUS_EXCLUIDO]   # imóvel excluído não pede mais cadastro
    # o mais incompleto primeiro: é o que mais precisa de gente
    itens.sort(key=lambda x: (x["fonte"] != "ficha", x["pct"] if x["pct"] is not None else -1, -(x["codigo"] or 0)))
    return jsonify({"itens": itens, "total": len(itens)})


@app.route("/admin/api/imoveis/conversa")
def api_cadastro_conversa():
    """A CONVERSA de onde o cadastro veio (Pedro, 09/10/2026: "esses imóveis que vêm de conversa eu quero ver a
    conversa ... em um popup"). ?codigo=<imóvel> ou ?ficha=<ficha da conversa>.

    Quem é a pessoa vem do card da origem (site_origem_do_cadastro, 326). A conversa vem do CRM, que tem tudo: as
    duas linhas (oficial e captação), o que a equipe escreveu, fotos e áudios (em endereço assinado, de validade
    curta). Se o CRM não responder, vai o texto que a captação guardou (sem as fotos). Só leitura; só com senha."""
    if not senha_do_admin_confere():
        return _sem_senha()
    codigo = request.args.get("codigo", type=int)
    ficha = request.args.get("ficha", type=int)
    if not codigo and not ficha:
        return jsonify({"erro": "diga o codigo ou a ficha"}), 400
    conn = conectar_escrita()
    try:
        o = (todas_linhas(conn, "SELECT site_origem_do_cadastro(%s, %s) AS o", (codigo, ficha))[0]["o"]) or {}
        digitos = re.sub(r"\D", "", str(o.get("telefone") or ""))
        if len(digitos) < 8:
            return jsonify({"erro": "Este cadastro não veio de uma conversa."}), 404
        cabeca = {"nome": o.get("nome"), "telefone": o.get("telefone"), "linha": o.get("linha"), "rotulo": o.get("rotulo")}
        try:
            from disparo_api import _crm
            status, j = _crm("GET", "/api/conversas/por-telefone?telefone=" + digitos, timeout=20)
        except Exception as e:  # noqa: BLE001
            status, j = 502, {"erro": str(e)}
        if status == 200 and j.get("conversas"):
            return jsonify({**cabeca, "conversas": j["conversas"], "de": "crm"})
        # o CRM não respondeu (ou não tem a conversa): o texto que a captação guardou
        linhas = todas_linhas(conn, """
            SELECT x.* FROM (
              SELECT m.id, m.direcao, m.origem, m.texto, m.criada_em FROM captacao_mensagens m
               WHERE right(regexp_replace(coalesce(m.telefone, ''), '[^0-9]', '', 'g'), 8) = %s
               ORDER BY m.id DESC LIMIT 500) x ORDER BY x.id""", (digitos[-8:],))
    finally:
        conn.close()
    if not linhas:
        return jsonify({**cabeca, "conversas": [], "de": "captacao", "aviso": j.get("erro")})
    quem = {"disparo": "Nay (disparo)", "resposta": "Nay", "humano": "Equipe"}
    mensagens = [{
        "id": str(m["id"]), "quando": m["criada_em"].isoformat(), "saida": m["direcao"] != "recebida",
        "autor": (quem.get(m["origem"], "Nosso número") if m["direcao"] != "recebida" else (o.get("nome") or "Contato")),
        "deGente": m["direcao"] != "recebida" and m["origem"] == "humano",
        "texto": m["texto"] or ("" if m["direcao"] != "recebida" else "[" + (m["origem"] or "mídia") + "]"),
        "midia": None, "transcricao": None, "citado": None, "falhou": False,
    } for m in linhas]
    return jsonify({**cabeca, "de": "captacao", "aviso": "O CRM não respondeu: aqui vai só o texto, sem fotos nem áudios.",
                    "conversas": [{"linha": "captacao", "rotulo": o.get("linha") or "Conversa da captação", "nome": o.get("nome"),
                                   "telefone": o.get("telefone"), "mensagens": mensagens}]})


@app.route("/admin/api/imoveis/origem")
def api_cadastro_origem():
    """O CARD DA ORIGEM do Cadastro rápido (326; Pedro, 09/10: "quero saber a origem, de onde veio, se por WhatsApp
    de qual número e quando"). ?codigo=<imóvel> ou ?ficha=<ficha da conversa>. Traz o telefone do dono: só com senha."""
    if not senha_do_admin_confere():
        return _sem_senha()
    codigo = request.args.get("codigo", type=int)
    ficha = request.args.get("ficha", type=int)
    if not codigo and not ficha:
        return jsonify({"erro": "diga o codigo ou a ficha"}), 400
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_origem_do_cadastro(%s, %s) AS o", (codigo, ficha))
        return jsonify(linhas[0]["o"] or {})
    finally:
        conn.close()


@app.route("/admin/api/imoveis/da-ficha/<int:fid>")
def api_ficha_preparada(fid):
    """A ficha do dono já analisada (327): os campos do cadastro, as fotos que ele mandou, o condomínio e o dono."""
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_ficha_preparada(%s) AS f", (fid,))
        f = linhas[0]["f"] if linhas else None
        return (jsonify(f), 200) if f else (jsonify({"erro": "ficha não encontrada"}), 404)
    finally:
        conn.close()


@app.route("/admin/api/imoveis/juntar", methods=["POST"])
def api_cadastro_juntar():
    """"NA VERDADE É ATUALIZAÇÃO DESTE IMÓVEL" (326; Pedro, 09/10). {de_codigo | de_ficha, em, fotos}: as fotos e o
    dono vão para o `em`, o duplicado vira Excluído e a ficha fica aplicada. Os campos que mudaram vão antes, pelo PUT."""
    if not senha_do_admin_confere():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    def inteiro(k):
        try:
            return int(corpo.get(k)) if corpo.get(k) not in (None, "") else None
        except (TypeError, ValueError):
            return None
    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT site_juntar_cadastro(%s, %s, %s, %s, %s) AS r",
                        (inteiro("de_codigo"), inteiro("de_ficha"), inteiro("em"), bool(corpo.get("fotos")), "cadastro rápido"))
            r = cur.fetchone()["r"]
        conn.commit()
        return jsonify(r)
    except psycopg2.Error as exc:
        conn.rollback()
        msg = (getattr(exc, "diag", None) and exc.diag.message_primary) or exc.__class__.__name__
        return jsonify({"erro": msg}), 400
    finally:
        conn.close()


def _baixar_foto(url):
    """Baixa uma foto de fora. Devolve (bytes, extensao) ou (None, motivo)."""
    import urllib.request
    pedido = urllib.request.Request(url, headers={"User-Agent": "imobeasy-importador/1.0"})
    with urllib.request.urlopen(pedido, timeout=25) as r:  # noqa: S310
        dados = r.read(12 * 1024 * 1024)
    if len(dados) < 1024:
        return None, "arquivo muito pequeno (%s bytes)" % len(dados)
    if dados[:3] == b"\xff\xd8\xff":
        return dados, "jpg"
    if dados[:8] == b"\x89PNG\r\n\x1a\n":
        return dados, "png"
    if dados[:4] == b"RIFF" and dados[8:12] == b"WEBP":
        return dados, "webp"
    return None, "nao e jpg, png nem webp"


@app.route("/admin/api/imoveis/<int:codigo>/importar", methods=["POST"])
def api_cadastro_importar(codigo):
    if not senha_do_admin_confere():
        return jsonify({"erro": "sem permissao"}), 401
    conn = conectar_escrita()
    fotos_ok, fotos_erro = 0, []
    try:
        # 1. a foto que mora num link de fora vem para o nosso servidor
        de_fora = todas_linhas(conn, r"""
            SELECT url FROM imovel_fotos
             WHERE codigo = %s AND url !~ '^https://imobeasy\.(com|online)/'
             ORDER BY ordem""", (codigo,))
        conn.rollback()
        if de_fora:
            pasta = os.path.join(PASTA_IMPORTADO, "importado", str(codigo))
            try:
                os.makedirs(pasta, exist_ok=True)
            except OSError as exc:
                fotos_erro.append("nao consegui criar a pasta: %s" % exc)
                de_fora = []
        for n, l in enumerate(de_fora, start=1):
            try:
                dados, ext = _baixar_foto(l["url"])
                if dados is None:
                    fotos_erro.append("%02d: %s" % (n, ext))
                    continue
                nome = "%02d.%s" % (n, ext)
                alvo = os.path.join(PASTA_IMPORTADO, "importado", str(codigo), nome)
                temporario = alvo + ".parcial"
                with open(temporario, "wb") as f:
                    f.write(dados)
                os.replace(temporario, alvo)
                nova = "%s/importado/%s/%s" % (URL_IMPORTADO, codigo, nome)
                with conn.cursor() as cur:
                    cur.execute("SELECT nai_foto_trocar_url(%s, %s, %s) AS n", (codigo, l["url"], nova))
                    if cur.fetchone()["n"]:
                        fotos_ok += 1
                conn.commit()
            except Exception as exc:  # noqa: BLE001
                conn.rollback()
                fotos_erro.append("%02d: %s" % (n, str(exc)[:80]))

        # 2. o resto: ficha da conversa, condomínio, endereço, proprietário
        with conn.cursor() as cur:
            cur.execute("SELECT nai_cadastro_importar(%s) AS r", (codigo,))
            r = cur.fetchone()["r"] or {}
        conn.commit()
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()
    if r.get("erro"):
        return jsonify(r), 404
    r["fotosImportadas"] = fotos_ok
    r["fotosErro"] = fotos_erro
    r["editor"] = "/admin/imovel-editar.html?codigo=%s" % codigo
    return jsonify(r)


@app.route("/admin/api/imoveis/<int:codigo>/privado")
def api_imovel_privado(codigo):
    """A UNIDADE (torre, apartamento, bloco, casa, lote) e a LOCACAO ATUAL do
    imovel -- so com a senha do /admin. A rota aberta /api/imoveis/<codigo>
    nunca devolve isto."""
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_escrita()
    try:
        saida = {c: None for c in PRIVADO_UNIDADE + PRIVADO_FICHA}
        u = todas_linhas(conn, "SELECT torre, unidade, bloco, casa, lote FROM imovel_privado WHERE codigo = %s", (codigo,))
        f = todas_linhas(conn, "SELECT locatario_nome, locatario_contato, observacao_aluguel, observacoes "
                               "FROM privado.imovel_ficha WHERE codigo = %s", (codigo,))
        v = todas_linhas(conn, "SELECT vencimento FROM contratos_locacao WHERE codigo = %s "
                               "ORDER BY vencimento DESC NULLS LAST LIMIT 1", (str(codigo),))
        if u:
            saida.update(u[0])
        if f:
            saida.update(f[0])
        saida["vencimento"] = v[0]["vencimento"].isoformat() if v and v[0]["vencimento"] else None
        saida["proprietario"] = _proprietario_do_imovel(conn, codigo)
        return jsonify(saida)
    finally:
        conn.close()


@app.route("/admin/api/imoveis/do-condominio/<int:cid>")
def api_imoveis_do_condominio(cid):
    """OS IMÓVEIS QUE JÁ EXISTEM NO CONDOMÍNIO (Pedro, 01/10/2026: "quando eu crie
    um imóvel e escolha um condomínio ele já mostre uma listinha de outros imóveis
    no condomínio para eu não acabar criando o imóvel duplicado").

    Ligados pelo id OU pelo nome (o mesmo critério da lista e da aba Condomínios).
    Vem com a UNIDADE (torre, bloco, apartamento, casa, lote): é ela que diz se é o
    mesmo imóvel -- e por ser dado privado, só com a senha do /admin. O Excluído
    fica de fora."""
    if not senha_do_admin_confere():
        return _sem_senha()
    # DUAS LEITURAS, cada uma com o papel que enxerga a sua parte: a visão dos
    # imóveis é do papel de leitura; a unidade (imovel_privado) só o de escrita lê.
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            SELECT v.codigo, v.status, v.tipo, v.quartos, v.area_total, v.valor_venda, v.valor_aluguel,
                   v.valor_texto, v.proprietario_nome, v.no_catalogo,
                   count(*) OVER () AS total
              FROM vw_imoveis_todos v
             WHERE (v.condo_id = %s
                    OR (v.condo_id IS NULL AND lower(nay_sem_acento(v.condominio)) =
                        (SELECT lower(nay_sem_acento(nome)) FROM condominios WHERE id = %s)))
               AND v.status <> %s
             ORDER BY (v.status = 'Disponível') DESC, v.codigo DESC
             LIMIT 200""", (cid, cid, STATUS_EXCLUIDO))
    finally:
        conn.close()
    unidades = {}
    if linhas:
        conn = conectar_escrita()
        try:
            for u in todas_linhas(conn, "SELECT codigo, torre, bloco, unidade, casa, lote FROM imovel_privado "
                                        "WHERE codigo = ANY(%s)", ([l["codigo"] for l in linhas],)):
                unidades[u["codigo"]] = u
        finally:
            conn.close()

    def valor(l):
        partes = []
        if l["valor_venda"]:
            partes.append("Venda " + formatar_reais(l["valor_venda"]))
        if l["valor_aluguel"]:
            partes.append("Aluguel " + formatar_reais(l["valor_aluguel"]))
        return " · ".join(partes) or (l["valor_texto"] or "")

    def unidade(l):
        u = unidades.get(l["codigo"]) or {}
        rotulos = (("torre", "Torre"), ("bloco", "Bloco"), ("unidade", "Apto"), ("casa", "Casa"), ("lote", "Lote"))
        return " · ".join(r + " " + str(u[c]).strip() for c, r in rotulos if u.get(c) and str(u[c]).strip())

    return jsonify({
        "total": linhas[0]["total"] if linhas else 0,
        "itens": [{
            "codigo": str(l["codigo"]), "status": l["status"], "tipo": l["tipo"] or "",
            "quartos": l["quartos"], "area": float(l["area_total"]) if l["area_total"] else None,
            "valor": valor(l), "unidade": unidade(l),
            "proprietario": l["proprietario_nome"] or "", "noCatalogo": l["no_catalogo"],
        } for l in linhas],
    })


@app.route("/admin/api/imoveis/valores")
def api_imovel_valores():
    """As listas que descem no cadastro, tiradas do proprio catalogo: as de
    /api/imoveis/valores (imoveis_api.py) mais as dos campos do site antigo --
    captado/indicado/inspecionado por sao nomes da equipe, por isso esta rota
    fica atras da senha e a aberta continua como estava."""
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_escrita()
    try:
        saida = {}
        for campo in ("tipo", "bairro", "cidade", "estado", "andar", "sol", "mobilia", "motivo_bloqueio", "captado_por"):
            linhas = todas_linhas(conn, psycopg2.sql.SQL(
                "SELECT btrim({c}) AS v, count(*) AS n FROM imoveis WHERE NULLIF(btrim({c}), '') IS NOT NULL "
                "GROUP BY 1 ORDER BY 2 DESC LIMIT 200").format(c=psycopg2.sql.Identifier(campo)))
            saida[campo] = [l["v"] for l in linhas]
        linhas = todas_linhas(conn, "SELECT btrim(c) AS v, count(*) AS n FROM imoveis, unnest(caracteristicas) c "
                                    "WHERE NULLIF(btrim(c), '') IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 300")
        saida["caracteristicas"] = [l["v"] for l in linhas]
        for chave in ("indicado por", "inspecionado por", "tipo de cobertura", "permuta"):
            linhas = todas_linhas(conn, "SELECT btrim(extras->>%s) AS v, count(*) AS n FROM imoveis "
                                        "WHERE NULLIF(btrim(extras->>%s), '') IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 200",
                                  (chave, chave))
            saida["x:" + chave] = [l["v"] for l in linhas]
        return jsonify(saida)
    finally:
        conn.close()


# =====================================================================
# REVISAO DO SITE (11/09/2026)
# =====================================================================

def _csv(cabecalho, linhas, nome):
    def campo(v):
        if v is None:
            return ""
        txt = str(v).replace('"', '""')
        return '"' + txt + '"' if any(c in txt for c in ',;"\n') else txt
    corpo = [",".join(cabecalho)] + [",".join(campo(x) for x in l) for l in linhas]
    return app.response_class("﻿" + "\n".join(corpo), mimetype="text/csv",
                              headers={"Content-Disposition": 'attachment; filename="%s.csv"' % nome})


# EXCLUIR IMÓVEL (Pedro, 01/10/2026: "e também uma opção de excluir imóvel").
# Linha de `imoveis` NUNCA se apaga (regra do CLAUDE.md), então excluir é uma
# situação: "Excluído". Como toda situação que não é Disponível, sai do site e
# da Nay (ver api_imovel_salvar) e fica travado contra a leitura do site antigo.
# A diferença para "Removido" (que é o que a planilha do site antigo chama de
# removido, 755 imóveis) é que o Excluído SOME DA LISTA: só aparece para quem
# marca "Excluído" no filtro de situação -- e de lá dá para trazer de volta,
# trocando a situação.
STATUS_EXCLUIDO = "Excluído"
STATUS_IMOVEL = ("Disponível", "Alugado", "Vendido", "Arquivado", "Removido",
                 "Rascunho", "Em revisão", "Indisponível", "Fora do site", STATUS_EXCLUIDO)
# O que se escolhe na lista suspensa: "Fora do site" não é situação, é anúncio.
STATUS_EDITAVEIS = ("Disponível", "Alugado", "Vendido", "Rascunho", "Em revisão",
                    "Arquivado", "Removido", "Indisponível", STATUS_EXCLUIDO)



# 244 (Pedro, 30/09): as faixas de preenchimento do cadastro, para filtrar e contar.
# A régua de pontos é do banco (nai_imovel_pontos / vw_imovel_pontuacao).
FAIXAS_DO_CADASTRO = {
    "100": (100, 100),
    "90": (90, 99),
    "75": (75, 89),
    "50": (50, 74),
    "baixo": (0, 49),
}


def _na_faixa_do_cadastro(pct, faixa):
    if faixa not in FAIXAS_DO_CADASTRO:
        return True
    de, ate = FAIXAS_DO_CADASTRO[faixa]
    return de <= (pct or 0) <= ate


@app.route("/api/imoveis-lista")
def api_imoveis_lista():
    """TODOS os imoveis, paginado, com filtros de verdade e a CONTAGEM AO LADO
    de cada opcao do filtro.

    A contagem ao lado ignora o proprio grupo da opcao. Sem isso o numero ao
    lado de "Alugado" viraria 0 no instante em que alguem marca "Disponivel", e
    o filtro deixaria de servir de mapa do acervo -- que e pra isso que ele
    existe: dar pra ver, antes de clicar, quanto tem de cada coisa.

    Sao tres leituras da visao (a pagina, a base das contagens e o resumo), ~47ms
    cada. A conta em si e feita aqui no Python sobre a base ja filtrada, em vez
    de uma consulta por grupo -- sete leituras seria meio segundo de espera.
    """
    a = request.args
    # MAPA (28/09): a tela pede o ponto de cada imovel, com os MESMOS filtros da
    # lista -- o mapa mostra o que esta filtrado. Pode vir o acervo inteiro.
    mapa = a.get("mapa") == "1"
    per = max(1, min(_inteiro(a.get("per") or 50, 50),
                     6000 if a.get("formato") == "csv" or mapa else 2000))
    page = max(1, _inteiro(a.get("page") or 1, 1))

    # Cada condicao e uma dupla (sql, parametros). Assim da pra montar o WHERE
    # de tres jeitos diferentes (a pagina, cada contagem, o CSV) sem nunca
    # desencontrar a ordem dos %s.
    base = []      # busca, lugar, valor, data -- valem para tudo
    grupos = {}    # as facetas, uma lista de condicoes por grupo
    # 244: a faixa de preenchimento do cadastro (completo, quase, incompleto...)
    faixa_cad = str(a.get("cadastro") or "").strip()
    if faixa_cad in FAIXAS_DO_CADASTRO:
        de, ate = FAIXAS_DO_CADASTRO[faixa_cad]
        grupos.setdefault("cadastro", []).append(
            ("v.codigo IN (SELECT codigo FROM vw_imovel_pontuacao WHERE pct BETWEEN %s AND %s)", [de, ate]))

    q = str(a.get("q") or "").strip()[:80]
    if q:
        if q.isdigit():
            base.append(("v.codigo::text LIKE %s", [q + "%"]))
        else:
            base.append(("nay_sem_acento(lower(concat_ws(' ', v.condominio, v.bairro, v.endereco, v.tipo, v.proprietario_nome))) "
                         "LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'", [q]))

    status = [x for x in str(a.get("status") or "").split(",") if x in STATUS_IMOVEL]
    if status:
        grupos.setdefault("status", []).append(("v.status = ANY(%s)", [status]))
    else:
        # sem situação marcada, o Excluído não aparece (nem na lista, nem no mapa,
        # nem nas contagens dos outros filtros). Fica no grupo "status" de
        # propósito: a contagem ao lado de cada situação ignora o próprio grupo,
        # e é assim que o número de "Excluído" continua à vista no filtro.
        grupos.setdefault("status", []).append(("v.status <> %s", [STATUS_EXCLUIDO]))

    grupo = a.get("grupo")
    if grupo in ("apartamento", "casa", "outros", "sem_tipo"):
        grupos.setdefault("tipo", []).append(("v.grupo_tipo = %s", [grupo]))
    tipo = str(a.get("tipo") or "").strip()[:60]
    if tipo:
        grupos.setdefault("tipo", []).append(("v.tipo ILIKE %s", [tipo + "%"]))

    condos = [int(x) for x in str(a.get("condo_ids") or "").split(",") if x.strip().isdigit()]
    if condos:
        base.append(("(v.condo_id = ANY(%s) OR lower(nay_sem_acento(v.condominio)) IN "
                     "(SELECT lower(nay_sem_acento(nome)) FROM condominios WHERE id = ANY(%s)))",
                     [condos, condos]))
    bairro = str(a.get("bairro") or "").strip()[:60]
    if bairro:
        base.append(("nay_sem_acento(lower(v.bairro)) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'", [bairro]))

    # VÁRIOS DE UMA VEZ (28/09, Pedro: "não consigo selecionar vários bairros,
    # quero os filtros dos imóveis igual os do enviar"). Os valores vêm da lista
    # de /api/imoveis/opcoes, escritos como estão no banco -- igualdade, sem LIKE.
    def varios(nome):
        return [x.strip()[:80] for x in a.getlist(nome) if x and x.strip()][:60]
    bairros = varios("bairros")
    # CONJUNTO E AVENIDA (Pedro, 30/09): viram os bairros deles, e somam com os
    # bairros marcados -- é tudo "onde". O conjunto pega também o condomínio de
    # mesmo nome (o Viver Melhor 4 do catálogo está na Colônia Terra Nova).
    conjuntos = varios("conjuntos")
    avenidas = varios("avenidas")
    # ZONA (Pedro, 30/09: "por bairro, por zona e por avenida"): a zona do bairro
    # (bairro_zona) e a que o imóvel tem em imovel_lugar (229)
    zonas = varios("zonas")
    onde, onde_p = [], []
    if bairros:
        onde.append("v.bairro = ANY(%s)")
        onde_p.append(bairros)
    if conjuntos:
        # 231: o conjunto vale para o bairro dele, para o bairro de mesmo nome e para o
        # imóvel ligado em imovel_lugar (Parque das Laranjeiras = Flores + o bairro homônimo)
        onde.append("(v.bairro IN (SELECT unnest(nai_bairros_do_conjunto(x)) FROM unnest(%s::text[]) x)"
                    " OR v.codigo IN (SELECT l.codigo FROM imovel_lugar l WHERE l.conjuntos && %s::text[]))")
        onde_p.append(conjuntos)
        onde_p.append(conjuntos)
    if avenidas:
        # 229: também o imóvel que tem a avenida no endereço, fora dos bairros da lista
        onde.append("(v.bairro IN (SELECT unnest(a.bairros) FROM nai_lugar_avenida a WHERE a.nome = ANY(%s))"
                    " OR v.codigo IN (SELECT l.codigo FROM imovel_lugar l WHERE l.avenidas && %s::text[]))")
        onde_p.append(avenidas)
        onde_p.append(avenidas)
    if zonas:
        onde.append("(v.bairro IN (SELECT z.bairro FROM bairro_zona z WHERE z.zona = ANY(%s))"
                    " OR v.codigo IN (SELECT l.codigo FROM imovel_lugar l WHERE l.zona = ANY(%s)))")
        onde_p.append(zonas)
        onde_p.append(zonas)
    if onde:
        base.append(("(" + " OR ".join(onde) + ")", onde_p))
    tipos = varios("tipos")
    if tipos:
        base.append(("v.tipo = ANY(%s)", [tipos]))
    condominios = varios("condominios")
    if condominios:
        base.append(("v.condominio = ANY(%s)", [condominios]))

    fin = a.get("finalidade")
    if fin == "venda":
        grupos.setdefault("fin", []).append(("(coalesce(v.valor_venda, 0) > 0 OR v.valor_texto ILIKE 'Venda%%')", []))
    elif fin == "aluguel":
        grupos.setdefault("fin", []).append(("(coalesce(v.valor_aluguel, 0) > 0 OR v.valor_texto ILIKE 'Aluguel%%')", []))

    # FLEXIBILIDADE NA BUSCA DE GENTE (Pedro, 01/10/2026: "quero flexibilidade na
    # hora de buscar imoveis manualmente... em todos os lugares onde podemos
    # buscar manualmente hoje"). O filtro nao esconde o imovel por falta do dado
    # filtrado: quartos/vagas em branco continuam aparecendo, e quem olha a
    # tela ve a coluna vazia. Sao 3 e 2 imoveis hoje -- mas eram justamente os
    # que desapareciam sem ninguem entender por que. O mesmo criterio da tela
    # Enviar imovel (migracao 253). O PRECO continua firme: sem preco nao cabe
    # numa faixa de preco.
    for chave, col, nome in (("quartos", "v.quartos", "quartos"), ("vagas", "v.vagas", "vagas")):
        val = str(a.get(chave) or "")
        n = val[:-1] if val.endswith("+") else val
        if n.isdigit():
            grupos.setdefault(nome, []).append(("(" + col + " >= %s OR " + col + " IS NULL)", [int(n)]))

    # FAIXA DE VALOR NA COLUNA DA FINALIDADE (28/09). Antes o minimo/maximo
    # comparava com coalesce(venda, aluguel): com "Aluguel" marcado, o imovel
    # que tem os dois precos era medido pelo de VENDA e sumia da faixa. Sem
    # finalidade, vale se um dos dois precos cabe inteiro na faixa.
    col_valor = {"aluguel": "nullif(v.valor_aluguel, 0)", "venda": "nullif(v.valor_venda, 0)"}.get(fin)
    faixa = []
    for chave, op in (("vmin", ">="), ("vmax", "<=")):
        val = re.sub(r"[^\d]", "", str(a.get(chave) or "").split(",")[0])
        if val:
            faixa.append((op, int(val)))
    if faixa:
        def na_faixa(col):
            return "(" + " AND ".join(col + " " + op + " %s" for op, _ in faixa) + ")"
        numeros = [x for _, x in faixa]
        if col_valor:
            base.append((na_faixa(col_valor), numeros))
        else:
            base.append(("(" + na_faixa("nullif(v.valor_venda, 0)") + " OR " +
                         na_faixa("nullif(v.valor_aluguel, 0)") + ")", numeros + numeros))

    if a.get("parceiro") == "sim":
        grupos.setdefault("parceiro", []).append(("v.e_parceiro", []))
    elif a.get("parceiro") == "nao":
        grupos.setdefault("parceiro", []).append(("NOT v.e_parceiro", []))

    if a.get("sem_dono") == "1":
        grupos.setdefault("dono", []).append(("coalesce(v.proprietario_nome, '') = ''", []))
    elif a.get("com_dono") == "1":
        grupos.setdefault("dono", []).append(("coalesce(v.proprietario_nome, '') <> ''", []))

    # ANUNCIO: esta no site ou nao. E outra coisa que a situacao do imovel --
    # um imovel disponivel pode estar fora do site de proposito.
    if a.get("anunciado") == "sim":
        grupos.setdefault("anuncio", []).append(("v.publicado_no_site", []))
    elif a.get("anunciado") == "nao":
        grupos.setdefault("anuncio", []).append(("NOT v.publicado_no_site", []))

    if a.get("com_foto") == "sim":
        grupos.setdefault("foto", []).append(("v.fotos > 0", []))
    elif a.get("com_foto") == "nao":
        grupos.setdefault("foto", []).append(("v.fotos = 0", []))

    if a.get("confirmar") == "1":
        grupos.setdefault("confirmar", []).append(("v.precisa_confirmacao", []))

    if a.get("catalogo") == "1":
        base.append(("v.no_catalogo", []))
    if a.get("financia") in ("Sim", "Não"):
        grupos.setdefault("financia", []).append(("v.financia = %s", [a.get("financia")]))

    # ---- DATA EM DOIS PASSOS: qual data, depois qual periodo ----------
    # As duas datas que existem de verdade no banco: o fim do contrato de
    # aluguel (contratos_locacao) e a data de cadastro. "Disponivel desde" e
    # "ultima confirmacao do proprietario" nao existem em coluna nenhuma --
    # ficam de fora em vez de virar filtro que mente.
    CAMPO_DATA = {"vencimento": ("v.vencimento", "futuro"), "criado": ("v.criado::date", "passado")}
    campo, quando = CAMPO_DATA.get(str(a.get("data_campo") or ""), (None, None))
    per_data = str(a.get("data_per") or "")
    if campo and per_data:
        meses = re.sub(r"[^\d]", "", str(a.get("data_meses") or ""))
        if per_data == "semdata":
            base.append((campo + " IS NULL", []))
        elif per_data == "vencido" and quando == "futuro":
            base.append((campo + " < current_date", []))
        elif per_data == "semana":
            # "esta semana" / "ultimos 7 dias" -- e o unico periodo que olha para
            # DENTRO da janela; os outros sao "ha mais de" e "nos proximos".
            if quando == "futuro":
                base.append((campo + " BETWEEN current_date AND current_date + 7", []))
            else:
                base.append((campo + " >= current_date - 7", []))
        elif per_data == "meses" and meses:
            if quando == "futuro":
                base.append((campo + " BETWEEN current_date AND current_date + (%s || ' months')::interval", [meses]))
            else:
                base.append((campo + " <= current_date - (%s || ' months')::interval", [meses]))
        elif per_data.isdigit():
            if quando == "futuro":
                base.append((campo + " BETWEEN current_date AND current_date + %s", [int(per_data)]))
            else:
                base.append((campo + " <= current_date - %s", [int(per_data)]))

    # O filtro de vencimento antigo (a faixa de datas em cima da tabela) continua
    # valendo: a tela de Anuncios usa ele.
    de, ate = periodo_da_query()
    if de:
        base.append(("v.vencimento >= %s", [de]))
    if ate:
        base.append(("v.vencimento <= %s", [ate]))
    for chave, op in (("criado_de", ">="), ("criado_ate", "<=")):
        val = str(a.get(chave) or "")
        if re.match(r"^\d{4}-\d{2}-\d{2}$", val):
            base.append(("v.criado::date " + op + " %s", [val]))

    def montar(conds):
        """(WHERE, parametros) na mesma ordem -- e o que impede o %s trocado."""
        if not conds:
            return "", []
        return ("WHERE " + " AND ".join(c[0] for c in conds),
                [p for c in conds for p in c[1]])

    todas = base + [c for g in grupos.values() for c in g]
    where, params = montar(todas)

    # "menor/maior valor" tambem olha o preco da finalidade escolhida
    col_ordem = col_valor or "coalesce(nullif(v.valor_venda, 0), v.valor_aluguel)"
    ordem = {"antigo": "v.criado ASC NULLS LAST, v.codigo",
             "menor": col_ordem + " ASC NULLS LAST",
             "maior": col_ordem + " DESC NULLS LAST",
             "codigo": "v.codigo DESC",
             "vencimento": "v.vencimento ASC NULLS LAST",
             "fotos": "v.fotos DESC, v.codigo DESC",
             # 244: do mais incompleto para o mais completo, e o contrário
             "falta": "pt.pct ASC NULLS LAST, v.codigo DESC",   # quem não está no catálogo não tem pontuação: vai para o fim
             "completo": "pt.pct DESC NULLS LAST, v.codigo DESC"}.get(a.get("ordem"), "v.criado DESC NULLS LAST, v.codigo DESC")

    conn = conectar()
    try:
        geo_col = (", g.lat, g.lon, g.precisao AS geo_precisao, g.bairro AS geo_bairro" if mapa else "")
        geo_join = (" LEFT JOIN imovel_geo g ON g.codigo = v.codigo " if mapa else " ")
        # QUANTO O CADASTRO ESTÁ PREENCHIDO (244, Pedro 30/09): o pct e o que falta
        linhas = todas_linhas(conn, "SELECT v.*" + geo_col +
                              ", pt.pct AS cadastro_pct, pt.falta AS cadastro_falta"
                              ", count(*) OVER () AS total FROM vw_imoveis_todos v" +
                              geo_join + " LEFT JOIN vw_imovel_pontuacao pt ON pt.codigo = v.codigo " + where +
                              " ORDER BY " + ordem + " LIMIT %s OFFSET %s",
                              tuple(params + [per, (page - 1) * per]))
        resumo = todas_linhas(conn, """
            SELECT count(*) FILTER (WHERE status = 'Disponível' AND coalesce(valor_aluguel, 0) > 0) AS aluguel,
                   count(*) FILTER (WHERE status = 'Disponível' AND coalesce(valor_venda, 0) > 0) AS venda,
                   count(*) FILTER (WHERE e_parceiro) AS parceiros,
                   count(*) FILTER (WHERE fotos > 0) AS com_foto,
                   count(*) AS todos
              FROM vw_imoveis_todos WHERE status <> %s""", (STATUS_EXCLUIDO,))[0]

        # ---- a base das contagens: uma leitura, o resto e conta no Python ----
        where_base, params_base = montar(base)
        crus = todas_linhas(conn, """
            SELECT v.codigo, v.status, v.tipo, v.grupo_tipo, v.publicado_no_site, v.fotos, v.quartos, v.vagas,
                   v.e_parceiro, v.financia, v.precisa_confirmacao,
                   coalesce(pt.pct, 0) AS cadastro_pct,
                   coalesce(v.proprietario_nome, '') <> '' AS tem_dono,
                   (coalesce(v.valor_venda, 0) > 0 OR v.valor_texto ILIKE 'Venda%%') AS e_venda,
                   (coalesce(v.valor_aluguel, 0) > 0 OR v.valor_texto ILIKE 'Aluguel%%') AS e_aluguel
              FROM vw_imoveis_todos v
              LEFT JOIN vw_imovel_pontuacao pt ON pt.codigo = v.codigo """ + where_base, tuple(params_base))

        # como cada grupo ja escolhido peneira a base, em Python
        PENEIRA = {
            "status": lambda l: (l["status"] in status) if status else l["status"] != STATUS_EXCLUIDO,
            "tipo": lambda l: ((not grupo or l["grupo_tipo"] == grupo)
                               and (not tipo or (l["tipo"] or "").lower().startswith(tipo.lower()))),
            "fin": lambda l: (l["e_venda"] if fin == "venda" else l["e_aluguel"]),
            # 01/10: igual ao SQL -- em branco nao e escondido
            "quartos": lambda l: l["quartos"] is None or l["quartos"] >= int(re.sub(r"[^\d]", "", a.get("quartos") or "0") or 0),
            "vagas": lambda l: l["vagas"] is None or l["vagas"] >= int(re.sub(r"[^\d]", "", a.get("vagas") or "0") or 0),
            "parceiro": lambda l: l["e_parceiro"] if a.get("parceiro") == "sim" else not l["e_parceiro"],
            "dono": lambda l: (not l["tem_dono"]) if a.get("sem_dono") == "1" else l["tem_dono"],
            "anuncio": lambda l: l["publicado_no_site"] if a.get("anunciado") == "sim" else not l["publicado_no_site"],
            "foto": lambda l: (l["fotos"] > 0) if a.get("com_foto") == "sim" else (l["fotos"] == 0),
            "confirmar": lambda l: l["precisa_confirmacao"],
            "financia": lambda l: l["financia"] == a.get("financia"),
            # 244: a faixa de preenchimento do cadastro
            "cadastro": lambda l: _na_faixa_do_cadastro(l["cadastro_pct"], a.get("cadastro")),
        }

        def sem(nome):
            """As linhas que passam por todos os grupos MENOS o `nome`."""
            outros = [PENEIRA[g] for g in grupos if g != nome and g in PENEIRA]
            return [l for l in crus if all(f(l) for f in outros)]

        def contar(nome, chaves):
            linhas_g = sem(nome)
            return {rotulo: sum(1 for l in linhas_g if teste(l)) for rotulo, teste in chaves.items()}

        facetas = {
            "status": contar("status", {s: (lambda l, s=s: l["status"] == s) for s in STATUS_IMOVEL}),
            "tipo": contar("tipo", {"": lambda l: True,
                                    "apartamento": lambda l: l["grupo_tipo"] == "apartamento",
                                    "casa": lambda l: l["grupo_tipo"] == "casa",
                                    "outros": lambda l: l["grupo_tipo"] == "outros",
                                    "sem_tipo": lambda l: l["grupo_tipo"] == "sem_tipo"}),
            "fin": contar("fin", {"venda": lambda l: l["e_venda"], "aluguel": lambda l: l["e_aluguel"]}),
            "quartos": contar("quartos", {str(n): (lambda l, n=n: (l["quartos"] or 0) >= n) for n in (1, 2, 3, 4)}),
            "vagas": contar("vagas", {str(n): (lambda l, n=n: (l["vagas"] or 0) >= n) for n in (1, 2, 3, 4)}),
            "parceiro": contar("parceiro", {"sim": lambda l: l["e_parceiro"], "nao": lambda l: not l["e_parceiro"]}),
            "dono": contar("dono", {"com": lambda l: l["tem_dono"], "sem": lambda l: not l["tem_dono"]}),
            "anuncio": contar("anuncio", {"sim": lambda l: l["publicado_no_site"],
                                          "nao": lambda l: not l["publicado_no_site"]}),
            "foto": contar("foto", {"sim": lambda l: l["fotos"] > 0, "nao": lambda l: l["fotos"] == 0}),
            "confirmar": contar("confirmar", {"sim": lambda l: l["precisa_confirmacao"]}),
            "financia": contar("financia", {"Sim": lambda l: l["financia"] == "Sim",
                                            "Não": lambda l: l["financia"] == "Não"}),
            "cadastro": contar("cadastro", {f: (lambda l, f=f: _na_faixa_do_cadastro(l["cadastro_pct"], f))
                                            for f in FAIXAS_DO_CADASTRO}),
        }

        def valor(l):
            if l["valor_venda"]:
                return f"Venda: {formatar_reais(l['valor_venda'])}"
            if l["valor_aluguel"]:
                return f"Aluguel: {formatar_reais(l['valor_aluguel'])}"
            return l["valor_texto"] or "Consulte"

        itens = [{
            "codigo": str(l["codigo"]), "status": l["status"], "noCatalogo": l["no_catalogo"],
            "tipo": l["tipo"], "financia": l["financia"], "valor": valor(l),
            "valorVenda": float(l["valor_venda"]) if l["valor_venda"] else None,
            "valorAluguel": float(l["valor_aluguel"]) if l["valor_aluguel"] else None,
            "condominio": l["condominio"] or "", "condoId": l["condo_id"],
            "bairro": l["bairro"], "endereco": l["endereco"] or "",
            "proprietario": l["proprietario_nome"] or "", "parceiro": l["e_parceiro"],
            "quartos": l["quartos"], "vagas": l["vagas"],
            "suites": l["suites"], "banheiros": l["banheiros"],
            "area": float(l["area_total"]) if l["area_total"] else None,
            "fotos": l["fotos"], "capa": l["capa"],
            # 244: quanto o cadastro está preenchido, e o que falta
            "cadastroPct": l.get("cadastro_pct"), "cadastroFalta": list(l.get("cadastro_falta") or []),
            "anunciado": l["publicado_no_site"], "precisaConfirmar": l["precisa_confirmacao"],
            # 274: a lista diz se a Nay oferece (nosso, Disponível, no site e sem bloqueio)
            "bloqueado": bool(l.get("bloqueado")),
            "criado": l["criado"].date().isoformat() if l["criado"] else None,
            "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
            **({"lat": l.get("lat"), "lon": l.get("lon"), "precisao": l.get("geo_precisao"),
                "bairroMapa": l.get("geo_bairro")} if mapa else {}),
        } for l in linhas]

        if a.get("formato") == "csv":
            return _csv(["codigo", "status", "anunciado", "tipo", "valor", "condominio", "bairro", "endereco",
                         "quartos", "suites", "banheiros", "vagas", "area", "fotos", "financia", "parceiro",
                         "proprietario", "vencimento", "cadastro"],
                        [[i["codigo"], i["status"], "sim" if i["anunciado"] else "nao", i["tipo"], i["valor"],
                          i["condominio"], i["bairro"], i["endereco"], i["quartos"], i["suites"], i["banheiros"],
                          i["vagas"], i["area"], i["fotos"], i["financia"], "sim" if i["parceiro"] else "nao",
                          i["proprietario"], i["vencimento"], i["criado"]] for i in itens],
                        "imoveis")
        return jsonify({"total": linhas[0]["total"] if linhas else 0, "page": page, "per": per,
                        "itens": itens, "facetas": facetas,
                        "resumo": {k: int(v or 0) for k, v in resumo.items()}})
    finally:
        conn.close()


@app.route("/api/mapa/bairros")
def api_mapa_bairros():
    """Os bairros de Manaus para o mapa (migracao 149): o contorno oficial do
    OpenStreetMap, um ponto de dentro (o rotulo), quem faz divisa com quem e
    quantos imoveis nossos caem em cada um. Muda pouco: o navegador guarda 1h."""
    conn = conectar()
    try:
        bairros = todas_linhas(conn, """
            SELECT b.bairro, b.lat, b.lon, b.poligono, b.fonte, b.area_km2,
                   (SELECT count(*) FROM imovel_geo g WHERE g.bairro = b.bairro) AS imoveis
              FROM geo_bairro b ORDER BY b.bairro""")
        viz = todas_linhas(conn, "SELECT bairro, vizinho, divisa, km FROM geo_bairro_vizinho ORDER BY bairro, km")
        por = {}
        for v in viz:
            por.setdefault(v["bairro"], []).append({"bairro": v["vizinho"], "divisa": v["divisa"], "km": float(v["km"])})
        saida = [{"bairro": b["bairro"], "lat": b["lat"], "lon": b["lon"], "poligono": b["poligono"],
                  "fonte": b["fonte"], "area_km2": float(b["area_km2"]) if b["area_km2"] is not None else None,
                  "imoveis": b["imoveis"], "vizinhos": por.get(b["bairro"], [])} for b in bairros]
        return jsonify(saida), 200, {"Cache-Control": "public, max-age=3600"}
    finally:
        conn.close()


@app.route("/api/imoveis/<int:codigo>/ao-redor")
def api_imovel_ao_redor(codigo):
    """Os bairros a ate 2 km do imovel, medidos ate a BORDA de cada bairro, e a
    precisao do ponto (condominio, rua ou centro do bairro)."""
    conn = conectar()
    try:
        g = todas_linhas(conn, "SELECT lat, lon, precisao, bairro FROM imovel_geo WHERE codigo = %s", (codigo,))
        perto = todas_linhas(conn, """SELECT bairro, km, dentro FROM imovel_bairro_ao_redor
                                       WHERE codigo = %s ORDER BY km, bairro""", (codigo,))
        return jsonify({"codigo": codigo, "ponto": g[0] if g else None,
                        "bairros": [{"bairro": l["bairro"], "km": float(l["km"]), "dentro": l["dentro"]} for l in perto]})
    finally:
        conn.close()


@app.route("/api/imoveis/opcoes")
def api_imoveis_opcoes():
    """As opções dos filtros de várias escolhas da lista de imóveis (28/09):
    bairros, tipos e condomínios como estão escritos no banco, com quantos
    imóveis cada um tem. Sem dado pessoal."""
    conn = conectar()
    try:
        def lista(coluna):
            return [{"valor": l["valor"], "n": l["n"]} for l in todas_linhas(conn,
                "SELECT " + coluna + " AS valor, count(*) AS n FROM vw_imoveis_todos "
                "WHERE coalesce(btrim(" + coluna + "), '') <> '' GROUP BY 1 ORDER BY 1")]
        # CONJUNTOS E AVENIDAS (Pedro, 30/09): as listas da Nay (206). O conjunto
        # conta o bairro dele e o condomínio de mesmo nome; a avenida, os bairros dela.
        conjuntos = [{"valor": l["valor"], "bairro": l["bairro"], "zona": l["zona"], "n": l["n"]} for l in todas_linhas(conn, """
            WITH v AS MATERIALIZED (SELECT codigo, bairro FROM vw_imoveis_todos),
                 cb AS MATERIALIZED (SELECT c.nome, c.zona, nai_bairros_do_conjunto(c.nome) AS bs
                                       FROM nai_lugar_conjunto c WHERE c.ativo),
                 u AS (SELECT cb.nome, v.codigo FROM cb JOIN v ON v.bairro = ANY (cb.bs)
                       UNION
                       SELECT cb.nome, l.codigo FROM cb JOIN imovel_lugar l ON cb.nome = ANY (l.conjuntos)
                        JOIN v ON v.codigo = l.codigo)
            SELECT cb.nome AS valor, array_to_string(cb.bs, ' / ') AS bairro, cb.zona, count(u.codigo) AS n
              FROM cb LEFT JOIN u ON u.nome = cb.nome
             GROUP BY 1, 2, 3 ORDER BY 1""")]
        # 229: a avenida conta também o imóvel que a tem no endereço (imovel_lugar)
        avenidas = [{"valor": l["valor"], "bairros": l["bairros"], "n": l["n"]} for l in todas_linhas(conn, """
            WITH v AS MATERIALIZED (SELECT codigo, bairro FROM vw_imoveis_todos),
                 u AS (SELECT a.nome, v.codigo FROM nai_lugar_avenida a JOIN v ON v.bairro = ANY (a.bairros) WHERE a.ativo
                       UNION
                       SELECT a.nome, l.codigo FROM nai_lugar_avenida a JOIN imovel_lugar l ON a.nome = ANY (l.avenidas)
                        JOIN v ON v.codigo = l.codigo WHERE a.ativo)
            SELECT a.nome AS valor, a.bairros, count(u.codigo) AS n
              FROM nai_lugar_avenida a LEFT JOIN u ON u.nome = a.nome
             WHERE a.ativo GROUP BY 1, 2 ORDER BY 1""")]
        # ZONA (229): os bairros de cada zona (bairro_zona) e quantos imóveis
        zonas = [{"valor": l["valor"], "bairros": l["bairros"], "n": l["n"]} for l in todas_linhas(conn, """
            WITH v AS MATERIALIZED (SELECT codigo, bairro FROM vw_imoveis_todos)
            SELECT z.zona AS valor, array_agg(DISTINCT z.bairro ORDER BY z.bairro) AS bairros,
                   count(DISTINCT v.codigo) AS n
              FROM bairro_zona z LEFT JOIN v ON v.bairro = z.bairro
             GROUP BY 1 ORDER BY 1""")]
        return jsonify({"bairros": lista("bairro"), "tipos": lista("tipo"),
                        "condominios": lista("condominio"), "conjuntos": conjuntos,
                        "avenidas": avenidas, "zonas": zonas}), 200, {"Cache-Control": "public, max-age=300"}
    finally:
        conn.close()


@app.route("/api/imoveis/<int:codigo>/sugestoes")
def api_imovel_sugestoes(codigo):
    """SUGESTOES POR PERTO (Tel, 28/09/2026): "agora que tem o mapa quero
    implementar sugestoes de imoveis proximos (no mesmo bairro) e em outros
    bairros, ai listar o bairro e embaixo os imoveis disponiveis (nome,
    status, se e locacao ou venda, e preco)".

    Primeiro o bairro do proprio imovel; depois os bairros a ate 2 km, os
    mesmos da gaveta ("Bairros ao redor"), do mais perto ao mais longe. Em cada
    um, os imoveis DISPONIVEIS e nossos -- parceria esta fora de tudo (Tel,
    28/09) --, do mais perto ao mais longe do ponto deste imovel.

    O bairro e o do PONTO no mapa (`imovel_geo`), nao o texto do cadastro: e o
    mesmo de `imovel_bairro_ao_redor`, e o cadastro escreve o mesmo bairro de
    varios jeitos."""
    por_bairro = max(1, min(_inteiro(request.args.get("por_bairro") or 8, 8), 30))
    max_bairros = max(0, min(_inteiro(request.args.get("bairros") or 6, 6), 15))
    conn = conectar()
    try:
        g = todas_linhas(conn, "SELECT lat, lon, bairro FROM imovel_geo WHERE codigo = %s", (codigo,))
        if not g or g[0]["lat"] is None or not g[0]["bairro"]:
            return jsonify({"codigo": codigo, "ponto": None, "bairros": []})
        p = g[0]
        vizinhos = [l["bairro"] for l in todas_linhas(conn, """
            SELECT bairro FROM imovel_bairro_ao_redor
             WHERE codigo = %s AND NOT dentro AND bairro <> %s
             ORDER BY km, bairro LIMIT %s""", (codigo, p["bairro"], max_bairros))]
        km_do_bairro = {l["bairro"]: float(l["km"]) for l in todas_linhas(conn, """
            SELECT bairro, km FROM imovel_bairro_ao_redor WHERE codigo = %s""", (codigo,))}
        ordem = [p["bairro"]] + vizinhos

        linhas = todas_linhas(conn, """
            WITH perto AS (
              SELECT v.codigo, v.condominio, v.tipo, v.status, v.valor_venda, v.valor_aluguel,
                     v.valor_texto, v.publicado_no_site, g.bairro,
                     6371 * 2 * asin(sqrt(power(sin(radians(g.lat - %(lat)s) / 2), 2)
                       + cos(radians(%(lat)s)) * cos(radians(g.lat))
                       * power(sin(radians(g.lon - %(lon)s) / 2), 2))) AS km
                FROM vw_imoveis_todos v
                JOIN imovel_geo g ON g.codigo = v.codigo
               WHERE g.bairro = ANY(%(bairros)s) AND v.codigo <> %(codigo)s
                 AND v.status = 'Disponível' AND NOT v.e_parceiro
            )
            SELECT *, row_number() OVER (PARTITION BY bairro ORDER BY km, codigo) AS n,
                   count(*) OVER (PARTITION BY bairro) AS no_bairro
              FROM perto""", {"lat": p["lat"], "lon": p["lon"], "bairros": ordem, "codigo": codigo})

        def finalidade(l):
            venda = (l["valor_venda"] or 0) > 0 or (l["valor_texto"] or "").lower().startswith("venda")
            aluguel = (l["valor_aluguel"] or 0) > 0 or (l["valor_texto"] or "").lower().startswith("aluguel")
            return "Venda e locação" if venda and aluguel else "Venda" if venda else "Locação" if aluguel else "—"

        grupos = {b: [] for b in ordem}
        total = {}
        for l in linhas:
            total[l["bairro"]] = l["no_bairro"]
            if l["n"] <= por_bairro:
                grupos[l["bairro"]].append({
                    "codigo": l["codigo"],
                    "nome": l["condominio"] or l["tipo"] or ("Imóvel %s" % l["codigo"]),
                    "tipo": l["tipo"],
                    "status": l["status"],
                    "finalidade": finalidade(l),
                    "valor_venda": float(l["valor_venda"]) if l["valor_venda"] else None,
                    "valor_aluguel": float(l["valor_aluguel"]) if l["valor_aluguel"] else None,
                    "valor_texto": l["valor_texto"],
                    "no_site": bool(l["publicado_no_site"]),
                    "km": round(float(l["km"]), 2),
                })
        saida = [{"bairro": b, "mesmo_bairro": b == p["bairro"],
                  "km": 0.0 if b == p["bairro"] else km_do_bairro.get(b),
                  "total": total.get(b, 0), "imoveis": grupos[b]} for b in ordem]
        return jsonify({"codigo": codigo, "ponto": {"bairro": p["bairro"]}, "bairros": saida})
    finally:
        conn.close()


# ===================================================== REGRAS SUGERIDAS --
# Tel, 27/09/2026: "crie uma nova função lá no site treino da Nay... vai me
# sugerir regras novas... ao clicar na regra aparece um popup com a conversa
# que ela veio". As tabelas existiam desde a 128; faltava a tela (Pedro, 28/09:
# "não achei no site, se não tem põe lá").
#
# Em /admin/api, com a senha conferida aqui dentro: os casos são conversas de
# corretores de verdade, e a /api/ deste serviço não tem senha nenhuma. Lê e
# grava pela role de CONTEÚDO, que só pode mudar o estado da sugestão (155).

@app.route("/admin/api/nai/regras-sugeridas")
def admin_regras_sugeridas():
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_conteudo()
    try:
        linhas = todas_linhas(conn, """
            SELECT s.id, s.rodada, s.categoria, s.importancia, s.tipo, s.estado,
                   s.titulo, s.regra, s.o_que_faz, s.porque,
                   to_char(s.janela_de, 'DD/MM') AS janela_de,
                   to_char(s.janela_ate, 'DD/MM') AS janela_ate,
                   to_char(s.criada_em, 'DD/MM/YYYY') AS criada_em,
                   to_char(s.decidido_em, 'DD/MM/YYYY HH24:MI') AS decidido_em,
                   s.decidido_por, s.nota_do_tel,
                   (SELECT count(*) FROM nai_regra_sugerida_caso c WHERE c.sugestao_id = s.id) AS casos
              FROM nai_regra_sugerida s
             ORDER BY CASE s.importancia WHEN 'alta' THEN 0 WHEN 'media' THEN 1 ELSE 2 END,
                      s.categoria, s.id""")
        return jsonify([dict(l) for l in linhas])
    finally:
        conn.close()


@app.route("/admin/api/nai/treino-pedidos")
def admin_treino_pedidos():
    """TREINAMENTO POR PEDIDO (Pedro, 30/09): os pedidos que a Nay não teve certeza
    (nai_treino_pedido, 234). ?estado=novo|explicado|implementado|ignorado|todos."""
    if not senha_do_admin_confere():
        return _sem_senha()
    estado = str(request.args.get("estado") or "novo").strip()
    cond = "" if estado == "todos" else "WHERE p.estado = %s"
    conn = conectar_conteudo()
    try:
        linhas = todas_linhas(conn, """
            SELECT p.id, p.turno_id, p.quem, p.texto, p.resposta, p.motivos, p.estado,
                   p.explicacao, p.explicado_por,
                   to_char(p.criado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando,
                   to_char(p.explicado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS explicado_quando,
                   (SELECT count(*) FROM nai_treino_pedido x WHERE x.estado = 'novo') AS novos
              FROM nai_treino_pedido p """ + cond + """
             ORDER BY p.criado_em DESC LIMIT 400""", (() if estado == "todos" else (estado,)))
        return jsonify([dict(l) for l in linhas])
    finally:
        conn.close()


@app.route("/admin/api/nai/treino-pedidos", methods=["POST"])
def admin_treino_pedidos_salvar():
    """Grava as explicações de uma vez: [{id, explicacao}]. Explicação vazia não mexe."""
    if not senha_do_admin_confere():
        return _sem_senha()
    dados = request.get_json(silent=True) or {}
    itens = dados.get("itens") if isinstance(dados, dict) else None
    por = str((dados or {}).get("por") or "painel").strip()[:60]
    if not isinstance(itens, list):
        return jsonify({"erro": "mande itens: [{id, explicacao}]"}), 400
    conn = conectar_conteudo()
    try:
        n = 0
        with conn.cursor() as cur:
            for it in itens[:500]:
                try:
                    pid = int(it.get("id"))
                except Exception:
                    continue
                exp = str(it.get("explicacao") or "").strip()[:4000]
                if not exp:
                    continue
                cur.execute("""
                    UPDATE nai_treino_pedido
                       SET explicacao = %s, explicado_por = %s, explicado_em = now(),
                           estado = CASE WHEN estado = 'novo' THEN 'explicado' ELSE estado END
                     WHERE id = %s AND explicacao IS DISTINCT FROM %s""", (exp, por, pid, exp))
                n += cur.rowcount
        conn.commit()
        return jsonify({"ok": True, "gravados": n})
    finally:
        conn.close()


@app.route("/admin/api/nai/regras-sugeridas/<int:sid>/casos")
def admin_regras_sugeridas_casos(sid):
    """As conversas que provam a sugestão -- o popup."""
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_conteudo()
    try:
        linhas = todas_linhas(conn, """
            SELECT c.id, c.quem, to_char(c.quando, 'DD/MM/YYYY HH24:MI') AS quando, c.turno_id,
                   c.ele_disse, c.ela_disse, c.o_ponto
              FROM nai_regra_sugerida_caso c
             WHERE c.sugestao_id = %s
             ORDER BY c.quando NULLS LAST, c.id""", (sid,))
        return jsonify([dict(l) for l in linhas])
    finally:
        conn.close()


@app.route("/admin/api/nai/regras-sugeridas/<int:sid>", methods=["PUT"])
def admin_regras_sugeridas_decidir(sid):
    """Aceita, recusa ou devolve para 'sugerida'. Aceitar NÃO muda a Nay:
    marca para implementar -- a regra passa a valer quando entra no prompt ou
    nas funções."""
    if not senha_do_admin_confere():
        return _sem_senha()
    dados = request.get_json(silent=True) or {}
    estado = str(dados.get("estado") or "").strip()
    if estado not in ("aceita", "recusada", "sugerida"):
        return jsonify({"erro": "estado tem que ser aceita, recusada ou sugerida"}), 400
    nota = str(dados.get("nota") or "").strip()[:2000] or None
    por = str(dados.get("por") or "painel").strip()[:60]
    conn = conectar_conteudo()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE nai_regra_sugerida
                   SET estado = %(estado)s,
                       decidido_em = CASE WHEN %(estado)s = 'sugerida' THEN NULL ELSE now() END,
                       decidido_por = CASE WHEN %(estado)s = 'sugerida' THEN NULL ELSE %(por)s END,
                       nota_do_tel = %(nota)s
                 WHERE id = %(id)s
             RETURNING id, estado""", {"estado": estado, "por": por, "nota": nota, "id": sid})
            r = cur.fetchone()
        conn.commit()
        if not r:
            return jsonify({"erro": "essa sugestão não existe"}), 404
        return jsonify({"ok": True, "id": r["id"], "estado": r["estado"]})
    finally:
        conn.close()


@app.route("/api/condominios/sugerir")
def api_condominios_sugerir():
    """Sugestao enquanto digita: sem acento, acha no meio do nome
    ("acquarelle" acha "Condominio Acquarelle") e tolera erro de digitacao
    (trigrama). O nome que comeca com o que ele digitou vem primeiro."""
    q = str(request.args.get("q") or "").strip()[:60]
    # desde a PRIMEIRA letra (Pedro, 08/10/2026: "desça a lista filtrando letra a letra")
    if len(q) < 1:
        return jsonify([])
    conn = conectar()
    try:
        linhas = todas_linhas(conn, r"""
            WITH b AS (SELECT lower(nay_sem_acento(%s)) AS q)
            SELECT c.id, c.nome, c.bairro,
                   (SELECT count(*) FROM imoveis i WHERE i.condo_id = c.id) AS imoveis
              FROM condominios c, b
             WHERE lower(nay_sem_acento(c.nome)) LIKE '%%' || b.q || '%%'
                OR similarity(lower(nay_sem_acento(c.nome)), b.q) > 0.3
             ORDER BY (regexp_replace(lower(nay_sem_acento(c.nome)),
                        '^(condominio|residencial|edificio|cond\.?)\s+', '') LIKE b.q || '%%') DESC,
                      (lower(nay_sem_acento(c.nome)) LIKE '%%' || b.q || '%%') DESC,
                      similarity(lower(nay_sem_acento(c.nome)), b.q) DESC, c.nome
             LIMIT 30
        """, (q,))
        return jsonify([{"id": l["id"], "nome": l["nome"], "bairro": l["bairro"], "imoveis": l["imoveis"]}
                        for l in linhas])
    finally:
        conn.close()


@app.route("/api/condominios/<int:cid>/endereco")
def api_condominio_endereco(cid):
    """O endereco de um condominio, para o editor preencher sozinho.

    Pedido do Tel (30/09/2026): "quando selecionado ele ja preenche com os
    dados de endereco desse condominio".

    DE ONDE VEM: a tabela `condominios` tem so id, nome e bairro -- rua e
    cidade nao existem la. Entao saem dos IMOVEIS ja ligados a esse condominio
    (`condo_id`), pelo valor mais frequente. Medido em 30/09: todo condominio
    com 3 ou mais imoveis tem UMA rua so, entao a moda e o endereco, nao um
    chute. `base` diz de quantos imoveis veio -- com 1 so, quem preenche ve
    de onde saiu e confere.
    """
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            SELECT c.nome, c.bairro AS bairro_cadastro,
                   count(i.codigo) FILTER (WHERE coalesce(i.logradouro, '') <> '') AS base,
                   mode() WITHIN GROUP (ORDER BY i.logradouro)
                     FILTER (WHERE coalesce(i.logradouro, '') <> '') AS logradouro,
                   mode() WITHIN GROUP (ORDER BY i.bairro)
                     FILTER (WHERE coalesce(i.bairro, '') <> '')     AS bairro_imoveis,
                   mode() WITHIN GROUP (ORDER BY i.cidade)
                     FILTER (WHERE coalesce(i.cidade, '') <> '')     AS cidade,
                   mode() WITHIN GROUP (ORDER BY i.estado)
                     FILTER (WHERE coalesce(i.estado, '') <> '')     AS estado,
                   mode() WITHIN GROUP (ORDER BY i.numero)
                     FILTER (WHERE coalesce(i.numero, '') <> '')     AS numero
              FROM condominios c
              LEFT JOIN imoveis i ON i.condo_id = c.id
             WHERE c.id = %s
             GROUP BY c.nome, c.bairro
        """, (cid,))
        if not linhas:
            return jsonify({"erro": "condominio nao encontrado"}), 404
        l = linhas[0]
        # A FICHA DO CONDOMÍNIO (Pedro, 30/09: "ao clicar no condomínio no cadastro
        # do imóvel pela OLX ele já preencha os outros campos"): lazer, elevador,
        # andares, construtora e ano da condominio_ficha (210/229), quando existe.
        ficha = todas_linhas(conn, """
            SELECT f.lazer, f.elevador, f.andares, f.aptos_por_andar, f.torres, f.construtora,
                   f.ano_lancamento, f.revestimento, f.endereco, f.unidades,
                   f.logradouro, f.numero, f.bairro, f.cidade, f.estado, f.cep
              FROM condominio_ficha f WHERE f.condominio_id = %s LIMIT 1""", (cid,))
        f = ficha[0] if ficha else None
        def inteiro(txt):
            m = re.search(r"\d+", str(txt or ""))
            return int(m.group(0)) if m else None
        # O CONDOMÍNIO GUARDA O PRÓPRIO ENDEREÇO (273, Pedro 02/10: "quando selecionei
        # condomínio não puxou o número"). A ordem: o que está nos campos da ficha; senão o
        # endereço em texto da ficha ("Av. X, nº 4731, Bairro Y, Manaus - AM"); senão o mais
        # comum entre os imóveis já ligados.
        do_texto = _endereco_em_partes(f["endereco"]) if f else {}
        def dado(campo, reserva=None):
            return ((f or {}).get(campo) or do_texto.get(campo) or reserva or None)
        return jsonify({
            "numero": dado("numero", l["numero"]),
            "cep": dado("cep"),
            "id": cid,
            "nome": l["nome"],
            "base": l["base"],
            "ficha": None if not f else {
                "lazer": list(f["lazer"] or []),
                "elevador": f["elevador"],
                # "Sim, possui 2 elevadores por torre" -> 2; "Sim, possui elevador" -> 1; "Não..." -> 0
                "elevadores": (0 if re.match(r"^\s*n[aã]o", str(f["elevador"] or ""), re.I)
                               else (inteiro(f["elevador"]) or (1 if f["elevador"] else None))),
                "andares": inteiro(f["andares"]),
                "aptos_por_andar": f["aptos_por_andar"],
                "torres": f["torres"],
                "construtora": f["construtora"],
                "ano_lancamento": f["ano_lancamento"],
                "revestimento": f["revestimento"],
                "endereco": f["endereco"],
                "unidades": f["unidades"],
            },
            # o bairro do cadastro manda; o dos imoveis e a reserva
            "bairro": l["bairro_cadastro"] or dado("bairro", l["bairro_imoveis"]),
            "logradouro": dado("logradouro", l["logradouro"]),
            "cidade": dado("cidade", l["cidade"]),
            "estado": dado("estado", l["estado"]),
            # O CEP so vem da ficha do condominio: a role de leitura do site nao tem
            # SELECT na coluna `cep` de `imoveis` (as permissoes dela sao por coluna).
            # Pedir a coluna derruba a rota inteira com "permission denied for
            # table imoveis" -- foi o que aconteceu ao subir isto em 30/09.
        })
    finally:
        conn.close()


def _endereco_em_partes(texto):
    """"Av. Cosme Ferreira, nº 4731, Bairro Aleixo, Manaus - AM" em rua, numero, cidade e
    estado. E o formato das fichas de condominio escritas a mao (30/09)."""
    partes = [p.strip() for p in str(texto or "").split(",") if p.strip()]
    if not partes:
        return {}
    d = {"logradouro": partes[0]}
    for p in partes[1:]:
        m = re.match(r"^(?:n[ºo°.]*\s*)?(\d[\w/-]*|s/?n)$", p, re.I)
        if m and "numero" not in d:
            d["numero"] = m.group(1)
            continue
        m = re.match(r"^(.+?)\s*[-/]\s*([A-Za-z]{2})$", p)
        if m and not re.match(r"^bairro\b", p, re.I):
            d["cidade"], d["estado"] = m.group(1).strip(), m.group(2).upper()
    return d


def _guardar_no_condominio(cur, codigo, corpo, extras):
    """O que se digita no cadastro de um imovel e que e DO CONDOMINIO (endereco, numero, CEP,
    andares, elevadores, caracteristicas do condominio) fica guardado no condominio, para o
    proximo imovel dele ja nascer preenchido (273, Pedro 02/10: "nao quero ter que digitar a
    mesma informacao 2 vezes"). Num savepoint: se isto falhar, o imovel e salvo do mesmo jeito."""
    dados = {k: str(corpo[k]).strip() for k in ("logradouro", "numero", "bairro", "cidade", "estado", "cep")
             if str(corpo.get(k) or "").strip()}
    if (extras or {}).get("caracteristicas do condominio"):
        dados["lazer"] = [x.strip() for x in re.split(r"[,\n]", extras["caracteristicas do condominio"]) if x.strip()]
    for k in ("andares", "elevadores"):
        if (extras or {}).get(k):
            dados[k] = str(extras[k])
    if not dados:
        return
    cur.execute("SAVEPOINT do_condominio")
    try:
        cur.execute("SELECT condo_id, tipo FROM imoveis WHERE codigo = %s", (codigo,))
        l = cur.fetchone()
        if l and l["condo_id"]:
            dados["vertical"] = bool(re.match(r"\s*(apartamento|flat|cobertura|studio|kitnet|loft|sala)", str(l["tipo"] or ""), re.I))
            cur.execute("SELECT site_condominio_guardar(%s, %s)", (l["condo_id"], psycopg2.extras.Json(dados)))
        cur.execute("RELEASE SAVEPOINT do_condominio")
    except Exception as exc:  # noqa: BLE001
        cur.execute("ROLLBACK TO SAVEPOINT do_condominio")
        app.logger.warning("condominio nao guardou os dados do imovel %s: %s", codigo, exc.__class__.__name__)


@app.route("/api/imoveis/campos")
def api_imovel_campos():
    """Os campos que o formulario pode gravar -- a tela de NOVO imovel usa."""
    return jsonify(CAMPOS_EDITAVEIS)


@app.route("/api/clientes-lista")
def api_clientes_lista():
    """Clientes do admin antigo (clientes_admin_real, 1.039). A tela era
    100%% estatica. Busca, funil de etapa, corretor, paginacao, CSV."""
    a = request.args
    per = max(1, min(int(a.get("per") or 30), 5000))
    page = max(1, int(a.get("page") or 1))
    conds, params = [], []
    q = str(a.get("q") or "").strip()[:80]
    if q:
        dig = re.sub(r"\D", "", q)
        conds.append("(nay_sem_acento(lower(c.nome)) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'"
                     " OR lower(coalesce(c.email, '')) LIKE '%%' || lower(%s) || '%%'"
                     " OR (length(%s) >= 4 AND regexp_replace(coalesce(c.telefone, ''), '\\D', '', 'g') LIKE '%%' || %s || '%%'))")
        params.extend([q, q, dig, dig])
    etapa = str(a.get("etapa") or "").strip()
    if etapa and etapa != "Todos":
        conds.append("coalesce(NULLIF(btrim(c.etapa), ''), 'Sem etapa') = %s")
        params.append(etapa)
    corretor = str(a.get("corretor") or "").strip()
    if corretor and corretor != "Todos":
        conds.append("c.corretor_nome = %s")
        params.append(corretor)
    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    ordem = "c.nome" if a.get("ordem") == "nome" else "c.id_admin DESC"
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT c.*, count(*) OVER () AS total FROM clientes_admin_real c " + where +
                              " ORDER BY " + ordem + " LIMIT %s OFFSET %s", tuple(params + [per, (page - 1) * per]))
        funil = todas_linhas(conn, "SELECT coalesce(NULLIF(btrim(etapa), ''), 'Sem etapa') AS etapa, count(*) AS n "
                                   "FROM clientes_admin_real GROUP BY 1 ORDER BY 2 DESC")
        corretores = todas_linhas(conn, "SELECT corretor_nome FROM clientes_admin_real WHERE NULLIF(btrim(corretor_nome), '') "
                                        "IS NOT NULL GROUP BY 1 ORDER BY 1")
        itens = [{"id": l["id_admin"], "nome": l["nome"] or "—", "telefone": l["telefone"] or "—",
                  "email": l["email"] or "—", "etapa": l["etapa"] or "Sem etapa",
                  "corretor": l["corretor_nome"] or "—"} for l in linhas]
        if a.get("formato") == "csv":
            return _csv(["nome", "telefone", "email", "etapa", "corretor"],
                        [[i["nome"], i["telefone"], i["email"], i["etapa"], i["corretor"]] for i in itens], "clientes")
        return jsonify({"total": linhas[0]["total"] if linhas else 0, "page": page, "per": per, "itens": itens,
                        "funil": [{"rotulo": f["etapa"], "contagem": f["n"]} for f in funil],
                        "corretores": [c["corretor_nome"] for c in corretores]})
    finally:
        conn.close()


@app.route("/api/imoveis", methods=["POST"])
@app.route("/admin/api/imoveis", methods=["POST"])
def api_imovel_criar():
    """NOVO IMOVEL pelo site. Codigo da faixa 9001-9999 (migracao 161: 4
    digitos como todo codigo da casa, e longe do imobeasy.com, que numera em
    sequencia e estava no 5765 em 28/09 -- a varredura sobrescreveria um codigo
    repetido). Ate 28/09 era 900000+, e o Pedro achou "um numero estranho".

    NENHUM CAMPO E OBRIGATORIO (Pedro, 28/09: "ponha todos os campos do site
    antigo mas sem ser obrigatorio, poe so as informacoes que tivermos") -- o
    tipo era, e o Tel nao conseguia cadastrar. Nasce como RASCUNHO, fora do
    site e da Nay, a nao ser que venha outra situacao; a regra e a mesma da
    edicao (Disponivel = no site e na Nay)."""
    if not senha_do_admin_confere():
        return _sem_senha()
    corpo = request.get_json(silent=True) or {}
    situacao = str(corpo.get("status") or "Rascunho").strip()
    if situacao not in STATUS_EDITAVEIS:
        return jsonify({"erro": "validação", "detalhes": ["status: use " + ", ".join(STATUS_EDITAVEIS)]}), 400
    no_ar = situacao == "Disponível"
    cols = ["origem", "status", "publicado_no_site", "disponivel", "criado_em"]
    vals = ["crm", situacao, no_ar, no_ar, datetime.now()]
    erros = []
    for campo, valor in corpo.items():
        regra = CAMPOS_EDITAVEIS.get(campo)
        if not regra or campo in ("publicado_no_site", "disponivel", "bloqueado", "motivo_bloqueio") or valor in (None, ""):
            continue
        try:
            if regra["tipo"] == "numero":
                valor = _numero_br(valor)
                absurdo = _valor_que_nao_existe(campo, valor)
                if absurdo:
                    erros.append(absurdo)
                    continue
            elif regra["tipo"] == "inteiro":
                valor = int(valor)
            elif regra["tipo"] == "booleano":
                valor = bool(valor)
            elif regra["tipo"] == "lista":
                if not isinstance(valor, list):
                    raise ValueError
                valor = [str(v) for v in valor]
            else:
                valor = str(valor)
        except (TypeError, ValueError):
            erros.append(f"{campo}: valor inválido")
            continue
        cols.append(campo)
        vals.append(valor)
    # os campos do site antigo (extras) e a parte privada (unidade, locacao)
    _apagar, gravar = _extras_do_corpo(corpo, erros)
    if gravar:
        cols.append("extras")
        vals.append(psycopg2.extras.Json(gravar))
    unidade, ficha, vencimento = _privado_do_corpo(corpo, erros)
    unidade = {k: v for k, v in unidade.items() if v is not None}
    ficha = {k: v for k, v in ficha.items() if v is not None}
    if vencimento is None:
        vencimento = _SEM_VENCIMENTO
    dono, _ = _proprietario_do_corpo(corpo)
    if erros:
        return jsonify({"erro": "validação", "detalhes": erros}), 400
    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            cid = corpo.get("condo_id")
            if cid not in (None, ""):
                cur.execute("SELECT id, nome FROM condominios WHERE id = %s", (int(cid),))
                c = cur.fetchone()
                if not c:
                    return jsonify({"erro": "validação", "detalhes": ["condomínio não existe"]}), 400
                cols += ["condo_id", "condominio_nome"]
                vals += [c["id"], c["nome"]]
            query = psycopg2.sql.SQL(
                "INSERT INTO imoveis (codigo, {}) VALUES (nextval('imoveis_crm_codigo_seq'), {}) RETURNING codigo"
            ).format(psycopg2.sql.SQL(", ").join(psycopg2.sql.Identifier(c) for c in cols),
                     psycopg2.sql.SQL(", ").join(psycopg2.sql.Placeholder() for _ in cols))
            cur.execute(query, vals)
            novo = cur.fetchone()["codigo"]
            _gravar_privado(cur, novo, unidade, ficha, vencimento)
            _gravar_proprietario(cur, novo, dono, True)
            _guardar_no_condominio(cur, novo, corpo, gravar)
        conn.commit()
        return jsonify({"status": "criado", "codigo": novo}), 201
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@app.route("/api/proprietarios-lista")
def api_proprietarios_lista():
    """Cadastro geral de proprietarios (base do admin antigo), SEM quem tem
    o selo de parceria e sem corretor/empresa/conta interna (a regra mora na
    view vw_proprietarios_site). Busca, funil, especialista, paginacao, CSV."""
    a = request.args
    per = max(1, min(int(a.get("per") or 30), 5000))
    page = max(1, int(a.get("page") or 1))
    conds, params = [], []
    q = str(a.get("q") or "").strip()[:80]
    if q:
        dig = re.sub(r"\D", "", q)
        conds.append("(nay_sem_acento(lower(p.nome)) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'"
                     " OR lower(coalesce(p.email, '')) LIKE '%%' || lower(%s) || '%%'"
                     " OR (length(%s) >= 4 AND regexp_replace(coalesce(p.telefone, ''), '\\D', '', 'g') LIKE '%%' || %s || '%%')"
                     " OR (%s <> '' AND (', ' || coalesce(p.codigos, '') || ',') LIKE '%%, ' || %s || ',%%'))")
        params.extend([q, q, dig, dig, q if q.isdigit() else "", q])
    etapa = str(a.get("etapa") or "").strip()
    if etapa and etapa != "Todos":
        conds.append("p.etapa = %s")
        params.append(etapa)
    esp = str(a.get("especialista") or "").strip()
    if esp and esp != "Todos":
        conds.append("p.especialista = %s")
        params.append(esp)
    # 05/10 (Pedro): "põe campos para eu pesquisar" -- cada campo filtra só a sua coluna
    nome = str(a.get("nome") or "").strip()[:80]
    if nome:
        conds.append("nay_sem_acento(lower(coalesce(p.nome, ''))) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'")
        params.append(nome)
    for campo, coluna in (("telefone", "p.telefone"), ("cpf", "p.cpf")):
        dig = re.sub(r"\D", "", str(a.get(campo) or ""))[:20]
        if len(dig) >= 3:
            conds.append("regexp_replace(coalesce(" + coluna + ", ''), '\\D', '', 'g') LIKE '%%' || %s || '%%'")
            params.append(dig)
    email = str(a.get("email") or "").strip()[:80]
    if email:
        conds.append("lower(coalesce(p.email, '')) LIKE '%%' || lower(%s) || '%%'")
        params.append(email)
    codigo = re.sub(r"\D", "", str(a.get("codigo") or ""))[:6]
    if codigo:
        conds.append("(', ' || coalesce(p.codigos, '') || ',') LIKE '%%, ' || %s || ',%%'")
        params.append(codigo)
    if a.get("imoveis") == "com":
        conds.append("p.imoveis > 0")
    elif a.get("imoveis") == "sem":
        conds.append("p.imoveis = 0")
    # "põe uma tag se foi conectado pela captação ou não": o lead da captação desse proprietário, se houver
    cap = ("(SELECT cl.status FROM captacao_leads cl WHERE cl.proprietario_id = p.id"
           " ORDER BY (cl.status IN ('respondendo', 'concluido')) DESC, (cl.status = 'enviado') DESC, cl.id DESC LIMIT 1)")
    filtro_cap = {"respondeu": cap + " IN ('respondendo', 'concluido')", "chamado": cap + " = 'enviado'",
                  "sim": cap + " IN ('respondendo', 'concluido', 'enviado')", "fila": cap + " = 'novo'",
                  "nao": cap + " IS NULL"}.get(str(a.get("captacao") or ""))
    if filtro_cap:
        conds.append(filtro_cap)
    # do mais antigo para o mais novo por padrão (o id segue a ordem do cadastro)
    ordem = {"antigos": "p.id", "recentes": "p.id DESC", "nome": "p.nome NULLS LAST, p.id",
             "nome_desc": "p.nome DESC NULLS LAST, p.id", "imoveis": "p.imoveis DESC, p.id",
             "imoveis_asc": "p.imoveis, p.id"}.get(a.get("ordem"), "p.id")
    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT p.*, " + cap + " AS captacao, count(*) OVER () AS total"
                              " FROM vw_proprietarios_site p " + where +
                              " ORDER BY " + ordem + " LIMIT %s OFFSET %s", tuple(params + [per, (page - 1) * per]))
        funil = todas_linhas(conn, "SELECT etapa, count(*) AS n FROM vw_proprietarios_site GROUP BY 1 ORDER BY 2 DESC")
        especialistas = todas_linhas(conn, "SELECT especialista FROM vw_proprietarios_site "
                                           "WHERE especialista IS NOT NULL GROUP BY 1 ORDER BY 1")
        itens = [{
            "id": l["id"], "nome": l["nome"] or "—", "etapa": l["etapa"], "especialista": l["especialista"],
            "cpf": mascarar_cpf(l["cpf"]) if l["cpf"] else "—", "telefone": l["telefone"] or "—",
            "email": l["email"] or "—", "imoveis": int(l["imoveis"] or 0), "codigos": l["codigos"],
            "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
            # novo | enviado | respondendo | concluido | sem_whatsapp | None (nunca entrou na captação)
            "captacao": l["captacao"],
        } for l in linhas]
        if a.get("formato") == "csv":
            return _csv(["nome", "etapa", "especialista", "telefone", "email", "imoveis", "codigos", "vencimento", "captacao"],
                        [[i["nome"], i["etapa"], i["especialista"], i["telefone"], i["email"], i["imoveis"],
                          i["codigos"], i["vencimento"], i["captacao"] or "fora"] for i in itens], "proprietarios")
        return jsonify({"total": linhas[0]["total"] if linhas else 0, "page": page, "per": per, "itens": itens,
                        "funil": [{"rotulo": f["etapa"], "contagem": f["n"]} for f in funil],
                        "especialistas": [e["especialista"] for e in especialistas]})
    finally:
        conn.close()


# A PONTE DO PAINEL NOVA NAY (06/10/2026, migracao/07-PAINEL-NOVA-NAY.md): a página admin/nova-nay.html só mostra
# o que a API do nay-core devolve. O navegador fala com o site (senha do /admin, pelo Traefik); o site fala com o
# nay-core pela rede do docker, com um segredo que nunca vai ao navegador (NAY_CORE_PAINEL_TOKEN).
@app.route("/admin/api/nova-nay/<path:rota>", methods=["GET", "POST"])
def admin_nova_nay(rota):
    import urllib.error
    import urllib.request
    if not senha_do_admin_confere():
        return _sem_senha()
    base = os.environ.get("NAY_CORE_URL", "")
    segredo = os.environ.get("NAY_CORE_PAINEL_TOKEN", "")
    if not base or not segredo:
        return jsonify({"erro": "a ponte do painel não está configurada"}), 503
    url = base.rstrip("/") + "/painel/" + rota
    if request.query_string:
        url += "?" + request.query_string.decode("utf-8", "ignore")
    req = urllib.request.Request(url, data=request.get_data() if request.method == "POST" else None,
                                 method=request.method,
                                 headers={"X-Painel-Token": segredo, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return Response(r.read(), status=r.status, mimetype="application/json",
                            headers={"Cache-Control": "no-store"})
    except urllib.error.HTTPError as e:
        return Response(e.read(), status=e.code, mimetype="application/json")
    except urllib.error.URLError:
        return jsonify({"erro": "o nay-core não respondeu"}), 502


@app.route("/api/proximos-passos", methods=["GET", "POST"])
def api_proximos_passos():
    conn = conectar_conteudo()
    try:
        if request.method == "GET":
            linhas = todas_linhas(conn, """
                SELECT id, titulo, descricao, ordem FROM site_proximos_passos ORDER BY ordem, id
            """)
            return jsonify(linhas)

        corpo = request.get_json(silent=True) or {}
        titulo = str(corpo.get("titulo") or "").strip()
        if not titulo:
            return jsonify({"erro": "título obrigatório"}), 400
        descricao = str(corpo.get("descricao") or "").strip()
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO site_proximos_passos (titulo, descricao, ordem)
                VALUES (%s, %s, COALESCE((SELECT max(ordem) + 1 FROM site_proximos_passos), 1))
                RETURNING id, titulo, descricao, ordem
            """, (titulo, descricao))
            novo = cur.fetchone()
        conn.commit()
        return jsonify(novo), 201
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@app.route("/api/proximos-passos/<int:item_id>", methods=["PUT", "DELETE"])
def api_proximo_passo_item(item_id):
    conn = conectar_conteudo()
    try:
        if request.method == "DELETE":
            with conn.cursor() as cur:
                cur.execute("DELETE FROM site_proximos_passos WHERE id = %s", (item_id,))
                afetadas = cur.rowcount
            conn.commit()
            if not afetadas:
                return jsonify({"erro": "não encontrado"}), 404
            return jsonify({"status": "removido"})

        corpo = request.get_json(silent=True) or {}
        titulo = str(corpo.get("titulo") or "").strip()
        if not titulo:
            return jsonify({"erro": "título obrigatório"}), 400
        descricao = str(corpo.get("descricao") or "").strip()
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE site_proximos_passos SET titulo = %s, descricao = %s WHERE id = %s
                RETURNING id, titulo, descricao, ordem
            """, (titulo, descricao, item_id))
            atualizado = cur.fetchone()
        conn.commit()
        if not atualizado:
            return jsonify({"erro": "não encontrado"}), 404
        return jsonify(atualizado)
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@app.route("/api/proprietarios-vencimento")
def api_proprietarios_vencimento():
    """Proprietários cujo imóvel tem contrato vencendo/vencido no período
    (?de=&ate=). Única rota que devolve telefone/e-mail SEM máscara --
    decisão consciente porque o ponto de uma lista de proprietários por
    vencimento é retomar contato de verdade; mascarar tornaria a lista
    inútil pro que ela foi pedida pra fazer. Usa a role nay_leitura (a
    mesma do nay-painel, SELECT em tudo, read-only forçado no banco) só
    porque proprietarios/imovel_privado não estão liberados pra
    nay_site_leitura."""
    de, ate = periodo_da_query()
    condicoes = ["p.telefone IS NOT NULL"]
    params = []
    if de:
        condicoes.append("c.vencimento >= %s")
        params.append(de)
    if ate:
        condicoes.append("c.vencimento <= %s")
        params.append(ate)
    where = "WHERE " + " AND ".join(condicoes)

    conn = conectar_tabelas()
    try:
        # Revisao 11/09: a fonte era proprietarios -> imovel_privado ->
        # imoveis -> contratos, e o JOIN com o catalogo reduzia 894 contratos
        # a 30 (e deixava passar parceiro). Agora sai do CONTRATO, com o dono
        # do admin antigo, e SEM parceiro/corretor/conta interna.
        where = where.replace("p.telefone IS NOT NULL", "coalesce(pa.telefone, c.proprietario_telefone) IS NOT NULL")
        linhas = todas_linhas(conn, f"""
            SELECT DISTINCT coalesce(pa.id, c.proprietario_id_admin) AS id,
                   coalesce(pa.nome, c.proprietario_nome) AS nome,
                   coalesce(pa.telefone, c.proprietario_telefone) AS telefone,
                   coalesce(pa.email, c.proprietario_email) AS email,
                   c.codigo, v.condominio AS condominio_nome, c.vencimento
            FROM contratos_locacao c
            LEFT JOIN proprietarios_admin pa ON pa.id = c.proprietario_id_admin
            LEFT JOIN vw_imoveis_todos v ON v.codigo::text = c.codigo
            LEFT JOIN proprietarios_export pe ON pe.id = c.proprietario_id_admin
            {where}
              AND NOT site_nao_e_dono(coalesce(pa.nome, c.proprietario_nome))
              AND coalesce(pe.corretor, '') !~* 'parceir'
              AND NOT coalesce(v.e_parceiro, false)
            ORDER BY c.vencimento ASC NULLS LAST
            LIMIT 2000
        """, params)
        return jsonify([{
            "id": l["id"],
            "nome": l["nome"] or "—",
            "telefone": l["telefone"],
            "email": l["email"],
            "codigo": l["codigo"],
            "condominio": l["condominio_nome"] or "—",
            "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
        } for l in linhas])
    finally:
        conn.close()


@app.route("/api/lead/<codigo>")
def api_lead(codigo):
    """Ficha completa de um lead: tudo que se sabe do imovel e do dono.

    Junta as quatro fontes numa resposta so -- snapshot do admin, detalhe
    raspado da ficha, dados do proprietario e o export em planilha. Onde as
    fontes divergem, a raspagem da ficha ganha (e' a mais recente); o export
    entra so pra preencher buraco."""
    conn = conectar_listas()
    try:
        linhas = todas_linhas(conn, """
            SELECT s.codigo, s.status_admin, s.vencimento AS venc_snapshot,
                   d.*,
                   p.nome AS prop_nome, p.telefone AS prop_telefone, p.email AS prop_email,
                   e.etapa_atual, e.etapa_em, e.etapa_qtd,
                   x.nome AS exp_nome, x.telefone AS exp_telefone, x.email AS exp_email,
                   x.cpf, x.corretor, x.criado_em AS prop_criado_em,
                   s.proprietario_id
              FROM imoveis_admin_snapshot s
              LEFT JOIN imoveis_admin_detalhe d      ON d.codigo = s.codigo
              LEFT JOIN proprietarios_admin p        ON p.id = s.proprietario_id
              LEFT JOIN proprietarios_admin_etapa e  ON e.proprietario_id = s.proprietario_id
              LEFT JOIN proprietarios_export x       ON x.id = s.proprietario_id
             WHERE s.codigo = %s
        """, (codigo,))
        if not linhas:
            return jsonify({"erro": "não encontrado"}), 404
        r = linhas[0]

        def txt(v):
            return None if v in (None, "") else str(v)
        def dec(v):
            return None if v is None else float(v)
        def dia(v):
            return v.isoformat() if v else None

        outros = todas_linhas(conn, """
            SELECT a.codigo, a.condominio, a.endereco,
                   s.status_admin, s.vencimento
              FROM proprietarios_admin_imoveis a
              LEFT JOIN imoveis_admin_snapshot s ON s.codigo = a.codigo
             WHERE a.proprietario_id = %s AND a.codigo <> %s
             ORDER BY a.codigo
        """, (r["proprietario_id"], codigo))

        return jsonify({
            "imovel": {
                "codigo": r["codigo"], "tipo": txt(r["tipo"]),
                "status": txt(r["status_admin"]),
                "condominio": txt(r["condominio"]),
                "logradouro": txt(r["logradouro"]), "numero": txt(r["numero"]),
                "bloco": txt(r["bloco"]), "casa": txt(r["casa"]),
                "torre": txt(r["torre"]), "apartamento": txt(r["apartamento"]),
                "andar": txt(r["andar"]), "cep": txt(r["cep"]),
                "bairro": txt(r["bairro"]), "cidade": txt(r["cidade"]),
                "estado": txt(r["estado"]),
                "area": dec(r["area"]), "terreno": dec(r["terreno"]),
                "area_construida": dec(r["area_construida"]),
                "quartos": r["quartos"], "suites": r["suites"],
                "banheiros": r["banheiros"], "vagas": r["vagas"],
                "vagas_cobertas": r["vagas_cobertas"],
                "lances_escada": r["lances_escada"], "sol": txt(r["sol"]),
                "caracteristicas": txt(r["caracteristicas"]),
                "observacoes": txt(r["observacoes"]),
                "inspecionado_por": txt(r["inspecionado_por"]),
                "captado_em": dia(r["captado_em"]),
                "visitas_30d": r["visitas_30d"],
            },
            "contrato": {
                "vencimento": dia(r["vencimento"] or r["venc_snapshot"]),
                "valor_aluguel": dec(r["valor_aluguel"]),
                "valor_venda": dec(r["valor_venda"]),
                "taxa_condominio": dec(r["taxa_condominio"]),
                "iptu": dec(r["iptu"]),
                "garantia": txt(r["garantia"]), "incluso": txt(r["incluso"]),
                "financiamento": txt(r["financiamento"]),
                "observacao_aluguel": txt(r["observacao_aluguel"]),
                "locatario_nome": txt(r["locatario_nome"]),
                "locatario_contato": txt(r["locatario_contato"]),
            },
            "proprietario": {
                "id": r["proprietario_id"],
                "nome": txt(r["prop_nome"]) or txt(r["exp_nome"]),
                "telefone": txt(r["prop_telefone"]) or txt(r["exp_telefone"]),
                "email": txt(r["prop_email"]) or txt(r["exp_email"]),
                "cpf": txt(r["cpf"]), "corretor": txt(r["corretor"]),
                "etapa": txt(r["etapa_atual"]),
                "etapa_em": dia(r["etapa_em"].date() if r["etapa_em"] else None),
                "cadastrado_em": dia(r["prop_criado_em"]),
                "qtd_imoveis": len(outros) + 1,
            },
            "outros_imoveis": [{
                "codigo": o["codigo"], "condominio": txt(o["condominio"]),
                "endereco": txt(o["endereco"]), "status": txt(o["status_admin"]),
                "vencimento": dia(o["vencimento"]),
            } for o in outros],
        })
    finally:
        conn.close()


def enriquecer_itens(conn, itens):
    """Completa cada linha de uma lista salva com o que a gente aprendeu depois.

    A lista guardada é uma fotografia com poucos campos -- foi assim que ela
    nasceu. Em vez de reescrever as listas antigas (o que apagaria a
    fotografia), a gente junta pelo código, na hora da leitura, o que está
    hoje em imoveis, imoveis_admin_snapshot e proprietarios_admin.

    O campo `vencimento_conferido` vem do admin real; se ele divergir do
    `vencimento` que estava congelado na lista, os dois aparecem, e quem lê
    decide. Nada é sobrescrito."""
    if not itens:
        return itens

    codigos = [str(i.get("codigo")) for i in itens if i.get("codigo")]
    if not codigos:
        return itens

    dados = {}
    for linha in todas_linhas(conn, """
        SELECT s.codigo,
               s.status_admin,
               s.vencimento              AS vencimento_conferido,
               s.proprietario_id,
               p.nome                    AS prop_nome,
               p.telefone                AS prop_telefone,
               p.email                   AS prop_email,
               i.tipo, i.bairro, i.cidade, i.logradouro, i.numero,
               i.condominio_nome, i.valor_aluguel, i.valor_venda,
               -- a tabela `imoveis` so tem o que esta anunciado publicamente;
               -- imovel alugado nao aparece la. O endereco desses vem do admin.
               a.condominio AS condominio_admin,
               a.endereco   AS endereco_admin,
               -- detalhe de lead raspado da ficha do admin
               d.tipo AS tipo_admin, d.bairro AS bairro_admin, d.cidade,
               d.logradouro AS log_admin, d.numero AS num_admin, d.andar,
               d.area, d.quartos, d.suites, d.banheiros, d.vagas,
               d.caracteristicas, d.valor_aluguel AS aluguel_admin,
               d.garantia, d.incluso, d.captado_em, d.visitas_30d,
               d.condominio AS cond_detalhe,
               e.etapa_atual, e.etapa_em,
               (SELECT count(*) FROM proprietarios_admin_imoveis x
                 WHERE x.proprietario_id = s.proprietario_id)            AS prop_qtd_imoveis,
               (SELECT string_agg(x.codigo, ', ' ORDER BY x.codigo)
                  FROM proprietarios_admin_imoveis x
                 WHERE x.proprietario_id = s.proprietario_id
                   AND x.codigo <> s.codigo)                             AS prop_outros_imoveis
          FROM imoveis_admin_snapshot s
          LEFT JOIN proprietarios_admin p ON p.id = s.proprietario_id
          LEFT JOIN imoveis i             ON i.codigo::text = s.codigo  -- imoveis.codigo e' integer
          LEFT JOIN proprietarios_admin_imoveis a
                 ON a.codigo = s.codigo AND a.proprietario_id = s.proprietario_id
          LEFT JOIN imoveis_admin_detalhe d      ON d.codigo = s.codigo
          LEFT JOIN proprietarios_admin_etapa e  ON e.proprietario_id = s.proprietario_id
         WHERE s.codigo = ANY(%s)
    """, (codigos,)):
        dados[str(linha["codigo"])] = linha

    saida = []
    for item in itens:
        novo = dict(item)
        extra = dados.get(str(item.get("codigo")))
        if extra:
            endereco = " ".join(str(x) for x in [extra["logradouro"], extra["numero"]] if x)
            endereco = endereco or extra["endereco_admin"]
            novo.update({
                "tipo": extra["tipo"] or extra["tipo_admin"],
                "bairro": extra["bairro"] or extra["bairro_admin"],
                "area": float(extra["area"]) if extra["area"] is not None else None,
                "quartos": extra["quartos"],
                "suites": extra["suites"],
                "banheiros": extra["banheiros"],
                "vagas": extra["vagas"],
                "andar": extra["andar"],
                "caracteristicas": extra["caracteristicas"],
                "garantia_aluguel": extra["garantia"],
                "incluso_no_aluguel": extra["incluso"],
                "captado_em": (extra["captado_em"].isoformat() if extra["captado_em"] else None),
                "visitas_30d": extra["visitas_30d"],
                "etapa_proprietario": extra["etapa_atual"],
                "etapa_desde": (extra["etapa_em"].date().isoformat() if extra["etapa_em"] else None),
                "endereco": endereco or None,
                "valor_aluguel": (float(extra["aluguel_admin"]) if extra["aluguel_admin"] is not None
                                  else extra["valor_aluguel"]),
                "status_admin": extra["status_admin"],
                "vencimento_conferido": (extra["vencimento_conferido"].isoformat()
                                         if extra["vencimento_conferido"] else None),
                "proprietario_nome": extra["prop_nome"] or item.get("proprietario_nome"),
                "proprietario_telefone": extra["prop_telefone"] or item.get("proprietario_telefone"),
                "proprietario_email": extra["prop_email"],
                "proprietario_id": extra["proprietario_id"],
                "prop_qtd_imoveis": extra["prop_qtd_imoveis"],
                "prop_outros_imoveis": extra["prop_outros_imoveis"],
            })
            if not novo.get("condominio") or novo.get("condominio") in ("—", "-"):
                novo["condominio"] = (extra["condominio_nome"]
                                      or extra["cond_detalhe"]
                                      or extra["condominio_admin"]
                                      or novo.get("condominio"))
        saida.append(novo)
    return saida


@app.route("/api/listas", methods=["GET", "POST"])
def api_listas():
    conn = conectar_listas()
    try:
        if request.method == "GET":
            linhas = todas_linhas(conn, """
                SELECT id, nome, area, filtro, quantidade, exportado_por, criado_em
                FROM site_listas ORDER BY criado_em DESC
            """)
            return jsonify([{
                "id": l["id"], "nome": l["nome"], "area": l["area"],
                "filtro": l["filtro"], "quantidade": l["quantidade"],
                "exportado_por": l["exportado_por"],
                "criado_em": l["criado_em"].isoformat(),
            } for l in linhas])

        corpo = request.get_json(silent=True) or {}
        nome = str(corpo.get("nome") or "").strip()
        area = str(corpo.get("area") or "").strip()
        itens = corpo.get("itens") or []
        if not nome or not area or not isinstance(itens, list):
            return jsonify({"erro": "nome, area e itens são obrigatórios"}), 400
        filtro = str(corpo.get("filtro") or "").strip()
        exportado_por = str(corpo.get("exportado_por") or "").strip() or "não informado"

        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO site_listas (nome, area, filtro, itens, quantidade, exportado_por)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id, criado_em
            """, (nome, area, filtro, psycopg2.extras.Json(itens), len(itens), exportado_por))
            novo = cur.fetchone()
        conn.commit()
        return jsonify({"id": novo["id"], "criado_em": novo["criado_em"].isoformat()}), 201
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@app.route("/api/listas/<int:lista_id>", methods=["GET", "DELETE"])
def api_lista_item(lista_id):
    conn = conectar_listas()
    try:
        if request.method == "DELETE":
            with conn.cursor() as cur:
                cur.execute("DELETE FROM site_listas WHERE id = %s", (lista_id,))
                afetadas = cur.rowcount
            conn.commit()
            if not afetadas:
                return jsonify({"erro": "não encontrada"}), 404
            return jsonify({"status": "removida"})

        linhas = todas_linhas(conn, "SELECT * FROM site_listas WHERE id = %s", (lista_id,))
        if not linhas:
            return jsonify({"erro": "não encontrada"}), 404
        l = linhas[0]
        itens = enriquecer_itens(conn, l["itens"] or [])
        return jsonify({
            "id": l["id"], "nome": l["nome"], "area": l["area"], "filtro": l["filtro"],
            "itens": itens, "quantidade": l["quantidade"],
            "exportado_por": l["exportado_por"], "criado_em": l["criado_em"].isoformat(),
        })
    finally:
        conn.close()


@app.route("/api/tabelas")
@app.route("/admin/api/tabelas")
def api_tabelas():
    """Lista todas as tabelas do naydb com contagem de linhas -- pra
    montar o menu do navegador de tabelas.

    COM SENHA desde 28/09 (Pedro: "fecha agora"): as tabelas mostravam a
    qualquer um na internet o nome e o contato do locatario e o numero do
    apartamento. O painel chama por /admin/api, onde o navegador ja manda a
    senha; pelo /api aberto a resposta e 401."""
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_tabelas()
    try:
        linhas = todas_linhas(conn, """
            SELECT relname AS tabela, n_live_tup AS linhas
            FROM pg_stat_user_tables
            -- So o public, igual a rota de dados logo abaixo: o schema
            -- `vagas` (candidatos e curriculos) nao entra nem pelo nome
            -- nem pela contagem.
            WHERE schemaname = 'public'
            ORDER BY relname
        """)
        return jsonify([{"tabela": l["tabela"], "linhas": l["linhas"]} for l in linhas])
    finally:
        conn.close()


@app.route("/api/tabelas/<nome>")
@app.route("/admin/api/tabelas/<nome>")
def api_tabela_dados(nome):
    """As primeiras 100 linhas de UMA tabela, qualquer uma do naydb.
    `nome` vem da URL (entrada do usuário) -- validado contra a lista real
    de tabelas antes de qualquer coisa chegar perto de SQL, e o nome só
    entra na query via psycopg2.sql.Identifier (nunca por %s, que não
    funciona pra nome de tabela, nem por f-string, que seria injeção).
    Com senha desde 28/09, igual à lista acima."""
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_tabelas()
    try:
        validas = todas_linhas(conn, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
        nomes_validos = {l["tablename"] for l in validas}
        if nome not in nomes_validos:
            return jsonify({"erro": "tabela não encontrada"}), 404

        query = psycopg2.sql.SQL("SELECT * FROM {} LIMIT 100").format(psycopg2.sql.Identifier(nome))
        with conn.cursor() as cur:
            cur.execute(query)
            colunas = [d.name for d in cur.description]
            brutas = cur.fetchall()

        linhas = []
        for linha in brutas:
            tratada = {}
            for col in colunas:
                tratada[col] = serializar_valor(mascarar_valor(col, linha[col]))
            linhas.append(tratada)

        return jsonify({"colunas": colunas, "linhas": linhas})
    finally:
        conn.close()


def periodo_da_query():
    """Lê ?de=AAAA-MM-DD&ate=AAAA-MM-DD da URL. Qualquer um dos dois pode
    faltar -- filtro sem limite de um dos lados."""
    de = request.args.get("de") or None
    ate = request.args.get("ate") or None
    return de, ate


@app.route("/api/contratos")
def api_contratos():
    """Todos os contratos de locação cadastrados, com filtro opcional de
    data de vencimento (?de=&ate=). Tabela existe mas está vazia hoje
    (frente nova, ver Roadmap) -- devolve lista vazia, que é o estado real."""
    de, ate = periodo_da_query()
    condicoes = []
    params = []
    if de:
        condicoes.append("c.vencimento >= %s")
        params.append(de)
    if ate:
        condicoes.append("c.vencimento <= %s")
        params.append(ate)
    where = ("WHERE " + " AND ".join(condicoes)) if condicoes else ""

    conn = conectar()
    try:
        linhas = todas_linhas(conn, f"""
            SELECT c.codigo, c.vencimento, c.status_renovacao, i.condominio_nome,
                   c.proprietario_nome, c.proprietario_telefone, c.proprietario_email
            FROM contratos_locacao c
            LEFT JOIN imoveis i ON i.codigo::text = c.codigo
            {where}
            ORDER BY c.vencimento ASC NULLS LAST
            LIMIT 2000
        """, params)
        # Contato do proprietário sem máscara, de propósito -- assim como em
        # /api/proprietarios-vencimento: o ponto de "contratos vencidos" é
        # ligar pro dono, mascarar tornaria a lista inútil pro que ela foi
        # pedida pra fazer. Extraído do admin real (imobeasy.com/admin) em
        # 05/09/2026, com login autorizado pelo Tel.
        return jsonify([{
            "codigo": l["codigo"],
            "condominio": l["condominio_nome"] or "—",
            "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
            "status": l["status_renovacao"],
            "proprietario_nome": l["proprietario_nome"],
            "proprietario_telefone": l["proprietario_telefone"],
            "proprietario_email": l["proprietario_email"],
        } for l in linhas])
    finally:
        conn.close()


@app.route("/api/avisos")
def api_avisos():
    """Contratos vencendo (próximos 30 dias) e vencidos, cruzados com o
    imóvel. contratos_locacao está vazia hoje -- devolve listas vazias,
    o que é o estado real, não um bug."""
    conn = conectar()
    try:
        vencendo = todas_linhas(conn, """
            SELECT c.codigo, c.vencimento, i.condominio_nome,
                   c.proprietario_nome, c.proprietario_telefone
            FROM contratos_locacao c
            LEFT JOIN imoveis i ON i.codigo::text = c.codigo
            WHERE c.vencimento >= CURRENT_DATE AND c.vencimento <= CURRENT_DATE + 30
            ORDER BY c.vencimento ASC LIMIT 50
        """)
        vencidos = todas_linhas(conn, """
            SELECT c.codigo, c.vencimento, i.condominio_nome,
                   c.proprietario_nome, c.proprietario_telefone
            FROM contratos_locacao c
            LEFT JOIN imoveis i ON i.codigo::text = c.codigo
            WHERE c.vencimento < CURRENT_DATE
            ORDER BY c.vencimento DESC LIMIT 50
        """)

        def formatar(linhas):
            saida = []
            for l in linhas:
                saida.append({
                    "codigo": l["codigo"],
                    "condominio": l["condominio_nome"] or "—",
                    "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
                    "proprietario_nome": l["proprietario_nome"],
                    "proprietario_telefone": l["proprietario_telefone"],
                })
            return saida

        return jsonify({"vencendo": formatar(vencendo), "vencidos": formatar(vencidos)})
    finally:
        conn.close()


@app.route("/api/status-sistema")
def api_status_sistema():
    """Semáforo dos recursos que sustentam o site e a Nay -- mesma lógica
    do nay-painel (banco, varredura, os 4 crons por batimento de arquivo)."""
    agora = datetime.now(FUSO)
    recursos = []

    try:
        conn = conectar()
        linha = todas_linhas(conn, "SELECT valor FROM config WHERE chave = 'varredura_rodou_em'")
        conn.close()
        recursos.append({"recurso": "Banco de dados", "status": "ok"})

        varredura_status = "alerta"
        varredura_detalhe = "sem registro"
        if linha and linha[0]["valor"]:
            try:
                quando = datetime.fromisoformat(linha[0]["valor"])
                mins = int((agora - quando).total_seconds() // 60)
                varredura_status = "ok" if mins <= 90 else "alerta"
                varredura_detalhe = f"há {mins} min" if mins < 60 else f"há {mins // 60}h"
            except ValueError:
                pass
        recursos.append({"recurso": "Varredura do catálogo", "status": varredura_status, "detalhe": varredura_detalhe})
    except Exception:  # noqa: BLE001
        recursos.append({"recurso": "Banco de dados", "status": "erro"})

    for arquivo, (rotulo, folga) in CRONS.items():
        caminho = os.path.join(HEARTBEAT_DIR, f".batimento_{arquivo}")
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(caminho), tz=FUSO)
            mins = int((agora - mtime).total_seconds() // 60)
            status = "ok" if mins <= folga else "alerta"
            detalhe = f"há {mins} min" if mins < 60 else f"há {mins // 60}h"
        except OSError:
            status, detalhe = "alerta", "sem batimento"
        recursos.append({"recurso": rotulo, "status": status, "detalhe": detalhe})

    return jsonify(recursos)


@app.route("/api/corretores-ativos")
def api_corretores_ativos():
    """"Melhores corretores" não existe como métrica no banco -- não tem
    nota de qualidade, só atividade. Isso aqui é quem mais trocou mensagem
    com a Nay nos últimos 30 dias, rotulado como "mais ativos", não
    "melhores". Nunca lê nome nem texto de mensagem -- só telefone e
    contagem, e o nome vem de `corretores` (coluna liberada)."""
    conn = conectar()
    try:
        linhas = todas_linhas(conn, """
            SELECT m.telefone, count(*) AS mensagens
            FROM mensagens m
            WHERE m.criada_em > now() - interval '30 days'
            GROUP BY m.telefone
            ORDER BY mensagens DESC
            LIMIT 20
        """)
        return jsonify([{"telefone": mascarar_telefone(l["telefone"]), "mensagens": l["mensagens"]} for l in linhas])
    finally:
        conn.close()


@app.route("/api/corretores")
def api_corretores():
    """Cartões de corretor -- sem nome nem CRECI (a role nunca leu essas
    colunas), telefone mascarado antes de sair do servidor. Filtro
    opcional por ultima_interacao (?de=&ate=) -- não é "expiração" de
    verdade (corretor não vence), é "sem contato desde"."""
    limit = min(int(request.args.get("limit", 60)), 2000)
    de, ate = periodo_da_query()
    condicoes = []
    params = []
    if de:
        condicoes.append("ultima_interacao >= %s")
        params.append(de)
    if ate:
        condicoes.append("ultima_interacao <= %s")
        params.append(ate)
    where = ("WHERE " + " AND ".join(condicoes)) if condicoes else ""
    params.append(limit)

    conn = conectar()
    try:
        linhas = todas_linhas(conn, f"""
            SELECT telefone, nome, aprovado, ativo, no_shows, ultima_interacao, criado_em
            FROM corretores
            {where}
            ORDER BY criado_em DESC
            LIMIT %s
        """, params)
        saida = []
        for l in linhas:
            saida.append({
                "telefone": mascarar_telefone(l["telefone"]),
                "aprovado": bool(l["aprovado"]),
                "ativo": bool(l["ativo"]) if l["ativo"] is not None else True,
                "no_shows": l["no_shows"] or 0,
                "ultima_interacao": l["ultima_interacao"].isoformat() if l["ultima_interacao"] else None,
                "nome": l.get("nome"),
            })
        return jsonify(saida)
    finally:
        conn.close()


@app.route("/api/indicadores")
def api_indicadores():
    conn = conectar()
    try:
        imoveis = todas_linhas(conn, """
            SELECT count(*) FILTER (WHERE disponivel) AS disponiveis,
                   count(*) AS cadastrados
            FROM imoveis
        """)[0]
        condos = todas_linhas(conn, "SELECT count(*) AS total FROM condominios")[0]
        # "Cadastrados" = TODOS os imoveis do sistema (catalogo + admin
        # antigo), e "em revisao" deixou de ser o 17 fixo do estatico.
        todos = todas_linhas(conn, """
            SELECT count(*) AS total, count(*) FILTER (WHERE status = 'Em revisão') AS revisao,
                   count(*) FILTER (WHERE status = 'Disponível') AS disponiveis
              FROM vw_imoveis_todos""")[0]
        corretores = todas_linhas(conn, """
            SELECT count(*) FILTER (WHERE aprovado) AS aprovados,
                   count(*) FILTER (WHERE NOT aprovado) AS aguardando
            FROM corretores
        """)[0]
        return jsonify({
            "imoveisDisponiveis": str(todos["disponiveis"]),
            "imoveisCadastrados": str(todos["total"]),
            "imoveisAguardandoRevisao": str(todos["revisao"]),
            "condominiosCadastrados": str(condos["total"]),
            "corretoresParceiros": str(corretores["aprovados"]),
            "parceirosAguardando": str(corretores["aguardando"]),
        })
    finally:
        conn.close()


# =====================================================================
# CAPTAÇÃO DE PROPRIETÁRIOS -- campanha temporária.
#
# A aba Captação do admin manda aqui. O disparo e a conversa quem faz é o
# fluxo n8n `Nay - captacao proprietarios`; esta API só existe para o lado
# humano: montar a lista, tirar quem não deve receber, ver o que voltou e
# fazer a curadoria.
#
# Escreve pela role nay_site_escrita, que tem grant SÓ nas quatro tabelas
# captacao_* (mais SELECT no que a importação precisa ler). Um bug de
# query aqui não alcança mensagens, pendências nem o cadastro de imóveis.
# =====================================================================

# Quem NÃO é o dono do imóvel. Estes nomes aparecem como "proprietário" no
# cadastro porque são o contato daquele imóvel, mas a campanha fala com o
# dono -- e o roteiro inteiro só faz sentido para ele.
#
# "(Parceira)" sozinho NÃO entra aqui como sinal de gênero (ver
# nay_tratamento_por_nome): lá a palavra aparece ao lado de nome de gente
# real. Aqui a pergunta é outra -- essa pessoa é a DONA do imóvel? -- e a
# resposta é não.
RE_NAO_E_DONO = re.compile(
    r"(?i)corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|"
    r"im[oó]veis|ltda|eireli|construtor|empreendiment")

# Situações que a campanha descobre, na ordem em que viram "balde" no CRM.
BALDES_CAPTACAO = {
    "disponivel": "Imóveis disponíveis",
    "alugado": "Imóveis não disponíveis (alugados)",
    "vendido": "Já vendeu",
}


def normalizar_telefone(bruto):
    """Devolve só dígitos com DDI, ou None se não der para usar.

    É o mesmo formato que a Z-API usa e que o webhook devolve. Guardar
    formatado ('(92) 9...') faria o lead nunca ser encontrado na resposta,
    porque a busca do fluxo é por igualdade exata de telefone.
    """
    digitos = re.sub(r"\D", "", str(bruto or ""))
    if not digitos:
        return None
    if not digitos.startswith("55"):
        # Número guardado sem DDI: 11 dígitos (com o 9) ou 10 (fixo).
        if len(digitos) in (10, 11):
            digitos = "55" + digitos
        else:
            return None
    return digitos if len(digitos) in (12, 13) else None


def chave_de(telefone):
    """Mesma regra do nay_fone_chave() do banco: DDI + DDD + os 8 finais.

    Existe aqui só para a importação deduplicar antes de escrever. Quem
    manda é a função do banco -- o UNIQUE está na coluna gerada por ela.
    """
    d = re.sub(r"\D", "", str(telefone or ""))
    if re.match(r"^55[0-9]{10,11}$", d):
        return d[:4] + d[-8:]
    return d


def candidatos_da_lista(conn, lista_id):
    """Transforma uma lista salva em candidatos a lead da campanha.

    Não escreve nada -- é o que alimenta o popup onde o Tel desmarca quem
    não deve receber. Cada candidato vem com `bloqueio`: quando ele não é
    None, a linha não pode entrar, e o motivo aparece na tela em vez de
    sumir em silêncio.
    """
    linhas = todas_linhas(conn, "SELECT * FROM site_listas WHERE id = %s", (lista_id,))
    if not linhas:
        return None, None
    lista = linhas[0]
    itens = enriquecer_itens(conn, lista["itens"] or [])

    # Pela CHAVE, não pelo telefone cru: 5596991712835 e 559691712835 são a
    # mesma pessoa, e o UNIQUE do banco é na chave. Comparar o número cru
    # deixaria a importação achar que o lead é novo e quebrar no INSERT.
    ja_na_campanha = {
        l["chave"] for l in todas_linhas(
            conn, "SELECT telefone_chave AS chave FROM captacao_leads")
    }

    # Sr. / Sra. de cada nome, numa consulta só. Quem decide é a função do
    # banco (nay_tratamento_por_nome), não este arquivo: assim a regra é a
    # mesma na importação, num recálculo em massa e em qualquer consulta
    # que alguém faça direto no psql. Ela devolve NULL quando não tem
    # certeza -- e NULL vira mensagem sem Sr./Sra., nunca um chute.
    nomes = sorted({str(i.get("proprietario_nome") or "") for i in itens} - {""})
    tratamentos = {}
    if nomes:
        tratamentos = {
            l["nome"]: l["tratamento"]
            for l in todas_linhas(conn, """
                SELECT n AS nome, nay_tratamento_por_nome(n) AS tratamento
                  FROM unnest(%s::text[]) AS n
            """, (nomes,))
        }

    vistos = {}
    saida = []
    for item in itens:
        codigo = str(item.get("codigo") or "")
        telefone = normalizar_telefone(item.get("proprietario_telefone"))
        condominio = item.get("condominio") or None
        bairro = item.get("bairro") or None
        nome = item.get("proprietario_nome") or None
        tratamento = tratamentos.get(str(nome or ""))

        # Como o imóvel entra na frase da mensagem. O fluxo usa isto direto:
        # "o seu imóvel " + imovel_desc + " está disponível para locação?"
        if condominio and str(condominio) not in ("—", "-"):
            imovel_desc = "no " + str(condominio).strip()
        elif bairro:
            imovel_desc = "no bairro " + str(bairro).strip()
        else:
            imovel_desc = None

        chave = chave_de(telefone)
        bloqueio = None
        if not telefone:
            bloqueio = "sem telefone utilizável"
        elif chave in ja_na_campanha:
            bloqueio = "já está na campanha"
        elif chave in vistos:
            # Um proprietário com três imóveis vira três linhas na lista.
            # Só o primeiro entra: telefone é UNIQUE, e mandar três vezes
            # a mesma pergunta para a mesma pessoa queima o número.
            bloqueio = "repetido nesta lista (imóvel %s)" % vistos[chave]
        elif not imovel_desc:
            bloqueio = "sem condomínio nem bairro para citar na mensagem"
        elif not nome and not tratamento:
            # A mensagem abre com um vocativo. Sem nome E sem tratamento não
            # há como abrir ("Olá , bom dia!"), e inventar não é opção.
            bloqueio = "sem nome para tratar"
        elif RE_NAO_E_DONO.search(str(nome or "")):
            # Corretor parceiro, imobiliária, assessoria: o imóvel chegou por
            # ele, mas o dono é outra pessoa. A mensagem inteira desta
            # campanha é dirigida a proprietário -- "o SEU imóvel está
            # disponível para locação?", "o Sr. tem algum OUTRO imóvel que
            # queira vender ou alugar?". Mandar isso para um parceiro é
            # constrangedor e não atualiza cadastro nenhum.
            # Medido na lista 7 (Contratos vencidos): 96 dos 464 elegíveis.
            bloqueio = "é corretor/parceiro, não o proprietário"

        if bloqueio is None:
            vistos[chave] = codigo

        saida.append({
            "codigo": codigo,
            "telefone": telefone,
            "telefone_bruto": item.get("proprietario_telefone"),
            "nome": nome,
            "tratamento": tratamento,
            "proprietario_id": item.get("proprietario_id"),
            "condominio": condominio,
            "bairro": bairro,
            "endereco": item.get("endereco"),
            "tipo_imovel": item.get("tipo"),
            "imovel_desc": imovel_desc,
            "bloqueio": bloqueio,
        })
    return lista, saida


@app.route("/api/captacao/resumo")
def api_captacao_resumo():
    """Métricas da aba + estado dos interruptores."""
    conn = conectar_escrita()
    try:
        cfg = {l["chave"]: l["valor"] for l in
               todas_linhas(conn, "SELECT chave, valor FROM captacao_config")}
        try:
            max_follow = int(cfg.get("max_followup") or 2)
        except ValueError:
            max_follow = 2

        m = todas_linhas(conn, """
            SELECT
              count(*)                                        AS total,
              count(*) FILTER (WHERE status = 'novo')         AS na_fila,
              count(*) FILTER (WHERE status = 'enviado')      AS aguardando,
              count(*) FILTER (WHERE status = 'respondendo')  AS conversando,
              count(*) FILTER (WHERE status = 'concluido')    AS concluidos,
              count(*) FILTER (WHERE status = 'erro')         AS com_erro,
              count(*) FILTER (WHERE respondeu_em IS NOT NULL) AS responderam,
              count(*) FILTER (WHERE situacao = 'disponivel') AS disponiveis,
              count(*) FILTER (WHERE situacao = 'alugado')    AS alugados,
              count(*) FILTER (WHERE situacao = 'vendido')    AS vendidos,
              count(*) FILTER (WHERE tem_outro_imovel)        AS com_outro_imovel,
              count(*) FILTER (WHERE quer_vender)             AS querem_vender,
              count(*) FILTER (WHERE humano_assumiu_em IS NOT NULL) AS com_o_tel,
              count(*) FILTER (WHERE opt_out)                 AS opt_out,
              -- "cinza": levou todas as tentativas e nunca respondeu. A IA
              -- não chama mais, e a linha fica apagada na tabela.
              count(*) FILTER (WHERE respondeu_em IS NULL
                                 AND tentativas >= %s)        AS sem_resposta
              FROM captacao_leads
        """, (max_follow,))[0]

        envios = todas_linhas(conn, """
            SELECT
              count(*) FILTER (WHERE direcao = 'enviada' AND status <> 'Falhou')  AS enviadas,
              count(*) FILTER (WHERE direcao = 'enviada' AND status = 'Falhou')   AS falharam,
              count(*) FILTER (WHERE direcao = 'recebida')                        AS recebidas,
              count(*) FILTER (WHERE direcao = 'enviada' AND status <> 'Falhou'
                    AND (criada_em AT TIME ZONE 'America/Manaus')::date
                      = (now() AT TIME ZONE 'America/Manaus')::date)              AS enviadas_hoje,
              max(criada_em) FILTER (WHERE direcao = 'enviada')                   AS ultimo_envio
              FROM captacao_mensagens
        """)[0]

        # A SAÚDE DO NÚMERO (migração 163): se o disparo sai agora e, se não,
        # por quê; o volume do dia contra os tetos; e os dois sinais que
        # antecederam a queda de 17/09 -- resposta e entrega dos últimos disparos.
        saude = dict(todas_linhas(conn, "SELECT * FROM captacao_disparo_liberado()")[0])
        sinais = todas_linhas(conn, """
            SELECT count(*) AS disparos,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM captacao_mensagens r
                                                   WHERE r.lead_id = d.lead_id AND r.direcao = 'recebida'
                                                     AND r.criada_em > d.criada_em)) AS responderam,
                   count(*) FILTER (WHERE d.entregue_em IS NOT NULL) AS entregues
              FROM (SELECT lead_id, criada_em, entregue_em FROM captacao_mensagens
                     WHERE direcao = 'enviada' AND origem = 'disparo' AND status = 'Enviado'
                       AND criada_em < now() - interval '30 minutes'
                     ORDER BY criada_em DESC LIMIT 20) d
        """)[0]
        saude.update({k: int(v or 0) for k, v in sinais.items()})
        saude["disjuntor"] = cfg.get("_disjuntor") or None
        saude["disjuntor_em"] = cfg.get("_disjuntor_em") or None
        saude["rampa_desde"] = cfg.get("rampa_desde") or None

        return jsonify({
            "config": cfg,
            "leads": {k: int(v or 0) for k, v in m.items()},
            "envios": {
                "enviadas": int(envios["enviadas"] or 0),
                "falharam": int(envios["falharam"] or 0),
                "recebidas": int(envios["recebidas"] or 0),
                "enviadasHoje": int(envios["enviadas_hoje"] or 0),
                "ultimoEnvio": (envios["ultimo_envio"].isoformat()
                                if envios["ultimo_envio"] else None),
            },
            "saude": saude,
        })
    finally:
        conn.close()


@app.route("/api/captacao/config", methods=["POST"])
def api_captacao_config():
    """Liga e desliga a campanha pelo CRM.

    Só as chaves desta lista podem ser mexidas daqui, e cada uma tem o
    conjunto de valores que aceita. O resto de captacao_config (inclusive
    telefone_teste) só muda por SQL, de propósito: é o tipo de campo que
    não deve ser editável por quem está com pressa na tela.
    """
    permitido = {
        "captacao_pausada": {"sim", "nao"},
        "resposta_pausada": {"sim", "nao"},
        "modo_teste": {"sim", "nao"},
        "limite_dia": None,             # inteiro 0..500
        "max_followup": None,           # inteiro 0..5
        "horas_primeiro_followup": None,  # inteiro 1..72
        "minutos_entre_disparos": None,   # inteiro 5..120
        # a segurança do número (migração 163)
        "rampa_inicio": None, "rampa_passo": None, "rampa_maximo": None,
        "limite_api_dia": None, "limite_total_dia": None,
        "disjuntor_resposta_min": None, "disjuntor_sem_entrega": None,
    }
    corpo = request.get_json(silent=True) or {}
    chave = str(corpo.get("chave") or "").strip()
    valor = str(corpo.get("valor") or "").strip()
    if chave not in permitido:
        return jsonify({"erro": "chave não permitida"}), 400

    aceitos = permitido[chave]
    if aceitos is not None:
        if valor not in aceitos:
            return jsonify({"erro": "valor inválido"}), 400
    else:
        if not valor.isdigit():
            return jsonify({"erro": "valor precisa ser número"}), 400
        # Cada chave tem o seu teto. horas_primeiro_followup começa em 1:
        # zero hora faria o lembrete sair junto com a mensagem original.
        tetos = {"limite_dia": (0, 500), "max_followup": (0, 5),
                 "horas_primeiro_followup": (1, 72),
                 "minutos_entre_disparos": (5, 120),
                 "rampa_inicio": (0, 50), "rampa_passo": (0, 20), "rampa_maximo": (0, 100),
                 "limite_api_dia": (0, 500), "limite_total_dia": (0, 1000),
                 "disjuntor_resposta_min": (0, 100), "disjuntor_sem_entrega": (2, 50)}
        piso, teto = tetos.get(chave, (0, 500))
        if not piso <= int(valor) <= teto:
            return jsonify({"erro": "valor fora do intervalo"}), 400
        valor = str(int(valor))

    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO captacao_config (chave, valor) VALUES (%s, %s)
                ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor
            """, (chave, valor))
        conn.commit()
        return jsonify({"chave": chave, "valor": valor})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@app.route("/api/captacao/previa/<int:lista_id>")
def api_captacao_previa(lista_id):
    """O popup: quem entraria se esta lista virasse campanha."""
    conn = conectar_escrita()
    try:
        lista, candidatos = candidatos_da_lista(conn, lista_id)
        if lista is None:
            return jsonify({"erro": "lista não encontrada"}), 404
        return jsonify({
            "lista": {"id": lista["id"], "nome": lista["nome"],
                      "area": lista["area"], "quantidade": lista["quantidade"]},
            "candidatos": candidatos,
            "aptos": sum(1 for c in candidatos if not c["bloqueio"]),
        })
    finally:
        conn.close()


@app.route("/api/captacao/importar", methods=["POST"])
def api_captacao_importar():
    """Cria os leads da campanha a partir de uma lista.

    O cliente manda só quais códigos DESMARCOU. Os candidatos são
    remontados aqui do banco -- nada do que o navegador diz sobre telefone
    ou nome é usado para escrever. Se a tela estiver com dado velho, quem
    manda é o banco.

    Entra sempre com status 'novo' e etapa 'novo'. Nada dispara por esta
    rota: quem envia é o cron do n8n, e só se captacao_pausada = 'nao'.
    """
    corpo = request.get_json(silent=True) or {}
    try:
        lista_id = int(corpo.get("lista_id"))
    except (TypeError, ValueError):
        return jsonify({"erro": "lista_id obrigatório"}), 400
    excluidos = {str(c) for c in (corpo.get("excluidos") or [])}
    quem = (str(corpo.get("quem") or "").strip() or "não informado")[:120]

    conn = conectar_escrita()
    try:
        lista, candidatos = candidatos_da_lista(conn, lista_id)
        if lista is None:
            return jsonify({"erro": "lista não encontrada"}), 404

        entram = [c for c in candidatos
                  if not c["bloqueio"] and c["codigo"] not in excluidos]
        if not entram:
            return jsonify({"importados": 0, "ignorados": len(candidatos),
                            "motivo": "ninguém sobrou depois dos bloqueios e exclusões"})

        with conn.cursor() as cur:
            # `fetch=True` + len() em vez de cur.rowcount.
            #
            # execute_values quebra a lista em páginas de 100 e manda uma
            # instrução por página; cur.rowcount fica com o total da ÚLTIMA
            # página, não do conjunto. Foi por isso que importar 364 leads
            # avisou "64 adicionados" (364 = 3x100 + 64) -- os 364 tinham
            # entrado, a contagem é que mentia.
            #
            # ON CONFLICT sem alvo: há dois UNIQUE nesta tabela (telefone e
            # telefone_chave). Nomear só um deixaria o outro estourar a
            # transação inteira em vez de simplesmente pular a linha.
            inseridos = psycopg2.extras.execute_values(cur, """
                INSERT INTO captacao_leads
                  (telefone, nome, tratamento, proprietario_id, codigo,
                   imovel_desc, condominio, bairro, tipo_imovel,
                   lista_id, quem_importou, status, etapa)
                VALUES %s
                ON CONFLICT DO NOTHING
                RETURNING id
            """, [(
                c["telefone"], c["nome"], c["tratamento"], c["proprietario_id"],
                c["codigo"], c["imovel_desc"], c["condominio"], c["bairro"],
                c["tipo_imovel"], lista["id"], quem, "novo", "novo",
            ) for c in entram], fetch=True)
            importados = len(inseridos)

            # TODOS os imóveis de cada proprietário, congelados agora.
            #
            # A campanha manda UMA mensagem por pessoa -- telefone é UNIQUE,
            # e um dono com três imóveis receberia três vezes a mesma
            # pergunta. Mas a conversa fala de UM imóvel só, e sem esta
            # lista a Nay não saberia dos outros: quando ele dissesse "tenho
            # o do Condomínio X também", ela registraria como imóvel novo um
            # imóvel que já é nosso.
            #
            # 34 dos 874 proprietários da base têm mais de um imóvel.
            cur.execute("""
                UPDATE captacao_leads l
                   SET imoveis_prop = COALESCE((
                         SELECT jsonb_agg(jsonb_build_object(
                                  'codigo', i.codigo,
                                  'condominio', i.condominio,
                                  'endereco', i.endereco) ORDER BY i.codigo)
                           FROM proprietarios_admin_imoveis i
                          WHERE i.proprietario_id = l.proprietario_id
                       ), '[]'::jsonb)
                 WHERE l.lista_id = %s AND l.proprietario_id IS NOT NULL
            """, (lista["id"],))
        conn.commit()
        return jsonify({
            "importados": importados,
            "desmarcados": len(excluidos),
            "bloqueados": sum(1 for c in candidatos if c["bloqueio"]),
        }), 201
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@app.route("/api/captacao/leads")
def api_captacao_leads():
    """A tabela de curadoria. `balde` filtra pelo resultado da conversa."""
    balde = str(request.args.get("balde") or "").strip()
    conn = conectar_escrita()
    try:
        cfg = {l["chave"]: l["valor"] for l in
               todas_linhas(conn, "SELECT chave, valor FROM captacao_config")}
        try:
            max_follow = int(cfg.get("max_followup") or 2)
        except ValueError:
            max_follow = 2

        conds, params = [], [max_follow]
        if balde in BALDES_CAPTACAO:
            conds.append("l.situacao = %s")
            params.append(balde)
        elif balde == "outro_imovel":
            conds.append("l.tem_outro_imovel")
        elif balde == "sem_resposta":
            conds.append("l.respondeu_em IS NULL AND l.tentativas >= %s")
            params.append(max_follow)
        elif balde == "andamento":
            conds.append("l.respondeu_em IS NOT NULL AND l.situacao IS NULL AND NOT l.quer_vender")
        elif balde == "quer_vender":
            conds.append("l.quer_vender")
        elif balde == "com_tel":
            conds.append("l.humano_assumiu_em IS NOT NULL")

        # BUSCA: nome da pessoa, imóvel (descrição, condomínio, bairro,
        # código) ou telefone. Sem acento e sem caixa dos dois lados --
        # "joao" acha "JOÃO", "acquarele" não acha, "acquarelle" acha.
        busca = str(request.args.get("q") or "").strip()[:80]
        if busca:
            conds.append("""(nay_sem_acento(lower(concat_ws(' ', l.nome, l.imovel_desc, l.condominio,
                                                        l.bairro, l.codigo)))
                             LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'
                          OR (length(regexp_replace(%s, '\\D', '', 'g')) >= 4
                              AND l.telefone LIKE '%%' || regexp_replace(%s, '\\D', '', 'g') || '%%'))""")
            params.extend([busca, busca, busca])
        onde = ("WHERE " + " AND ".join(conds)) if conds else ""

        linhas = todas_linhas(conn, """
            SELECT l.id, l.telefone, l.nome, l.tratamento, l.tratamento_manual,
                   l.codigo, l.imovel_desc, l.condominio,
                   l.bairro, l.status, l.etapa, l.situacao, l.contrato_ate,
                   l.tentativas, l.opt_out, l.tem_outro_imovel, l.motivo_fim,
                   l.ultimo_envio_em, l.respondeu_em, l.criado_em,
                   l.quer_vender, l.valor_venda_pedido, l.humano_assumiu_em,
                   (l.respondeu_em IS NULL AND l.tentativas >= %s) AS cinza,
                   (SELECT count(*) FROM captacao_mensagens m
                     WHERE m.lead_id = l.id AND m.direcao = 'enviada') AS enviadas,
                   (SELECT count(*) FROM captacao_mensagens m
                     WHERE m.lead_id = l.id AND m.direcao = 'recebida') AS recebidas,
                   (SELECT string_agg(e.descricao, ' | ' ORDER BY e.id)
                      FROM captacao_imoveis_extra e WHERE e.lead_id = l.id) AS outros_imoveis
              FROM captacao_leads l
              """ + onde + """
             ORDER BY (l.respondeu_em IS NOT NULL) DESC, l.atualizado_em DESC
             LIMIT 800
        """, tuple(params))

        return jsonify([{
            "id": l["id"], "telefone": l["telefone"], "nome": l["nome"],
            "tratamento": l["tratamento"], "tratamentoManual": l["tratamento_manual"],
            "codigo": l["codigo"], "imovel": l["imovel_desc"] or l["condominio"],
            "bairro": l["bairro"], "status": l["status"], "etapa": l["etapa"],
            "situacao": l["situacao"], "contratoAte": l["contrato_ate"],
            "tentativas": l["tentativas"], "optOut": l["opt_out"],
            "temOutroImovel": l["tem_outro_imovel"], "outrosImoveis": l["outros_imoveis"],
            "motivoFim": l["motivo_fim"], "cinza": l["cinza"],
            "enviadas": int(l["enviadas"] or 0), "recebidas": int(l["recebidas"] or 0),
            "ultimoEnvio": (l["ultimo_envio_em"].isoformat() if l["ultimo_envio_em"] else None),
            "respondeuEm": (l["respondeu_em"].isoformat() if l["respondeu_em"] else None),
            "querVender": l["quer_vender"], "valorVendaPedido": l["valor_venda_pedido"],
            "comOTel": (l["humano_assumiu_em"].isoformat() if l["humano_assumiu_em"] else None),
        } for l in linhas])
    finally:
        conn.close()


@app.route("/api/captacao/exportar")
def api_captacao_exportar():
    """CSV de um balde.

    É o que fecha a campanha: quem move o lead de "Todos" para os outros
    baldes é a IA, pela conversa. O humano não empurra ninguém — ele
    exporta o resultado. Por isso "Adicionar lista" só existe em "Todos" e
    "Exportar" só existe nos baldes de resultado.
    """
    balde = str(request.args.get("balde") or "").strip()
    if not balde:
        return jsonify({"erro": "exportar exige um balde"}), 400

    conn = conectar_escrita()
    try:
        cfg = {l["chave"]: l["valor"] for l in
               todas_linhas(conn, "SELECT chave, valor FROM captacao_config")}
        try:
            max_follow = int(cfg.get("max_followup") or 2)
        except ValueError:
            max_follow = 2

        onde, params = "", []
        if balde in BALDES_CAPTACAO:
            onde, params = "WHERE l.situacao = %s", [balde]
        elif balde == "outro_imovel":
            onde = "WHERE l.tem_outro_imovel"
        elif balde == "sem_resposta":
            onde, params = ("WHERE l.respondeu_em IS NULL AND l.tentativas >= %s",
                            [max_follow])
        elif balde == "andamento":
            onde = "WHERE l.respondeu_em IS NOT NULL AND l.situacao IS NULL AND NOT l.quer_vender"
        elif balde == "quer_vender":
            onde = "WHERE l.quer_vender"
        elif balde == "com_tel":
            onde = "WHERE l.humano_assumiu_em IS NOT NULL"
        else:
            return jsonify({"erro": "balde desconhecido"}), 400

        linhas = todas_linhas(conn, """
            SELECT l.codigo, l.nome, l.tratamento, l.telefone, l.condominio,
                   l.bairro, l.imovel_desc, l.situacao, l.contrato_ate,
                   l.tem_outro_imovel, l.tentativas, l.respondeu_em,
                   l.quer_vender, l.valor_venda_pedido, l.humano_assumiu_em,
                   (SELECT string_agg(e.descricao || ' [' || e.negocio || ']', ' | '
                                      ORDER BY e.id)
                      FROM captacao_imoveis_extra e WHERE e.lead_id = l.id) AS outros
              FROM captacao_leads l """ + onde + " ORDER BY l.nome", tuple(params))

        def csv_campo(v):
            if v is None:
                return ""
            txt = str(v).replace('"', '""')
            return '"' + txt + '"' if any(c in txt for c in ',;"\n') else txt

        cabecalho = ["codigo", "nome", "tratamento", "telefone", "condominio",
                     "bairro", "imovel", "situacao", "contrato_ate",
                     "tem_outro_imovel", "tentativas", "respondeu_em",
                     "outros_imoveis", "quer_vender", "valor_venda_pedido", "com_o_tel"]
        corpo = [",".join(cabecalho)]
        for l in linhas:
            corpo.append(",".join(csv_campo(x) for x in [
                l["codigo"], l["nome"], l["tratamento"], l["telefone"],
                l["condominio"], l["bairro"], l["imovel_desc"], l["situacao"],
                l["contrato_ate"], "sim" if l["tem_outro_imovel"] else "nao",
                l["tentativas"],
                l["respondeu_em"].strftime("%d/%m/%Y %H:%M") if l["respondeu_em"] else "",
                l["outros"],
                "sim" if l["quer_vender"] else "nao", l["valor_venda_pedido"],
                "sim" if l["humano_assumiu_em"] else "nao",
            ]))

        # BOM na frente: sem ele o Excel em português abre "João" como "JoÃ£o".
        dados = "﻿" + "\n".join(corpo)
        return app.response_class(
            dados, mimetype="text/csv",
            headers={"Content-Disposition":
                     'attachment; filename="captacao-%s.csv"' % balde})
    finally:
        conn.close()


@app.route("/api/captacao/lead/<int:lead_id>/tratamento", methods=["POST"])
def api_captacao_tratamento(lead_id):
    """Corrige o Sr./Sra. de um lead na mão.

    A função do banco acerta ~94% dos nomes da base e devolve NULL no
    resto. Este endpoint existe para o resto -- e marca tratamento_manual,
    para um recálculo em massa nunca desfazer a correção humana.
    """
    corpo = request.get_json(silent=True) or {}
    valor = corpo.get("tratamento")
    if valor not in ("Sr.", "Sra.", None, ""):
        return jsonify({"erro": "tratamento tem que ser Sr., Sra. ou vazio"}), 400
    valor = valor or None

    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE captacao_leads
                   SET tratamento = %s, tratamento_manual = true, atualizado_em = now()
                 WHERE id = %s
             RETURNING id, nome, tratamento
            """, (valor, lead_id))
            linha = cur.fetchone()
        conn.commit()
        if not linha:
            return jsonify({"erro": "não encontrado"}), 404
        return jsonify({"id": linha["id"], "nome": linha["nome"],
                        "tratamento": linha["tratamento"]})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@app.route("/api/captacao/lead/<int:lead_id>/mudar", methods=["POST"])
def api_captacao_mudar(lead_id):
    """"Mudar manualmente" (pedido do Tel, 10/09): põe o lead num balde na mão.

    situacao: disponivel | alugado | vendido | "" (tira a situação -> volta
    para "Em andamento" se ele já respondeu). Com uma situação escolhida, a
    IA PARA de chamar esse proprietário (status/etapa 'concluido') -- senão o
    disparo ou o lembrete ainda sairiam para quem o Tel já resolveu. O que
    foi feito fica em motivo_fim, com quem e quando.
    """
    corpo = request.get_json(silent=True) or {}
    situacao = corpo.get("situacao") or None
    if situacao not in (None, "disponivel", "alugado", "vendido"):
        return jsonify({"erro": "situação tem que ser disponivel, alugado, vendido ou vazia"}), 400
    contrato = str(corpo.get("contrato_ate") or "").strip()[:40] or None
    outro = corpo.get("tem_outro_imovel")
    if outro not in (True, False, None):
        return jsonify({"erro": "tem_outro_imovel tem que ser true ou false"}), 400
    quem = re.sub(r"[^\w .@-]", "", str(corpo.get("quem") or "admin"))[:40] or "admin"
    quer_vender = corpo.get("quer_vender")
    if quer_vender not in (True, False, None):
        return jsonify({"erro": "quer_vender tem que ser true ou false"}), 400
    valor_venda = str(corpo.get("valor_venda") or "").strip()[:80] or None
    humano = corpo.get("humano")
    if humano not in (True, False, None):
        return jsonify({"erro": "humano tem que ser true ou false"}), 400
    # "Quer vender" marcado na mao tambem resolve o lead: a Nay para de chamar.
    resolve = bool(situacao) or quer_vender is True

    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE captacao_leads
                   SET situacao = %(sit)s,
                       contrato_ate = CASE WHEN %(sit)s = 'alugado'
                                           THEN coalesce(%(contrato)s, contrato_ate)
                                           ELSE contrato_ate END,
                       tem_outro_imovel = coalesce(%(outro)s, tem_outro_imovel),
                       quer_vender = coalesce(%(qv)s, quer_vender),
                       valor_venda_pedido = CASE WHEN coalesce(%(qv)s, quer_vender)
                                                 THEN coalesce(%(valor)s, valor_venda_pedido)
                                                 ELSE valor_venda_pedido END,
                       humano_assumiu_em = CASE WHEN %(humano)s IS TRUE THEN coalesce(humano_assumiu_em, now())
                                                WHEN %(humano)s IS FALSE THEN NULL
                                                ELSE humano_assumiu_em END,
                       humano_motivo = CASE WHEN %(humano)s IS TRUE THEN coalesce(humano_motivo, 'marcado no CRM por ' || %(quem)s)
                                            WHEN %(humano)s IS FALSE THEN NULL
                                            ELSE humano_motivo END,
                       status = CASE WHEN %(resolve)s THEN 'concluido'
                                     WHEN status = 'concluido' AND respondeu_em IS NOT NULL THEN 'respondendo'
                                     WHEN status = 'concluido' THEN 'enviado'
                                     ELSE status END,
                       etapa = CASE WHEN %(resolve)s THEN 'concluido' ELSE etapa END,
                       fechado_em = CASE WHEN %(resolve)s THEN now() ELSE fechado_em END,
                       motivo_fim = 'manual (' || %(quem)s || ', ' ||
                                    to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') || '): ' ||
                                    coalesce(%(sit)s, 'sem situação') ||
                                    CASE WHEN %(qv)s IS TRUE THEN ', quer vender' ELSE '' END ||
                                    CASE WHEN %(humano)s IS TRUE THEN ', com o Tel' ELSE '' END,
                       atualizado_em = now()
                 WHERE id = %(id)s
             RETURNING id, nome, situacao, status, tem_outro_imovel, contrato_ate,
                       quer_vender, valor_venda_pedido, humano_assumiu_em
            """, {"sit": situacao, "contrato": contrato, "outro": outro, "quem": quem, "id": lead_id,
                  "qv": quer_vender, "valor": valor_venda, "humano": humano, "resolve": resolve})
            linha = cur.fetchone()
        conn.commit()
        if not linha:
            return jsonify({"erro": "não encontrado"}), 404
        return jsonify({"id": linha["id"], "nome": linha["nome"], "situacao": linha["situacao"],
                        "status": linha["status"], "temOutroImovel": linha["tem_outro_imovel"],
                        "contratoAte": linha["contrato_ate"], "querVender": linha["quer_vender"],
                        "valorVendaPedido": linha["valor_venda_pedido"],
                        "comOTel": bool(linha["humano_assumiu_em"])})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    finally:
        conn.close()


@app.route("/api/captacao/lead/<int:lead_id>")
def api_captacao_lead(lead_id):
    """A conversa inteira de um lead -- é onde a curadoria acontece."""
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT * FROM captacao_leads WHERE id = %s", (lead_id,))
        if not linhas:
            return jsonify({"erro": "não encontrado"}), 404
        l = linhas[0]
        msgs = todas_linhas(conn, """
            SELECT id, direcao, origem, texto, status, criada_em
              FROM captacao_mensagens WHERE lead_id = %s ORDER BY id
        """, (lead_id,))
        extras = todas_linhas(conn, """
            SELECT id, descricao, negocio, criado_em
              FROM captacao_imoveis_extra WHERE lead_id = %s ORDER BY id
        """, (lead_id,))
        return jsonify({
            "id": l["id"], "telefone": l["telefone"], "nome": l["nome"],
            "imovel": l["imovel_desc"], "codigo": l["codigo"],
            "situacao": l["situacao"], "contratoAte": l["contrato_ate"],
            "etapa": l["etapa"], "status": l["status"],
            "perguntaPendente": l["pergunta_pendente"],
            "mensagens": [{
                "id": m["id"], "direcao": m["direcao"], "origem": m["origem"],
                "texto": m["texto"], "status": m["status"],
                "em": m["criada_em"].isoformat(),
            } for m in msgs],
            "outrosImoveis": [{
                "id": e["id"], "descricao": e["descricao"], "negocio": e["negocio"],
                "em": e["criado_em"].isoformat(),
            } for e in extras],
        })
    finally:
        conn.close()


# =====================================================================
# FLUXOS DE MENSAGEM -- o editor de cards da página "Fluxo de mensagens".
#
# Antes o fluxo vivia só no navegador (a única forma de guardar era baixar
# uma cópia do HTML). Aqui fica a versão oficial: todo aparelho que abre a
# página carrega esta, e o botão "Atualizar fluxo" grava por cima.
#
# Role nay_site_conteudo: CRUD só nas tabelas de conteúdo do site.
# =====================================================================
RE_NOME_FLUXO = re.compile(r"^[a-z0-9_-]{1,40}$")
RE_ID_CARD = re.compile(r"^[\w-]{1,120}$")
RE_CLASSE_CARD = re.compile(r"^a-[a-z]{2,20}$")
# Segunda linha de defesa: quem abre a página renderiza este HTML. A
# primeira é o sanitizador do próprio editor, que só deixa passar tags e
# atributos de formatação. Aqui barra o óbvio antes de chegar ao banco.
RE_HTML_PERIGOSO = re.compile(
    r"(?i)<\s*(script|iframe|object|embed|link|meta|style|base|form)\b|"
    r"\son\w+\s*=|javascript:|url\s*\(")
LIMITE_FLUXO_BYTES = 4 * 1024 * 1024
HISTORICO_POR_FLUXO = 100


def validar_conteudo_fluxo(conteudo):
    """Devolve None se o conteúdo é aceitável, ou o motivo da recusa."""
    if not isinstance(conteudo, dict):
        return "conteudo precisa ser um objeto"
    cards = conteudo.get("cards")
    ligacoes = conteudo.get("edges")
    if not isinstance(cards, list) or not isinstance(ligacoes, list):
        return "conteudo precisa ter cards e edges"
    if len(cards) > 2000 or len(ligacoes) > 10000:
        return "fluxo grande demais"
    for c in cards:
        if not isinstance(c, dict):
            return "card inválido"
        if not RE_ID_CARD.match(str(c.get("id") or "")):
            return "id de card inválido"
        if not RE_CLASSE_CARD.match(str(c.get("cls") or "")):
            return "tipo de card inválido"
        for campo in ("style", "html"):
            valor = c.get(campo)
            if not isinstance(valor, str) or len(valor) > 60000:
                return "card com %s inválido" % campo
            if RE_HTML_PERIGOSO.search(valor):
                return "card com conteúdo não permitido"
    for e in ligacoes:
        if (not isinstance(e, list) or not 2 <= len(e) <= 4
                or not all(isinstance(x, str) for x in e)
                or not RE_ID_CARD.match(e[0]) or not RE_ID_CARD.match(e[1])
                or any(len(x) > 300 for x in e)):
            return "ligação inválida"
    return None


@app.route("/api/fluxos/<nome>", methods=["GET", "PUT"])
def api_fluxo(nome):
    if not RE_NOME_FLUXO.match(nome):
        return jsonify({"erro": "nome inválido"}), 400

    conn = conectar_conteudo()
    try:
        if request.method == "GET":
            # ?so_versao=1 é o que o editor consulta a cada poucos segundos
            # para saber se outro aparelho salvou: devolve só o número, sem
            # trafegar o fluxo inteiro.
            if request.args.get("so_versao"):
                linhas = todas_linhas(conn, "SELECT versao, atualizado_em FROM site_fluxos WHERE nome = %s", (nome,))
                if not linhas:
                    return jsonify({"versao": 0})
                return jsonify({"versao": linhas[0]["versao"],
                                "atualizado_em": linhas[0]["atualizado_em"].isoformat()})
            linhas = todas_linhas(conn, """
                SELECT versao, conteudo, atualizado_em, atualizado_por
                  FROM site_fluxos WHERE nome = %s
            """, (nome,))
            if not linhas:
                return jsonify({"versao": 0}), 404
            l = linhas[0]
            return jsonify({"versao": l["versao"], "conteudo": l["conteudo"],
                            "atualizado_em": l["atualizado_em"].isoformat(),
                            "atualizado_por": l["atualizado_por"]})

        if (request.content_length or 0) > LIMITE_FLUXO_BYTES:
            return jsonify({"erro": "fluxo grande demais"}), 413
        corpo = request.get_json(silent=True) or {}
        conteudo = corpo.get("conteudo")
        motivo = validar_conteudo_fluxo(conteudo)
        if motivo:
            return jsonify({"erro": motivo}), 400
        try:
            base = int(corpo.get("versao_base") or 0)
        except (TypeError, ValueError):
            return jsonify({"erro": "versao_base inválida"}), 400
        forcar = bool(corpo.get("forcar"))
        quem = (str(corpo.get("quem") or "").strip() or "não informado")[:80]

        with conn.cursor() as cur:
            # FOR UPDATE: dois aparelhos salvando no mesmo segundo não passam
            # os dois pela checagem de versão.
            cur.execute("SELECT versao FROM site_fluxos WHERE nome = %s FOR UPDATE", (nome,))
            linha = cur.fetchone()
            atual = linha["versao"] if linha else 0
            if atual != base and not forcar:
                conn.rollback()
                return jsonify({"erro": "conflito", "versao_atual": atual}), 409
            nova = atual + 1
            cur.execute("""
                INSERT INTO site_fluxos (nome, conteudo, versao, atualizado_em, atualizado_por)
                VALUES (%s, %s, %s, now(), %s)
                ON CONFLICT (nome) DO UPDATE
                   SET conteudo = EXCLUDED.conteudo, versao = EXCLUDED.versao,
                       atualizado_em = now(), atualizado_por = EXCLUDED.atualizado_por
                RETURNING atualizado_em
            """, (nome, psycopg2.extras.Json(conteudo), nova, quem))
            quando = cur.fetchone()["atualizado_em"]
            cur.execute("""
                INSERT INTO site_fluxos_historico (nome, versao, conteudo, salvo_por)
                VALUES (%s, %s, %s, %s)
            """, (nome, nova, psycopg2.extras.Json(conteudo), quem))
            cur.execute("""
                DELETE FROM site_fluxos_historico
                 WHERE nome = %s AND id NOT IN (
                   SELECT id FROM site_fluxos_historico WHERE nome = %s
                    ORDER BY id DESC LIMIT %s)
            """, (nome, nome, HISTORICO_POR_FLUXO))
        conn.commit()
        return jsonify({"versao": nova, "atualizado_em": quando.isoformat()})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
    finally:
        conn.close()


@app.route("/api/painel/atendimento")
def api_painel_atendimento():
    """Números do atendimento por dia (pedido do Tel, 12/09): quantos
    corretores falaram com a Nay e quantas visitas foram agendadas.

    Vem das views `vw_painel_*`, que pertencem ao `nay`: a role do site lê os
    AGREGADOS, nunca o texto das mensagens nem telefone de ninguém."""
    try:
        dias = max(1, min(90, int(request.args.get("dias", 30))))
    except ValueError:
        dias = 30
    campos = ("corretores", "corretores_novos", "mensagens_recebidas",
              "corretores_falaram_de_visita", "visitas_pedidas", "visitas_confirmadas",
              "visitas_realizadas", "visitas_canceladas", "visitas_marcadas_para_o_dia",
              "visitas_urgentes", "captacao_disparos", "captacao_responderam",
              "captacao_com_o_tel")
    conn = conectar()
    try:
        serie = [dict({"dia": l["dia"].isoformat()},
                      **{c: int(l[c] or 0) for c in campos})
                 for l in todas_linhas(conn, "SELECT * FROM vw_painel_atendimento LIMIT %s", (dias,))]
        resumo = {}
        for l in todas_linhas(conn, "SELECT * FROM vw_painel_resumo"):
            resumo[l["periodo"]] = {k: int(v or 0) for k, v in l.items()
                                    if k not in ("periodo", "desde")}
            resumo[l["periodo"]]["desde"] = l["desde"].isoformat()
        nai = todas_linhas(conn, "SELECT * FROM vw_painel_nai")[0]
        modo = {"teste": "teste", "todos": "todos", "desligado": "desligado"}.get(nai["modo"], nai["modo"])
        return jsonify({
            "dias": serie,
            "resumo": resumo,
            "visitas_modo": modo,
            "visitas_numeros": ("%d número(s) de teste" % int(nai["numeros_teste"] or 0)
                                if modo == "teste" else None),
            # As DUAS Nays são números diferentes e estados diferentes.
            "locacao": {
                "whatsapp_pausado": bool(nai["locacao_pausada"]),
                "ia_modo": modo,
                "ia_pausada": bool(nai["nai_pausada"]),
                "numeros_teste": int(nai["numeros_teste"] or 0),
            },
            "captacao": {
                "pausada": bool(nai["captacao_pausada"]),
                "modo_teste": bool(nai["captacao_teste"]),
            },
        })
    finally:
        conn.close()


@app.route("/api/saude")
def api_saude():
    try:
        conn = conectar()
        todas_linhas(conn, "SELECT 1")
        conn.close()
        return jsonify({"status": "ok"})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"status": "erro", "detalhe": exc.__class__.__name__}), 200


# A PAGINA PUBLICA DO IMOVEL (Pedro, 02/10/2026): imobeasy.online/imovel/<codigo>.
# Rota ABERTA, sem senha. Tudo o que ela mostra sai de site_imovel_publico()
# (migracao 271), que nao devolve rua, numero, complemento, CEP nem andar, e
# so responde imovel publicado e disponivel. Nao monte o imovel aqui com
# SELECT em `imoveis`: o filtro do que pode aparecer mora na funcao.
@app.route("/api/imovel-publico/<int:codigo>")
def api_imovel_publico(codigo):
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT site_imovel_publico(%s) AS imovel", (codigo,))
        imovel = linhas[0]["imovel"] if linhas else None
        if not imovel:
            return jsonify({"erro": "não encontrado"}), 404
        return jsonify(imovel)
    finally:
        conn.close()


# "ME ENVIA O IMOVEL" (Pedro, 02/10/2026): o corretor digita o WhatsApp dele na
# pagina publica e recebe o card e as fotos pela Nay. Quem manda e quem segura
# e site_me_envia() (271): cai na mesma caixa do "Enviar imovel" do painel, com
# as paredes de sempre (parceiro nao sai, indisponivel nao sai, 24 h por pessoa)
# e com TETOS por numero, por IP e no total do dia -- a rota e aberta e qualquer
# um pode digitar qualquer numero. Cada pedido fica em privado.me_envia.
@app.route("/api/me-envia", methods=["POST"])
def api_me_envia():
    corpo = request.get_json(silent=True) or {}
    telefone = str(corpo.get("telefone") or "")[:30]
    codigos = []
    for c in (corpo.get("codigos") or [])[:30]:
        try:
            codigos.append(int(c))
        except (TypeError, ValueError):
            continue
    # O Traefik sobrescreve X-Real-Ip com quem conectou; o X-Forwarded-For o
    # proprio visitante preenche, entao nao serve para teto.
    ip = (request.headers.get("X-Real-Ip") or request.remote_addr or "")[:64]
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_me_envia(%s, %s, %s) AS r", (telefone, codigos, ip))
        conn.commit()
        r = linhas[0]["r"] if linhas else {"ok": False, "mensagem": "Não foi possível enviar agora."}
        return jsonify(r), (200 if r.get("ok") else 429 if r.get("teto") else 422)
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        app.logger.warning("me-envia falhou: %s", exc.__class__.__name__)
        return jsonify({"ok": False, "mensagem": "Não foi possível enviar agora. Tente de novo em alguns minutos."}), 500
    finally:
        conn.close()


# A TELA /imoveis (Pedro, 02/10/2026): "um link /imoveis que vou mandar para os
# corretores acharem os imoveis e se enviarem pelo whatsapp". A lista inteira
# vem de site_imoveis_para_enviar() (275): so o que a Nay oferece, sem rua,
# numero, CEP, andar ou dono. O envio e o mesmo /api/me-envia da pagina do imovel.
@app.route("/api/imoveis-para-enviar")
def api_imoveis_para_enviar():
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT site_imoveis_para_enviar() AS r")
        resposta = jsonify({"imoveis": (linhas[0]["r"] if linhas else None) or []})
        resposta.headers["Cache-Control"] = "public, max-age=120"
        return resposta
    finally:
        conn.close()


# A AGENDA DOS GRUPOS (279, Pedro 03/10/2026): "uma aba Grupos no site, onde eu vou criar e agendar
# mensagens com os imoveis, numa agenda geral, filtrando por grupo... e metrificar: quantas pessoas
# chegaram nas 6 h seguintes". E a GRADE do publicador (tabela vagas): o cron disparar_grade.sh a
# executa a cada minuto, nada de agendador novo. Tudo atras da senha do /admin.
@app.route("/admin/api/grade")
def admin_grade_agenda():
    if not senha_do_admin_confere():
        return _sem_senha()
    de = request.args.get("de") or None
    ate = request.args.get("ate") or None
    for valor in (de, ate):
        if valor and not re.match(r"^\d{4}-\d{2}-\d{2}$", valor):
            return jsonify({"erro": "data inválida (use AAAA-MM-DD)"}), 400
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_grade_agenda(%s::date, %s::date) AS j", (de, ate))
        return jsonify(linhas[0]["j"] if linhas else {})
    finally:
        conn.close()


@app.route("/admin/api/grade/opcoes")
def admin_grade_opcoes():
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_grade_opcoes() AS j")
        return jsonify(linhas[0]["j"] if linhas else {})
    finally:
        conn.close()


# A LISTA DE IMOVEIS NA AGENDA (286, Pedro 03/10/2026): "que crie, no criar mensagem, lista de imoveis,
# e editar essa mensagem fisicamente". Devolve o texto que o publicador montaria AGORA para a categoria
# e o negocio: e o ponto de partida do que ele edita a mao na tela.
@app.route("/admin/api/grade/lista")
def admin_grade_lista():
    if not senha_do_admin_confere():
        return _sem_senha()
    categoria = (request.args.get("categoria") or "").strip()[:40]
    negocio = (request.args.get("negocio") or "").strip()[:20]
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_grade_lista_previa(%s, %s) AS j", (categoria, negocio))
        r = linhas[0]["j"] if linhas else {"ok": False, "erro": "Não consegui montar a lista."}
        return jsonify(r), (200 if r.get("ok") else 422)
    finally:
        conn.close()


# AS METRICAS DA AGENDA (286): quantas vezes cada mensagem saiu e quanta gente chegou no privado da Nay
# marcando o post ou escrevendo o codigo do imovel nas 6 h seguintes. So contagem: nenhum telefone sai daqui.
@app.route("/admin/api/grade/metricas")
def admin_grade_metricas():
    if not senha_do_admin_confere():
        return _sem_senha()
    de = request.args.get("de") or None
    ate = request.args.get("ate") or None
    for valor in (de, ate):
        if valor and not re.match(r"^\d{4}-\d{2}-\d{2}$", valor):
            return jsonify({"erro": "data inválida (use AAAA-MM-DD)"}), 400
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT site_grade_metricas(%s::date, %s::date) AS j", (de, ate))
        r = (linhas[0]["j"] if linhas else None) or {}
        return jsonify(r), (422 if r.get("erro") else 200)
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        app.logger.warning("grade/metricas: %s", exc.__class__.__name__)
        return jsonify({"erro": "Não consegui calcular as métricas agora."}), 500
    finally:
        conn.close()


@app.route("/admin/api/grade", methods=["POST"])
@app.route("/admin/api/grade/<int:vaga_id>", methods=["PUT", "DELETE"])
def admin_grade_mudar(vaga_id=None):
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_escrita()
    try:
        with conn.cursor() as cur:
            if request.method == "DELETE":
                cur.execute("SELECT site_grade_excluir(%s) AS r", (vaga_id,))
            else:
                corpo = request.get_json(silent=True) or {}
                if vaga_id is not None:
                    corpo["id"] = vaga_id
                cur.execute("SELECT site_grade_salvar(%s) AS r", (psycopg2.extras.Json(corpo),))
            r = cur.fetchone()["r"]
        conn.commit()
        return jsonify(r), (200 if r.get("ok") else 422)
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        app.logger.warning("grade: %s", exc.__class__.__name__)
        return jsonify({"ok": False, "erro": "Não consegui salvar agora."}), 500
    finally:
        conn.close()


# CAPTACAO ATIVA POR GRUPOS (336, Pedro 09/10/2026): "quero adicionar uma aba na aba Grupos ... poe a
# nova aba ao lado de Metricas". Os pedidos que os corretores fazem nos grupos, lidos pela IA e comparados
# com o nosso catalogo pelo servico nay-grupos (Python, /root/nay-grupos). Aqui so se le o que ele gravou e
# se guardam os julgamentos ("leitura correta / errada"), a rejeicao, os testes colados e os apelidos.
# MODO TREINO: nenhuma rota daqui envia mensagem, e a funcao do banco recusa "aprovado".
# Tem nome e telefone de corretor: so com a senha do /admin.
def _captacao_grupos(sql, params=()):
    if not senha_do_admin_confere():
        return _sem_senha()
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, sql, params)
        conn.commit()
        r = (linhas[0]["j"] if linhas else None) or {}
        return jsonify(r), (422 if isinstance(r, dict) and r.get("erro") else 200)
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        app.logger.warning("grupos/captacao: %s", exc.__class__.__name__)
        return jsonify({"erro": "Não consegui agora. Tente de novo."}), 500
    finally:
        conn.close()


@app.route("/admin/api/grupos/captacao")
def admin_grupos_captacao():
    filtro = (request.args.get("filtro") or "todos").strip().lower()
    if filtro not in ("todos", "verde", "amarelo", "sem_match", "teste"):
        filtro = "todos"
    horas = _inteiro(request.args.get("horas"), 0) or None
    return _captacao_grupos("SELECT site_captacao_grupos(%s, %s, %s) AS j", (filtro, horas, 120))


@app.route("/admin/api/grupos/captacao/<int:pedido_id>/julgar", methods=["POST"])
def admin_grupos_captacao_julgar(pedido_id):
    corpo = request.get_json(silent=True) or {}
    return _captacao_grupos("SELECT site_captacao_grupos_julgar(%s, %s, %s) AS j",
                            (pedido_id, str(corpo.get("leitura") or ""), str(corpo.get("erro") or "")))


@app.route("/admin/api/grupos/captacao/<int:pedido_id>/estado", methods=["POST"])
def admin_grupos_captacao_estado(pedido_id):
    corpo = request.get_json(silent=True) or {}
    return _captacao_grupos("SELECT site_captacao_grupos_estado(%s, %s) AS j", (pedido_id, str(corpo.get("estado") or "")))


# 339: o ENVIO MANUAL (o botão "Enviar ao corretor"). Um clique dele por pedido; quem confere e enfileira é o banco
# (as travas estão em site_captacao_grupos_enviar) e quem entrega é o enviador manual, pelo número da Parceria.
@app.route("/admin/api/grupos/captacao/<int:pedido_id>/enviar", methods=["POST"])
def admin_grupos_captacao_enviar(pedido_id):
    corpo = request.get_json(silent=True) or {}
    return _captacao_grupos("SELECT site_captacao_grupos_enviar(%s, %s, %s, %s) AS j",
                            (pedido_id, _inteiro(corpo.get("codigo"), 0), str(corpo.get("abertura") or ""), "painel do site"))


@app.route("/admin/api/grupos/captacao/testar", methods=["POST"])
def admin_grupos_captacao_testar():
    corpo = request.get_json(silent=True) or {}
    return _captacao_grupos("SELECT site_captacao_grupos_testar(%s, %s) AS j",
                            (str(corpo.get("texto") or ""), str(corpo.get("nome") or "")))


@app.route("/admin/api/grupos/captacao/testar/<int:teste_id>")
def admin_grupos_captacao_teste_lido(teste_id):
    return _captacao_grupos("SELECT site_captacao_grupos_teste_lido(%s) AS j", (teste_id,))


# 337: a conversa EXPORTADA do WhatsApp (a Z-API não devolve o histórico dos grupos). O navegador lê o arquivo
# e manda só as mensagens de texto da janela; o leitor trata cada uma como mensagem de grupo.
@app.route("/admin/api/grupos/captacao/importar", methods=["POST"])
def admin_grupos_captacao_importar():
    corpo = request.get_json(silent=True) or {}
    mensagens = corpo.get("mensagens")
    if not isinstance(mensagens, list):
        mensagens = []
    return _captacao_grupos("SELECT site_captacao_grupos_importar(%s, %s) AS j",
                            (str(corpo.get("grupo") or ""), psycopg2.extras.Json(mensagens[:2000])))


@app.route("/admin/api/grupos/captacao/demanda")
def admin_grupos_captacao_demanda():
    return _captacao_grupos("SELECT site_captacao_grupos_demanda(%s) AS j", (_inteiro(request.args.get("dias"), 30),))


@app.route("/admin/api/grupos/captacao/apelidos", methods=["GET", "POST", "DELETE"])
def admin_grupos_captacao_apelidos():
    if request.method == "GET":
        return _captacao_grupos("SELECT site_captacao_grupos_apelidos() AS j")
    corpo = request.get_json(silent=True) or {}
    if request.method == "DELETE":
        return _captacao_grupos("SELECT site_captacao_grupos_apelido_excluir(%s) AS j", (str(corpo.get("apelido") or ""),))
    return _captacao_grupos("SELECT site_captacao_grupos_apelido_salvar(%s, %s, %s) AS j",
                            (str(corpo.get("apelido") or ""), str(corpo.get("tipo") or ""), str(corpo.get("oficial") or "")))


# Quem mais se envia imoveis. Tem telefone: so com a senha do /admin.
@app.route("/admin/api/me-envia/ranking")
def admin_me_envia_ranking():
    if not senha_do_admin_confere():
        return _sem_senha()
    dias = max(1, min(_inteiro(request.args.get("dias"), 30), 365))
    conn = conectar_escrita()
    try:
        linhas = todas_linhas(conn, "SELECT * FROM site_me_envia_ranking(%s)", (dias,))
        for l in linhas:
            for campo in ("primeiro", "ultimo"):
                if l.get(campo) is not None:
                    l[campo] = l[campo].isoformat()
        return jsonify({"dias": dias, "ranking": linhas})
    finally:
        conn.close()


# O painel do cerebro (trace por execucao). Em try/except de proposito: se
# este modulo falhar ao importar, as rotas do site continuam de pe e so o
# painel novo fica fora do ar.
try:
    from trace_api import trace_bp
    app.register_blueprint(trace_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("trace_api nao carregou: %s", _e)

# O menu de TREINO. Mesmo try/except, mesma razao: um erro de import aqui nao
# pode levar junto as 49 rotas do site nem o painel do cerebro.
try:
    from treino_api import treino_bp
    app.register_blueprint(treino_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("treino_api nao carregou: %s", _e)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8092)

# A pagina de VAGAS (/vagas-manaus) e a tela Vagas do painel. Mesmo
# try/except: um erro de import aqui nao pode levar junto o resto da API.
try:
    from vagas_api import vagas_bp
    app.register_blueprint(vagas_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("vagas_api nao carregou: %s", _e)

# A ESTRUTURA DA NAY (a mente mestra e a secretaria, em fluxograma). Mesmo
# try/except, mesma razao.
try:
    from estrutura_api import estrutura_bp
    app.register_blueprint(estrutura_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("estrutura_api nao carregou: %s", _e)

# O QUE FALTAVA NA TELA DE IMOVEIS: as listas por campo, o proprietario do
# imovel e a ficha com os buracos. Mesmo try/except, mesma razao.
try:
    from imoveis_api import imoveis_bp
    app.register_blueprint(imoveis_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("imoveis_api nao carregou: %s", _e)

# ENVIAR IMOVEL (28/09): a aba de disparo do painel, que repassa ao CRM.
# Mesmo try/except, mesma razao.
try:
    from disparo_api import disparo_bp
    app.register_blueprint(disparo_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("disparo_api nao carregou: %s", _e)

# CAPTACAO PELA OLX (28/09): o pre-cadastro que o botao "Enviar para Imob Easy"
# manda do navegador, e as fotos baixadas uma a uma. Mesmo try/except.
try:
    from olx_api import olx_bp
    app.register_blueprint(olx_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("olx_api nao carregou: %s", _e)

# A BIBLIOTECA DE FOTOS DO CADASTRO (03/10): subir do computador, reordenar e
# excluir as fotos de um imovel, com a senha do painel. Mesmo try/except.
try:
    from fotos_api import fotos_bp
    app.register_blueprint(fotos_bp)
except Exception as _e:  # noqa: BLE001
    app.logger.warning("fotos_api nao carregou: %s", _e)

# A CAPTACAO PEDE SENHA (28/09, Pedro: "com bastante seguranca para o numero nao
# cair"). As rotas /api/captacao/* e /api/nai/captacao* respondiam sem senha
# nenhuma: qualquer um na internet ligava o disparo (captacao_pausada), punha o
# teto em 500 ou lia o telefone dos proprietarios. Agora todas exigem a senha do
# /admin, e as telas chamam pelo proprio dominio (/admin/api/...), onde o
# navegador ja manda a senha. A guarda e uma so, aqui, para rota nova de
# captacao nascer protegida.
_PREFIXOS_CAPTACAO = ("/api/captacao", "/api/nai/captacao", "/admin/api/captacao", "/admin/api/nai/captacao")


def _maquina_do_crm_confere():
    """O card do proprietário no CRM (29/09) entra com a senha de máquina da
    captação (CAPTACAO_FOTO_SEGREDO), só nas rotas dele: /api/captacao/crm/*."""
    import hmac
    segredo = os.environ.get("CAPTACAO_FOTO_SEGREDO", "")
    return bool(segredo) and request.path.startswith("/api/captacao/crm/") and hmac.compare_digest(
        request.headers.get("x-captacao-segredo", ""), segredo)


# O PROMPT E A CONFIGURACAO DA NAY PEDEM SENHA (30/09). PUT /api/nai/config
# (modo, pausada, envio_simulado, numeros_teste...) e PUT /api/nai/prompt/<papel>
# respondiam sem senha em api.imobeasy.online: qualquer um calava a Nay ou
# reescrevia o que ela diz, sem registro de quem foi (entrevista de 29/09,
# pergunta 50). Mesma guarda da captacao; as telas passam a chamar pelo
# proprio dominio (/admin/api/...), onde o navegador ja manda a senha.
# A PAUSA TAMBEM (30/09): PUT /api/nai/pausa liga e desliga a Nay inteira.
_PREFIXOS_NAI_PAINEL = ("/api/nai/config", "/api/nai/prompt", "/api/nai/pausa",
                        "/admin/api/nai/config", "/admin/api/nai/prompt", "/admin/api/nai/pausa")


@app.before_request
def _captacao_exige_senha():
    if request.method != "OPTIONS" and request.path.startswith(_PREFIXOS_CAPTACAO) \
            and not senha_do_admin_confere() and not _maquina_do_crm_confere():
        return _sem_senha()
    if request.method != "OPTIONS" and request.path.startswith(_PREFIXOS_NAI_PAINEL) \
            and not senha_do_admin_confere():
        return _sem_senha()


for _regra in list(app.url_map.iter_rules()):
    if _regra.rule.startswith(("/api/captacao", "/api/nai/captacao", "/api/nai/config", "/api/nai/prompt", "/api/nai/pausa")):
        app.add_url_rule("/admin" + _regra.rule, endpoint=_regra.endpoint + "__admin",
                         view_func=app.view_functions[_regra.endpoint],
                         methods=sorted(m for m in _regra.methods if m not in ("HEAD", "OPTIONS")))
