"""
Prompt 3 do guia: varre todas as páginas de venda e aluguel e grava tudo em
catalogo.json. Não escreve em nenhum banco.

Uso:
    .venv/bin/python varrer_catalogo.py                        # 67 venda + 8 aluguel
    .venv/bin/python varrer_catalogo.py --paginas-venda 3 --paginas-aluguel 2   # teste rápido
"""
import argparse
import json
import random
import time

import requests

from extrair_pagina import baixar_pagina, extrair_anuncios

PAUSA_MIN = 1.0
PAUSA_MAX = 2.0


def varrer(ad_type, num_paginas, pausa_min=PAUSA_MIN, pausa_max=PAUSA_MAX, log=print):
    anuncios = []
    falhas = []
    for page in range(1, num_paginas + 1):
        try:
            html = baixar_pagina(ad_type, page)
        except requests.RequestException as exc:
            log(f"  [FALHA] {ad_type} página {page}: {exc}")
            falhas.append({"ad_type": ad_type, "pagina": page, "erro": str(exc)})
        else:
            encontrados = extrair_anuncios(html)
            for a in encontrados:
                a["ad_type"] = ad_type
                a["pagina"] = page
            anuncios.extend(encontrados)
            log(f"  {ad_type} página {page}/{num_paginas}: {len(encontrados)} anúncios")

        if page < num_paginas:
            time.sleep(random.uniform(pausa_min, pausa_max))
    return anuncios, falhas


def resumo(anuncios, falhas):
    total = len(anuncios)
    parceiros = sum(1 for a in anuncios if a["e_parceiro"])

    codigos_venda = {a["codigo"] for a in anuncios if a["ad_type"] == "Venda"}
    codigos_aluguel = {a["codigo"] for a in anuncios if a["ad_type"] == "Aluguel"}
    repetidos = codigos_venda & codigos_aluguel

    return {
        "total_anuncios": total,
        "total_parceiros": parceiros,
        "codigos_repetidos_venda_aluguel": len(repetidos),
        "lista_codigos_repetidos": sorted(repetidos, key=lambda c: int(c)),
        "paginas_falharam": len(falhas),
        "falhas": falhas,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--paginas-venda", type=int, default=67)
    parser.add_argument("--paginas-aluguel", type=int, default=8)
    parser.add_argument("--saida", default="catalogo.json")
    parser.add_argument("--pausa-min", type=float, default=PAUSA_MIN)
    parser.add_argument("--pausa-max", type=float, default=PAUSA_MAX)
    args = parser.parse_args()

    print(f"Varrendo Venda: {args.paginas_venda} página(s)")
    anuncios_venda, falhas_venda = varrer(
        "Venda", args.paginas_venda, args.pausa_min, args.pausa_max)

    print(f"Varrendo Aluguel: {args.paginas_aluguel} página(s)")
    anuncios_aluguel, falhas_aluguel = varrer(
        "Aluguel", args.paginas_aluguel, args.pausa_min, args.pausa_max)

    anuncios = anuncios_venda + anuncios_aluguel
    falhas = falhas_venda + falhas_aluguel

    with open(args.saida, "w", encoding="utf-8") as f:
        json.dump(anuncios, f, ensure_ascii=False, indent=2)

    r = resumo(anuncios, falhas)
    print(f"\nGravado em {args.saida}\n")
    print(f"Total de anúncios: {r['total_anuncios']}")
    print(f"Total de parceiro: {r['total_parceiros']}")
    print(f"Códigos repetidos entre venda e aluguel: {r['codigos_repetidos_venda_aluguel']}")
    if r["lista_codigos_repetidos"]:
        print(f"  -> {', '.join(r['lista_codigos_repetidos'])}")
    print(f"Páginas que falharam: {r['paginas_falharam']}")
    for falha in r["falhas"]:
        print(f"  -> {falha['ad_type']} página {falha['pagina']}: {falha['erro']}")


if __name__ == "__main__":
    main()
