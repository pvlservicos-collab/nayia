"""A BIBLIOTECA DE CONVERSAS (498, Pedro 25/10/2026): a aba Biblioteca da página admin › Inteligência.

Pedro: "crie um registro de conversas que deram certo x conversas com erro e salvar, isso vai ficar lá na aba inteligência
no site também ... vamos usar futuramente para treino".
  GET /admin/api/biblioteca?nay=&resultado=&confianca=&fonte=&tipo=&busca=&de=&ate=&pagina=   site_biblioteca(filtros)
  GET /admin/api/biblioteca/<id>                                                            site_biblioteca_conversa(id)
Só leitura; atrás da senha do /admin (o Traefik e _admin_autenticado).
"""
from flask import Blueprint, jsonify, request

from modelos_api import _negado, _um
from imoveis_api import _admin_autenticado

biblioteca_bp = Blueprint("biblioteca", __name__)
FILTROS = ("nay", "resultado", "confianca", "fonte", "tipo", "busca", "de", "ate", "pagina", "limite")


@biblioteca_bp.route("/admin/api/biblioteca")
def listar():
    if not _admin_autenticado():
        return _negado()
    filtros = {k: request.args.get(k) for k in FILTROS if request.args.get(k)}
    try:
        from psycopg2.extras import Json
        return jsonify(_um("SELECT site_biblioteca(%s) AS r", (Json(filtros),)) or {})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li a biblioteca: %s" % str(exc).splitlines()[0][:200]}), 500


@biblioteca_bp.route("/admin/api/biblioteca/<int:i>")
def conversa(i):
    if not _admin_autenticado():
        return _negado()
    try:
        r = _um("SELECT site_biblioteca_conversa(%s) AS r", (i,))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li a conversa: %s" % str(exc).splitlines()[0][:200]}), 500
    return (jsonify(r), 200) if r else (jsonify({"erro": "não existe"}), 404)
