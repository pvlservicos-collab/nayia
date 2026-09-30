"""
Testa o envio para corretor pedido em linguagem natural (Tel, 14/09).

POR QUE EXISTE: ele pediu "esse mesmo comando que eu estou te passando aqui
para enviar imóveis para corretor, coloca na Nay". Os três que ele tinha
passado entram aqui literalmente.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * VALOR NÃO É CÓDIGO. "até 4.200" era lido como os códigos 4 e 200 -- que não
    existem -- e o site devolve página vazia que o envio aceitava. A Flávia
    receberia dois cards "📍 Imóvel 4";

  * O TELEFONE É O DESTINO onde quer que esteja. "para Ana 92 9396-5797 os
    imóveis que ela está pedindo" põe o telefone no MEIO, e a preposição
    seguinte ("para ela") virava destinatário;

  * VALOR SOLTO É VALOR EXATO. "Grand Prix / 2 quartos sendo 1 suíte / 3.5k"
    não pode mandar o Grand Prix de R$ 4.000 -- foi o que ficou de fora de
    propósito no pedido da Waldyrene;

  * SÓ CATEGORIA NÃO BASTA. "a casa do morada do passaro" com o nome errado a
    ponto de não casar não pode virar "todas as casas";

  * CARD VAZIO NÃO SAI: página que não existe é "não achei";

  * CADASTRA SÓ QUEM JÁ CONVERSOU, e nunca reativa quem foi desativado;

  * TETO POR LEVA: centenas de imóveis não saem de uma vez.

A resolução contra o catálogo (SQL) é provada de ponta a ponta no servidor com
as três mensagens reais; aqui fica o que não precisa de banco.

Uso:
    .venv/bin/python teste_pedido_de_imoveis.py
"""
import publicador
from interpretar_comando import (_codigos_do_pedido, _separar_destino_por_telefone,
                                 interpretar_comando as ic)
from montar_destinos import e_comercial, e_residencial
from pedido_de_imoveis import (casar_bairros, casar_condominios,
                               condominios_parecidos,
                               desempatar_condominio_e_bairro,
                               e_titulo_ou_recado, ler_pedido,
                                _resumo_do_pedido)

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


WALDYRENE = """envia para o número da corretora parceira Waldyrene 92 9307-2954 os imóveis que ela pediu
ela pediu os imóveis abaixo:

✅ APARTAMENTOS DISPONÍVEIS PARA
Estilo Golf / 2 quartos sendo 1 suíte / 2.6k
Grand Prix / 2 quartos sendo 1 suíte / 3.5k"""
FLAVIA = ("envia toda as casas que temos para locação até 4.200 para corretora "
          "Flavia Soares 92 9131-8844")
ANA = """manda para Ana   92 9396-5797 os imóveis que ela está pedindo
os dois acquarelle que ela está pedindo de 2 e 3 quartos que temos disponível para locação
e a casa do morada do pássaros, envia as informações e as fotos para ela."""

print("--- as três mensagens do Tel ---")
r = ic(FLAVIA)
checar("Flávia: envio", r["acao"], "enviar_para_corretor")
checar("Flávia: NENHUM código (4.200 é valor)", r["codigos"], [])
checar("Flávia: o destino é o telefone", r["destino"], "92 9131-8844")
checar("Flávia: o nome que ele escreveu", r["nome_dito"], "Flavia Soares")
checar("Flávia: o pedido", r["pedido"], "toda as casas que temos para locação até 4.200")

r = ic(ANA)
checar("Ana: lista", r["acao"], "enviar_lista_para_corretor")
checar("Ana: o destino é o telefone do MEIO", r["destino"], "92 9396-5797")
checar("Ana: nome", r["nome_dito"], "Ana")
checar("Ana: a moldura sai, os dois pedidos ficam", len(r["linhas"]), 2)

r = ic(WALDYRENE)
checar("Waldyrene: lista", r["acao"], "enviar_lista_para_corretor")
checar("Waldyrene: destino", r["destino"], "92 9307-2954")
checar("Waldyrene: sem o artigo no nome", r["nome_dito"], "Waldyrene")

print()
print("--- VALOR NÃO É CÓDIGO ---")
for texto, esperado in [
    ("o 5750 e o 5751", ["5750", "5751"]),
    ("todas as casas até 4.200", []),
    ("apartamentos de 3.500", []),
    ("acquarelle 3.5k", []),
    ("casa até 4 mil", []),
    ("acquarelle de 2 e 3 quartos", []),
    ("o 5718 até 4200", ["5718"]),
    ("R$ 2.600", []),
]:
    checar(f"{texto!r}", _codigos_do_pedido(texto), esperado)

print()
print("--- O TELEFONE, onde quer que esteja ---")
for linha, tel, nome in [
    ("manda o 5750 p/ 92 99999-8888", "92 99999-8888", None),
    ("envia pro 92994717316", "92994717316", None),
    ("envia para a corretora Samira 92 8854-8030 o acquarelle", "92 8854-8030", "Samira"),
    ("envia pro +55 92 99471-7316", "+55 92 99471-7316", None),
]:
    s = _separar_destino_por_telefone(linha)
    checar(f"{linha[:40]!r} telefone", s and s[0], tel)
    checar("  e nome", s and s[1], nome)
checar("sem telefone não separa", _separar_destino_por_telefone("manda o 5750 pro Sergio"), None)
checar("valor não é telefone", _separar_destino_por_telefone("casas até 4.200 para a Samira"), None)

