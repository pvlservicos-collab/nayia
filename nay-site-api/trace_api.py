"""API do painel do CÉREBRO da Nay de Locação (trace por execução, por setor).

Ele (19/09/2026): "quero um painel de logs para eu ver que caminho a ia percorreu
em cada execução... quero dividir ela em setores para ficar mais fácil
identificar erros".

POR QUE É UM BLUEPRINT E NÃO MAIS 300 LINHAS NO `app.py`:
o `app.py` já tem 2.873 linhas e 49 rotas. Somar o trace ali faria dois arquivos
grandes brigarem por conflito de merge a cada ajuste, e um erro de import aqui
derrubaria as 49 rotas do site. Como Blueprint, este arquivo é isolado: se ele
falhar no import, o site continua de pé (ver o `try/except` do passo de
instalação, em PASSO-A-PASSO.md).

COMO LIGAR no `app.py` -- duas linhas, no fim do arquivo, depois de `app` existir:

    from trace_api import trace_bp
    app.register_blueprint(trace_bp)

SOMENTE LEITURA. Não existe POST, PUT nem DELETE aqui. A conexão usa a mesma
`NAI_DATABASE_URL` das outras rotas `/api/nai/*`, e as views já entregam o
telefone e o CPF mascarados pelo `nai_mascarar` do arquivo 64 -- o mascaramento
mora no BANCO, não aqui, para que nenhuma rota futura possa esquecer de aplicar.
"""
import os
from datetime import date, datetime
from decimal import Decimal

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, request

trace_bp = Blueprint("trace", __name__)

NAI_DATABASE_URL = os.environ.get("NAI_DATABASE_URL")

# Tetos de paginação. Existem porque uma tela sem limite acaba pedindo 50 mil
# linhas no dia em que o trace ficar grande, e aí o lento é o Postgres.
LIMITE_PADRAO = 60
LIMITE_MAXIMO = 300

VEREDITOS = {"ok", "corrigida", "parada", "barrada", "muda", "erro"}
PAPEIS = {"corretor", "proprietario", "motoboy", "tel"}


