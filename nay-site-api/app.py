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
from flask import Flask, jsonify, request

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
}


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
    else:
        resp.headers["Cache-Control"] = "no-store"
    return resp


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
    where = ("WHERE " + " AND ".join(condicoes)) if condicoes else ""

    conn = conectar()
    try:
        linhas = todas_linhas(conn, f"""
            SELECT codigo, tipo, condominio_nome, bairro, logradouro, numero,
                   complemento, area_util, quartos, suites, banheiros, vagas,
                   valor_venda, valor_aluguel, e_parceiro
            FROM imoveis
            {where}
            ORDER BY criado_em DESC
            LIMIT %s
        """, (limit,))
        fotos = buscar_fotos(conn, [l["codigo"] for l in linhas])
        return jsonify([imovel_para_cartao(l, fotos) for l in linhas])
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
}


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
                         FROM vw_imoveis_todos),
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
                   e_parceiro, criado_em, sincronizado_em
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
        item["campos_editaveis"] = CAMPOS_EDITAVEIS
        return jsonify(item)
    finally:
        conn.close()


@app.route("/api/imoveis/<int:codigo>", methods=["PUT"])
def api_imovel_salvar(codigo):
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

    for campo, valor in corpo.items():
        regra = CAMPOS_EDITAVEIS.get(campo)
        if not regra:
            continue  # ignora silenciosamente qualquer campo fora da lista

        if valor is None:
            sets.append(psycopg2.sql.SQL("{} = %s").format(psycopg2.sql.Identifier(campo)))
            valores.append(None)
            continue

        try:
            if regra["tipo"] == "numero":
                valores.append(float(valor))
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

    if erros:
        return jsonify({"erro": "validação", "detalhes": erros}), 400
    if not sets:
        return jsonify({"erro": "nenhum campo editável enviado"}), 400

    conn = conectar_escrita()
    try:
        query = psycopg2.sql.SQL("UPDATE imoveis SET {} WHERE codigo = %s").format(
            psycopg2.sql.SQL(", ").join(sets)
        )
        with conn.cursor() as cur:
            cur.execute(query, valores + [codigo])
            afetadas = cur.rowcount
        conn.commit()
        if afetadas == 0:
            return jsonify({"erro": "não encontrado"}), 404
        return jsonify({"status": "salvo", "codigo": codigo})
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        return jsonify({"erro": exc.__class__.__name__}), 500
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


STATUS_IMOVEL = ("Disponível", "Alugado", "Vendido", "Arquivado", "Removido",
                 "Rascunho", "Em revisão", "Indisponível", "Fora do site")


