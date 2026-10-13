"""O banco da Nay (naydb), como o serviço da OLX fala com ele.

Aqui não há regra de negócio, só a chamada: quem decide o que sobe, o que sai e quem a Nay atende é o banco
(migração 364: olx_anuncios_plano, olx_nay_fila...).
"""
from __future__ import annotations

import json

import psycopg2
import psycopg2.extras

from olx import config


def conectar():
    conn = psycopg2.connect(config.DATABASE_URL, connect_timeout=10, application_name="nay-olx",
                            options="-c statement_timeout=60000 -c lock_timeout=5000")
    conn.autocommit = True
    return conn


def linhas(conn, sql: str, params=None) -> list[dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()] if cur.description else []


def um(conn, sql: str, params=None):
    """O primeiro valor da primeira linha (ou None)."""
    with conn.cursor() as cur:
        cur.execute(sql, params)
        r = cur.fetchone() if cur.description else None
        return r[0] if r else None


def chaves(conn) -> dict[str, str]:
    """As chaves de `privado.olx_config`, relidas a cada volta: mudar na tela vale na volta seguinte."""
    return {l["chave"]: l["valor"] or "" for l in linhas(conn, "SELECT chave, valor FROM privado.olx_config")}


def token_da_conta(conn, conta: str) -> str | None:
    return um(conn, "SELECT crm_olx_conta_token(%s)", (conta,)) or None


def js(v) -> str:
    return json.dumps(v, ensure_ascii=False)
