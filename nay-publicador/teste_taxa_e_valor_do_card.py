"""
A taxa de condomínio no card, e a trava do valor impossível.

OS DOIS PEDIDOS VIERAM NA MESMA MENSAGEM (Tel, 03/10/2026). Ele colou o card do
9013 do jeito que quer:

    📍 Thiago de Mello
    •  Bairro: Dom Pedro
    •  70m2
    •  2 quartos sendo 1 suíte
    •  2 banheiros
    •  1 vaga coberta
    •  poente
    • taxa de condomínio 1092,10
    • Venda: R$ 690.000
    •  aceita financiamento
    Código: 9013

e escreveu: "acrescentando também a taxa de condomínio quando tem, lembrando que
você coloca a taxa de condomínio somente dos imóveis tem 45 dias em diante a
taxa atualizada no site".

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * a taxa entra NA POSIÇÃO DELE -- depois do sol/mobília e antes dos valores.
    Card é o que o corretor lê em 19 grupos; ordem trocada ele nota na hora;

  * o card NÃO DECIDE nada sobre validade. A linha vem pronta do banco
    (`nay_linha_da_taxa`), porque `nai_card_do_banco` monta ESTE MESMO card em
    SQL -- duas cópias da regra divergem na primeira edição, e é o padrão 4.3
    do HISTORICO. Se alguém reescrever a decisão aqui, este teste cai;

  * taxa sem linha NÃO VIRA LINHA EM BRANCO. É o estado de 124 dos 149 imóveis
    no mercado com taxa (o import da planilha de 26/09);

  * VALOR IMPOSSÍVEL NÃO POSTA. O 9013 está cadastrado com `valor_venda = 690`
    e o card dele sairia "Venda: R$ 690" em 19 grupos. Medido em 03/10: são
    TRÊS imóveis assim (9008, 9010, 9013), todos postáveis agora, todos do
    cadastro novo. Postagem não desfaz.

Uso:
    .venv/bin/python teste_taxa_e_valor_do_card.py
"""
from buscar_imovel import valor_implausivel
from montar_mensagem import montar_mensagem

# O grupo que aceita os dois negócios, a mesma convenção do
# `teste_montar_mensagem.py` -- aqui se prova o card, não a regra de grupo.
GRUPO_COMUM = {"aceita_venda": True, "aceita_locacao": True}

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}")
        print(f"         veio     {obtido!r}")


# O 9013 como ele está no banco hoje, com a venda já corrigida para o valor que
# o Tel escreveu -- aqui se prova o FORMATO, e o 690 tem teste próprio embaixo.
NOVE_MIL_E_TREZE = {
    "codigo": "9013", "tipo": "Apartamento", "condominio": "Thiago de Mello",
    "bairro": "Dom Pedro", "area": 70, "area_e_construida": False,
    "quartos": 2, "suites": 1, "banheiros": 2,
    "vagas": None, "vagas_cobertas": 1, "sol": "Poente", "mobilia": None,
    "caracteristicas": [], "lances_de_escada": None, "observacao": None,
    "valor_venda": 690000.0, "valor_aluguel": None,
    "aceita_financiamento": "Sim", "incluso_no_aluguel": None,
    "taxa_condominio": 1092.10,
    "linha_da_taxa": "• taxa de condomínio 1092,10",
}

print("--- o card que ele pediu, linha por linha ---")
card = montar_mensagem(NOVE_MIL_E_TREZE, GRUPO_COMUM)
checar("é exatamente o card do pedido dele", card, "\n".join([
    "📍 Thiago de Mello",
    "• Bairro: Dom Pedro",
    "• 70m2",
    "• 2 quartos sendo 1 suíte",
    "• 2 banheiros",
    "• 1 vaga coberta",
    "• poente",
    "• taxa de condomínio 1092,10",
    "Venda: R$ 690.000",
    "• aceita financiamento",
    "Código: 9013",
]))

print()
print("--- a POSIÇÃO: depois do sol, antes dos valores ---")
linhas = card.split("\n")
checar("a taxa vem depois de 'poente'",
       linhas.index("• taxa de condomínio 1092,10") > linhas.index("• poente"), True)
checar("e antes da venda",
       linhas.index("• taxa de condomínio 1092,10") < linhas.index("Venda: R$ 690.000"), True)