@app.route("/api/imoveis-lista")
def api_imoveis_lista():
    """TODOS os imoveis (catalogo + admin antigo), paginado, com total e
    filtros de verdade. Antes: so o catalogo, corte em 200, filtros sem
    efeito, e o filtro de vencimento na carga inicial reduzia a 1 imovel."""
    a = request.args
    per = max(1, min(int(a.get("per") or 50), 6000 if a.get("formato") == "csv" else 2000))
    page = max(1, int(a.get("page") or 1))
    conds, params = [], []

    q = str(a.get("q") or "").strip()[:80]
    if q:
        if q.isdigit():
            conds.append("v.codigo::text LIKE %s")
            params.append(q + "%")
        else:
            conds.append("nay_sem_acento(lower(concat_ws(' ', v.condominio, v.bairro, v.endereco, v.tipo, v.proprietario_nome))) "
                         "LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'")
            params.append(q)
    status = [x for x in str(a.get("status") or "").split(",") if x in STATUS_IMOVEL]
    if status:
        conds.append("v.status = ANY(%s)")
        params.append(status)
    grupo = a.get("grupo")
    if grupo in ("apartamento", "casa", "outros", "sem_tipo"):
        conds.append("v.grupo_tipo = %s")
        params.append(grupo)
    tipo = str(a.get("tipo") or "").strip()[:60]
    if tipo:
        conds.append("v.tipo ILIKE %s")
        params.append(tipo + "%")
    condos = [int(x) for x in str(a.get("condo_ids") or "").split(",") if x.strip().isdigit()]
    if condos:
        conds.append("(v.condo_id = ANY(%s) OR lower(nay_sem_acento(v.condominio)) IN "
                     "(SELECT lower(nay_sem_acento(nome)) FROM condominios WHERE id = ANY(%s)))")
        params.extend([condos, condos])
    bairro = str(a.get("bairro") or "").strip()[:60]
    if bairro:
        conds.append("nay_sem_acento(lower(v.bairro)) LIKE '%%' || nay_sem_acento(lower(%s)) || '%%'")
        params.append(bairro)
    fin = a.get("finalidade")
    if fin == "venda":
        conds.append("(coalesce(v.valor_venda, 0) > 0 OR v.valor_texto ILIKE 'Venda%%')")
    elif fin == "aluguel":
        conds.append("(coalesce(v.valor_aluguel, 0) > 0 OR v.valor_texto ILIKE 'Aluguel%%')")
    for chave, col in (("quartos", "v.quartos"), ("vagas", "v.vagas")):
        val = str(a.get(chave) or "")
        if val.endswith("+") and val[:-1].isdigit():
            conds.append(col + " >= %s")
            params.append(int(val[:-1]))
        elif val.isdigit():
            conds.append(col + " = %s")
            params.append(int(val))
    for chave, op in (("vmin", ">="), ("vmax", "<=")):
        val = re.sub(r"[^\d]", "", str(a.get(chave) or "").split(",")[0])
        if val:
            conds.append("coalesce(nullif(v.valor_venda, 0), v.valor_aluguel) " + op + " %s")
            params.append(int(val))
    if a.get("parceiro") == "sim":
        conds.append("v.e_parceiro")
    elif a.get("parceiro") == "nao":
        conds.append("NOT v.e_parceiro")
    if a.get("catalogo") == "1":
        conds.append("v.no_catalogo")
    if a.get("financia") in ("Sim", "Não"):
        conds.append("v.financia = %s")
        params.append(a.get("financia"))
    de, ate = periodo_da_query()
    if de:
        conds.append("v.vencimento >= %s")
        params.append(de)
    if ate:
        conds.append("v.vencimento <= %s")
        params.append(ate)
    for chave, op in (("criado_de", ">="), ("criado_ate", "<=")):
        val = str(a.get(chave) or "")
        if re.match(r"^\d{4}-\d{2}-\d{2}$", val):
            conds.append("v.criado::date " + op + " %s")
            params.append(val)

    ordem = {"antigo": "v.criado ASC NULLS LAST, v.codigo",
             "menor": "coalesce(nullif(v.valor_venda, 0), v.valor_aluguel) ASC NULLS LAST",
             "maior": "coalesce(nullif(v.valor_venda, 0), v.valor_aluguel) DESC NULLS LAST",
             "codigo": "v.codigo DESC"}.get(a.get("ordem"), "v.criado DESC NULLS LAST, v.codigo DESC")
    where = ("WHERE " + " AND ".join(conds)) if conds else ""

    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT v.*, count(*) OVER () AS total FROM vw_imoveis_todos v " + where +
                              " ORDER BY " + ordem + " LIMIT %s OFFSET %s",
                              tuple(params + [per, (page - 1) * per]))
        resumo = todas_linhas(conn, """
            SELECT count(*) FILTER (WHERE status = 'Disponível' AND coalesce(valor_aluguel, 0) > 0) AS aluguel,
                   count(*) FILTER (WHERE status = 'Disponível' AND coalesce(valor_venda, 0) > 0) AS venda,
                   count(*) FILTER (WHERE e_parceiro) AS parceiros,
                   count(*) AS todos
              FROM vw_imoveis_todos""")[0]

        def valor(l):
            if l["valor_venda"]:
                return f"Venda: {formatar_reais(l['valor_venda'])}"
            if l["valor_aluguel"]:
                return f"Aluguel: {formatar_reais(l['valor_aluguel'])}"
            return l["valor_texto"] or "Consulte"

        itens = [{
            "codigo": str(l["codigo"]), "status": l["status"], "noCatalogo": l["no_catalogo"],
            "tipo": l["tipo"], "financia": l["financia"], "valor": valor(l),
            "condominio": l["condominio"] or "", "condoId": l["condo_id"],
            "bairro": l["bairro"], "endereco": l["endereco"] or "",
            "proprietario": l["proprietario_nome"] or "", "parceiro": l["e_parceiro"],
            "quartos": l["quartos"], "vagas": l["vagas"],
            "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
        } for l in linhas]

        if a.get("formato") == "csv":
            return _csv(["codigo", "status", "tipo", "valor", "condominio", "bairro", "endereco",
                         "quartos", "vagas", "financia", "parceiro", "proprietario", "vencimento"],
                        [[i["codigo"], i["status"], i["tipo"], i["valor"], i["condominio"], i["bairro"],
                          i["endereco"], i["quartos"], i["vagas"], i["financia"],
                          "sim" if i["parceiro"] else "nao", i["proprietario"], i["vencimento"]] for i in itens],
                        "imoveis")
        return jsonify({"total": linhas[0]["total"] if linhas else 0, "page": page, "per": per,
                        "itens": itens, "resumo": {k: int(v or 0) for k, v in resumo.items()}})
    finally:
        conn.close()


