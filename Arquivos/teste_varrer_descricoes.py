"""
Testa a extração da descrição contra HTML real capturado do site.

O QUE IMPORTA PROVAR: separar o resumo AUTO-GERADO (que o site monta dos
campos da ficha) do texto ESCRITO À MÃO, que é o único que interessa.
Gravar o auto-gerado em `descricao` seria pior do que deixar vazio -- a
Nay passaria a "explicar" o imóvel repetindo o que já está na ficha.

Os HTMLs abaixo são recortes reais de 31/08, dos códigos citados.

Uso:
    .venv/bin/python teste_varrer_descricoes.py
"""
from varrer_descricoes import extrair_descricao

falhas = 0


def checar(rotulo, condicao, detalhe=""):
    global falhas
    ok = bool(condicao)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {rotulo}")
    if not ok and detalhe:
        print(f"         {detalhe}")


def pagina(*blocos, com_rotulos=True):
    """Monta uma página no formato real: campos com <label>, descrição sem."""
    partes = []
    if com_rotulos:
        partes.append(
            '<div class="form-group"><label>Bairro</label>'
            '<span class="form-control">Lago Azul</span></div>'
            '<div class="form-group"><label>Quartos</label>'
            '<span class="form-control">2</span></div>'
        )
    for b in blocos:
        partes.append(f'<div class="form-group"><span class="form-control">{b}</span></div>')
    return "<html><body>" + "".join(partes) + "</body></html>"


AUTO_4098 = "Apartamento localizado no condomínio Flex Parque Dez\r\n- 2 quartos\r\n- 1 banheiro\r\n- 65 m2"
MANUAL_4098 = "100% mobiliado\nAceita pet."
AUTO_1327 = "Casa\r\n- 3 quartos (sendo 2 suítes)\r\n- 3 banheiros\r\n- 124 m2"
MANUAL_1327 = "Linda Casa em Via Pública com Ponto Comercial\nMóveis planejados em uma das suítes"
AUTO_5611 = "Apartamento localizado no condomínio Condomínio Acquarelle\r\n- 3 quarto (sendo 1 suite)\r\n- 3 banheiro\r\n- 88 m2"

print("--- casos reais do site ---")
r = extrair_descricao(pagina(AUTO_4098, MANUAL_4098))
checar("4098 pega o texto escrito à mão", r and "100% mobiliado" in r, f"veio: {r!r}")
checar("4098 traz a informação que faltava",
       r and "100% mobiliado" in r and "Aceita pet" in r)

r = extrair_descricao(pagina(AUTO_1327, MANUAL_1327))
checar("1327 pega o escrito à mão", r and "Ponto Comercial" in r, f"veio: {r!r}")
checar("1327 traz o ponto comercial (a pergunta do Leonan)",
       r and "Ponto Comercial" in r)

r = extrair_descricao(pagina(AUTO_5611))
checar("5611 só tem o auto-gerado -> None", r is None, f"veio: {r!r}")

print()
print("--- o auto-gerado nunca entra ---")
for rotulo, auto in [("apartamento", AUTO_4098), ("casa", AUTO_1327), ("acquarelle", AUTO_5611)]:
    r = extrair_descricao(pagina(auto))
    checar(f"auto-gerado de {rotulo} é descartado", r is None, f"veio: {r!r}")

print()
print("--- campos com rótulo nunca viram descrição ---")
r = extrair_descricao(pagina())
checar("página só com campos rotulados -> None", r is None, f"veio: {r!r}")

print()
print("--- robustez ---")
checar("página vazia não quebra", extrair_descricao("<html></html>") is None)
checar("html sem form-group não quebra", extrair_descricao("<p>oi</p>") is None)

r = extrair_descricao(pagina(AUTO_4098, "  \n  "))
checar("bloco em branco não vira descrição", r is None, f"veio: {r!r}")

r = extrair_descricao(pagina(AUTO_4098, MANUAL_4098, "Aceita financiamento pela Caixa"))
checar("dois blocos manuais são juntados",
       r and "Aceita pet" in r and "Caixa" in r, f"veio: {r!r}")

print()
print("--- a ORDEM não importa (o site pode mudar) ---")
r = extrair_descricao(pagina(MANUAL_4098, AUTO_4098))
checar("manual antes do auto ainda é reconhecido",
       r and "100% mobiliado" in r, f"veio: {r!r}")

print()
print("--- os casos que a SIMULAÇÃO contra o site revelou ---")
print("    (o teste inicial passou e mesmo assim gravaria lixo:")
print("     havia um SEGUNDO formato auto-gerado, em prosa)")

# Formato B: frase gerada em prosa, sem bullets nenhum.
r = extrair_descricao(pagina("Casa com 3 quartos (sendo 1 suite) e 1 banheiro.", com_rotulos=False))
checar("840: eco em prosa vira None", r is None, f"veio: {r!r}")

r = extrair_descricao(pagina(
    "Apartamento, localizado no condomínio Solar da Praia, com 4 quartos (sendo 1 suite) e 0 banheiros.",
    com_rotulos=False))
checar("962: eco em prosa com condomínio vira None", r is None, f"veio: {r!r}")

r = extrair_descricao(pagina("Prédio com 0 quartos e 1 banheiro.", com_rotulos=False))
checar("831: eco com zero quartos vira None", r is None, f"veio: {r!r}")

# O bloco pre-preenchido e EDITAVEL: o Tel acrescenta dentro dele.
# Descartar o bloco inteiro perderia o que so existe ali.
r = extrair_descricao(pagina(
    "com 4 quartos (sendo 3 suites) e 5 banheiros. valor fora a taxa de condomínio",
    "Lindo apartamento no condomínio Castelli. São 3 suítes",
    com_rotulos=False))
checar("887: guarda o que o Tel acrescentou ao bloco gerado",
       r and "valor fora a taxa" in r, f"veio: {r!r}")
checar("887: descarta o eco de quartos e banheiros",
       r and "5 banheiros" not in r, f"veio: {r!r}")

r = extrair_descricao(pagina(
    "Apartamento localizado no condomínio Acquarelle Residencial\n"
    "- 3 quartos (sendo 1 suite)\n- Sala de estar Ampla;\n- Varanda;\n"
    "- Climatizado;\n- 2 banheiros \n- 98 m2",
    "Acquarelle compre um conceito de vida moderno",
    com_rotulos=False))
checar("1125: guarda os bullets escritos à mão",
       r and "Varanda" in r and "Climatizado" in r, f"veio: {r!r}")
checar("1125: descarta os bullets que são eco da ficha",
       r and "3 quartos" not in r and "98 m2" not in r, f"veio: {r!r}")

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