print()
print("--- sem linha pronta, nenhuma linha sai ---")
# É o estado das 124 taxas do import: o número existe, a data não, e o banco
# devolve NULL. O card não pode inventar a linha a partir do número cru.
sem = dict(NOVE_MIL_E_TREZE, linha_da_taxa=None)
card_sem = montar_mensagem(sem, GRUPO_COMUM)
checar("nenhuma menção a taxa", "taxa de condomínio" in card_sem, False)
checar("e nenhuma linha vazia sobrando", "\n\n" in card_sem, False)
checar("o resto do card continua igual",
       card_sem, card.replace("• taxa de condomínio 1092,10\n", ""))

print()
print("--- o card não decide validade: ele imprime o que vem do banco ---")
# Se alguém reescrever a regra aqui, o número cru voltaria a mandar -- e taxa de
# dois anos atrás voltaria ao grupo sem nada falhar.
so_o_numero = dict(NOVE_MIL_E_TREZE, linha_da_taxa=None, taxa_condominio=1092.10)
checar("taxa_condominio cru NÃO vira linha",
       "taxa de condomínio" in montar_mensagem(so_o_numero, GRUPO_COMUM), False)
# E o contrário: a linha pronta manda, mesmo sem o número cru ao lado.
so_a_linha = dict(NOVE_MIL_E_TREZE, taxa_condominio=None)
checar("a linha pronta manda sozinha",
       "• taxa de condomínio 1092,10" in montar_mensagem(so_a_linha, GRUPO_COMUM),
       True)

print()
print("--- a chave ausente não derruba o card ---")
# `_complementar_do_banco` falha em silêncio quando o banco não responde, e aí
# a chave nem existe no dicionário. O card tem que sair sem a taxa, não quebrar.
sem_chave = {k: v for k, v in NOVE_MIL_E_TREZE.items() if k != "linha_da_taxa"}
checar("card sai sem a taxa",
       "taxa de condomínio" in montar_mensagem(sem_chave, GRUPO_COMUM), False)

print()
print("--- VALOR IMPOSSÍVEL: os três do catálogo de hoje ---")
# Medido em 03/10, e os três estão postáveis: 9008=900, 9010=590, 9013=690.
for codigo, venda in (("9008", 900), ("9010", 590), ("9013", 690)):
    motivo = valor_implausivel({"valor_venda": float(venda)})
    checar(f"o {codigo} (venda {venda}) é recusado", bool(motivo), True)
    checar(f"  e a recusa diz o número do cadastro",
           f"R$ {venda}" in (motivo or ""), True)
    checar(f"  e diz qual seria o certo",
           f"R$ {venda}.000" in (motivo or ""), True)

print()
print("--- e o que é legítimo passa ---")
# O piso é medido: a menor venda legítima do catálogo no mercado é 80.000.
for titulo, imovel in (
        ("a menor venda legítima do catálogo (80.000)", {"valor_venda": 80000.0}),
        ("o 9013 corrigido (690.000)", {"valor_venda": 690000.0}),
        ("aluguel normal (2.500)", {"valor_aluguel": 2500.0}),
        ("imóvel só de aluguel (venda ausente)", {"valor_aluguel": 5000.0}),
        ("imóvel só de venda (aluguel ausente)", {"valor_venda": 450000.0}),
        ("venda zero não é venda baixa", {"valor_venda": 0}),
        ("aluguel zero não é aluguel baixo", {"valor_aluguel": 0}),
        ("dicionário vazio", {}),
):
    checar(titulo, valor_implausivel(imovel), None)
checar("None não levanta", valor_implausivel(None), None)

print()
print("--- aluguel impossível também trava ---")
# Nenhum caso no catálogo hoje, e a trava existe porque o MESMO cadastro novo
# que errou três vendas vai cadastrar aluguel amanhã.
checar("aluguel de 2,50 é recusado",
       bool(valor_implausivel({"valor_aluguel": 2.5})), True)
checar("e a recusa não escreve bobagem com centavos",
       "R$ 2,50" in valor_implausivel({"valor_aluguel": 2.5}), True)
checar("venda com centavos não ganha o palpite de milhares",
       ".000" in (valor_implausivel({"valor_venda": 2.5}) or ""), False)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA TAXA E DO VALOR DO CARD PASSARAM")
