"""
As características que o Tel marca no admin entram no card (pedido de 14/09).

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * SÓ A SEÇÃO DO IMÓVEL. Logo abaixo, com a MESMA marcação, vem
    "Características do Condomínio" -- e no apartamento 2665 ali estão
    "Piscina", "Hidromassagem" e "Gerador de Energia". Sem cortar no título
    seguinte, o card diria ao corretor que o APARTAMENTO tem piscina;

  * TUDO QUE ESTÁ MARCADO entra, inclusive o que não estava na lista de casa
    ("Varanda Gourmet") -- decisão do Tel;

  * A POSIÇÃO do exemplo dele: depois dos quartos, antes das vagas;

  * NADA DUAS VEZES: Semi-Mobiliado/Mobiliado saem na linha de mobília, e o
    "climatizado" pode vir da página e do banco ao mesmo tempo;

  * A MOBÍLIA DA PÁGINA manda mais que a do banco.

Uso:
    .venv/bin/python teste_caracteristicas_do_card.py
"""
from bs4 import BeautifulSoup

from buscar_imovel import _caracteristicas_do_imovel
from montar_mensagem import montar_mensagem

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


def pagina(imovel, condominio):
    itens = lambda xs: "".join(
        f'<div class="col-md-4 tx-inverse tx-left pd-y-10">\n  {x}\n</div>' for x in xs)
    return f"""
    <div class="card-body">
      <div class="slim-card-title mg-t-20 tx-left">Características do Imóvel</div>
      <hr>
      <div class="row">{itens(imovel)}</div>
      <div class="slim-card-title mg-t-20 tx-left">Características do Condomínio</div>
      <hr>
      <div class="row">{itens(condominio)}</div>
    </div>"""


print("--- a seção do imóvel, e só ela ---")
# O 2665 real: piscina e hidromassagem são do CONDOMÍNIO
s = BeautifulSoup(pagina(
    ["Varanda Gourmet", "Closet", "Apartamento em conceito aberto", "Semi-Mobiliado", "Climatizado"],
    ["Academia", "Hidromassagem", "Piscina", "Gerador de Energia", "Condomínio fechado"]),
    "html.parser")
c = _caracteristicas_do_imovel(s)
checar("lê as do imóvel, na ordem da página", c,
       ["Varanda Gourmet", "Closet", "Apartamento em conceito aberto", "Semi-Mobiliado", "Climatizado"])
checar("piscina do CONDOMÍNIO não entra", "Piscina" in c, False)
checar("hidromassagem do CONDOMÍNIO não entra", "Hidromassagem" in c, False)

s = BeautifulSoup(pagina(["Caixa d'água", "conceito ABERTO", "", "Piscina", "Piscina"], []), "html.parser")
checar("grafia padronizada pela lista do admin, sem vazio e sem repetir",
       _caracteristicas_do_imovel(s), ["Caixa d’água", "Conceito aberto", "Piscina"])
checar("página sem a seção", _caracteristicas_do_imovel(BeautifulSoup("<div></div>", "html.parser")), [])

print()
print("--- o card ---")
BASE = dict(codigo="1885", tipo="Casa de condomínio", condominio="Condomínio Itapuranga III",
            bairro="Ponta Negra", area=550, quartos=4, suites=3, banheiros=4, vagas=6,
            valor_venda=3700000.0, valor_aluguel=15000.0)
GRUPO = {"aceita_venda": True, "aceita_locacao": True}
card = montar_mensagem(dict(BASE, caracteristicas=["Piscina", "Hidromassagem", "Closet",
                                                   "Semi-Mobiliado"],
                            mobilia="semi-mobiliado"), GRUPO).split("\n")
checar("minúsculo, como no exemplo", ["• piscina", "• hidromassagem", "• closet"]
       == [l for l in card if l in ("• piscina", "• hidromassagem", "• closet")], True)
i_quartos = next(i for i, l in enumerate(card) if "quartos" in l)
i_piscina = card.index("• piscina")
i_vagas = next(i for i, l in enumerate(card) if "vagas" in l)
checar("depois dos quartos e antes das vagas", i_quartos < i_piscina < i_vagas, True)
checar("semi-mobiliado uma vez só", card.count("• semi-mobiliado"), 1)

card = montar_mensagem(dict(BASE, caracteristicas=["Climatizado"], mobilia="so ar-condicionado"),
                       GRUPO).split("\n")
checar("climatizado da página e do banco sai uma vez", card.count("• climatizado"), 1)

card = montar_mensagem(dict(BASE), GRUPO)
checar("sem características, o card de sempre", "• piscina" in card, False)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DAS CARACTERÍSTICAS DO CARD PASSARAM")
