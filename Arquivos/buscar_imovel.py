"""
Doc 28, passo 3: busca um imóvel direto na página do anúncio individual
(imobeasy.com/anuncios/<codigo>), não na listagem.

Usado pelo publicador de grupos porque um imóvel captado hoje ainda não
está na cópia sincronizada do banco (naydb) -- só no site tem a versão
atual. Reaproveita USER_AGENT e _parse_valor de extrair_pagina.py.

Uso:
    .venv/bin/python buscar_imovel.py 5643
"""
import re
import sys

import requests
from bs4 import BeautifulSoup

from extrair_pagina import USER_AGENT, _parse_valor

BASE_URL = "https://imobeasy.com/anuncios"


def baixar_anuncio(codigo, timeout=15):
    resp = requests.get(
        f"{BASE_URL}/{codigo}",
        headers={"User-Agent": USER_AGENT},
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.text


def _campo(soup, rotulo):
    label = soup.find(
        "label", class_="form-control-label",
        string=lambda s: s and s.strip() == rotulo,
    )
    if not label:
        return None
    span = label.find_next_sibling("span", class_="form-control")
    return span.get_text(" ", strip=True) if span else None


def _campo_int(soup, rotulo):
    texto = _campo(soup, rotulo)
    if not texto:
        return None
    m = re.search(r"(\d+)", texto)
    return int(m.group(1)) if m else None


def _tipo(soup):
    # O h5 do topo traz "{tipo} / {tipo} - {condominio ou bairro}" -- só
    # o tipo interessa aqui, o resto já vem de outros campos.
    h5 = soup.find("h5", class_="mg-b-0 tx-black")
    if not h5:
        return None
    texto = h5.get_text(strip=True)
    return texto.split("/")[0].strip() or None


def _id_da_imagem(url):
    """O trecho estavel da URL: '000/118/179'. A galeria serve 'huge' e o
    og:image serve 'medium', entao comparar a URL inteira nunca casa."""
    m = re.search(r"/images/(\d+/\d+/\d+)/", url or "")
    return m.group(1) if m else None


def _capa_primeiro(soup, fotos):
    """Poe a foto de CAPA na frente, sem perder nem duplicar nenhuma.

    A capa e a que o site usa em `og:image` -- a mesma que o Tel escolhe no
    admin. Ate 31/08 mandavamos a primeira da galeria, e ele viu um imovel
    sair no grupo com a foto errada. Medido: em 4 de 5 imoveis a capa NAO
    era a primeira.

    Se o og:image nao existir ou nao casar com nenhuma foto, devolve a
    lista como veio -- nunca deixa o imovel sem foto por causa disto.
    """
    if not fotos:
        return fotos
    og = soup.find("meta", property="og:image")
    alvo = _id_da_imagem(og.get("content") if og else None)
    if not alvo:
        return fotos
    for i, url in enumerate(fotos):
        if _id_da_imagem(url) == alvo:
            if i == 0:
                return fotos
            return [fotos[i]] + fotos[:i] + fotos[i + 1:]
    return fotos


def extrair_imovel(html, codigo):
    soup = BeautifulSoup(html, "html.parser")

    tipo = _tipo(soup)
    condominio = _campo(soup, "Condomínio")
    bairro = _campo(soup, "Bairro")

    # Apartamentos têm um único rótulo "Área"; casas separam "Tamanho do
    # Terreno" (lote) de "Área Construída" -- a segunda é a equivalente a
    # area_util e é a que interessa aqui.
    area_txt = _campo(soup, "Área Construída") or _campo(soup, "Área")
    area = None
    if area_txt:
        m = re.search(r"([\d.]+)", area_txt)
        area = int(float(m.group(1))) if m else None

    quartos_txt = _campo(soup, "Quartos")
    quartos = suites = None
    if quartos_txt:
        m = re.search(r"(\d+)", quartos_txt)
        quartos = int(m.group(1)) if m else None
        m_suites = re.search(r"(\d+)\s*su[ií]te", quartos_txt)
        suites = int(m_suites.group(1)) if m_suites else 0

    banheiros = _campo_int(soup, "Banheiros")
    vagas_cobertas = _campo_int(soup, "Vagas Cobertas")
    # Quando os dois rótulos aparecem juntos, "Vagas" é só a parcela
    # descoberta, não o total -- confirmado contra o texto livre de
    # observações do código 5615 ("4 vagas amplas sendo 2 cobertas" com
    # Vagas=2 e Vagas Cobertas=2 na página). O total é a soma dos dois;
    # quando só um dos rótulos existe, o outro entra como 0 e a soma dá
    # o valor certo de qualquer jeito.
    vagas_descobertas = _campo_int(soup, "Vagas")
    vagas = None
    if vagas_descobertas is not None or vagas_cobertas is not None:
        vagas = (vagas_descobertas or 0) + (vagas_cobertas or 0)

    # A seção "Informações de Valores" fica comentada no HTML visível da
    # página; os valores só aparecem em <meta name="description">, no
    # formato "R$ X (aluguel) / R$ Y (venda)" quando o imóvel tem os dois.
    valor_venda = valor_aluguel = None
    meta = soup.find("meta", attrs={"name": "description"})
    if meta and meta.get("content"):
        for valor_txt, rotulo_valor in re.findall(
            r"R\$\s*([\d.,]+)\s*\((venda|aluguel)\)", meta["content"]
        ):
            valor = _parse_valor("R$ " + valor_txt)
            if rotulo_valor == "venda":
                valor_venda = valor
            else:
                valor_aluguel = valor

    fotos = [
        (a["href"] if a["href"].startswith("http") else "https://imobeasy.com" + a["href"])
        for a in soup.select("ul#imagens a.gallery-item[href]")
    ]
    fotos = _capa_primeiro(soup, fotos)

    # ACEITA FINANCIAMENTO. O Tel pediu isto no card do disparo (02/09) para o
    # imóvel em VIA PÚBLICA à venda: casa de rua muitas vezes não pode ser
    # financiada -- documentação, contrato de gaveta -- e o corretor descobre
    # isso depois de já ter levado o cliente.
    #
    # O site responde "Sim"/"Não" e às vezes não traz o campo (o 2943 é um
    # desses). Ausente fica None e a linha simplesmente não sai: dizer "não
    # financia" de um imóvel que financia é pior que não dizer nada.
    aceita_financiamento = _campo(soup, "Aceita Financiamento?")

    return dict(
        codigo=str(codigo),
        tipo=tipo,
        aceita_financiamento=aceita_financiamento,
        condominio=condominio,
        bairro=bairro,
        area=area,
        quartos=quartos,
        suites=suites,
        banheiros=banheiros,
        vagas=vagas,
        vagas_cobertas=vagas_cobertas,
        valor_venda=valor_venda,
        valor_aluguel=valor_aluguel,
        fotos=fotos,
    )


def buscar_imovel(codigo):
    html = baixar_anuncio(codigo)
    return extrair_imovel(html, codigo)


def main():
    if len(sys.argv) != 2:
        print("Uso: buscar_imovel.py <codigo>", file=sys.stderr)
        sys.exit(1)

    codigo = sys.argv[1]
    try:
        imovel = buscar_imovel(codigo)
    except requests.RequestException as exc:
        print(f"Falha ao baixar o anúncio {codigo}: {exc}", file=sys.stderr)
        sys.exit(1)

    for chave, valor in imovel.items():
        if chave == "fotos":
            print(f"fotos ({len(valor)}):")
            for url in valor:
                print(f"  {url}")
        else:
            print(f"{chave}: {valor}")


if __name__ == "__main__":
    main()
