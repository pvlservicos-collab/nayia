"""A aba ENVIAR IMÓVEL do painel (Tel, 28/09/2026).

"põe no site uma aba de disparo que eu disparo o imóvel automático... lá em
cima o número, embaixo um campo de pesquisar imóvel... eu seleciono também
qual número quero enviar, por padrão fica o de parceria. Quero esse menu de
envio no site e no CRM lá em cima."

UM REMETENTE SÓ: esta rota não manda nada -- repassa ao CRM (`/api/disparo`),
que é quem chama as paredes da Nay no banco (parceiro não sai, indisponível
não sai, fotos do mesmo imóvel 1x a cada 24h por pessoa) e quem fala com as
linhas de WhatsApp. As duas telas fazendo o mesmo caminho é o que impede uma
de ter regra que a outra não tem.

  GET  /admin/api/disparo/linhas   -- as linhas de WhatsApp (Parceria primeiro)
  GET  /admin/api/disparo/buscar   -- o disparo por faixa: acha os imoveis para marcar
  POST /admin/api/disparo          -- {telefone, codigos, integrationId}

SÓ O ADMIN: dispara mensagem de verdade. Confere a mesma senha do /admin aqui
dentro, porque este processo também atende api.imobeasy.online, que não tem
senha nenhuma.

COMO LIGAR no `app.py` -- o mesmo try/except dos outros blueprints -- e a linha
`COPY disparo_api.py .` no Dockerfile. Variáveis: CRM_API_BASE (a rede interna,
http://crm-imobeasy:3000) e CRM_API_TOKEN (um token `atl_` do CRM).
"""
import base64
import hmac
import json
import os
import urllib.error
import urllib.parse
import urllib.request

from flask import Blueprint, jsonify, request

try:
    from passlib.context import CryptContext
    _CTX = CryptContext(schemes=["apr_md5_crypt", "bcrypt", "sha256_crypt"])
except Exception:  # noqa: BLE001
    _CTX = None

disparo_bp = Blueprint("disparo", __name__)

ADMIN_HTPASSWD = os.environ.get("ADMIN_HTPASSWD", "")
CRM_API_BASE = os.environ.get("CRM_API_BASE", "http://crm-imobeasy:3000").rstrip("/")
CRM_API_TOKEN = os.environ.get("CRM_API_TOKEN", "")


def _usuario_admin():
    """O usuário do /admin, se a senha confere; senão None."""
    if ":" not in ADMIN_HTPASSWD or _CTX is None:
        return None
    usuario_ok, hash_ok = ADMIN_HTPASSWD.split(":", 1)
    cab = request.headers.get("Authorization", "")
    if not cab.startswith("Basic "):
        return None
    try:
        usuario, senha = base64.b64decode(cab[6:]).decode("utf-8").split(":", 1)
    except Exception:  # noqa: BLE001
        return None
    if not hmac.compare_digest(usuario, usuario_ok):
        return None
    try:
        return usuario if _CTX.verify(senha, hash_ok) else None
    except Exception:  # noqa: BLE001
        return None


def _nao_autenticado():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


def _crm(metodo, caminho, corpo=None, timeout=15):
    """Chama o CRM e devolve (status, json). Erro de rede vira 502 com o motivo."""
    if not CRM_API_TOKEN:
        return 500, {"erro": "CRM_API_TOKEN não configurado na API do site."}
    dados = json.dumps(corpo).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request(CRM_API_BASE + caminho, data=dados, method=metodo, headers={
        "Authorization": "Bearer " + CRM_API_TOKEN,
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        try:
            j = json.loads(e.read().decode("utf-8") or "{}")
        except Exception:  # noqa: BLE001
            j = {}
        return e.code, {"erro": j.get("error") or j.get("erro") or f"o CRM respondeu {e.code}"}
    except Exception as e:  # noqa: BLE001
        return 502, {"erro": f"não consegui falar com o CRM: {e}"}


@disparo_bp.get("/admin/api/disparo/linhas")
def linhas():
    if not _usuario_admin():
        return _nao_autenticado()
    status, j = _crm("GET", "/api/disparo")
    return jsonify(j), status


@disparo_bp.get("/admin/api/disparo/buscar")
def buscar():
    """O disparo por faixa (28/09): acha os imoveis para a tela marcar. Quem
    procura e o CRM (`/api/disparo/buscar`), com as paredes da Nay."""
    if not _usuario_admin():
        return _nao_autenticado()
    # as listas vem repetindo o parametro (bairro=A&bairro=B): repassa todas
    pares = [(k, str(request.args.get(k))[:60]) for k in ("finalidade", "vmin", "vmax") if request.args.get(k)]
    for k in ("bairro", "tipo", "mobilia", "quartos"):
        pares += [(k, str(v)[:60]) for v in request.args.getlist(k)[:30] if v]
    q = urllib.parse.urlencode(pares)
    status, j = _crm("GET", "/api/disparo/buscar?" + q, timeout=20)
    if status >= 400 and "erro" not in j:
        j = {"erro": j.get("error") or "não consegui procurar"}
    return jsonify(j), status


@disparo_bp.post("/admin/api/disparo")
def disparar():
    usuario = _usuario_admin()
    if not usuario:
        return _nao_autenticado()
    b = request.get_json(silent=True) or {}
    corpo = {
        "telefone": str(b.get("telefone") or "")[:40],
        "codigos": [c for c in (b.get("codigos") or [])][:10],
        "integrationId": b.get("integrationId") or None,
        "quem": usuario,
    }
    # A API oficial manda card e fotos na hora, uma a uma: pode passar de 15 s.
    status, j = _crm("POST", "/api/disparo", corpo, timeout=80)
    if status >= 400 and "erro" not in j:
        j = {"erro": j.get("error") or "não consegui enviar"}
    return jsonify(j), status
