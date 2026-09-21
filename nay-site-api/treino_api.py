"""API do MENU DE TREINO do Cérebro da Nay.

Tel (19/09/2026): "cria um menu de treinamento lá dentro do cérebro da Nay
e lá nós vamos testar... eu vou marcar como conversou corretamente, ou
descrever um erro... e mais um campo verde solução".
E, logo depois: "esses testes não são no whatsapp e sim no nosso site com
intuito de aprendizado".

Essa última frase é a regra deste arquivo. Nenhuma rota aqui envia mensagem,
dispara fluxo ou fala com a Z-API. Quem re-executa é o `nai_treino_rodar.py`,
rodado à mão no servidor; aqui só se LÊ o que ele produziu e se GRAVA o
julgamento do Tel.

COMO LIGAR no `app.py` -- duas linhas, junto das do trace:

    from treino_api import treino_bp
    app.register_blueprint(treino_bp)

As duas conexões são separadas de propósito: leitura vai pela role de leitura
(`NAI_DATABASE_URL`) e o julgamento vai pela de conteúdo
(`CONTEUDO_DATABASE_URL`), que no banco só tem permissão em
`nai_treino_julgamento`. Assim uma rota nova escrita com pressa não consegue
alterar turno, saída nem imóvel -- o Postgres recusa antes.
"""
import os
from datetime import date, datetime
from decimal import Decimal

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, request

treino_bp = Blueprint("treino", __name__)

NAI_DATABASE_URL = os.environ.get("NAI_DATABASE_URL")
CONTEUDO_DATABASE_URL = os.environ.get("CONTEUDO_DATABASE_URL")

LIMITE_MAXIMO = 300


