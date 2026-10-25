"""INTELIGÊNCIAS GERAIS DOS AGENTES (495, Pedro 25/10/2026): a aba de baixo da página admin › Agentes.

Pedro: "comparar a Nay Parceria ... ver o que ela tem que as outras Nay não têm mas poderiam ... e salvar em uma aba lá
no site Agentes ... Inteligências gerais dos agentes, e vai salvar lá essas regras para futuramente".
  GET  /admin/api/inteligencias    site_inteligencias(): todas as regras, para quem valem e onde já estão aplicadas
  POST /admin/api/inteligencias    {id?, regra, porque, vale_para[], aplicada_em[], assunto, ativa}: site_inteligencia_salvar
"""
from flask import Blueprint, jsonify, request

from modelos_api import _negado, _quem, _um
from imoveis_api import _admin_autenticado

inteligencias_bp = Blueprint("inteligencias", __name__)


@inteligencias_bp.route("/admin/api/inteligencias")
def listar():
    if not _admin_autenticado():
        return _negado()
    try:
        return jsonify({"regras": _um("SELECT site_inteligencias() AS r") or []})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li as inteligências: %s" % str(exc).splitlines()[0][:200]}), 500


@inteligencias_bp.route("/admin/api/inteligencias", methods=["POST"])
def salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        from psycopg2.extras import Json
        i = _um("SELECT site_inteligencia_salvar(%s, %s) AS r", (Json(b), _quem()), escrita=True)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não salvei: %s" % str(exc).splitlines()[0][:200]}), 422
    return jsonify({"ok": True, "id": i})
