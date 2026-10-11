"""Resumo do agentes.json no terminal (conferência depois de publicar)."""
import json

d = json.load(open("/docker/nay-site-web/public/admin/dados/agentes.json", encoding="utf-8"))
print(len(d["itens"]), "itens | hoje:", d["hoje"])
for i in d["itens"]:
    if i["tipo"] == "rotina":
        continue
    print(" ", i["id"], "ativo" if i.get("ativo") else "PARADO", "cpu_s", i.get("cpu_s"), "mem", round(i.get("mem", 0) / 1048576), "MB")