def _conectar(url=None):
    alvo = url or NAI_DATABASE_URL
    if not alvo:
        raise RuntimeError("NAI_DATABASE_URL não configurada")
    conn = psycopg2.connect(alvo, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def _linhas(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def _limpar(v):
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, dict):
        return {k: _limpar(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_limpar(x) for x in v]
    return v


def _saida(linhas):
    return [_limpar(dict(r)) for r in linhas]


# ============================================================== os ciclos --
@treino_bp.route("/api/nai/treino/ciclos")
def ciclos():
    """Os ciclos já montados, mais quanto ainda sobra no pool."""
    with _conectar() as conn:
        lista = _linhas(conn, """
            SELECT c.id, c.rotulo, c.tamanho, c.criado_em, c.fechado_em,
                   count(k.id)                                        AS casos,
                   count(*) FILTER (WHERE k.estado = 'rodado')        AS rodados,
                   count(*) FILTER (WHERE k.estado = 'erro')          AS com_erro,
                   count(*) FILTER (WHERE j.caso_id IS NOT NULL)      AS julgados,
                   count(*) FILTER (WHERE j.veredito = 'correto')     AS corretos,
                   count(*) FILTER (WHERE j.veredito = 'errado')      AS errados,
                   count(*) FILTER (WHERE j.solucao IS NOT NULL
                                      AND j.aplicada_em IS NULL)      AS solucoes_abertas
              FROM nai_treino_ciclo c
              LEFT JOIN nai_treino_caso k        ON k.ciclo_id = c.id
              LEFT JOIN nai_treino_julgamento j  ON j.caso_id  = k.id
             GROUP BY c.id
             ORDER BY c.id DESC
        """)
        pool = _linhas(conn, "SELECT count(*) AS n FROM nai_treino_pool")[0]["n"]
        usados = _linhas(conn, "SELECT count(*) AS n FROM nai_treino_caso")[0]["n"]
    return jsonify({"ciclos": _saida(lista), "pool": pool, "ja_usados": usados})


# =============================================================== os casos --
@treino_bp.route("/api/nai/treino/casos")
def casos():
    """Os casos de um ciclo, com o contexto para montar o mockup.

    `contexto` são as falas anteriores daquela conversa, na ordem -- é o que
    permite julgar "ela respondeu certo?" sem abrir o WhatsApp para descobrir
    do que ele estava falando.
    """
    ciclo = request.args.get("ciclo", type=int)
    if not ciclo:
        return jsonify({"erro": "diga qual ciclo (?ciclo=N)"}), 400

    # O `contexto` já vem pronto na view, como jsonb gravado quando o ciclo
    # foi montado. NÃO é montado aqui com JOIN em `nai_turno`/`nai_saida`:
    # a role desta API não pode ler mensagem de ninguém (parede do arquivo
    # 67), e a primeira versão desta rota levava
    # "permission denied for table nai_saida" na cara.
    with _conectar() as conn:
        lista = _linhas(conn, """
            SELECT * FROM nai_treino_painel
             WHERE ciclo_id = %s
             ORDER BY quando_original DESC, id DESC
             LIMIT %s
        """, (ciclo, LIMITE_MAXIMO))

    return jsonify({"ciclo": ciclo, "casos": _saida(lista)})


# ========================================================== o julgamento --
@treino_bp.route("/api/nai/treino/julgamento/<int:caso_id>", methods=["PUT", "DELETE"])
def julgamento(caso_id):
    """Grava (ou apaga) o julgamento de um caso.

    É a única rota de escrita do arquivo, e ela só alcança uma tabela.
    """
    if request.method == "DELETE":
        with _conectar(CONTEUDO_DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM nai_treino_julgamento WHERE caso_id = %s", (caso_id,))
            conn.commit()
        return jsonify({"ok": True, "apagado": True})

    dados = request.get_json(silent=True) or {}
    veredito = (dados.get("veredito") or "").strip()
    erro = (dados.get("erro") or "").strip() or None
    solucao = (dados.get("solucao") or "").strip() or None
    por = (dados.get("por") or "painel").strip()[:60]

    if veredito not in ("correto", "errado"):
        return jsonify({"erro": "veredito tem que ser 'correto' ou 'errado'"}), 400
    if veredito == "errado" and not erro and not solucao:
        return jsonify({"erro": "para marcar errado, escreva o erro ou a solução"}), 400

    with _conectar(CONTEUDO_DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO nai_treino_julgamento
                       (caso_id, veredito, erro, solucao, julgado_por, julgado_em)
                VALUES (%s, %s, %s, %s, %s, now())
                ON CONFLICT (caso_id) DO UPDATE
                   SET veredito = EXCLUDED.veredito,
                       erro     = EXCLUDED.erro,
                       solucao  = EXCLUDED.solucao,
                       julgado_por = EXCLUDED.julgado_por,
                       julgado_em  = now()
                RETURNING caso_id, veredito, julgado_em
            """, (caso_id, veredito, erro, solucao, por))
            r = cur.fetchone()
        conn.commit()
    return jsonify({"ok": True, "julgamento": _limpar(dict(r))})


# ============================================================ as soluções --
@treino_bp.route("/api/nai/treino/solucoes")
def solucoes():
    """O apanhado do ciclo: tudo que ele marcou como errado, com a solução.

    É o que eu leio no fim de cada ciclo para implementar em massa. Vem
    separado entre o que ainda não foi aplicado e o que já foi, para um
    ciclo novo não me fazer refazer o que já está feito.
    """
    ciclo = request.args.get("ciclo", type=int)
    sql = """
        SELECT k.id, k.ciclo_id, k.turno_origem, k.quando_original,
               k.ele_disse, k.ela_respondeu_antes, k.ela_respondeu_agora,
               k.ferramentas_agora,
               j.erro, j.solucao, j.aplicada_em, j.aplicada_como, j.julgado_em
          FROM nai_treino_caso k
          JOIN nai_treino_julgamento j ON j.caso_id = k.id
         WHERE j.veredito = 'errado'
    """
    params = []
    if ciclo:
        sql += " AND k.ciclo_id = %s"
        params.append(ciclo)
    sql += " ORDER BY j.aplicada_em NULLS FIRST, k.id"

    with _conectar() as conn:
        linhas = _saida(_linhas(conn, sql, params))
    return jsonify({
        "abertas": [x for x in linhas if not x.get("aplicada_em")],
        "aplicadas": [x for x in linhas if x.get("aplicada_em")],
    })
