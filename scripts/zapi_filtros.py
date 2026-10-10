# Liga (ou desliga) a entrega das mensagens de GRUPO no webhook "Ao receber" da instância da Parceria na Z-API.
#
#   python3 zapi_filtros.py ligar      -> messageFilters = []                      (grupo volta a chegar)
#   python3 zapi_filtros.py desligar   -> messageFilters = ["FILTER_FROM_GROUP"]   (como estava: grupo não chega)
#
# Pedro, 09/10/2026: a aba Grupos do CRM foi pedida "justamente para monitorar isso" e nunca recebeu uma mensagem
# de grupo; a Z-API só entregava avisos. Não imprime token nem endereço.
import json
import sys
import urllib.error
import urllib.request

env = {}
for ln in open("/root/nay-publicador/.env", encoding="utf-8"):
    if "=" in ln and not ln.lstrip().startswith("#"):
        k, v = ln.strip().split("=", 1)
        env[k] = v.strip().strip('"').strip("'")
filtros = {"ligar": [], "desligar": ["FILTER_FROM_GROUP"]}.get(sys.argv[1] if len(sys.argv) > 1 else "")
if filtros is None:
    raise SystemExit("use: ligar | desligar")
url = "https://api.z-api.io/instances/%s/token/%s/update-filters" % (env["ZAPI_INSTANCIA"], env["ZAPI_TOKEN"])
req = urllib.request.Request(url, data=json.dumps({"messageFilters": filtros}).encode("utf-8"), method="PUT",
                             headers={"Client-Token": env.get("ZAPI_CLIENT_TOKEN", ""), "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        corpo, codigo = r.read().decode("utf-8", "replace"), r.status
except urllib.error.HTTPError as e:
    corpo, codigo = e.read().decode("utf-8", "replace"), e.code
limpo = corpo.replace(env["ZAPI_INSTANCIA"], "(instancia)").replace(env["ZAPI_TOKEN"], "(token)")
print("messageFilters =", json.dumps(filtros), "->", codigo, " ".join(limpo.split())[:200])