print()
print("--- a leitura do pedido ---")
f = ler_pedido("os dois acquarelle que ela está pedindo de 2 e 3 quartos que temos disponível para locação")
checar("'os dois' é quantidade", f["quantidade"], 2)
checar("'2 e 3 quartos'", f["quartos"], {2, 3})
checar("locação", f["negocio"], "locacao")
f = ler_pedido("toda as casas que temos para locação até 4.200")
checar("'toda' é todos", f["todos"], True)
checar("casa sozinha são as duas", f["categorias"], {"casa_condominio", "casa_via_publica"})
checar("teto lido", (f["teto"] or "").strip(), "4.200")
# "até 4.200 e 3 quartos" não pode ler o "0" do 4.200 como quarto
checar("quarto não come o valor", ler_pedido("casas até 4.200 e 3 quartos")["quartos"], {3})
# "de 2 a 3 quartos" é faixa de QUARTO, não de preço
f = ler_pedido("apartamentos de 2 a 3 quartos")
checar("faixa de quartos", f["quartos"], {2, 3})
checar("  e não vira teto", f["teto"], None)
checar("valor solto é exato", ler_pedido("Grand Prix / 2 quartos sendo 1 suíte / 3.5k")["valores"], ["3.5k"])
checar("'3 e 2 qtos' (como a Ana escreve)", ler_pedido("acquarelle de 3 e 2 qtos")["quartos"], {2, 3})
checar("'2 quartos' não é quantidade", ler_pedido("os 2 quartos do acquarelle")["quantidade"], None)
checar("venda", ler_pedido("casa para venda até 500k")["negocio"], "venda")

print()
print("--- a moldura da mensagem ---")
for linha, esperado in [("✅ APARTAMENTOS DISPONÍVEIS PARA", True),
                        ("ela pediu os imóveis abaixo:", True),
                        ("", True),
                        ("Estilo Golf / 2 quartos / 2.6k", False),
                        ("a casa do morada do pássaros", False),
                        # O FORMATO DE 15/09: 🔥 no título, ✅ colado em cada
                        # imóvel. Com a regra antiga, as linhas com ✅ viravam
                        # título e a lista colada inteira sumia.
                        ("🔥 APARTAMENTOS PARA LOCAÇÃO DE 1.9k A 10k 🔥", True),
                        ("🔥 APARTAMENTOS PARA LOCAÇÃO DE 1.9k A 10k 🔥 (continuação)", True),
                        ("✅Conquista rio negro / 2 quartos / semi-mobiliado / 1.9k (incluso a tx)", False),
                        ("✅ Arezzo Residencial / 2 quartos / 2.5k", False),
                        # condomínio cadastrado em caixa alta continua sendo imóvel
                        ("✅RESIDENCIAL MIRANTE / 2 quartos / 2.5k", False)]:
    checar(f"{linha!r}", e_titulo_ou_recado(linha), esperado)

print()
print("--- o BAIRRO no pedido (15/09) ---")
# O Tel mandou "apartamento para locação no bairro, flores, paz, parque dez,
# compensa, parque das laranjeiras até 3.000" e a Nay respondeu que não achou
# nada: o pedido descrito não lia bairro nenhum.
#
# Os dois lados chegam normalizados por `nay_normalizar_lugar` NO BANCO -- é
# ela que faz "parque dez" virar "parque 10" e "pq" virar "parque".
B = [("Flores", "flores"), ("Da Paz", "da paz"), ("Compensa", "compensa"),
     ("Parque 10 de Novembro", "parque 10 de novembro"),
     ("Parque das Laranjeiras", "parque das laranjeiras"),
     ("Ponta Negra", "ponta negra"), ("Novo Aleixo", "novo aleixo"),
     ("Parque Mundo Novo", "parque mundo novo")]
FRASE = ("apartamento para locacao no bairro flores paz parque 10 compensa "
         "parque das laranjeiras ate 3 000")
checar("os cinco bairros que ele listou", casar_bairros(FRASE, B),
       ["Compensa", "Da Paz", "Flores", "Parque 10 de Novembro",
        "Parque das Laranjeiras"])
# "parque dez" tem que achar "Parque 10 de Novembro" pela METADE das palavras,
# sem arrastar os outros bairros que começam com "Parque" -- com uma palavra só
# ele casaria "Parque das Laranjeiras" e "Parque Mundo Novo" também.
checar("'parque dez' sozinho não arrasta os outros Parque",
       casar_bairros("locacao no parque 10 ate 3 000", B),
       ["Parque 10 de Novembro"])
checar("'da paz' casa escrito só 'paz'", casar_bairros("apartamento na paz", B),
       ["Da Paz"])
checar("sem bairro nenhum, lista vazia",
       casar_bairros("todas as casas de locacao ate 4 200", B), [])
checar("bairro que não é nosso não inventa",
       casar_bairros("apartamento no leblon ate 3 000", B), [])

print()
print("--- CONDOMÍNIO x BAIRRO: quando um nome cabe dentro do outro ---")
# Os dois casadores olham a mesma frase sem saber um do outro. Quando um nome
# contém o outro, os dois casam, a consulta vira condomínio E bairro, e não
# sobra imóvel nenhum -- o Tel ouve "não achei imóvel para ...". Aconteceu nos
# DOIS sentidos, e cada um custou um pedido perdido.

# 15/09 -- "parque das laranjeiras" é BAIRRO. O casador de condomínio achou
# "Condomínio Laranjeiras" e "Residencial Laranjeiras", porque "laranjeiras"
# está na frase. Aqui o BAIRRO é o específico.
CH = {"Condomínio Laranjeiras": "laranjeiras",
      "Residencial Laranjeiras": "laranjeiras",
      "Mirante Das Flores": "mirante das flores",
      "Residencial Ponta Negra I": "ponta negra i",
      "Condomínio Acquarelle": "acquarelle"}
checar("o condomínio contido no bairro cai",
       desempatar_condominio_e_bairro(
           ["Condomínio Laranjeiras", "Residencial Laranjeiras"],
           ["Parque das Laranjeiras"], CH),
       ([], ["Parque das Laranjeiras"]))

# 25/09 -- "o mirante das flores" é CONDOMÍNIO, em PONTA NEGRA. O casador de
# bairro achou "Flores", palavra que está no nome dele. Aqui o CONDOMÍNIO é o
# específico, e a recusa que o Tel recebeu dizia "(entendi: locação; no
# Mirante Das Flores; no bairro Flores)".
checar("o bairro contido no condomínio cai",
       desempatar_condominio_e_bairro(
           ["Mirante Das Flores"], ["Flores"], CH),
       (["Mirante Das Flores"], []))

