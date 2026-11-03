"""MÍDIAS (579, Pedro 03/11/2026): a aba admin › Mídias, no lugar do "Gerador de posts" do menu.

Pedro: "uma aba Mídias lá dentro do site e organizar essas demandas ... criando um calendário de conteúdo bonitinho ... e lá
em Mídias vai ter abas: uma aba Insta, outra Face, outra YouTube, outra Google SEO e outra IA GEO".
  GET  /admin/api/midias                 site_midias(): as demandas e as peças do calendário
  POST /admin/api/midias                 {id?, canal, tipo, titulo, ...}: site_midia_salvar (cria ou muda)
  POST /admin/api/midias/<id>/excluir    site_midia_excluir (some da tela; fica no banco)
"""
import json

from flask import Blueprint, jsonify, request

from modelos_api import _negado, _quem, _um
from imoveis_api import _admin_autenticado

midias_bp = Blueprint("midias", __name__)


@midias_bp.route("/admin/api/midias")
def listar():
    if not _admin_autenticado():
        return _negado()
    try:
        return jsonify(_um("SELECT site_midias() AS r") or {})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": "Não li as mídias: %s" % str(exc).splitlines()[0][:200]}), 500


@midias_bp.route("/admin/api/midias", methods=["POST"])
def salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_midia_salvar(%s::jsonb, %s) AS r", (json.dumps(b), _quem()), escrita=True)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não salvei: %s" % str(exc).splitlines()[0][:200]}), 422
    return jsonify(dict(r, ok=True))


@midias_bp.route("/admin/api/midias/<int:i>/excluir", methods=["POST"])
def excluir(i):
    if not _admin_autenticado():
        return _negado()
    try:
        r = _um("SELECT site_midia_excluir(%s, %s) AS r", (i, _quem()), escrita=True)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não excluí: %s" % str(exc).splitlines()[0][:200]}), 422
    return jsonify(dict(r, ok=True))
