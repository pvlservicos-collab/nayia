#!/usr/bin/env python3
"""Apaga no WhatsApp mensagens que o publicador enviou, pela Z-API.

Um argumento: o código do imóvel. Sem `--apagar`, só mostra o que faria.
`--limite N` apaga só as N primeiras -- é assim que se testa em UM grupo antes
de mexer em dezesseis.
"""
import argparse
import os
import sys
import time

import requests

import db

BASE = "https://api.z-api.io/instances/{i}/token/{t}/messages"


def alvos(conn, codigo):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT e.id, e.telefone, e.message_id, g.nome AS grupo "
            "  FROM envios e LEFT JOIN grupos g ON g.id_grupo = e.telefone "
            " WHERE e.codigo::text = %s AND coalesce(e.message_id,'') <> '' "
            " ORDER BY e.id", (str(codigo),))
        return cur.fetchall()


def apagar(telefone, message_id):
    url = BASE.format(i=os.environ["ZAPI_INSTANCIA"], t=os.environ["ZAPI_TOKEN"])
    r = requests.delete(
        url,
        params={"messageId": message_id, "phone": telefone, "owner": "true"},
        headers={"Client-Token": os.environ["ZAPI_CLIENT_TOKEN"]},
        timeout=30)
    return r.status_code, (r.text or "")[:200]


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("codigo")
    p.add_argument("--apagar", action="store_true")
    p.add_argument("--limite", type=int, default=None)
    a = p.parse_args()

    conn = db.conectar()
    linhas = alvos(conn, a.codigo)
    if a.limite:
        linhas = linhas[:a.limite]
    print(f"  {len(linhas)} mensagem(ns) do {a.codigo}")
    falhas = 0
    for i, l in enumerate(linhas):
        if not a.apagar:
            print(f"  [simulado] {l['grupo']}  ({l['message_id']})")
            continue
        if i:
            time.sleep(1.2)
        st, corpo = apagar(l["telefone"], l["message_id"])
        ok = 200 <= st < 300
        falhas += 0 if ok else 1
        print(f"  {'OK ' if ok else 'ERRO'} {st}  {l['grupo']}  {corpo[:90]}")
    conn.close()
    if not a.apagar:
        print("\n  (simulação -- use --apagar)")
    elif falhas:
        print(f"\n  {falhas} falharam")
        sys.exit(1)