# "Residencial Ponta Negra I" tem o "i", que não está no bairro: ele SOBREVIVE
# ao primeiro passo (a regra de 15/09). Mas o bairro "Ponta Negra" cabe inteiro
# dentro do nome dele, então cai no segundo -- e isso é o certo, pelo mesmo
# motivo do Mirante: o condomínio pode não ficar no bairro que o nome dele
# sugere, e quem manda é o condomínio. Se ficar, o filtro de bairro não
# acrescentava nada mesmo.
checar("o condomínio sobrevive e o bairro contido nele cai",
       desempatar_condominio_e_bairro(
           ["Residencial Ponta Negra I"], ["Ponta Negra"], CH),
       (["Residencial Ponta Negra I"], []))
checar("condomínio e bairro sem relação: os dois ficam",
       desempatar_condominio_e_bairro(
           ["Condomínio Acquarelle"], ["Parque 10 de Novembro"], CH),
       (["Condomínio Acquarelle"], ["Parque 10 de Novembro"]))

# Se os dois passos rodassem cegos, um caso em que cada lado contém o outro
# derrubaria OS DOIS -- e o pedido ficaria sem lugar nenhum, que é o mesmo
# "não achei" por outro caminho. O segundo passo só olha o que sobrou.
checar("nomes iguais: cai o condomínio e o bairro FICA",
       desempatar_condominio_e_bairro(["Flores"], ["Flores"], {"Flores": "flores"}),
       ([], ["Flores"]))

checar("sem bairro, nada muda",
       desempatar_condominio_e_bairro(["Condomínio Acquarelle"], [], CH),
       (["Condomínio Acquarelle"], []))
checar("sem condomínio, nada muda",
       desempatar_condominio_e_bairro([], ["Flores"], CH),
       ([], ["Flores"]))

print()
print('--- "DE <NÚMERO>" É PREÇO, NÃO CÓDIGO (Tel, 25/09) ---')
# Ele escreveu "envia o parque imperial de 2750 para locação" e recebeu
# "2750: nao achei esse codigo no site" -- o 2750 caiu na faixa dos códigos do
# catálogo (45 a 5755) e foi lido como imóvel.
#
# O ARTIGO É O QUE SEPARA: ele chama o imóvel de "o 5750", nunca de "de 5750".
# MEDIDO no corpus inteiro antes de escrever a regra: ZERO mensagens, dele ou
# de qualquer corretor, com "de <número de 3 a 5 dígitos>".
checar("'de 2750' vira valor", ler_pedido("o parque imperial de 2750 para locação")["valores"],
       ["2750"])
checar("com ponto continua valendo",
       ler_pedido("o parque imperial de 2.750 para locação")["valores"], ["2.750"])
checar("e 'de 700 mil' também",
       ler_pedido("o acquarelle de 700 mil")["valores"], ["700 mil"])

# A CAUDA DE UNIDADE FICA DE FORA, senão "área de 250m2" viraria preço de 250.
checar("'de 250m2' não é preço",
       ler_pedido("a casa de 250m2 no aleixo")["valores"], [])
checar("'de 120 m²' não é preço",
       ler_pedido("apartamento de 120 m² para venda")["valores"], [])
# Quartos saem do texto ANTES de ler valor, e o mínimo de três dígitos também
# os excluiria -- mas o teste registra as duas paredes.
checar("'de 3 quartos' não é preço",
       ler_pedido("apartamento de 3 quartos para locação")["valores"], [])
checar("'de 2 e 3 quartos' não é preço",
       ler_pedido("os acquarelle de 2 e 3 quartos")["valores"], [])
checar("'de 3 suítes' não é preço",
       ler_pedido("casa de 3 suítes no tarumã")["valores"], [])
checar("'de 4 vagas' não é preço",
       ler_pedido("casa de 4 vagas")["valores"], [])

print()
print("--- e o código continua sendo código ---")
from interpretar_comando import interpretar_comando as _ic2
for frase, esperado in [
    # O ARTIGO. É assim que ele nomeia imóvel, e é a forma mais usada de todas.
    ("Nay envia o 5750 pro Sergio", ["5750"]),
    ("Nay manda o 5750 p/ 92 99999-8888", ["5750"]),
    ("92 8531-1259 envia o 5756", ["5756"]),
    ("envia 92 9450-0381 o 5739", ["5739"]),
    ("Nay envia os acquarelle de 2 e 3 quartos para locacao para o Sergio", []),
    # E a frase que motivou tudo: nenhum código, o valor vira o filtro.
    ("92 8604-9936 envia o parque imperial de 2750 para locação", []),
]:
    checar(f"{frase[:46]!r}", _ic2(frase).get("codigos"), esperado)

print()
print("--- o plural de locação (o que fez o pedido dele falhar) ---")
# "locações" vira "locacoes" depois do sem_acento, e `\bloca[çc][ãa]o\b` não
# casava -- o pedido ficava SEM negócio.
checar("locações", ler_pedido("todas as locações até 2800")["negocio"], "locacao")
checar("locação", ler_pedido("todas as locação até 2800")["negocio"], "locacao")
checar("aluguel", ler_pedido("aluguel até 2800")["negocio"], "locacao")
checar("venda continua venda", ler_pedido("vendas até 500 mil")["negocio"], "venda")

