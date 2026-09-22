"""API da página ESTRUTURA DA NAY.

Tel (22/09/2026): "implementa visualmente lá no nay ia, lá no site como vai
ficar essa estrutura nova em fluxograma".

O fluxograma em si é desenho -- mora no HTML. O que vem daqui são os NÚMEROS
que enchem o desenho: quantas mensagens a mente mandou para cada lado, o que a
secretária já aprendeu com o Tel, o que ela ainda está esperando ele responder
e os imóveis que entraram pelo cadastro dela.

Só leitura. Nenhuma rota aqui liga, desliga, envia mensagem ou muda regra --
quem faz isso é a página da Nay Locação, que já tem o caminho com senha.

COMO LIGAR no `app.py` -- duas linhas, junto das do treino:

    from estrutura_api import estrutura_bp
    app.register_blueprint(estrutura_bp)
"""
import os
from datetime import date, datetime
from decimal import Decimal

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify

estrutura_bp = Blueprint("estrutura", __name__)

NAI_DATABASE_URL = os.environ.get("NAI_DATABASE_URL")


def _conectar():
    if not NAI_DATABASE_URL:
        raise RuntimeError("NAI_DATABASE_URL não configurada")
    conn = psycopg2.connect(NAI_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def _simples(v):
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    return v


def _linhas(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return [{k: _simples(v) for k, v in linha.items()} for linha in cur.fetchall()]


@estrutura_bp.route("/api/nai/estrutura")
def api_nai_estrutura():
    conn = _conectar()
    try:
        ligada = _linhas(conn, """
            SELECT valor FROM nai_config WHERE chave = 'secretaria_ligada'
        """)
        return jsonify({
            "secretaria_ligada": (ligada[0]["valor"] if ligada else "nao") == "sim",

            # Para onde a mente mandou cada mensagem, nos últimos 7 dias.
            "decisoes": _linhas(conn, """
                SELECT atendente, por, count(*) AS quantas
                  FROM nai_mente
                 WHERE criado_em > now() - interval '7 days'
                 GROUP BY 1, 2 ORDER BY 3 DESC
            """),
            "ultimas_decisoes": _linhas(conn, """
                SELECT m.id, m.atendente, m.motivo, m.criado_em,
                       left(coalesce(t.texto, '(só mídia)'), 120) AS escreveu
                  FROM nai_mente m LEFT JOIN nai_turno t ON t.id = m.turno_id
                 ORDER BY m.id DESC LIMIT 25
            """),

            # O que ela já aprendeu com o Tel, e o que ainda está esperando.
            "saber": _linhas(conn, """
                SELECT id, pergunta, resposta, vezes_usada, criado_em
                  FROM nai_saber WHERE ativo ORDER BY id DESC LIMIT 30
            """),
            "esperando": _linhas(conn, """
                SELECT id, o_que_falta AS pergunta, criada_em
                  FROM pendencias
                 WHERE de_quem = 'secretaria' AND status = 'aberta'
                 ORDER BY id DESC LIMIT 20
            """),

            # Os imóveis que entraram pela conversa dela.
            "fichas": _linhas(conn, """
                SELECT n.id, n.situacao, n.codigo, n.tipo, n.finalidade, n.condominio,
                       n.bairro, n.quartos, n.valor, n.criado_em,
                       (SELECT count(*) FROM nai_imovel_novo_foto f WHERE f.novo_id = n.id) AS fotos,
                       nai_imovel_novo_falta(n.id) AS falta
                  FROM nai_imovel_novo n ORDER BY n.id DESC LIMIT 30
            """),
        })
    finally:
        conn.close()
