"""
Prompt 1 do guia: baixa UMA página da listagem pública da Imob Easy e extrai
os dados de cada anúncio. Não escreve em nenhum banco.

Uso:
    .venv/bin/python extrair_pagina.py --ad-type Venda --page 2
"""
import argparse
import re
import sys

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://imobeasy.com/anuncios"
USER_AGENT = "Mozilla/5.0 (compatible; nay-catalogo-sync/0.1)"

CAMPOS = [
    "codigo", "e_parceiro", "condominio", "endereco", "bairro", "complemento",
    "area", "quartos", "suites", "banheiros", "vagas", "valor_venda", "valor_aluguel",
]


def baixar_pagina(ad_type, page, timeout=15):
    resp = requests.get(
        BASE_URL,
        params={"ad_type": ad_type, "page": page},
        headers={"User-Agent": USER_AGENT},
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.text


def _parse_valor(texto):
    if not texto:
        return None
    numero = re.sub(r"[^\d,]", "", texto).replace(",", ".")
    return float(numero) if numero else None


def _texto_coluna(card, rotulo):
    label_span = card.find("span", string=lambda s: s and s.strip() == rotulo)
    if not label_span:
        return None
    col = label_span.find_parent("div", class_="col-3")
    if not col:
        return None
    valor_span = col.find_all("span", class_="d-block")[-1]
    return valor_span.get_text(" ", strip=True)


def _int_coluna(card, rotulo):
    texto = _texto_coluna(card, rotulo)
    if not texto:
        return None
    m = re.search(r"(\d+)", texto)
    return int(m.group(1)) if m else None


def extrair_anuncios(html):
    """Recebe o HTML da listagem e devolve uma lista de dicts, um por anúncio.

    A página traz cada anúncio em dois blocos (grade e lista, este último
    oculto com `d-none`) — usamos só o bloco de grade para não duplicar.
    """
    soup = BeautifulSoup(html, "html.parser")
    cards = soup.select("div.real-estate-item.real-estate-grid")

    anuncios = []
    for card in cards:
        link = card.select_one("a.btn.btn-purple[href^='/imoveis/']")
        codigo = link["href"].rsplit("/", 1)[-1] if link else None

        e_parceiro = card.find(string=lambda s: s and "Imóvel Parceiro" in s) is not None

        header = card.select_one("div.real-estate-header")
        titulo = header.select_one("h5 div.d-inline-flex.flex-fill") if header else None
        condominio = titulo.get_text(strip=True) if titulo else None

        paragrafos = header.find_all("p") if header else []
        endereco = bairro = complemento = None
        if paragrafos:
            primeiro = paragrafos[0].get_text(strip=True)
            if " - " in primeiro:
                endereco, bairro = (p.strip() for p in primeiro.rsplit(" - ", 1))
            else:
                endereco = primeiro
        if len(paragrafos) >= 2:
            complemento = paragrafos[1].get_text(strip=True)

        area = _int_coluna(card, "Área")
        quartos = _int_coluna(card, "Quartos")
        quartos_txt = _texto_coluna(card, "Quartos") or ""
        m_suites = re.search(r"(\d+)\s*su[ií]te", quartos_txt)
        suites = int(m_suites.group(1)) if m_suites else 0
        banheiros = _int_coluna(card, "Banheiros")
        vagas = _int_coluna(card, "Garagem")

        valor_venda = valor_aluguel = None
        for item in card.select("div.row-values p.contact-item"):
            spans = item.find_all("span")
            if len(spans) < 2:
                continue
            rotulo = spans[0].get_text(strip=True)
            valor = _parse_valor(spans[1].get_text(strip=True))
            if rotulo.startswith("Venda"):
                valor_venda = valor
            elif rotulo.startswith("Aluguel"):
                valor_aluguel = valor

        anuncios.append(dict(
            codigo=codigo, e_parceiro=e_parceiro, condominio=condominio,
            endereco=endereco, bairro=bairro, complemento=complemento,
            area=area, quartos=quartos, suites=suites, banheiros=banheiros,
            vagas=vagas, valor_venda=valor_venda, valor_aluguel=valor_aluguel,
        ))
    return anuncios


def _fmt(valor):
    if valor is None:
        return "-"
    if isinstance(valor, float):
        return f"{valor:,.2f}".replace(",", "_").replace(".", ",").replace("_", ".")
    if isinstance(valor, bool):
        return "sim" if valor else "não"
    return str(valor)


def imprimir_tabela(anuncios):
    larguras = {c: max(len(c), *(len(_fmt(a[c])) for a in anuncios)) for c in CAMPOS}
    linha_cab = " | ".join(c.ljust(larguras[c]) for c in CAMPOS)
    print(linha_cab)
    print("-+-".join("-" * larguras[c] for c in CAMPOS))
    for a in anuncios:
        print(" | ".join(_fmt(a[c]).ljust(larguras[c]) for c in CAMPOS))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ad-type", default="Venda", choices=["Venda", "Aluguel"])
    parser.add_argument("--page", type=int, default=2)
    args = parser.parse_args()

    try:
        html = baixar_pagina(args.ad_type, args.page)
    except requests.RequestException as exc:
        print(f"Falha ao baixar a página: {exc}", file=sys.stderr)
        sys.exit(1)

    anuncios = extrair_anuncios(html)
    print(f"ad_type={args.ad_type} page={args.page} -> {len(anuncios)} anúncios encontrados\n")
    imprimir_tabela(anuncios)


if __name__ == "__main__":
    main()