print()
print("--- a FAIXA de valor e o PERFIL (15/09) ---")
# "Nay envia locação de 3k a 6k nos bairros parque dez, flores e compensa" --
# as cinco formas que ele escreveu, mais comercial e residencial.
for frase, piso, teto, negocio, perfil, cats in [
    ("Nay envia locação de 3k a 6k nos bairros parque dez, flores e compensa",
     "3k", "6k", "locacao", None, set()),
    ("Nay envia locação de 3 mil a 6 mil nos bairros parque dez, flores e compensa",
     "3 mil", "6 mil", "locacao", None, set()),
    ("Nay envia casa para venda em condomínio de 250 mil a 600 mil nos bairros parque dez",
     "250 mil", "600 mil", "venda", None, {"casa_condominio"}),
    # sem negócio escrito: é o VALOR que diz que é venda -- e quem garante
    # isso é a faixa valer de um lado só (ver `imoveis_do_pedido`).
    ("Nay envia casa em condomínio de 250 mil a 600 mil nos bairros parque dez",
     "250 mil", "600 mil", None, None, {"casa_condominio"}),
    ("Nay envia casa em condomínio de 250k a 600k nos bairros parque dez",
     "250k", "600k", None, None, {"casa_condominio"}),
    ("Nay envia imóvel comercial de 200 mil a 900 mil",
     "200 mil", "900 mil", None, "comercial", {"sala"}),
    ("Nay envia imóvel residencial para venda de 250k a 600k no parque dez",
     "250k", "600k", "venda", "residencial", set()),
    ("Nay envia imóvel residencial de locação a partir de 6 mil",
     "6 mil", None, "locacao", "residencial", set()),
    ("Nay envia comercial para locação até 5 mil",
     None, "5 mil", "locacao", "comercial", {"sala"}),
    ("Nay envia galpão para venda no distrito", None, None, "venda", "comercial", set()),
]:
    f = ler_pedido(frase)
    checar(f"{frase[15:55]!r} piso", (f["piso"] or "").strip() or None, piso)
    checar("  teto", (f["teto"] or "").strip() or None, teto)
    checar("  negócio", f["negocio"], negocio)
    checar("  perfil", f["perfil"], perfil)
    checar("  categorias", f["categorias"], cats)

# "Residencial" É NOME DE CONDOMÍNIO na maior parte das vezes -- não pode
# virar perfil e apagar o imóvel comercial de um "Residencial" qualquer.
checar("'Residencial Acquarelle de 3 quartos' não é perfil",
       ler_pedido("e a casa do Residencial Acquarelle de 3 quartos")["perfil"], None)
checar("'Residencial Ponta Negra I' não é perfil",
       ler_pedido("o apto do Residencial Ponta Negra I")["perfil"], None)

# O QUE É COMERCIAL E O QUE É RESIDENCIAL, pelos tipos que existem mesmo no
# cadastro (medido em 15/09). Lote fica de fora dos dois.
for tipo, comercial, residencial in [
    ("Sala/Andar", True, False), ("Sala", True, False), ("Loja/Ponto", True, False),
    ("Galpão/Depósito", True, False), ("Prédio", True, False),
    ("Apartamento", False, True), ("Casa de condomínio", False, True),
    ("Casa", False, True), ("Flat", False, True), ("Cobertura", False, True),
    ("Apartamento em Via Pública", False, True), ("Chácara", False, True),
    ("Lote em Condomínio", False, False), ("Lote", False, False), ("", False, False),
]:
    checar(f"{tipo!r} comercial", e_comercial({"tipo": tipo}), comercial)
    checar(f"{tipo!r} residencial", e_residencial({"tipo": tipo}), residencial)

print()
print("--- O DESTINATÁRIO QUE FALTOU (15/09) ---")
# As frases dele SEM destino nenhum. O único "para" é o de "para venda", e a
# cauda gulosa virava o nome do corretor -- ela ia procurar alguém chamado
# "venda em condomínio de 250 mil a 600 mil nos bairros parque dez...".
for frase in [
    "Nay envia casa para venda em condomínio de 250 mil a 600 mil nos bairros parque dez, flores e compensa",
    "Nay envia imóvel comercial para locação de 3 mil a 8 mil",
    "Nay envia casa para venda de 250k a 600k",
    "Nay manda apartamento para locação até 3 mil",
]:
    checar(f"{frase[10:52]!r} pergunta para quem",
           ic(frase)["acao"], "enviar_sem_destino")
# O "para" QUE NÃO É DESTINO, e sim o negócio (15/09): ele mandou "envia o
# vista dos cedros para locação" e a frase morria em "não entendi o comando".
for frase in [
    "envia o vista dos cedros para locação",
    "Nay envia o life parque dez para locação",
    "manda o acquarelle para venda",
]:
    checar(f"negócio na cauda: {frase[:46]!r}",
           ic(frase)["acao"], "enviar_sem_destino")
# mas com o destinatário no fim continua sendo envio de verdade
checar("com o número no fim, é envio",
       ic("envia o vista dos cedros para locação para 92 9191-3793")["acao"],
       "enviar_para_corretor")
# e o verbo de GRUPO tem caminho próprio -- não pode ser roubado aqui
checar("'posta ... para locação' continua sendo postagem",
       ic("posta o jardim das cerejeiras para locação")["acao"], "postar_por_nome")
checar("'dispara ... para locação' continua sendo lista",
       ic("Nay dispara apartamentos para locação")["acao"], "disparar_lista")

# A LISTA DE CATEGORIA continua sendo lista no parser -- quem segura a frase
# que nomeia um condomínio ("envia as casas do morada dos pássaros para
# aluguel") é o publicador, que enxerga o catálogo. Ver teste_postar_por_nome.
for frase, acao in [
    ("envia as casas do morada dos pássaros para aluguel", "disparar_lista"),
    ("Nay dispara lista de apartamentos para locação", "disparar_lista"),
    ("Nay dispara lista de casas para venda de novo", "disparar_lista"),
    ("dispara a lista de salas comerciais para locação", "disparar_lista"),
    ("Nay dispara lista de apartamentos para locação no easy", "disparar_lista"),
    ("Nay dispara lista de apartamentos para locação para os grupos parceiros",
     "disparar_lista"),
    ("Nay envia a lista de apartamento pro Sergio", "envio_recusado"),
]:
    checar(f"{frase[:52]!r}", ic(frase)["acao"], acao)

