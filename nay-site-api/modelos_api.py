"""MODELOS (470, Pedro 22/10/2026): a página admin › Modelos, o mapa de onde estão os modelos de IA e quanto gastam.

Pedro: "mostrando onde estão todos os modelos de IA e dando a opção de substituirmos esses modelos por lá, e um contador
de quanto estamos gastando em cada modelo, por nó de modelo ... e um painel no topo fixado com os gastos por período".
O desenho do ecossistema (os nós e as ligações) mora na página (assets/js/modelos.js); aqui só o que muda:
  GET  /admin/api/modelos           site_ia_modelos(): gastos e chamadas por nó e período, o modelo escolhido, os preços
  POST /admin/api/modelos/trocar    {no, modelo}: site_ia_modelo_trocar (só os nós que leem o modelo do banco)
"""
import os

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, request

from imoveis_api import _admin_autenticado
from disparo_api import _usuario_admin

modelos_bp = Blueprint("modelos", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")


def _um(sql, params=(), escrita=False):
    url = WRITE_DATABASE_URL if escrita else DATABASE_URL
    if not url:
        raise RuntimeError("banco do site não configurado")
    c = psycopg2.connect(url, connect_timeout=5)
    try:
        with c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
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


@modelos_bp.route("/admin/api/modelos")
def modelos():
    if not _admin_autenticado():
        return _negado()
    try:
        return jsonify(_um("SELECT site_ia_modelos() AS r") or {})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li os modelos: %s" % str(exc).splitlines()[0][:200]}), 500


@modelos_bp.route("/admin/api/modelos/trocar", methods=["POST"])
def trocar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_ia_modelo_trocar(%s, %s, %s) AS r",
                (str(b.get("no") or ""), str(b.get("modelo") or ""), _quem()), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não troquei: %s" % str(exc).splitlines()[0][:200]}), 500
    return jsonify(r), (200 if r.get("ok") else 422)
