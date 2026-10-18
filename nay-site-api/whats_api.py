"""WHATSAPP › MENSAGENS (410, Pedro 18/10/2026): etiquetas e observação por modelo da Meta.

Pedro: "uma aba whatsapp onde vai ficar os grupos e as mensagens aprovadas ... um panorama geral de todas que foram
aprovadas como uma lista filtrável por data e tipo, e aprovada ou não, e também tags, eu ponho tags nela".
Os modelos vêm de admin/dados/modelos.json (cron nay-agentes lê a Graph API de dentro do CRM). Aqui só o que é nosso:
  GET  /admin/api/whats/modelos/notas        {notas: {"nome|idioma": {etiquetas, observacao}}, etiquetas: [...]}
  POST /admin/api/whats/modelos/notas        {nome, idioma, etiquetas: [...], observacao}
"""
import json
import os

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, request

from imoveis_api import _admin_autenticado
from disparo_api import _usuario_admin

whats_bp = Blueprint("whats", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")


def _conn(escrita):
    url = WRITE_DATABASE_URL if escrita else DATABASE_URL
    if not url:
        raise RuntimeError("banco do site não configurado")
    c = psycopg2.connect(url, connect_timeout=5)
    c.cursor_factory = psycopg2.extras.RealDictCursor
    return c


def _um(sql, params=(), escrita=False):
    c = _conn(escrita)
    try:
        with c.cursor() as cur:
            cur.execute(sql, params)
            linha = cur.fetchone()
        if escrita:
            c.commit()
        return linha["r"] if linha else None
    except Exception:
        c.rollback()
        raise
    finally:
        c.close()


def _negado():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


def _quem():
    try:
        return _usuario_admin() or "admin"
    except Exception:  # noqa: BLE001
        return "admin"


@whats_bp.route("/admin/api/whats/modelos/notas")
def notas():
    if not _admin_autenticado():
        return _negado()
    try:
        return jsonify(_um("SELECT site_whats_modelos_notas() AS r") or {"notas": {}, "etiquetas": []})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li as etiquetas: %s" % str(exc).splitlines()[0][:200]}), 500


@whats_bp.route("/admin/api/whats/modelos/notas", methods=["POST"])
def nota_salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_whats_modelo_nota_salvar(%s::jsonb, %s) AS r", (json.dumps(b, ensure_ascii=False), _quem()), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não salvou: %s" % str(exc).splitlines()[0][:200]}), 500
    return jsonify(r), (200 if r.get("ok") else 422)
