"""IDEIAS REFINADAS (514, Pedro 28/10/2026): a aba Ideias refinadas da página admin › Aprendizado.

Pedro: "cada ideia vai ter a tua sugestão, como é hoje, onde isso pode nos ajudar, e se a execução é curto, médio ou
longo prazo, e uma nota em formato de uma barrinha vertical que eu vou mexer ... filtrar lá em cima só as acima de 90".
  GET  /admin/api/aprendizado/ideias              site_aprendizado_ideias(): as ideias e os vídeos estudados
  POST /admin/api/aprendizado/ideias/<id>/nota    {nota}: site_aprendizado_ideia_nota (a barrinha)
Quem grava as ideias é a rotina da noite (scripts/aprendizado.py gravar), direto no banco.
"""
from flask import Blueprint, jsonify, request

from modelos_api import _negado, _quem, _um
from imoveis_api import _admin_autenticado

aprendizado_bp = Blueprint("aprendizado", __name__)


@aprendizado_bp.route("/admin/api/aprendizado/ideias")
def listar():
    if not _admin_autenticado():
        return _negado()
    try:
        return jsonify(_um("SELECT site_aprendizado_ideias() AS r") or {})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li as ideias: %s" % str(exc).splitlines()[0][:200]}), 500


@aprendizado_bp.route("/admin/api/aprendizado/ideias/<int:i>/nota", methods=["POST"])
def nota(i):
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_aprendizado_ideia_nota(%s, %s, %s) AS r", (i, int(b.get("nota")), _quem()), escrita=True)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não salvei: %s" % str(exc).splitlines()[0][:200]}), 422
    return jsonify(dict(r, ok=True))
