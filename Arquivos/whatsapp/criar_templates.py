# -*- coding: utf-8 -*-
"""Cria os templates da Nay na API oficial do WhatsApp (Cloud API).

Tel, 25/09/2026: "quero que vc gere uns templates do whatsapp api oficial".

    python3 criar_templates.py --listar          # o que ja existe la
    python3 criar_templates.py --conferir        # so mostra o que enviaria
    python3 criar_templates.py --criar           # envia de verdade, para aprovacao

O TOKEN NAO MORA AQUI. Ele vem do ambiente:

    export META_TOKEN='...'          # o token do usuario de sistema
    export META_WABA_ID='...'        # a conta do WhatsApp (WhatsApp Business Account)

ANTES DE RODAR, no Meta Business Suite:
  Configuracoes do neg. -> Usuarios -> Usuarios do sistema -> "token1"
  -> Adicionar ativos -> Contas do WhatsApp -> marcar a conta -> Controle total

Sem isso, `/me/assigned_whatsapp_business_accounts` devolve lista vazia e
nada aqui funciona -- foi exatamente o que aconteceu no primeiro teste.

CRIAR TEMPLATE NAO ENVIA MENSAGEM PARA NINGUEM. Ele vai para a fila de
aprovacao da Meta (costuma sair em minutos). Enquanto esta PENDING, nao da
para usar; quando vira APPROVED, da.
"""
import argparse
import io
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://graph.facebook.com/v23.0"
AQUI = os.path.dirname(os.path.abspath(__file__))


def token():
    t = os.environ.get("META_TOKEN")
    if not t:
        sys.exit("faltou META_TOKEN no ambiente")
    return t


def waba():
    w = os.environ.get("META_WABA_ID")
    if not w:
        sys.exit("faltou META_WABA_ID no ambiente (veja o cabecalho deste arquivo)")
    return w


def chamar(caminho, corpo=None, metodo=None):
    url = "%s/%s" % (API, caminho)
    dados = json.dumps(corpo).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request(url, data=dados, method=metodo)
    req.add_header("Authorization", "Bearer " + token())
    if dados:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"erro": json.loads(e.read().decode("utf-8", "replace"))}


def ler_templates():
    """O JSON ao lado. As chaves que comecam com _ sao anotacao nossa e nao
    vao para a Meta -- ela recusa campo que nao conhece."""
    bruto = json.load(io.open(os.path.join(AQUI, "templates_nay.json"), encoding="utf-8"))
    return [{k: v for k, v in t.items() if not k.startswith("_")} for t in bruto]


def listar():
    d = chamar("%s/message_templates?limit=100" % waba())
    if "erro" in d:
        print(json.dumps(d, ensure_ascii=False, indent=1))
        return
    print("%d templates na conta:" % len(d.get("data", [])))
    for t in d.get("data", []):
        print("  %-32s %-6s %-10s %s"
              % (t["name"], t["language"], t["status"], t.get("category", "")))


def conferir():
    for t in ler_templates():
        corpo = [c for c in t["components"] if c["type"] == "BODY"][0]
        print("\n--- %s (%s, %s)" % (t["name"], t["category"], t["language"]))
        print(corpo["text"])
        botoes = [c for c in t["components"] if c["type"] == "BUTTONS"]
        if botoes:
            print("   botoes: " + " | ".join(b["text"] for b in botoes[0]["buttons"]))


def criar():
    ja = chamar("%s/message_templates?limit=100" % waba())
    existentes = {t["name"] for t in ja.get("data", [])} if "erro" not in ja else set()

    for t in ler_templates():
        if t["name"] in existentes:
            print("  %-32s ja existe, pulei" % t["name"])
            continue
        d = chamar("%s/message_templates" % waba(), t, "POST")
        if "erro" in d:
            msg = d["erro"].get("error", {})
            print("  %-32s RECUSADO: %s"
                  % (t["name"], msg.get("error_user_msg") or msg.get("message")))
        else:
            print("  %-32s criado: %s (%s)" % (t["name"], d.get("id"), d.get("status")))


def main():
    p = argparse.ArgumentParser(description="Templates da Nay na API oficial")
    p.add_argument("--listar", action="store_true")
    p.add_argument("--conferir", action="store_true")
    p.add_argument("--criar", action="store_true")
    a = p.parse_args()

    if a.conferir:
        conferir()
    elif a.listar:
        listar()
    elif a.criar:
        criar()
    else:
        p.print_help()


if __name__ == "__main__":
    main()
