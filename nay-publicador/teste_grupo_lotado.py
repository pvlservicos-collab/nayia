"""
Prova os comandos dos QUATRO grupos de maior movimento ("grupo lotado").

O PEDIDO (Tel, 27/09): "tem uns grupos que o movimento é maior que vou postar
todo dia uns imóveis neles" -- e os quatro nomes: 📍CREDENCIADOS | Corretores
Performance, Top imóveis venda e aluguéis 💰💰, Novos Negócios Imobiliários -
AM e FECHANDO PARCERIAS 1.0. Com cinco frases de exemplo e o pedido de
variantes.

O QUE ESTE CASO TEM DE DIFERENTE: é o PRIMEIRO APELIDO COLETIVO. Easy, Alto
Padrão e Comercial são um grupo cada; "lotado" são quatro. O código aguentou
sem mudar -- `grupos_com_apelido` sempre devolveu lista e `_postar_easy`
sempre percorreu --, mas o BANCO não: `grupos_apelido_unico` garantia um grupo
por apelido, e o UPDATE foi recusado. A trava continua valendo para os outros
três e abre só para este (`grupo_lotado.sql`).

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * AS CINCO FRASES DELE, ao pé da letra. Uma delas -- "segunda, quarta e
    sexta as 08" -- traz a HORA SEM O "h", que nenhuma outra forma do
    projeto tinha.

  * A HORA SEM O "h" SÓ VALE EM CONTEXTO DE AGENDA. Solta ela é perigosa:
    "envia as 2 casas" viraria 2h, e "os 2" é a resposta de desambiguação de
    12/09. Por isso só é consultada quando a frase já fala de dia.

  * NADA ROUBADO. "lotado" não pode pegar o que era do Comercial, do Easy,
    do Alto Padrão, da lista, nem o envio a pessoa.

  * CADA APELIDO COM SUA TABELA DE RESERVA. Duas apontando para a mesma
    fariam "já foi postado no Easy" barrar uma postagem nos lotados.

Uso:
    .venv/bin/python teste_grupo_lotado.py
"""
import datetime

import publicador
from interpretar_comando import interpretar_comando as ic

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


DIAS = {0: "dom", 1: "seg", 2: "ter", 3: "qua", 4: "qui", 5: "sex", 6: "sab"}


def agenda(frase):
    r = ic(frase) or {}
    if r.get("acao") != "criar_vaga" or r.get("destino") != "lotado":
        return r.get("acao")
    d = r.get("dias_semana")
    return (",".join(DIAS[x] for x in d) if d else r.get("tipo_recorrencia"),
            str(r.get("horario")), r.get("codigos"))


print("--- AS CINCO FRASES QUE ELE ESCREVEU, ao pé da letra ---")
for frase, esperado in [
    ("posta 5713 no grupo lotado todo dia as 12:30", ("diaria", "12:30:00")),
    # A HORA SEM O "h" -- nenhuma outra forma do projeto tinha esta.
    ("posta 5713 no grupo lotado segunda, quarta e sexta as 08", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo lotado o 5713 seg, qua e sex as 8h", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo lotado o 5713 as 08:00 segunda, quarta e sexta", ("seg,qua,sex", "08:00:00")),
]:
    checar(frase, agenda(frase), esperado + (["5713"],))
checar("posta no grupo lotado o 5763 todo sabado as 10h",
       agenda("posta no grupo lotado o 5763 todo sabado as 10h"),
       ("sab", "10:00:00", ["5763"]))

