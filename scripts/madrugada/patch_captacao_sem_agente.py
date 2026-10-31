# -*- coding: utf-8 -*-
"""CAPTACAO SEM O AGENTE VELHO (Pedro, 31/10/2026: "tire tudo do n8n quero tudo em python"; plano, etapa 1).
Uso: python3 patch_captacao_sem_agente.py ENTRADA.json SAIDA.json

O que muda no fluxo "Nay - captacao proprietarios" (CjsUJefRYcQIIi1F):
  - "Gravar na fila" nao segue mais para a "Janela de 20s" (nem para o AI Agent velho). A mensagem continua gravada em
    captacao_mensagens (e dali que a Nay Leads e o nay-captacao leem) e a vaga do n8n solta na hora. Antes: 41 rodadas
    do agente em 11 h sem nenhum envio, 281 escaladas em 7 dias (260 de gente sem cadastro).
  - "Cron do disparo" e "Cron do followup" desligados (0 envios: o disparo e o do Python).
  - "Cron da fila parada" so chama o "Vigia do numero" (a fila parada era do agente velho).
Para tudo se uma ancora nao bater (o fluxo mudou)."""
import json
import sys

entrada, saida = sys.argv[1], sys.argv[2]
texto = open(entrada, encoding="utf-8").read()
dados, _ = json.JSONDecoder().raw_decode(texto[texto.index("["):] if texto.lstrip()[0] == "[" else texto)
w = dados[0] if isinstance(dados, list) else dados
nos = {n["name"]: n for n in w["nodes"]}
con = w["connections"]


def ancora(ok, o_que):
    if not ok:
        print("ANCORA NAO BATEU:", o_que)
        sys.exit(1)


ancora([[c["node"] for c in s] for s in con.get("Gravar na fila", {}).get("main", [])] == [["Janela de 20s"]],
       "Gravar na fila -> Janela de 20s")
fila = con.get("Cron da fila parada", {}).get("main", [[]])
ancora(sorted(c["node"] for c in fila[0]) == ["Pegar conversa sem resposta", "Vigia do numero"],
       "Cron da fila parada -> Pegar conversa / Vigia")
for nome in ("Cron do disparo", "Cron do followup"):
    ancora(nome in nos, nome)

con["Gravar na fila"]["main"] = [[]]
con["Cron da fila parada"]["main"] = [[c for c in fila[0] if c["node"] == "Vigia do numero"]]
for nome in ("Cron do disparo", "Cron do followup"):
    nos[nome]["disabled"] = True

json.dump([w], open(saida, "w", encoding="utf-8"), ensure_ascii=False)
print("ok: Gravar na fila termina ali; crons de disparo/followup desligados; fila parada so com o vigia")
