"""
Doc 28, passo 5: monta o texto da mensagem, por grupo.

Regra do Tel: no grupo restrito ("SÓ TERCEIROS COMPRA, VEN"), a
mensagem sai só com a parte de venda -- a linha de locação nunca
aparece, mesmo que o imóvel tenha aluguel. Nos outros 9 grupos, sai
completa, com venda e locação juntos quando o imóvel tiver os dois.

A função não olha o id do grupo -- olha aceita_venda/aceita_locacao,
os mesmos campos que montar_destinos.py usa para decidir quem recebe o
imóvel. Assim a mesma trava decide "esse grupo recebe?" e "o que
aparece no texto?", sem duas cópias da regra (doc 27, Parte 4.3): se
amanhã existir um segundo grupo restrito (só aluguel, por exemplo),
funciona sem precisar mexer aqui.

Uso:
    .venv/bin/python montar_mensagem.py 5644 --grupos-csv grupos.csv
"""
import argparse

from buscar_imovel import buscar_imovel
from montar_destinos import carregar_grupos_csv


def _fmt_valor(v):
    return f"{v:,.0f}".replace(",", ".")


def _e_via_publica(imovel):
    """Imóvel de rua é o que NÃO tem condomínio.

    POR QUE ASSIM E NÃO POR UMA LISTA DE TIPOS: os tipos vêm em pares
    (`Casa` x `Casa de condomínio`, `Apartamento em Via Pública` x
    `Apartamento`, `Lote` x `Lote em Condomínio`), e uma lista fixa envelhece
    no dia em que o cadastro ganhar um tipo novo. Medido em 02/09 contra 10
    anúncios reais: os quatro sem condomínio eram exatamente os de via pública
    (duas casas, um apartamento em via pública, um prédio) e os seis com
    condomínio eram os de dentro. É o mesmo campo que já decide a primeira
    linha do card."""
    return not (imovel.get("condominio") or "").strip()


def _linha_de_financiamento(imovel):
    """A linha "aceita financiamento", só para imóvel de rua à venda.

    O Tel pediu isto em 02/09: casa de rua muitas vezes não pode ser
    financiada -- documentação pendente, contrato de gaveta -- e sem essa
    linha o corretor leva o cliente e descobre depois. Em condomínio ele já
    parte do princípio de que financia, então lá a linha só faria barulho.

    Valor ausente NÃO vira "não financia": o site não traz o campo em todo
    anúncio, e afirmar que não financia um imóvel que financia derruba
    negócio. Sem o dado, a linha não sai -- mesma disciplina do `area=0`.
    """
    if not _e_via_publica(imovel):
        return None
    bruto = (imovel.get("aceita_financiamento") or "").strip().lower()
    if bruto.startswith("s"):
        return "• aceita financiamento"
    if bruto.startswith("n"):
        return "• não aceita financiamento"
    return None


def montar_mensagem(imovel, grupo):
    condominio = imovel.get("condominio") or imovel.get("tipo") or f"Imóvel {imovel['codigo']}"

    linhas = [f"📍 {condominio}"]
    if imovel.get("bairro"):
        linhas.append(f"• Bairro: {imovel['bairro']}")
    if imovel.get("area"):  # area=0 é dado incompleto -- omite a linha, não mostra "0m2"
        linhas.append(f"• {imovel['area']}m2")
    if imovel.get("quartos") is not None:
        suites = imovel.get("suites") or 0
        sufixo = f" sendo {suites} suíte" if suites else ""
        linhas.append(f"• {imovel['quartos']} quartos{sufixo}")
    if imovel.get("banheiros") is not None:
        linhas.append(f"• {imovel['banheiros']} banheiros")
    if imovel.get("vagas_cobertas"):
        linhas.append(f"• {imovel['vagas_cobertas']} vagas cobertas")
    elif imovel.get("vagas"):
        linhas.append(f"• {imovel['vagas']} vagas")

    if grupo.get("aceita_venda") and imovel.get("valor_venda") is not None:
        linhas.append(f"Venda: R$ {_fmt_valor(imovel['valor_venda'])}")
        financia = _linha_de_financiamento(imovel)
        if financia:
            linhas.append(financia)
    if grupo.get("aceita_locacao") and imovel.get("valor_aluguel") is not None:
        linhas.append(f"Locação: R$ {_fmt_valor(imovel['valor_aluguel'])}")

    linhas.append(f"Código: {imovel['codigo']}")
    return "\n".join(linhas)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("codigo")
    parser.add_argument("--grupos-csv", required=True)
    args = parser.parse_args()

    imovel = buscar_imovel(args.codigo)
    grupos = carregar_grupos_csv(args.grupos_csv)

    for g in grupos:
        print(f"=== {g['nome']} ===")
        print(montar_mensagem(imovel, g))
        print()


if __name__ == "__main__":
    main()
