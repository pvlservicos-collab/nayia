"""MODELOS (470, Pedro 22/10/2026): a página admin › Modelos, o mapa de onde estão os modelos de IA e quanto gastam.

Pedro: "mostrando onde estão todos os modelos de IA e dando a opção de substituirmos esses modelos por lá, e um contador
de quanto estamos gastando em cada modelo, por nó de modelo ... e um painel no topo fixado com os gastos por período".
O desenho do ecossistema (os nós e as ligações) mora na página (assets/js/modelos.js); aqui só o que muda:
  GET  /admin/api/modelos           site_ia_modelos(): gastos e chamadas por nó e período, o modelo escolhido, os preços
  POST /admin/api/modelos/trocar    {no, modelo}: site_ia_modelo_trocar (só os nós que leem o modelo do banco)
"""
import json
import os
import urllib.request

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


COTACAO_HORAS = 12
FONTES_DA_COTACAO = (
    ("Frankfurter (BCE)", "https://api.frankfurter.dev/v1/latest?base=USD&symbols=BRL", lambda j: j["rates"]["BRL"]),
    ("AwesomeAPI", "https://economia.awesomeapi.com.br/json/last/USD-BRL", lambda j: j["USDBRL"]["bid"]),
)


def _cotacao():
    """474 (Pedro, 22/10: "em reais principalmente, e dólar pequenininho"): a cotação guardada; passou de 12 h, busca
    outra (a primeira fonte que responder) e guarda. Falhou tudo: segue com a guardada."""
    c = _um("SELECT site_ia_cotacao() AS r") or {}
    if c.get("usd_brl") and float(c.get("horas") or 0) < COTACAO_HORAS:
        return c
    for nome, url, ler in FONTES_DA_COTACAO:
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "imobeasy"}), timeout=4) as r:
                valor = float(ler(json.loads(r.read().decode("utf-8"))))
            _um("SELECT site_ia_cotacao_salvar(%s, %s) AS r", (valor, nome), escrita=True)
            return _um("SELECT site_ia_cotacao() AS r") or c
        except Exception:  # noqa: BLE001
            continue
    return c


@modelos_bp.route("/admin/api/modelos")
def modelos():
    if not _admin_autenticado():
        return _negado()
    try:
        r = _um("SELECT site_ia_modelos() AS r") or {}
        r["cotacao"] = _cotacao()
        return jsonify(r)
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
