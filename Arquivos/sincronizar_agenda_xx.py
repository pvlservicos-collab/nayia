#!/usr/bin/env python3
"""
Corretor salvo com "Xx" na agenda do WhatsApp da Nay entra na lista dela.

Tel (22/09/2026): "separa direitinho para responder apenas os corretores, que
sao todos os que estao nos grupos ou estao com xx antes no numero".

A lista de `corretores` ja vinha dos grupos (fonte = 'grupo'). Esta e a
segunda porta: o NOME QUE O TEL SALVOU no celular da Nay. Esse nome nao
chega pelo fluxo -- o no "Filtrar e normalizar" grava `senderName` (o nome
que a propria pessoa usa) e so cai no `chatName` (o da agenda) quando o
primeiro vem vazio. Por isso ele e lido direto da agenda, pela Z-API
(GET /contacts), que devolve o nome salvo de cada contato.

O que faz, toda vez que roda:
  * quem esta salvo com "Xx" na frente -> entra/fica com pode_falar, fonte 'agenda';
  * quem era fonte 'agenda' e perdeu o "Xx" -> perde o pode_falar;
  * quem o Tel marcou com NAO CORRETOR fica de fora, com ou sem "Xx";
  * fonte 'grupo', 'site' e 'tel' nao sao tocadas.

So LE a agenda. Nao manda mensagem para ninguem.

Uso, no servidor (cron de hora em hora):
    python3 sincronizar_agenda_xx.py
"""
import json
import os
import re
import sys
import urllib.request

import psycopg2

PREFIXO = re.compile(r"^\s*xx\b", re.I)


def agenda():
    base = "https://api.z-api.io/instances/%s/token/%s/" % (
        os.environ["ZAPI_INSTANCIA"], os.environ["ZAPI_TOKEN"])
    cab = {"Client-Token": os.environ["ZAPI_CLIENT_TOKEN"]}
    todos, pagina = [], 1
    while pagina <= 60:
        req = urllib.request.Request(base + "contacts?page=%d&pageSize=500" % pagina, headers=cab)
        lote = json.load(urllib.request.urlopen(req, timeout=60))
        if not lote:
            break
        todos += lote
        if len(lote) < 500:
            break
        pagina += 1
    return todos


def main():
    contatos = agenda()
    # Seguranca: agenda vazia quase sempre e a Z-API fora do ar, nao o Tel
    # apagando a agenda inteira. Sem isto, uma falha tirava todo mundo.
    if len(contatos) < 100:
        sys.exit("a agenda veio com %d contatos -- parece falha da Z-API, nao mexo em nada" % len(contatos))

    xx = {}
    for c in contatos:
        nome = str(c.get("name") or "")
        fone = re.sub(r"\D", "", str(c.get("phone") or ""))
        if PREFIXO.match(nome) and len(fone) >= 10:
            xx[fone] = nome.strip()[:120]

    conn = psycopg2.connect(os.environ.get("DATABASE_URL") or os.environ["NAI_DATABASE_URL"])
    conn.autocommit = False
    with conn, conn.cursor() as cur:
        entrou = 0
        for fone, nome in xx.items():
            cur.execute("""
                INSERT INTO corretores (telefone, nome, origem, aprovado, ativo, pode_falar, fonte)
                SELECT %s, %s, 'agenda do WhatsApp da Nay: salvo com Xx', true, true, true, 'agenda'
                 WHERE NOT EXISTS (SELECT 1 FROM corretores k WHERE nai_chave(k.telefone) = nai_chave(%s))
                   AND NOT EXISTS (SELECT 1 FROM nai_corretor_pergunta q
                                    WHERE q.chave = nai_chave(%s) AND q.decisao = 'nao')
            """, (fone, nome, fone, fone))
            entrou += cur.rowcount
            # ja estava na tabela (dos grupos, por exemplo): garante que pode falar,
            # a nao ser que o Tel tenha dito NAO CORRETOR
            cur.execute("""
                UPDATE corretores k SET pode_falar = true, aprovado = true, ativo = true
                 WHERE nai_chave(k.telefone) = nai_chave(%s) AND NOT k.pode_falar
                   AND NOT EXISTS (SELECT 1 FROM nai_corretor_pergunta q
                                    WHERE q.chave = nai_chave(%s) AND q.decisao = 'nao')
            """, (fone, fone))
            entrou += cur.rowcount
        # perdeu o Xx na agenda: sai, mas so quem entrou por aqui
        cur.execute("""
            UPDATE corretores k SET pode_falar = false
             WHERE k.fonte = 'agenda' AND k.pode_falar
               AND NOT (nai_chave(k.telefone) = ANY (SELECT nai_chave(x) FROM unnest(%s::text[]) x))
        """, (list(xx.keys()),))
        saiu = cur.rowcount
    conn.close()
    print("agenda: %d contatos, %d com Xx | entraram ou voltaram: %d | sairam: %d"
          % (len(contatos), len(xx), entrou, saiu))


if __name__ == "__main__":
    main()
