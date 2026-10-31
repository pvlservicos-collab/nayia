"""
O CONFERIDOR E A Z-API DA NAY (tirado do enviador_manual.py em 31/10/2026, migração 550).

Usado pelos dois que mandam o que está em nai_saida pela Z-API da Parceria:
  - enviador_manual.py  a entrega pedida por gente (Enviar imóvel, Me envia, ENVIA)
  - agenda_nai.py       a agenda e as respostas da Nay velha, no lugar do n8n

É o porte do nó "Conferir cabeçalho" do n8n (o CHECK DUPLO: a chave do destino recalculada aqui, sem confiar na do
banco) e do nó "Enviar Z-API". Credenciais no ambiente (ZAPI_INSTANCIA, ZAPI_TOKEN, ZAPI_CLIENT_TOKEN); a URL leva o
token, então nunca vai para o registro.
"""
import json
import os
import re

import requests

TIMEOUT_ZAPI_S = 30


def chave(p):
    """A chave do destino recalculada aqui, independente da do banco (nai_chave)."""
    p = str(p or "")
    if re.search(r"@lid$", p, re.I):
        d = re.sub(r"\D", "", p)
        return "lid:" + d if d else None
    d = re.sub(r"\D", "", p)
    if not d:
        return None
    if len(d) in (10, 11) and not d.startswith("55"):
        d = "55" + d
    if re.fullmatch(r"55\d{10,11}", d):
        return d[:4] + d[-8:]
    return d


def motivo_para_nao_enviar(j):
    """None = pode enviar; senão o motivo do bloqueio (os mesmos nomes do n8n)."""
    corpo = j.get("corpo") or {}
    if not j.get("id"):
        return "sem_id"
    if not corpo or str(corpo.get("phone")) != str(j.get("telefone")):
        return "telefone_do_corpo_diferente"
    if not j.get("chave_esperada") or chave(j.get("telefone")) != str(j.get("chave_esperada")):
        return "chave_nao_confere_py"
    if j.get("rota") not in ("send-text", "send-image"):
        return "rota_invalida"
    if j.get("rota") == "send-image":
        cod = int(j.get("codigo") or 0)
        img = str(corpo.get("image") or "")
        foto_do_imovel = cod > 0 and (
            re.match(r"^https://imobeasy\.com/system/pictures/", img)
            or re.match(r"^https://imobeasy\.online/fotos(-captacao/[a-z]+)?/%d/" % cod, img)
            or img == "https://imobeasy.online/colagens/%d.jpg" % cod)
        if not foto_do_imovel:
            return "foto_sem_codigo"
    if j.get("rota") == "send-text" and not str(corpo.get("message") or "").strip():
        return "texto_vazio"
    return None


def zapi_base():
    inst, tok = os.environ["ZAPI_INSTANCIA"], os.environ["ZAPI_TOKEN"]
    return "https://api.z-api.io/instances/%s/token/%s" % (inst, tok)


def zapi_cabecalho():
    return {"Client-Token": os.environ["ZAPI_CLIENT_TOKEN"], "Content-Type": "application/json"}


def enviar_zapi(rota, corpo):
    """Devolve o JSON da Z-API ou um {"error": ...} -- nai_confirmar_envio decide se tenta de novo."""
    try:
        r = requests.post(zapi_base() + "/" + rota, headers=zapi_cabecalho(), data=json.dumps(corpo), timeout=TIMEOUT_ZAPI_S)
        try:
            resp = r.json()
        except ValueError:
            resp = {"error": "%s %s" % (r.status_code, (r.text or "")[:200])}
        if not isinstance(resp, dict):
            resp = {"resposta": resp}
        if r.status_code >= 400 and "error" not in resp:
            resp["error"] = "%s %s" % (r.status_code, json.dumps(resp)[:200])
        return resp
    except requests.RequestException as e:
        return {"error": "%s: %s" % (e.__class__.__name__, str(e)[:200])}