print()
print("--- as variantes ---")
for frase, esperado in [
    ("posta no grupo lotado o 5713 todo dia as 12:30", ("diaria", "12:30:00")),
    ("posta nos grupos lotados o 5713 todo dia as 8h", ("diaria", "08:00:00")),
    ("Nay posta no grupo lotado 5713 segunda, quarta e sexta as 08", ("seg,qua,sex", "08:00:00")),
    ("posta 5713 nos lotados todo dia as 9", ("diaria", "09:00:00")),
    # "movimentado" é a palavra com que ele descreveu a ideia.
    ("posta no grupo movimentado o 5713 todo dia as 10h", ("diaria", "10:00:00")),
    ("posta nos grupos movimentados o 5713 terça e quinta as 14h", ("ter,qui", "14:00:00")),
    # outros verbos, como ele já fala com o Alto Padrão
    ("manda no grupo lotado o 5713 todo dia as 8h", ("diaria", "08:00:00")),
    ("envia para os grupos lotados o 5713 de segunda a sexta as 7h",
     ("seg,ter,qua,qui,sex", "07:00:00")),
    ("publica no grupo lotado o 5713 às segundas, quartas e sextas às 8h",
     ("seg,qua,sex", "08:00:00")),
    # hora por período e hora antes dos dias
    ("posta no grupo lotado o 5713 todo dia as 8 da manha", ("diaria", "08:00:00")),
    ("posta no grupo lotado o 5713 sabado e domingo as 2 da tarde", ("dom,sab", "14:00:00")),
    ("posta no grupo lotado o 5713 as 12:30 todo dia", ("diaria", "12:30:00")),
    ("posta no grupo lotado o 5713 todo dia as 19", ("diaria", "19:00:00")),
]:
    checar(frase, agenda(frase), esperado + (["5713"],))

print()
print("--- sem horário, posta AGORA nos quatro ---")
for frase in ["posta no grupo lotado o 5713", "posta 5713 no grupo lotado",
              "Nay posta nos grupos lotados o 5713"]:
    r = ic(frase) or {}
    checar(frase, (r.get("acao"), r.get("codigo")), ("postar_lotado", "5713"))
r = ic("posta no grupo lotado de novo o 5713") or {}
checar('"de novo" passa por cima da reserva',
       (r.get("acao"), r.get("de_novo")), ("postar_lotado", True))

print()
print("--- a HORA SEM O 'h' só vale em contexto de agenda ---")
# Solta ela é perigosa: "as 2" viraria 2h. Sem dia nem "todo dia", a frase
# NÃO pode virar agendamento -- e é por isso que ela não entra no HORA_RE.
r = ic("posta no grupo lotado o 5713 as 08") or {}
checar("sem dia nem 'todo dia', não vira vaga", r.get("acao") != "criar_vaga", True)
# E a resposta de desambiguação continua sendo escolha, não hora.
checar('"os dois" continua sendo escolha',
       (ic("os dois") or {}).get("acao"), "escolher_codigos")
checar('"os 2" também', (ic("os 2") or {}).get("acao"), "escolher_codigos")
# "envia as 2 casas para <telefone>" continua sendo envio a pessoa.
checar("envio com 'as 2 casas' continua envio",
       (ic("envia as 2 casas para 92 99999-8888") or {}).get("acao"),
       "enviar_para_corretor")

print()
print("--- nada roubado ---")
for frase, esperado in [
    ("posta o 5763", "postar_agora"),
    ("posta o 5763 todo dia as 14h", "criar_vaga"),
    ("posta no grupo comercial 5763", "postar_comercial"),
    ("posta no grupo comercial o 5763 todo dia as 8h", "criar_vaga"),
    ("posta no grupo anunciar easy 5763", "postar_easy"),
    ("posta no grupo alto padrao easy 4567", "postar_alto_padrao_easy"),
    ("Nay manda o 5750 pro Sergio", "enviar_para_corretor"),
    ("posta lista de sala comercial no grupo comercial", "disparar_lista"),
    ("dispara lista de apartamento para locação", "disparar_lista"),
    ("Nay VAGAS", "listar_vagas"),
]:
    checar(frase, (ic(frase) or {}).get("acao"), esperado)
# A vaga do lotado tem que ter destino 'lotado', e a do Comercial 'comercial'
# -- destinos trocados postariam o imóvel no grupo errado, todo dia.
checar("a vaga do Comercial continua com destino comercial",
       (ic("posta no grupo comercial o 5763 todo dia as 8h") or {}).get("destino"),
       "comercial")