# E SEM NENHUM "para" na frase -- as formas que ele escreveu primeiro.
for frase in [
    "Nay envia locação de 3k a 6k nos bairros parque dez, flores e compensa",
    "Nay envia locação de 3 mil a 6 mil nos bairros parque dez, flores e compensa",
    "Nay envia casa em condomínio de 250k a 600k nos bairros parque dez, flores e compensa",
    "Nay envia casa em condomínio de 250 mil a 600 mil nos bairros parque dez",
    "Nay envia locação até 2800 no parque dez",
]:
    checar(f"sem 'para': {frase[10:52]!r}", ic(frase)["acao"], "enviar_sem_destino")

# E O QUE NÃO PODE SER ROUBADO por esta parede: a cauda sem dinheiro continua
# sendo destinatário, a lista de categoria continua sendo lista, e frase sem
# verbo de envio na frente não vira comando por ter preço dentro.
for frase, acao in [
    ("Nay envia locação de 3k a 6k no parque dez para 92 9947-1731", "enviar_para_corretor"),
    ("Nay envia locação de 3k a 6k no parque dez para o Sergio", "enviar_para_corretor"),
    ("Nay manda o 5750 pro Sergio", "enviar_para_corretor"),
    ("Nay dispara apartamentos para locação", "disparar_lista"),
    ("Nay envia apartamentos para locação", "disparar_lista"),
    ("Nay envia casas para venda", "disparar_lista"),
    ("Nay lista de apartamentos para locação", "listar_categoria"),
    ("Nay posta o 5750", "postar_agora"),
    ("Nay ALUGOU 5611", "liberar_vaga"),
    ("Nay envia o acquarelle de 2.5k pro Sergio", "enviar_para_corretor"),
    # sem "Nay" na frente não é comando, mesmo com preço dentro
    ("manda 2.5k", "nao_reconhecido"),
    ("Nay o imóvel saiu por 2.5k", "nao_reconhecido"),
]:
    checar(f"{frase[4:46]!r}", ic(frase)["acao"], acao)


print()
print("--- o condomínio contido na frase ---")
C = [("Condomínio Acquarelle", "acquarelle"), ("Morada dos Pássaros", "morada dos passaros"),
     ("Moradas do Parque", "moradas"), ("Isla Morada", "isla morada"),
     ("Casa", ""), ("Residencial Ponta Negra I", "ponta negra i"), ("Negra", "negra"),
     ("Condomínio Laranjeiras", "laranjeiras"), ("Residencial Laranjeiras", "laranjeiras")]
checar("'morada DO pássaros' casa com 'Morada DOS Pássaros'",
       casar_condominios("e a casa do morada do pássaros, envia", C), ["Morada dos Pássaros"])
checar("acquarelle", casar_condominios("os dois acquarelle de 2 e 3 quartos", C),
       ["Condomínio Acquarelle"])
checar("palavra inteira: 'morada' não casa 'Moradas do Parque'",
       "Moradas do Parque" in casar_condominios("morada", C), False)
checar("rótulo 'Casa' não casa com qualquer frase",
       casar_condominios("a casa do aleixo", C), [])
checar("vale o nome mais comprido", casar_condominios("apto no ponta negra i", C),
       ["Residencial Ponta Negra I"])
checar("dois com a mesma chave voltam os dois", casar_condominios("casa laranjeiras", C),
       ["Condomínio Laranjeiras", "Residencial Laranjeiras"])
# "xanadu imperial" NÃO é o Parque Imperial -- casou por pedaço na prova de
# 14/09, e com "apartamento" no lugar de "casa" mandaria o 5717.
C2 = C + [("Condomínio Parque Imperial", "imperial")]
checar("nome de uma palavra colado a palavra desconhecida não casa",
       casar_condominios("a casa do xanadu imperial", C2), [])
checar("mas 'o apartamento do imperial' casa",
       casar_condominios("o apartamento do imperial", C2), ["Condomínio Parque Imperial"])
checar("e 'parque imperial' casa", casar_condominios("parque imperial 2 quartos", C2),
       ["Condomínio Parque Imperial"])
checar("e 'os dois acquarelle' casa", casar_condominios("manda os dois acquarelle", C2),
       ["Condomínio Acquarelle"])

print()
print("--- o PLURAL do cadastro (15/09) ---")
# Ele mandou "envia o VISTA dos cedros para locação para 92 9191-3793" e ouviu
# "não consegui identificar nenhum imóvel assim". O imóvel (5743) estava no ar;
# o cadastro é que escreve "VistaS dos Cedros".
C3 = C + [("Vistas dos Cedros", "vistas dos cedros"),
          ("Vista das Mangueiras", "vistas das mangueiras")]
checar("'vista dos cedros' acha 'Vistas dos Cedros'",
       casar_condominios("o vista dos cedros para locacao", C3), ["Vistas dos Cedros"])
checar("escrito no plural também",
       casar_condominios("o vistas dos cedros", C3), ["Vistas dos Cedros"])
# A tolerância NÃO vale para nome de uma palavra só: viraria condomínio
# diferente. Medido no catálogo inteiro: nenhum nome exato passa a casar errado.
checar("'morada' sozinho continua não casando 'Moradas do Parque'",
       "Moradas do Parque" in casar_condominios("morada", C3), False)
checar("e 'mangueira' não arrasta 'Vistas dos Cedros'",
       casar_condominios("a casa da vista das mangueira", C3), ["Vista das Mangueiras"])

print()
print("--- a recusa que ensina o nome certo ---")
checar("sugere o parecido", condominios_parecidos("o vista dos cedros para locacao", C3),
       ["Vistas dos Cedros"])
checar("nome que não lembra nada não sugere",
       condominios_parecidos("o xanadu imperial", C3), [])
# palavra curta não vale: "casa" apontaria metade do catálogo
checar("palavra de menos de 4 letras não sugere",
       condominios_parecidos("a casa do rio", C3), [])