def _conectar():
    if not NAI_DATABASE_URL:
        raise RuntimeError("NAI_DATABASE_URL não configurada")
    conn = psycopg2.connect(NAI_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def _linhas(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def _limpar(valor):
    """Deixa o valor pronto para JSON.

    `jsonify` do Flask 3 sabe data e datetime, mas NÃO sabe Decimal -- e as views
    de trace têm `round(...)` que volta como Decimal. Sem isto, a rota de setores
    devolve 500 justo quando existe dado para mostrar (que é o único momento em
    que alguém abre a tela).
    """
    if isinstance(valor, Decimal):
        # float e o certo aqui: sao porcentagens e medias para desenhar na tela,
        # nao dinheiro. Nenhum valor financeiro passa por estas rotas.
        return float(valor)
    if isinstance(valor, (datetime, date)):
        return valor.isoformat()
    if isinstance(valor, dict):
        return {k: _limpar(v) for k, v in valor.items()}
    if isinstance(valor, (list, tuple)):
        return [_limpar(v) for v in valor]
    return valor


def _linha(l):
    return {k: _limpar(v) for k, v in dict(l).items()}


def _limite():
    try:
        n = int(request.args.get("limite") or LIMITE_PADRAO)
    except (TypeError, ValueError):
        n = LIMITE_PADRAO
    return max(1, min(n, LIMITE_MAXIMO))


# ==========================================================================
# 1. OS SETORES -- a primeira tela: onde está doendo
# ==========================================================================
@trace_bp.route("/api/nai/trace/setores")
def setores():
    """Semáforo de runtime (7 dias) + o mapa de código, um por setor.

    São duas perguntas diferentes sobre o mesmo setor, e o Tel precisa das duas
    lado a lado: "está dando erro agora?" (semáforo) e "quanta regra velha mora
    aqui?" (mapa). Separadas em duas telas, ninguém cruza.
    """
    conn = _conectar()
    try:
        saude = {l["setor"]: _linha(l) for l in _linhas(conn, "SELECT * FROM vw_nai_setor_saude")}
        mapa = {l["setor"]: _linha(l) for l in _linhas(conn, "SELECT * FROM vw_nai_setor_mapa")}
        fora = []
        for setor, s in saude.items():
            m = mapa.get(setor, {})
            s["funcoes"] = m.get("funcoes")
            s["da_ia_nova"] = m.get("da_ia_nova")
            s["da_ia_antiga"] = m.get("da_ia_antiga")
            s["candidatas_a_entulho"] = m.get("candidatas_a_entulho")
            s["dependencias_da_antiga"] = m.get("dependencias_da_antiga")
            fora.append(s)
        fora.sort(key=lambda x: x.get("ordem") or 999)
        return jsonify({"setores": fora})
    finally:
        conn.close()


@trace_bp.route("/api/nai/trace/setor/<setor>")
def setor_etapas(setor):
    """As etapas de UM setor, ordenadas pelo que mais age, com os últimos
    turnos com problema -- para clicar e cair na execução."""
    setor = (setor or "").strip().lower()
    conn = _conectar()
    try:
        existe = _linhas(conn, "SELECT setor, titulo, descricao FROM nai_setor WHERE setor = %s", (setor,))
        if not existe:
            return jsonify({"erro": "setor desconhecido"}), 404
        etapas = _linhas(conn, "SELECT * FROM vw_nai_setor_etapas WHERE setor = %s", (setor,))
        return jsonify({
            "setor": _linha(existe[0]),
            "etapas": [_linha(l) for l in etapas],
        })
    finally:
        conn.close()


# ==========================================================================
# 2. AS EXECUÇÕES
# ==========================================================================
@trace_bp.route("/api/nai/trace/execucoes")
def execucoes():
    """A lista, com filtro por veredito e por papel.

    O filtro é por lista branca, não por interpolação: `veredito` e `papel` vêm
    da URL, e montar SQL com texto de URL é como se abre um banco para
    estranho. Valor fora da lista é ignorado em silêncio.
    """
    veredito = (request.args.get("veredito") or "").strip().lower()
    papel = (request.args.get("papel") or "").strip().lower()
    busca = (request.args.get("busca") or "").strip()

    onde = ["1=1"]
    params = []
    if veredito in VEREDITOS:
        onde.append("veredito = %s")
        params.append(veredito)
    if papel in PAPEIS:
        onde.append("papel = %s")
        params.append(papel)
    if busca:
        # 120 caracteres bastam para um trecho de mensagem ou um codigo; mais
        # que isso e alguem colando um texto enorme numa consulta com ILIKE.
        onde.append("(ele_disse ILIKE %s OR quem ILIKE %s OR imovel::text = %s)")
        params += ["%" + busca[:120] + "%", "%" + busca[:120] + "%", busca[:10]]

    # `só problema` é o atalho que o Tel vai usar 90% das vezes
    if request.args.get("so_problema") == "1":
        onde.append("veredito <> 'ok'")

    params.append(_limite())
    conn = _conectar()
    try:
        linhas = _linhas(conn, """
            SELECT * FROM vw_nai_execucoes
             WHERE """ + " AND ".join(onde) + """
             ORDER BY turno DESC
             LIMIT %s
        """, params)
        # O resumo dos vereditos vem da MESMA janela de tempo que a lista, senão
        # os números do topo não fecham com as linhas de baixo e o Tel
        # (com razão) para de confiar na tela.
        resumo = _linhas(conn, """
            SELECT veredito, count(*) AS quantas
              FROM vw_nai_execucoes
             WHERE quando > now() - interval '7 days'
             GROUP BY veredito ORDER BY 2 DESC
        """)
        return jsonify({
            "execucoes": [_linha(l) for l in linhas],
            "resumo_7_dias": [_linha(l) for l in resumo],
        })
    finally:
        conn.close()


@trace_bp.route("/api/nai/trace/execucao/<int:turno>")
def execucao(turno):
    """UMA execução: o cabeçalho e a trilha inteira, por setor."""
    conn = _conectar()
    try:
        cab = _linhas(conn, "SELECT * FROM vw_nai_execucoes WHERE turno = %s", (turno,))
        if not cab:
            return jsonify({"erro": "execução não encontrada"}), 404
        trilha = _linhas(conn, "SELECT * FROM nai_trilha(%s)", (turno,))
        # Agrupado por setor já daqui: a tela desenha uma coluna por setor, e
        # agrupar no navegador significaria repetir esta lógica em JavaScript.
        grupos, ordem = {}, []
        for l in trilha:
            d = _linha(l)
            s = d["setor"]
            if s not in grupos:
                grupos[s] = {"setor": s, "ordem": d.get("setor_ordem"), "passos": []}
                ordem.append(s)
            grupos[s]["passos"].append(d)
        titulos = {l["setor"]: l["titulo"] for l in _linhas(conn, "SELECT setor, titulo FROM nai_setor")}
        saida = []
        for s in sorted(ordem, key=lambda x: grupos[x].get("ordem") or 999):
            g = grupos[s]
            g["titulo"] = titulos.get(s, s)
            g["tem_problema"] = any(p["resultado"] != "ok" for p in g["passos"])
            saida.append(g)
        return jsonify({"cabecalho": _linha(cab[0]), "setores": saida})
    finally:
        conn.close()


# ==========================================================================
# 3. O INVENTÁRIO -- "o que é regra viva e o que é entulho"
# ==========================================================================
@trace_bp.route("/api/nai/trace/inventario")
def inventario():
    """Tudo o que responde à pergunta do Tel sobre regras antigas atrapalhando."""
    conn = _conectar()
    try:
        fotos = _linhas(conn, """
            SELECT f.id, f.tirada_em, f.rotulo,
                   (SELECT count(*) FROM nai_funcao_foto x WHERE x.foto_id = f.id) AS funcoes
              FROM nai_foto f ORDER BY f.id DESC LIMIT 10
        """)
        # A diferença contra a ÚLTIMA foto: a lista nominal do que o banco tem
        # a mais (ou a menos) que o repositório sabia.
        try:
            desvio = _linhas(conn, "SELECT * FROM nai_foto_diferenca()")
        except psycopg2.Error:
            conn.rollback()
            desvio = []
        return jsonify({
            "mapa":        [_linha(l) for l in _linhas(conn, "SELECT * FROM vw_nai_setor_mapa")],
            "acoplamento": [_linha(l) for l in _linhas(conn, "SELECT * FROM vw_nai_acoplamento")],
            "orfas":       [_linha(l) for l in _linhas(conn, "SELECT * FROM vw_nai_funcao_orfa")],
            "sobrecargas": [_linha(l) for l in _linhas(conn, "SELECT * FROM vw_nai_sobrecarga")],
            "fotos":       [_linha(l) for l in fotos],
            "desvio":      [_linha(l) for l in desvio],
        })
    finally:
        conn.close()


# ==========================================================================
# 4. AS REGRAS -- "ela ignora as regras que eu ensinei"
# ==========================================================================
@trace_bp.route("/api/nai/trace/regras")
def regras():
    """Quais regras ela ignora, quantas vezes, e em quais conversas.

    Vem do arquivo 66. Se ele ainda não tiver sido aplicado, a rota devolve
    `instalado: false` em vez de 500 -- a tela mostra o aviso e as outras abas
    continuam funcionando.
    """
    conn = _conectar()
    try:
        try:
            linhas = _linhas(conn, "SELECT * FROM vw_nai_regras_ignoradas")
            obed = _linhas(conn, "SELECT * FROM vw_nai_obediencia LIMIT 30")
        except psycopg2.Error:
            conn.rollback()
            return jsonify({
                "instalado": False,
                "erro": "o arquivo 66_regras.sql ainda não foi aplicado",
                "regras": [], "obediencia": [],
            })
        return jsonify({
            "instalado": True,
            "regras": [_linha(l) for l in linhas],
            "obediencia": [_linha(l) for l in obed],
        })
    finally:
        conn.close()


@trace_bp.route("/api/nai/trace/saude")
def saude():
    """Ping da tela: diz se o trace está ligado e quanto ele já guardou.

    Serve para a pergunta que vai aparecer: "o painel está vazio, está quebrado?"
    -- aqui se vê se está vazio porque o trace está desligado, porque os nós do
    n8n ainda não foram instalados, ou porque de fato não houve mensagem.
    """
    conn = _conectar()
    try:
        r = _linhas(conn, """
            SELECT (SELECT valor FROM nai_config WHERE chave = 'trace_nivel')   AS trace_nivel,
                   (SELECT valor FROM nai_config WHERE chave = 'trace_payload') AS trace_payload,
                   (SELECT valor FROM nai_config WHERE chave = 'trace_dias')    AS trace_dias,
                   (SELECT count(*) FROM nai_evento)                            AS eventos,
                   (SELECT max(criado_em) FROM nai_evento)                      AS ultimo_evento,
                   (SELECT count(DISTINCT setor) FROM nai_evento)               AS setores_com_dado,
                   (SELECT count(*) FROM nai_turno
                     WHERE criado_em > now() - interval '24 hours')             AS turnos_24h,
                   (SELECT count(*) FROM nai_turno
                     WHERE criado_em > now() - interval '24 hours'
                       AND exec_id IS NOT NULL)                                 AS turnos_24h_com_exec,
                   pg_size_pretty(pg_total_relation_size('nai_evento'))         AS tamanho_trace
        """)
        d = _linha(r[0]) if r else {}
        # O diagnóstico em palavras, para a tela não precisar interpretar.
        if d.get("trace_nivel") == "desligado":
            d["diagnostico"] = "o trace está DESLIGADO (nai_config.trace_nivel)"
        elif not d.get("eventos"):
            d["diagnostico"] = ("trace ligado, mas nenhum evento gravado: os nós do n8n "
                                "provavelmente ainda não foram instalados")
        elif d.get("turnos_24h") and not d.get("turnos_24h_com_exec"):
            d["diagnostico"] = ("há turnos, mas nenhum com id de execução: o nó do cabeçalho "
                                "está gravando, o do modelo não")
        else:
            d["diagnostico"] = "ok"
        return jsonify(d)
    finally:
        conn.close()
