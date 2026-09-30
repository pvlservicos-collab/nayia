#!/usr/bin/env python3
"""Preenche `caracteristicas` e `mobilia` lendo o anuncio do site.

Por que existe (Tel, 13/09/2026): ele perguntou a Nay se o 5718 era mobiliado e
ela subiu a pergunta para ele -- "isso e uma informacao que temos". Temos no
SITE: o anuncio traz "Caracteristicas do Imovel -> Semi-Mobiliado". Na tabela
`imoveis` esse campo esta vazio em metade do catalogo de locacao, porque a
varredura (extrair_pagina.py) nunca leu essa secao.

REGRAS DO PROJETO, seguidas aqui:
  * COMPLEMENTAR: so escreve onde esta vazio. Nunca sobrescreve, nunca apaga.
  * Simulacao por padrao. So grava com --escrever.
  * Pausa entre requisicoes.

Uso:
  python3 preencher_caracteristicas.py                 # simula, locacao no mercado
  python3 preencher_caracteristicas.py --escrever
  python3 preencher_caracteristicas.py --todos         # o catalogo inteiro
  python3 preencher_caracteristicas.py --codigo 5718
"""
import argparse
import os
import re
import sys
import time
import urllib.request

import psycopg2
import psycopg2.extras

URL = "https://imobeasy.com/anuncios/%s"
BLOCO = re.compile(r"Caracter[íi]sticas do Im[óo]vel(.*?)(?:slim-card-title|</body>)", re.S | re.I)
ITEM = re.compile(r'col-md-4[^>]*>\s*([^<>]{2,60}?)\s*<', re.I)


def pagina(codigo):
    req = urllib.request.Request(URL % codigo, headers={"User-Agent": "Mozilla/5.0 (ImobEasy interno)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def caracteristicas_do_anuncio(html):
    m = BLOCO.search(html)
    if not m:
        return []
    vistos, saida = set(), []
    for item in ITEM.findall(m.group(1)):
        t = re.sub(r"\s+", " ", item).strip()
        if not t or t.lower() in vistos or len(t) > 60:
            continue
        if re.match(r"^(r\$|\d+([,.]\d+)?\s*(m2|m²)?$)", t.lower()):
            continue
        vistos.add(t.lower())
        saida.append(t)
    return saida


def mobilia_de(lista):
    junto = " | ".join(lista).lower()
    if re.search(r"semi.?mobiliad", junto):
        return "semi-mobiliado"
    if re.search(r"\bmobiliad", junto):
        return "mobiliado"
    if re.search(r"(sem mobilia|n[ãa]o mobiliad)", junto):
        return "sem mobilia"
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--escrever", action="store_true")
    p.add_argument("--todos", action="store_true")
    p.add_argument("--codigo", type=int)
    p.add_argument("--limite", type=int, default=0)
    a = p.parse_args()

    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        for linha in open("/root/nay-publicador/.env"):
            if linha.startswith("DATABASE_URL="):
                dsn = linha.split("=", 1)[1].strip()
    con = psycopg2.connect(dsn)
    con.autocommit = False
    cur = con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    onde = ["(caracteristicas IS NULL OR array_length(caracteristicas, 1) IS NULL OR coalesce(mobilia, '') = '')",
            "NOT coalesce(e_parceiro, false)"]
    if a.codigo:
        onde.append("codigo = %d" % a.codigo)
    elif not a.todos:
        onde.append("nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)")
        onde.append("coalesce(valor_aluguel, 0) > 0")
    sql = "SELECT codigo, mobilia, caracteristicas FROM imoveis WHERE " + " AND ".join(onde) + " ORDER BY codigo"
    if a.limite:
        sql += " LIMIT %d" % a.limite
    cur.execute(sql)
    linhas = cur.fetchall()
    print("imoveis a olhar: %d%s" % (len(linhas), "" if a.escrever else "  (SIMULACAO -- nada sera gravado)"))

    n_car = n_mob = n_sem = 0
    for i, linha in enumerate(linhas, 1):
        cod = linha["codigo"]
        try:
            lista = caracteristicas_do_anuncio(pagina(cod))
        except Exception as e:
            print("  %s: nao consegui ler o anuncio (%s)" % (cod, e))
            continue
        if not lista:
            n_sem += 1
            continue
        mob = mobilia_de(lista)
        campos, valores = [], []
        if not linha["caracteristicas"]:
            campos.append("caracteristicas = %s")
            valores.append(lista)
            n_car += 1
        if mob and not (linha["mobilia"] or "").strip():
            campos.append("mobilia = %s")
            valores.append(mob)
            n_mob += 1
        if not campos:
            continue
        print("  %s: %s%s" % (cod, ", ".join(lista[:6]), "  ->  mobilia=" + mob if mob else ""))
        if a.escrever:
            cur.execute("UPDATE imoveis SET " + ", ".join(campos) + ", sincronizado_em = now() WHERE codigo = %s",
                        valores + [cod])
        if i % 20 == 0:
            print("  ... %d/%d" % (i, len(linhas)))
            if a.escrever:
                con.commit()
        time.sleep(1.5)

    if a.escrever:
        con.commit()
    print("caracteristicas preenchidas: %d | mobilia preenchida: %d | anuncios sem a secao: %d" % (n_car, n_mob, n_sem))
    if not a.escrever:
        print("nada foi gravado. rode de novo com --escrever para valer.")
    con.close()


if __name__ == "__main__":
    sys.exit(main())