# --------------------------------------------------------------------
class Cursor:
    def __init__(self, conn):
        self.conn, self.linhas = conn, []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        self.linhas = []
        if s.startswith("SELECT telefone, nome FROM corretores") or "FROM corretores WHERE aprovado" in s:
            self.linhas = list(self.conn.aprovados)
        elif s.startswith("SELECT 1 FROM corretores"):
            self.linhas = [{"x": 1}] if self.conn.existe_na_tabela else []
        elif "FROM mensagens" in s:
            self.linhas = list(self.conn.historico)
        elif s.startswith("INSERT INTO corretores"):
            self.conn.cadastrados.append(params)
            self.linhas = [{"telefone": params[0], "nome": params[1]}]
        elif "FROM envios" in s:
            self.linhas = []

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class Conn:
    def __init__(self, aprovados=(), historico=(), existe_na_tabela=False):
        self.aprovados, self.historico = list(aprovados), list(historico)
        self.existe_na_tabela, self.cadastrados = existe_na_tabela, []

    def cursor(self):
        return Cursor(self)

    def commit(self):
        pass


print()
print("--- a resposta de quem esqueceu o destinatário ---")


class ConnPedido(Conn):
    """Catálogo vazio: o que importa aqui é a FRASE que ela devolve."""

    def cursor(self):
        c = Cursor(self)
        c.execute = lambda sql, params=None: None
        c.fetchall = lambda: []
        c.fetchone = lambda: None
        return c


r = publicador._envio_sem_destino(
    {"pedido": "casa para venda de 250k a 600k",
     "texto": "Nay envia casa para venda de 250k a 600k"}, ConnPedido())
checar("diz que não mandou", "não mandei nada" in r, True)
checar("e devolve a frase dele pronta, com o destino no fim",
       "Nay envia casa para venda de 250k a 600k para 92 9999-9999" in r, True)

print()
print("--- CADASTRA SÓ QUEM JÁ CONVERSOU ---")
conn = Conn(historico=[{"telefone": "559291318844", "nome": "Flávia Soares 👑💙"}])
tel, nome, aviso = publicador._destinatario(conn, {"destino": "92 9131-8844",
                                                  "nome_dito": "Flavia Soares"})
checar("quem já mandou mensagem entra", tel, "559291318844")
checar("com o nome que o Tel escreveu", nome, "Flavia Soares")
checar("e como MANUAL, para a sincronização não trocar", conn.cadastrados[0][2], "manual")
checar("e o Tel é avisado", "cadastrei agora" in aviso, True)

conn = Conn()
tel, motivo, _ = publicador._destinatario(conn, {"destino": "92 9999-0000", "nome_dito": "Fulano"})
checar("número sem histórico NÃO entra", tel, None)
checar("  e nada é cadastrado", conn.cadastrados, [])
checar("  e a recusa diz o motivo", "nao esta cadastrado" in motivo, True)

conn = Conn(historico=[{"telefone": "559291318844", "nome": "X"}], existe_na_tabela=True)
tel, _, _ = publicador._destinatario(conn, {"destino": "92 9131-8844", "nome_dito": "X"})
checar("quem está na tabela DESATIVADO não é reativado", tel, None)
checar("  e nada é gravado", conn.cadastrados, [])

conn = Conn(historico=[{"telefone": "559291318844", "nome": "X"}])
tel, _, _ = publicador._destinatario(conn, {"destino": "Flávia", "nome_dito": None})
checar("sem telefone escrito, não cadastra por nome", tel, None)

print()
print("--- CARD VAZIO NÃO SAI ---")
enviados = []
publicador.buscar_imovel = lambda c: {"codigo": c, "tipo": None, "valor_venda": None,
                                      "valor_aluguel": None, "fotos": []}
publicador.enviar_texto = lambda *a, **k: None
publicador.enviar_imovel = lambda *a, **k: enviados.append(a) or {}
resp = publicador._mandar_os_codigos(Conn(), "559291318844", "Flávia", ["4", "200"])
checar("nada é enviado", enviados, [])
checar("e diz que não achou", resp.count("nao achei esse codigo no site"), 2)

print()
print("--- TETO POR LEVA ---")
publicador._resolver_as_linhas = lambda conn, linhas: ([str(5000 + i) for i in range(40)], [], [], [])
publicador._destinatario = lambda conn, comando: ("559291318844", "Flávia", "")
mandou = []
publicador._mandar_os_codigos = lambda *a: mandou.append(a) or ""
resp = publicador._enviar_lista_para_corretor({"destino": "92 9131-8844", "linhas": ["todos os apartamentos"]}, Conn())
checar("40 imóveis não saem", mandou, [])
checar("e ela diz quantos são", "dá 40 imóveis" in resp, True)

print()
print("--- pedido sem código vai pelo caminho da lista ---")
visto = []
publicador._enviar_lista_para_corretor = lambda comando, conn: visto.append(comando) or "ok"
publicador._enviar_para_corretor({"acao": "enviar_para_corretor", "codigos": [],
                                  "destino": "92 9131-8844", "nome_dito": "Flavia Soares",
                                  "pedido": "toda as casas até 4.200"}, Conn())
checar("delegou", len(visto), 1)
checar("com o pedido como linha", visto[0]["linhas"], ["toda as casas até 4.200"])
checar("e o nome junto", visto[0]["nome_dito"], "Flavia Soares")

print()
print("--- FORA DE CONDOMÍNIO é via pública, não o contrário (Tel, 27/09) ---")
# A busca por "condom" casa DENTRO de "fora de condomínio", e a frase que pede
# casa de RUA mandava justamente a de condomínio. Medido com a frase dele:
# "casas para ela até 3.000 fora de condomínio" devolvia o 5551 (que É de
# condomínio) e escondia o 1327 e o 5709, que são as de rua.
import pedido_de_imoveis as _pi
for _frase, _esperado in [
    ("casas de locacao ate 3.000 fora de condominio", ["casa_via_publica"]),
    ("casas sem condominio", ["casa_via_publica"]),
    ("casas que nao sao de condominio", ["casa_via_publica"]),
    # e o sentido oposto continua valendo
    ("casas de condominio", ["casa_condominio"]),
    ("casas em condominio", ["casa_condominio"]),
    # sem qualificador são AS DUAS, que é a regra antiga e não pode mudar
    ("casas de locacao ate 3.000", ["casa_condominio", "casa_via_publica"]),
    ("casas de via publica", ["casa_via_publica"]),
    ("casas na rua", ["casa_via_publica"]),
]:
    checar(f"{_frase[:44]!r}", sorted(_pi._categorias(_frase)), sorted(_esperado))