@app.route("/api/condominios/sugerir")
def api_condominios_sugerir():
    """Sugestao enquanto digita: sem acento, acha no meio do nome
    ("acquarelle" acha "Condominio Acquarelle") e tolera erro de digitacao
    (trigrama). O nome que comeca com o que ele digitou vem primeiro."""
    q = str(request.args.get("q") or "").strip()[:60]
    if len(q) < 2:
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
             LIMIT 15
        """, (q,))
        return jsonify([{"id": l["id"], "nome": l["nome"], "bairro": l["bairro"], "imoveis": l["imoveis"]}
                        for l in linhas])
    finally:
        conn.close()


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
def api_imovel_criar():
    """NOVO IMOVEL pelo site. Codigo da faixa 900000+ (nunca colide com o
    codigo do imobeasy.com, que a varredura horaria sobrescreveria). Nasce
    FORA do site (publicado_no_site = false): nao aparece na vitrine nem e
    oferecido pela Nay ate alguem publicar."""
    corpo = request.get_json(silent=True) or {}
    cols = ["origem", "publicado_no_site", "disponivel", "criado_em"]
    vals = ["crm", False, True, datetime.now()]
    erros = []
    if not str(corpo.get("tipo") or "").strip():
        return jsonify({"erro": "validação", "detalhes": ["tipo: obrigatório"]}), 400
    for campo, valor in corpo.items():
        regra = CAMPOS_EDITAVEIS.get(campo)
        if not regra or campo in ("publicado_no_site", "bloqueado", "motivo_bloqueio") or valor in (None, ""):
            continue
        try:
            if regra["tipo"] == "numero":
                valor = float(valor)
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
        if campo == "disponivel":
            vals[cols.index("disponivel")] = valor
            continue
        cols.append(campo)
        vals.append(valor)
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
    ordem = {"nome": "p.nome", "recentes": "p.criado_em DESC NULLS LAST, p.id DESC"}.get(a.get("ordem"), "p.nome")
    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    conn = conectar()
    try:
        linhas = todas_linhas(conn, "SELECT p.*, count(*) OVER () AS total FROM vw_proprietarios_site p " + where +
                              " ORDER BY " + ordem + " LIMIT %s OFFSET %s", tuple(params + [per, (page - 1) * per]))
        funil = todas_linhas(conn, "SELECT etapa, count(*) AS n FROM vw_proprietarios_site GROUP BY 1 ORDER BY 2 DESC")
        especialistas = todas_linhas(conn, "SELECT especialista FROM vw_proprietarios_site "
                                           "WHERE especialista IS NOT NULL GROUP BY 1 ORDER BY 1")
        itens = [{
            "id": l["id"], "nome": l["nome"] or "—", "etapa": l["etapa"], "especialista": l["especialista"],
            "cpf": mascarar_cpf(l["cpf"]) if l["cpf"] else "—", "telefone": l["telefone"] or "—",
            "email": l["email"] or "—", "imoveis": int(l["imoveis"] or 0), "codigos": l["codigos"],
            "vencimento": l["vencimento"].isoformat() if l["vencimento"] else None,
        } for l in linhas]
        if a.get("formato") == "csv":
            return _csv(["nome", "etapa", "especialista", "telefone", "email", "imoveis", "codigos", "vencimento"],
                        [[i["nome"], i["etapa"], i["especialista"], i["telefone"], i["email"], i["imoveis"],
                          i["codigos"], i["vencimento"]] for i in itens], "proprietarios")
        return jsonify({"total": linhas[0]["total"] if linhas else 0, "page": page, "per": per, "itens": itens,
                        "funil": [{"rotulo": f["etapa"], "contagem": f["n"]} for f in funil],
                        "especialistas": [e["especialista"] for e in especialistas]})
    finally:
        conn.close()


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
def api_tabelas():
    """Lista todas as tabelas do naydb com contagem de linhas -- pra
    montar o menu do navegador de tabelas."""
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
def api_tabela_dados(nome):
    """As primeiras 100 linhas de UMA tabela, qualquer uma do naydb.
    `nome` vem da URL (entrada do usuário) -- validado contra a lista real
    de tabelas antes de qualquer coisa chegar perto de SQL, e o nome só
    entra na query via psycopg2.sql.Identifier (nunca por %s, que não
    funciona pra nome de tabela, nem por f-string, que seria injeção)."""
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
                 "minutos_entre_disparos": (5, 120)}
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
