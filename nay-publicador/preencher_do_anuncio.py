#!/usr/bin/env python3
"""Preenche, a partir do ANÚNCIO do site, o que está vazio na tabela `imoveis`.

Por que existe (Tel, 13 e 14/09/2026): ele perguntou "é mobiliado?" e depois
"tem garagem?" e a Nay subiu as duas para ele -- "isso é informação que temos".
Temos no SITE: o anúncio individual traz Quartos, Suítes, Banheiros, Vagas,
Sol, Andar, Taxa de Condomínio, IPTU, Incluso no Aluguel e Características.
Metade do catálogo de locação estava sem esses campos, porque a varredura lê a
LISTAGEM (onde "Área" e "Garagem" são ambíguos) e nunca leu a página do anúncio.

REGRAS DO PROJETO, seguidas aqui:
  * COMPLEMENTAR: só escreve onde está vazio. Nunca sobrescreve, nunca apaga.
  * Simulação por padrão. Só grava com --escrever.
  * Pausa entre requisições, para não martelar o site.

Uso:
  python3 preencher_do_anuncio.py                 # simula (locação no mercado)
  python3 preencher_do_anuncio.py --escrever
  python3 preencher_do_anuncio.py --codigo 4159
  python3 preencher_do_anuncio.py --todos         # o catálogo inteiro
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
PAR = re.compile(r'form-control-label"[^>]*>\s*([^<]{2,40}?)\s*</label>.*?form-control"[^>]*>\s*([^<]{1,120}?)\s*</',
                 re.S | re.I)
BLOCO_CAR = re.compile(r"Caracter[íi]sticas do Im[óo]vel(.*?)(?:slim-card-title|</body>)", re.S | re.I)
ITEM_CAR = re.compile(r'col-md-4[^>]*>\s*([^<>]{2,60}?)\s*<', re.I)


def pagina(codigo):
    req = urllib.request.Request(URL % codigo, headers={"User-Agent": "Mozilla/5.0 (ImobEasy interno)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def campos_do_anuncio(html):
    """label -> valor, na ordem; a primeira ocorrência vence (a página repete
    alguns campos em blocos de resumo)."""
    out = {}
    for rotulo, valor in PAR.findall(html):
        chave = re.sub(r"\s+", " ", rotulo).strip().lower()
        v = re.sub(r"\s+", " ", valor).strip()
        if chave and v and chave not in out:
            out[chave] = v
    return out


def caracteristicas(html):
    m = BLOCO_CAR.search(html)
    if not m:
        return []
    vistos, saida = set(), []
    for item in ITEM_CAR.findall(m.group(1)):
        t = re.sub(r"\s+", " ", item).strip()
        if not t or t.lower() in vistos or len(t) > 60:
            continue
        if re.match(r"^(r\$|\d+([,.]\d+)?\s*(m2|m²)?$)", t.lower()):
            continue
        vistos.add(t.lower())
        saida.append(t)
    return saida


def inteiro(v):
    d = re.sub(r"[^0-9]", "", v or "")
    if not d:
        return None
    n = int(d)
    return n if 0 <= n <= 60 else None      # contagem alta é número de sala, não contagem


def dinheiro(v):
    t = re.sub(r"[^0-9,.]", "", v or "").replace(".", "").replace(",", ".")
    try:
        n = float(t)
    except ValueError:
        return None
    return n if 0 < n < 1000000 else None


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
    cur = con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    onde = ["NOT coalesce(e_parceiro, false)"]
    if a.codigo:
        onde.append("codigo = %d" % a.codigo)
    elif not a.todos:
        onde.append("nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)")
        onde.append("coalesce(valor_aluguel, 0) > 0")
    sql = ("SELECT codigo, quartos, suites, banheiros, vagas, sol, andar, taxa_condominio, iptu, mobilia, vagas_cobertas, "
           "caracteristicas, extras FROM imoveis WHERE " + " AND ".join(onde) + " ORDER BY codigo")
    if a.limite:
        sql += " LIMIT %d" % a.limite
    cur.execute(sql)
    linhas = cur.fetchall()
    print("imóveis a olhar: %d%s" % (len(linhas), "" if a.escrever else "   (SIMULAÇÃO -- nada será gravado)"))

    conta = {}
    for i, l in enumerate(linhas, 1):
        cod = l["codigo"]
        try:
            html = pagina(cod)
        except Exception as e:
            print("  %s: não consegui ler o anúncio (%s)" % (cod, e))
            continue
        c = campos_do_anuncio(html)
        car = caracteristicas(html)
        campos, valores, mostra = [], [], []

        def poe(coluna, valor, rotulo):
            if valor is None:
                return
            campos.append(coluna + " = %s")
            valores.append(valor)
            mostra.append("%s=%s" % (rotulo, valor))
            conta[coluna] = conta.get(coluna, 0) + 1

        if not l["quartos"]:
            poe("quartos", inteiro(c.get("quartos")), "quartos")
        if not l["suites"]:
            poe("suites", inteiro(c.get("suítes") or c.get("suites")), "suítes")
        if not l["banheiros"]:
            poe("banheiros", inteiro(c.get("banheiros")), "banheiros")
        # VAGAS É CORRIGIDO, não só preenchido (Tel, 29/09).
        #
        # O CASO: a Nay disse a um corretor "tem 2 vagas de garagem" sobre o
        # 5739 (Life Parque Dez) e ele respondeu "tá dizendo aí só 1". O CARD
        # estava certo -- lê a página ao vivo; a resposta veio da TABELA, que
        # guardava 2 desde a importação de agosto. O anúncio diz 1.
        #
        # É O QUARTO CAMPO com o mesmo defeito em dois dias (mobília, lances de
        # escada, fotos, vagas): `preencher se estiver vazio` resolve o
        # primeiro dia e apodrece no segundo mês. Aqui a página já foi baixada
        # -- corrigir não custa requisição nenhuma.
        #
        # MEDIDO antes de mexer: em 15 imóveis sorteados, quartos, suítes e
        # banheiros batiam em TODOS; só `vagas` divergia, e num só. A página
        # traz os dois campos separados ("Vagas" e "Vagas Cobertas") e o banco
        # guarda igual -- o 2973 e o 2947 batem certo. Não há total a somar.
        _vagas_da_pagina = inteiro(c.get("vagas"))
        if _vagas_da_pagina is not None and _vagas_da_pagina != l["vagas"]:
            poe("vagas", _vagas_da_pagina, "vagas")
        _cobertas = inteiro(c.get("vagas cobertas"))
        if _cobertas is not None and _cobertas != l["vagas_cobertas"]:
            poe("vagas_cobertas", _cobertas, "vagas_cobertas")
        if not (l["sol"] or "").strip():
            poe("sol", (c.get("sol") or None), "sol")
        if not (l["andar"] or "").strip():
            v = c.get("andar")
            poe("andar", v if v and v.lower() not in ("não especificado", "nao especificado", "-") else None, "andar")
        if l["taxa_condominio"] is None:
            poe("taxa_condominio", dinheiro(c.get("taxa de condomínio")), "taxa_cond")
        if l["iptu"] is None:
            poe("iptu", dinheiro(c.get("iptu")), "iptu")
        if not l["caracteristicas"] and car:
            poe("caracteristicas", car, "características")
        if not (l["mobilia"] or "").strip() and car:
            poe("mobilia", mobilia_de(car), "mobília")

        # LANCES DE ESCADA (Tel, 28/09): "todo imóvel que for escada, sempre na
        # descrição coloque quantos lances de escada, caso tenha na descrição
        # do imóvel". O CARD já mostra -- ele lê a página AO VIVO --, mas a
        # tabela não guardava, e é dela que sai o card quando o site não
        # responde. Medido em 28/09: 8 imóveis no mercado têm o dado.
        #
        # ZERO É RESPOSTA, não ausência: quer dizer "não tem escada", e o card
        # já sabe não imprimir linha nenhuma nesse caso. Guardar o zero evita
        # rebaixar a página toda hora para reaprender que não tem.
        esc = c.get("lances de escada")
        if esc is not None and str(esc).strip().isdigit() \
                and not ((l["extras"] or {}).get("lances de escada") or "").strip():
            campos.append("extras = coalesce(extras, '{}'::jsonb) || "
                          "jsonb_build_object('lances de escada', %s::text)")
            valores.append(str(esc).strip())
            mostra.append("escada=%s" % esc)
            conta["lances de escada"] = conta.get("lances de escada", 0) + 1

        inc = c.get("incluso no aluguel")
        if inc and not ((l["extras"] or {}).get("incluso no aluguel") or "").strip():
            campos.append("extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('incluso no aluguel', %s::text)")
            valores.append(inc)
            mostra.append("incluso=%s" % inc)
            conta["incluso no aluguel"] = conta.get("incluso no aluguel", 0) + 1

        if campos:
            print("  %s: %s" % (cod, ", ".join(mostra)))
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
    print("preenchido: " + (", ".join("%s %d" % (k, v) for k, v in sorted(conta.items())) or "nada"))
    if not a.escrever:
        print("nada foi gravado. rode com --escrever para valer.")
    con.close()


if __name__ == "__main__":
    sys.exit(main())