print()
print("--- A MOBÍLIA COMO FILTRO (Tel, 28/09) ---")
# "envia o imóvel para o Walter no tarumã e ponta negra até 3.500 mas que
# esteja SÓ MARCADO COMO MOBILIADO".
#
# O "SÓ" É O PEDIDO INTEIRO: medido no catálogo, `mobiliado` e `mobiliado
# (moveis + cama + tudo)` são 38 imóveis; `semi-mobiliado` e `semi-mobiliado
# (moveis planejados + ar)` são outros 74. Quem pede mobiliado e recebe semi
# recebe imóvel errado -- e aqui o imóvel vai para um corretor, sem desfazer.
checar_mobilia = lambda t, e: checar(
    f"mobília de {t[:44]!r}", ler_pedido(t).get("mobilia"), e)

checar_mobilia("no tarumã e ponta negra até 3.500 mas que esteja só marcado "
               "como mobiliado", "mobiliado")
checar_mobilia("apartamento mobiliado no aleixo", "mobiliado")
checar_mobilia("casa com mobilia ate 4000", "mobiliado")

# A ORDEM IMPORTA: "semi-mobiliado" CONTÉM "mobiliado". Lido ao contrário,
# todo pedido de semi devolveria os 38 mobiliados -- e vice-versa.
checar_mobilia("apartamento semi-mobiliado no aleixo", "semi")
checar_mobilia("apartamento semi mobiliado no aleixo", "semi")
checar_mobilia("apartamento semimobiliado", "semi")

checar_mobilia("casa sem mobilia ate 4000", "sem")
checar_mobilia("imovel vazio no centro", "sem")
checar_mobilia("apartamento desmobiliado", "sem")

# E SILÊNCIO QUANDO ELE NÃO PEDIU: filtro que aparece sozinho tiraria imóvel
# de todo pedido que não menciona mobília.
checar_mobilia("apartamento no tarumã até 3.000", None)
checar_mobilia("casas de locação no parque dez até 4.000", None)
checar_mobilia("os dois acquarelle de 2 e 3 quartos", None)

print()
print("--- e a mobília entra no resumo, para a recusa ensinar ---")
# Recusa que não diz o que entendeu não ensina nada -- é a lição de 15/09,
# quando ele viu "não achei" e não soube que ela tinha lido CASA.
_f = ler_pedido("no tarumã até 3.500 mas que esteja só marcado como mobiliado")
_resumo = _resumo_do_pedido(_f, [], ["Tarumã"], "3.500", None)
checar("o resumo diz 'só mobiliado'", "só mobiliado" in _resumo, True)
_f2 = ler_pedido("apartamento semi-mobiliado no aleixo")
checar("e diz 'semi-mobiliado' quando é semi",
       "semi-mobiliado" in _resumo_do_pedido(_f2, [], ["Aleixo"], None, None), True)
_f3 = ler_pedido("apartamento no aleixo")
checar("e não fala de mobília quando ele não pediu",
       "mobili" in _resumo_do_pedido(_f3, [], ["Aleixo"], None, None), False)

print()
print("--- o VALOR da faixa não pode virar CÓDIGO (Tel, 28/09) ---")
# Ele escreveu "só semi-mobiliado de 3200 a até 5.000" e recebeu o IMÓVEL 3200
# (Palacio das Águas, sem valor de aluguel). O `nay_codigos_citados` roda antes
# de tudo e leu o piso da faixa como código.
#
# A função do banco JÁ TIRA VALOR, e bem -- "Paga até 4000" não vira o imóvel
# 4000. Mas ela reconhece dinheiro pela CARA ("3.5k", "2.600", "4 mil"), e
# "3200" cru não tem cara de dinheiro. Quem sabe que aquilo é dinheiro é a
# POSIÇÃO: veio depois de "de", dentro de uma faixa.
from pedido_de_imoveis import _sem_os_valores

checar("o piso da faixa sai do texto",
       "3200" in _sem_os_valores("apartamento no flores de 3200 a até 5.000"), False)
checar("e o teto também",
       "5.000" in _sem_os_valores("apartamento no flores de 3200 a até 5.000"), False)
checar("teto sozinho também sai",
       "4000" in _sem_os_valores("apartamento no flores ate 4000"), False)
# MAS O CÓDIGO DE VERDADE FICA -- senão "envia o 3200" pararia de funcionar,
# e o 3200 existe: Palacio das Águas.
checar("código pedido de propósito continua",
       "3200" in _sem_os_valores("envia o 3200 para ela"), True)
checar("e dois códigos continuam",
       _sem_os_valores("envia o 3200 e o 5718").count("3200") == 1
       and "5718" in _sem_os_valores("envia o 3200 e o 5718"), True)
# Os quartos saem junto: "de 2 a 3 quartos" não é faixa de preço, e o 2 e o 3
# também não são códigos.
checar("quartos não viram código",
       any(c.isdigit() for c in _sem_os_valores("de 2 a 3 quartos no aleixo")), False)


print()
print("--- 'de X A ATÉ Y' é faixa (Tel, 28/09) ---")
# Ele escreve as duas ligações juntas: "de 3200 a até 5.000". Com só "a" ou só
# "até" na regex, a faixa inteira era perdida e sobrava o TETO -- o pedido
# mandava também o que estava ABAIXO do piso, calado.
for _t, _piso, _teto in [("de 3200 a ate 5.000", "3200", "5.000"),
                         ("de 3200 a 5.000", "3200", "5.000"),
                         ("de 3200 ate 5.000", "3200", "5.000"),
                         ("de 3.200 a ate 5.000", "3.200", "5.000"),
                         ("de 250k a ate 600k", "250k", "600k")]:
    _f = ler_pedido(_t)
    checar(f"faixa de {_t!r}", (_f["piso"], _f["teto"]), (_piso, _teto))
