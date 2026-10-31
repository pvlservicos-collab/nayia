# -*- coding: utf-8 -*-
"""Esvazia os webhooks de PRESENCA e ENTREGA da instancia Z-API da captacao (8595), como na nota de 28/09.
Pedro, 31/10/2026 (plano "tirar tudo do n8n", etapa 1): 807 + 106 execucoes inuteis em 11 h no n8n da VPS2.
O segredo vem do banco do CRM no proprio servidor; nada sai daqui. Uso: python3 zapi_limpar.py [--limpar]"""
import json
import subprocess
import sys
import urllib.request

INST = "3F8E05E72BA832E61BD40E085F490F69"
INTEGRACAO = "83eedc53-2660-4acb-9796-092525ce671f"
bruto = subprocess.check_output([
    "docker", "exec", "nay-postgres", "psql", "-U", "nay", "-d", "crmdb", "-At", "-c",
    "SELECT secret FROM integration_secrets WHERE integration_id = '%s'" % INTEGRACAO,
]).decode().strip()
s = json.loads(bruto)
base = "https://api.z-api.io/instances/%s/token/%s" % (INST, s["instance_token"])
cab = {"Content-Type": "application/json"}
if s.get("client_token"):
    cab["Client-Token"] = s["client_token"]


def chamar(metodo, caminho, corpo=None):
    dados = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(base + caminho, data=dados, headers=cab, method=metodo)
    return json.loads(urllib.request.urlopen(req, timeout=20).read() or b"{}")


def mostrar():
    for k, v in sorted(chamar("GET", "/me").items()):
        if "allback" in k or "ebhook" in k:
            print("  %s = %s" % (k, v))


print("ANTES:")
mostrar()
if "--limpar" in sys.argv:
    print("presenca ->", chamar("PUT", "/update-webhook-chat-presence", {"value": ""}))
    print("entrega  ->", chamar("PUT", "/update-webhook-delivery", {"value": ""}))
    print("DEPOIS:")
    mostrar()
