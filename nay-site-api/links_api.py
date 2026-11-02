"""LINKS ORGÂNICOS (559, Pedro 02/11/2026): "organize todos os leads que possam vir de nossas redes sociais ou blogs em uma
página ... Links orgânicos, são variações de links de WhatsApp com UTM para o número 92 8595-6408 para eu saber de onde
está vindo o lead baseado em uma mensagem automática também, ex.: Vim do blog, Vim do site".

  GET  /w/<código>?utm_source=...        o link curto (público): anota o clique com os UTMs e abre o WhatsApp do 8595 com a
                                         mensagem pronta do link; o lead é reconhecido pela marca dela quando chega
                                         (gatilho link_organico_do_lead em captacao_mensagens)
  GET  /admin/api/links-organicos        os links com cliques e leads (site_links_organicos)
  POST /admin/api/links-organicos        criar ou mudar um link (site_link_organico_salvar)
"""
import json
import os
from urllib.parse import quote

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, redirect, request

from imoveis_api import _admin_autenticado
from disparo_api import _usuario_admin

links_bp = Blueprint("links", __name__)

WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
NUMERO = "559285956408"            # o WhatsApp do 8595 (92 8595-6408), como a Z-API grava
BASE_CURTA = "https://api.imobeasy.online/w/"


def _um(sql, params=()):
    if not WRITE_DATABASE_URL:
        raise RuntimeError("banco do site não configurado")
    c = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
    c.cursor_factory = psycopg2.extras.RealDictCursor
    try:
        with c.cursor() as cur:
            cur.execute(sql, params)
            linha = cur.fetchone()
        c.commit()
        return linha["r"] if linha else None
    except Exception:
        c.rollback()
        raise
    finally:
        c.close()


def wa(mensagem):
    return "https://wa.me/%s?text=%s" % (NUMERO, quote(mensagem or "", safe=""))


@links_bp.route("/w/<codigo>")
def link_curto(codigo):
    utm = {k: v[:120] for k, v in request.args.items() if k.startswith("utm_")}
    ip = (request.headers.get("X-Real-Ip") or request.remote_addr or "")[:64]
    try:
        r = _um("SELECT site_link_organico_clique(%s, %s::jsonb, %s, %s) AS r",
                (codigo[:40], json.dumps(utm), (request.referrer or "")[:300], ip))
    except Exception:  # noqa: BLE001 -- o clique nunca deixa a pessoa sem o WhatsApp
        r = None
    return redirect(wa(r.get("mensagem")) if r else "https://wa.me/%s" % NUMERO, code=302)


def _negado():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


@links_bp.route("/admin/api/links-organicos")
def listar():
    if not _admin_autenticado():
        return _negado()
    try:
        links = _um("SELECT site_links_organicos() AS r") or []
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li os links: %s" % str(exc).splitlines()[0][:200]}), 500
    for l in links:
        utm = "utm_source=%s&utm_medium=%s&utm_campaign=%s" % (
            quote(l["utm_source"]), quote(l["utm_medium"]), quote(l["utm_campaign"]))
        l["link_curto"] = BASE_CURTA + l["codigo"] + "?" + utm
        l["link_direto"] = wa(l["mensagem"])
    return jsonify({"links": links, "numero": NUMERO})


@links_bp.route("/admin/api/links-organicos", methods=["POST"])
def salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        quem = _usuario_admin() or "admin"
    except Exception:  # noqa: BLE001
        quem = "admin"
    try:
        r = _um("SELECT site_link_organico_salvar(%s::jsonb, %s) AS r", (json.dumps(b, ensure_ascii=False), quem)) or {}
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não salvou: %s" % str(exc).splitlines()[0][:200]}), 500
    return jsonify(r), (200 if r.get("ok") else 422)