# E o teto sozinho continua teto -- a alternativa nova não pode roubar.
_f = ler_pedido("ate 4.000")
checar("'até 4.000' continua sendo só teto", (_f["piso"], _f["teto"]), (None, "4.000"))


print()
print("--- a mobília é CONFERIDA NO SITE antes de filtrar (Tel, 28/09) ---")
# "quando eu coloco mobiliado ou semi-mobiliado a Nay precisa olhar no sistema
# para saber se está marcado na caixa esta opção para poder enviar o correto".
#
# MEDIDO: dos 20 candidatos do pedido dele, SEIS divergiam -- todos com a
# coluna VAZIA no banco e a caixa marcada no anúncio. "só semi-mobiliado"
# devolvia 5; os certos eram 9. Quatro ficavam de fora, calados.
from pedido_de_imoveis import (_casa_mobilia, _mobilia_conferida,
                               LIMITE_LEITURAS_DE_MOBILIA)

checar("semi casa 'semi-mobiliado'", _casa_mobilia("semi-mobiliado", "semi"), True)
checar("semi casa o rótulo longo",
       _casa_mobilia("semi-mobiliado (moveis planejados + ar)", "semi"), True)
# O PONTO TODO DO PEDIDO: "só mobiliado" NÃO pode trazer o semi.
checar("mobiliado NÃO casa semi", _casa_mobilia("semi-mobiliado", "mobiliado"), False)
checar("semi NÃO casa mobiliado", _casa_mobilia("mobiliado", "semi"), False)
checar("mobiliado casa o rótulo longo",
       _casa_mobilia("mobiliado (moveis + cama + tudo)", "mobiliado"), True)
checar("vazio não é mobiliado", _casa_mobilia(None, "mobiliado"), False)
checar("vazio não é semi", _casa_mobilia("", "semi"), False)
# "SEM MOBÍLIA" INCLUI O VAZIO: 138 imóveis não têm o campo, e quem pede sem
# mobília não quer ouvir "não tenho nenhum" por causa de cadastro em branco.
checar("sem mobília inclui o vazio", _casa_mobilia(None, "sem"), True)
checar("sem mobília inclui 'so ar-condicionado'",
       _casa_mobilia("so ar-condicionado", "sem"), True)
checar("sem mobília NÃO inclui mobiliado", _casa_mobilia("mobiliado", "sem"), False)


class _ConnMob:
    """Banco de mentira que guarda o que foi gravado."""

    def __init__(self, tabela):
        self.tabela = dict(tabela)
        self.gravados = []

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                if "UPDATE imoveis" in sql:
                    conn.tabela[params[1]] = params[0]
                    conn.gravados.append((params[1], params[0]))
                    s.linhas = []
                else:
                    s.linhas = [{"c": c, "mobilia": conn.tabela.get(c)}
                                for c in params[0]]

            def fetchall(s):
                return s.linhas
        return C()

    def commit(self):
        pass

    def rollback(self):
        pass


# O CASO REAL: o banco vazio e o site dizendo semi -- o 5742, o 5732 e o 150.
_conn = _ConnMob({"5718": "semi-mobiliado", "5742": None, "5717": "mobiliado"})
_site = {"5718": {"tipo": "Apartamento", "mobilia": "semi-mobiliado"},
         "5742": {"tipo": "Apartamento", "mobilia": "semi-mobiliado"},
         "5717": {"tipo": "Apartamento", "mobilia": "mobiliado"}}
_r = _mobilia_conferida(_conn, ["5718", "5742", "5717"],
                        buscar=lambda c: _site.get(c, {}), pausa=lambda s: None)
checar("o que o banco não sabia vem do site", _r["5742"], "semi-mobiliado")
checar("e é GRAVADO, para o banco convergir", _conn.gravados, [("5742", "semi-mobiliado")])
checar("o que já batia não é regravado", len(_conn.gravados), 1)

# ANÚNCIO FORA DO AR NÃO ZERA: `buscar_imovel` devolve dict TRUTHY com tudo
# None quando o anúncio sai, e gravar dali apagaria o que o banco sabe.
_conn2 = _ConnMob({"5718": "semi-mobiliado"})
_r2 = _mobilia_conferida(_conn2, ["5718"],
                         buscar=lambda c: {"tipo": None, "mobilia": None},
                         pausa=lambda s: None)
checar("fora do ar mantém o do banco", _r2["5718"], "semi-mobiliado")
checar("e não grava nada", _conn2.gravados, [])

# UM ANÚNCIO QUE EXPLODE não derruba o pedido inteiro.
_conn3 = _ConnMob({"5718": "semi-mobiliado", "5742": None})


def _meio_quebrado(c):
    if c == "5718":
        raise RuntimeError("timeout")
    return {"tipo": "Apartamento", "mobilia": "mobiliado"}


_r3 = _mobilia_conferida(_conn3, ["5718", "5742"], buscar=_meio_quebrado,
                         pausa=lambda s: None)
checar("o que deu certo entra", _r3["5742"], "mobiliado")
checar("e o que falhou fica com o banco", _r3["5718"], "semi-mobiliado")

# A PAUSA entre leituras (regra 5 do projeto), e nunca antes da primeira.
_pausas = []
_mobilia_conferida(_ConnMob({}), ["1", "2", "3"],
                   buscar=lambda c: {}, pausa=_pausas.append)
checar("duas pausas para três leituras", len(_pausas), 2)

# O TETO DE LEITURAS existe para o pedido largo não virar espera de minutos.
_lidos = []
_mobilia_conferida(_ConnMob({}), [str(i) for i in range(100)],
                   buscar=lambda c: _lidos.append(c) or {}, pausa=lambda s: None)
checar("lê no máximo o teto", len(_lidos), LIMITE_LEITURAS_DE_MOBILIA)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO PEDIDO DE IMÓVEIS PASSARAM")
