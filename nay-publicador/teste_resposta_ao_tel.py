"""
O "sim"/"não" do Tel no Python casa EXATAMENTE com o do n8n.

Os dois lados leem `casos_resposta_ao_tel.json`. Divergir aqui custa nos dois
sentidos: o nó manda um "sim" que o Python não entende (ele fica sem
resposta), ou o Python entenderia um que o nó não manda (o agente responde no
lugar, que é o que aconteceu em 14/09 com "Pode postar novamente").

Uso:
    .venv/bin/python teste_resposta_ao_tel.py
"""
import json

from interpretar_comando import interpretar_comando, resposta_ao_tel

with open("casos_resposta_ao_tel.json", encoding="utf-8") as f:
    casos = json.load(f)

falhas = 0
for texto, esperado in casos:
    deu = resposta_ao_tel(texto) or "nada"
    ok = deu == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {deu:5s} {texto!r}")

# E o dispatch entrega a ação certa -- o parser não pode deixar outro ramo
# pegar a resposta antes.
for texto, resposta in [("sim", "sim"), ("Pode postar novamente", "sim"), ("não precisa", "nao")]:
    r = interpretar_comando(texto)
    ok = r == {"acao": "responder_pergunta", "resposta": resposta}
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} dispatch {texto!r} -> {r}")

# "de novo" escrito pelo Tel já é a confirmação
r = interpretar_comando("posta no anunciar easy de novo o 1885")
ok = r.get("acao") == "postar_easy" and r.get("de_novo") is True
falhas += 0 if ok else 1
print(f"  {'OK  ' if ok else 'FALHOU'} 'de novo' explícito -> {r}")
r = interpretar_comando("Posta no grupo anunciar easy 1885")
ok = r.get("de_novo") is False
falhas += 0 if ok else 1
print(f"  {'OK  ' if ok else 'FALHOU'} sem 'de novo' -> {r}")

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print(f"TODOS OS {len(casos) + 5} CASOS DA RESPOSTA AO TEL PASSARAM")
