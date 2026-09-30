"""
Prompt 4 do guia: compara catalogo.json (varredura do site) com uma
exportação CSV da tabela `imoveis`. Só produz relatório — não escreve
em nenhum lugar.

O banco está no servidor, não nesta máquina. Gere o CSV no servidor com:

  docker exec nay-postgres psql -U nay -d naydb -c "COPY (
    SELECT codigo, condominio_nome, bairro, valor_venda, valor_aluguel,
           e_parceiro, publicado_no_site, disponivel
    FROM imoveis ORDER BY codigo
  ) TO STDOUT WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')" > /root/imoveis_export.csv

Traga esse arquivo para esta máquina e rode:

  .venv/bin/python comparar_catalogo.py --banco-csv imoveis_export.csv
"""
import argparse
import csv
import json

CAMPOS_CONSISTENCIA = [
    "condominio", "bairro", "endereco", "area", "quartos", "suites",
    "banheiros", "vagas", "valor_venda", "valor_aluguel", "e_parceiro",
]


def _bool_csv(valor):
    if valor is None:
        return None
    v = str(valor).strip().lower()
    if v == "":
        return None
    return v in ("t", "true", "1")


def _num_csv(valor):
    if valor is None or str(valor).strip() == "":
        return None
    return float(valor)


def carregar_site(caminho_json):
    with open(caminho_json, encoding="utf-8") as f:
        anuncios = json.load(f)

    por_codigo = {}
    for a in anuncios:
        codigo = a["codigo"]
        anterior = por_codigo.get(codigo)
        if anterior is None:
            por_codigo[codigo] = a
            continue
        # o mesmo código pode aparecer na listagem de venda e na de aluguel;
        # confere que os dois cartões concordam antes de descartar a segunda
        # ocorrência (se não concordarem, o site está inconsistente e é
        # melhor parar do que decidir qual valor usar em silêncio)
        for campo in CAMPOS_CONSISTENCIA:
            if anterior[campo] != a[campo]:
                raise ValueError(
                    f"código {codigo} tem campo '{campo}' divergente entre "
                    f"a listagem de venda e a de aluguel: "
                    f"{anterior[campo]!r} vs {a[campo]!r}"
                )
    return por_codigo


def carregar_banco(caminho_csv):
    por_codigo = {}
    with open(caminho_csv, encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            codigo = linha["codigo"]
            por_codigo[codigo] = {
                "condominio": linha.get("condominio_nome"),
                "bairro": linha.get("bairro"),
                "valor_venda": _num_csv(linha.get("valor_venda")),
                "valor_aluguel": _num_csv(linha.get("valor_aluguel")),
                "e_parceiro": _bool_csv(linha.get("e_parceiro")),
                "publicado_no_site": _bool_csv(linha.get("publicado_no_site")),
                "disponivel": _bool_csv(linha.get("disponivel")),
            }
    return por_codigo


def comparar(site, banco):
    codigos_site = set(site)
    codigos_banco = set(banco)
    em_ambos = codigos_site & codigos_banco

    desvios = []
    parceiro_diferente = []
    for codigo in em_ambos:
        s, b = site[codigo], banco[codigo]
        dv = abs((s["valor_venda"] or 0) - (b["valor_venda"] or 0))
        da = abs((s["valor_aluguel"] or 0) - (b["valor_aluguel"] or 0))
        maior = max(dv, da)
        if maior > 0:
            desvios.append({
                "codigo": codigo,
                "condominio": s["condominio"],
                "valor_venda_site": s["valor_venda"], "valor_venda_banco": b["valor_venda"],
                "valor_aluguel_site": s["valor_aluguel"], "valor_aluguel_banco": b["valor_aluguel"],
                "desvio": maior,
            })
        if s["e_parceiro"] != b["e_parceiro"]:
            parceiro_diferente.append(codigo)

    desvios.sort(key=lambda d: d["desvio"], reverse=True)

    return {
        "total_site": len(codigos_site),
        "total_banco": len(codigos_banco),
        "em_ambos": len(em_ambos),
        "so_no_site": sorted(codigos_site - codigos_banco, key=int),
        "so_no_banco": sorted(codigos_banco - codigos_site, key=int),
        "desvios": desvios,
        "parceiro_diferente": sorted(parceiro_diferente, key=int),
    }


def imprimir_relatorio(r):
    print(f"Códigos no site (catalogo.json): {r['total_site']}")
    print(f"Códigos no banco (CSV): {r['total_banco']}")
    print()
    print(f"Códigos do site que existem no banco: {r['em_ambos']}")
    print(f"Códigos do site que NÃO existem no banco (novos desde 10/08): {len(r['so_no_site'])}")
    if r["so_no_site"]:
        amostra = ", ".join(r["so_no_site"][:30])
        sufixo = " ..." if len(r["so_no_site"]) > 30 else ""
        print(f"  -> {amostra}{sufixo}")
    print(f"Códigos do banco que não aparecem no site (disponível sem anúncio): {len(r['so_no_banco'])}")
    print()
    print(f"Com valor diferente entre site e banco: {len(r['desvios'])}")
    print(f"Com e_parceiro diferente entre site e banco: {len(r['parceiro_diferente'])}")
    if r["parceiro_diferente"]:
        amostra = ", ".join(r["parceiro_diferente"][:30])
        sufixo = " ..." if len(r["parceiro_diferente"]) > 30 else ""
        print(f"  -> {amostra}{sufixo}")

    if r["desvios"]:
        print(f"\n{min(20, len(r['desvios']))} maiores desvios de valor:")
        for d in r["desvios"][:20]:
            print(
                f"  {d['codigo']} ({d['condominio']}): "
                f"venda site={d['valor_venda_site']} banco={d['valor_venda_banco']} | "
                f"aluguel site={d['valor_aluguel_site']} banco={d['valor_aluguel_banco']} | "
                f"desvio=R$ {d['desvio']:,.2f}"
            )


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--catalogo", default="catalogo.json")
    parser.add_argument("--banco-csv", required=True)
    args = parser.parse_args()

    site = carregar_site(args.catalogo)
    banco = carregar_banco(args.banco_csv)
    imprimir_relatorio(comparar(site, banco))


if __name__ == "__main__":
    main()