print()
print("--- o apelido coletivo no publicador ---")
checar("'lotado' está registrado", "lotado" in publicador.GRUPOS_DE_APELIDO, True)
checar("com tabela de reserva própria",
       publicador.GRUPOS_DE_APELIDO["lotado"]["tabela"], "lotado_publicacoes")
checar("e dispensa `todas_fotos` (os quatro recebem a metadinha)",
       publicador.GRUPOS_DE_APELIDO["lotado"]["exige_todas_fotos"], False)
# O NOME JÁ TRAZ A PREPOSIÇÃO: com um "no " fixo no código, quatro grupos
# saíam como "no grupos lotados". Cada apelido diz a frase certa.
checar("com nome legível e concordando",
       publicador.NOME_DO_GRUPO_DE_APELIDO["lotado"], "nos grupos lotados")
checar("e os de um grupo só continuam no singular",
       publicador.NOME_DO_GRUPO_DE_APELIDO["comercial"], "no grupo comercial")

# QUATRO GRUPOS SOB UM APELIDO: `grupos_com_apelido` devolve os quatro, e o
# Easy continua sozinho. Era o ponto de dúvida do desenho.
GRUPOS = [
    {"id_grupo": "g-easy", "nome": "IMÓVEIS PARA ANUNCIAR EASY",
     "todas_fotos": True, "apelido": "easy"},
    {"id_grupo": "g-1", "nome": "CREDENCIADOS", "todas_fotos": False,
     "apelido": "lotado"},
    {"id_grupo": "g-2", "nome": "Top imóveis", "todas_fotos": False,
     "apelido": "lotado"},
    {"id_grupo": "g-3", "nome": "Novos Negócios", "todas_fotos": False,
     "apelido": "lotado"},
    {"id_grupo": "g-4", "nome": "FECHANDO PARCERIAS 1.0", "todas_fotos": False,
     "apelido": "lotado"},
    {"id_grupo": "g-outro", "nome": "Parceria", "todas_fotos": False,
     "apelido": None},
]
_orig = publicador.carregar_grupos_db
publicador.carregar_grupos_db = lambda conn: GRUPOS
try:
    checar("o apelido devolve OS QUATRO",
           sorted(g["id_grupo"] for g in
                  publicador.grupos_com_apelido(None, "lotado",
                                                exige_todas_fotos=False)),
           ["g-1", "g-2", "g-3", "g-4"])
    checar("e o Easy continua sozinho",
           [g["id_grupo"] for g in publicador.grupos_com_apelido(None, "easy")],
           ["g-easy"])
finally:
    publicador.carregar_grupos_db = _orig

print()
print("--- o disparo da vaga vai para o apelido certo ---")
chamadas = []
_pe = publicador._postar_easy
publicador._postar_easy = (lambda cod, conn, de_novo=False, apelido="easy":
                           chamadas.append((cod, apelido, de_novo)) or "ok")
try:
    publicador._postar_da_vaga("5713", [], None, "lotado")
    checar("vaga do lotado -> apelido lotado, com de_novo",
           chamadas[-1], ("5713", "lotado", True))
finally:
    publicador._postar_easy = _pe

# E o agendador reconhece a vaga: 28/09/2026 é uma SEGUNDA (DOW 1).
import agendador
vaga = {"codigos": ["5713"], "categoria": None, "destino": "lotado",
        "horario": datetime.time(12, 30), "tipo_recorrencia": "diaria",
        "dias_semana": None, "data_unica": None}
checar("dispara às 12:30",
       agendador.vaga_deve_disparar(vaga, datetime.datetime(2026, 9, 28, 12, 30)),
       True)
checar("não dispara às 12:31",
       agendador.vaga_deve_disparar(vaga, datetime.datetime(2026, 9, 28, 12, 31)),
       False)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO GRUPO LOTADO PASSARAM")
