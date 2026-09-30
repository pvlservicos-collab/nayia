"""
Prova a família de comandos do grupo "🟢 Comercial - OFERTA e BUSCA 🔍".

O PEDIDO (Tel, 27/09): "posta no grupo comercial 5763 (desta forma manda no
grupo) / posta lista de imóvel comercial no grupo comercial / posta lista de
sala comercial no grupo comercial (vai postar só as salas comerciais de
condomínio) / posta todo dia as 08h / posta segunda, quarta e sabado as 07h".

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * A ORDEM NO DISPATCH. Sem a regra na frente, "posta no grupo comercial
    5763" casa o `POSTAR_RE` e sai nos 17 grupos de uma vez -- MEDIDO em
    27/09, antes de escrever. E postagem em grupo não desfaz.

  * AS FORMAS DE LISTA NÃO PODEM SER ROUBADAS. "posta lista de sala comercial
    no grupo comercial" tem as duas marcas; se o caminho de imóvel a pegasse,
    ela procuraria um código onde não tem nenhum.

  * O GRUPO É `so_comercial`, então imóvel residencial é RECUSA, não post. E
    a parede vem ANTES da reserva: reservar e recusar deixaria o código
    marcado como postado sem nada ter saído, e o pedido seguinte cairia em
    "já foi" -- o buraco que o Easy teve até 14/09.

  * FALHA FECHADA na parede: site fora do ar ou erro de rede não vira "pode
    postar". Sem saber o tipo, não posta.

  * ELE NÃO É `todas_fotos`, e tem apelido. `grupos_com_apelido` exigia a
    marca, então o grupo nunca resolvia e a resposta seria "não achei o
    grupo" para um grupo que existe. Recebe a metadinha, como os normais --
    e a FRASE de sucesso tem que dizer isso, não "com todas as fotos".

  * HORÁRIO DE UM IMÓVEL NÃO EXISTE para grupo de apelido, e o CHECK
    `vagas_imovel_ou_lista` é quem diz (vaga de imóvel exige `destino IS
    NULL`). Antes desta recusa, "posta no grupo comercial 5763 todo dia as
    08h" postava NA HORA e engolia o horário -- ele pediria programação e
    receberia post imediato, sem desfazer. O Alto Padrão tinha o mesmo furo.

  * O "SIM" DA REPOSTAGEM VOLTA AO MESMO GRUPO. `_postar_easy` era chamado
    sem parâmetro nenhum ali, então "sim" a uma pergunta do Alto Padrão (ou
    do Comercial) postava no EASY. O apelido viaja na pergunta.

Uso:
    .venv/bin/python teste_grupo_comercial.py
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


print("--- as formas que viram postagem no grupo Comercial ---")
for frase in [
    "posta no grupo comercial 5763",            # a frase que ele deu
    "posta no grupo comercial o 5763",
    "Nay posta no grupo comercial 5763",
    "posta 5763 no grupo comercial",
    "publica no grupo comercial o 5763",
    "Nay posta no comercial o 5763",
    "posta no grupo comercial de novo o 5763",
]:
    r = ic(frase) or {}
    checar(frase, (r.get("acao"), r.get("codigo")), ("postar_comercial", "5763"))

print()
print("--- o que NÃO pode ser roubado por essa regra ---")
# Cada um destes já era um comando vivo antes de 27/09.
for frase, esperado in [
    ("posta o 5763", "postar_agora"),
    ("posta no grupo anunciar easy 5763", "postar_easy"),
    ("posta no grupo alto padrao easy 5763", "postar_alto_padrao_easy"),
    ("Nay posta o 5763 todo dia às 14h", "criar_vaga"),
    # PESSOA na cauda é recusa, nunca post -- a parede de 31/08.
    ("posta o 5763 pro corretor comercial", "envio_recusado"),
    # AS LISTAS. "comercial" aparece DUAS vezes na frase dele e nenhuma das
    # duas pode virar busca de código.
    ("posta lista de sala comercial no grupo comercial", "disparar_lista"),
    ("posta lista de imovel comercial no grupo comercial", "disparar_lista"),
    ("dispara lista de sala comercial para locação", "disparar_lista"),
]:
    checar(frase, (ic(frase) or {}).get("acao"), esperado)

print()
print("--- o DESTINO da lista, que é o que escolhe os grupos ---")
for frase, destino in [
    ("posta lista de sala comercial no grupo comercial", "comercial"),
    ("dispara lista de sala comercial para venda no grupo comercial", "comercial"),
    # sem nomear o grupo, continua indo para os de parceiro
    ("dispara lista de sala comercial para locação", "parceiros"),
    # e o Easy continua sendo o Easy
    ("Nay dispara lista de sala comercial para locação no anunciar easy", "easy"),
    # "sala comercial" SOZINHO não é o grupo -- senão toda lista de sala
    # comercial deixaria de ir aos 13 grupos de parceiro sem ninguém pedir.
    ("dispara lista de sala comercial para venda", "parceiros"),
]:
    checar(frase, (ic(frase) or {}).get("destino"), destino)

# O TIRA tem que casar o MESMO destino do agendar: o DELETE filtra por ele, e
# destino divergente deixa vaga que não se consegue mais apagar.
r = ic("tira a lista de sala comercial para locação do grupo comercial") or {}
checar("o TIRA usa o mesmo destino",
       (r.get("acao"), r.get("destino")),
       ("remover_lista_da_grade", "comercial"))
r = ic("posta lista de sala comercial para locação no grupo comercial todo dia as 08h") or {}
checar("e o AGENDAR também",
       (r.get("acao"), r.get("destino"), r.get("horario"), r.get("tipo_recorrencia")),
       ("agendar_lista", "comercial", datetime.time(8, 0), "diaria"))
r = ic("posta lista de sala comercial para locação no grupo comercial "
       "segunda, quarta e sabado as 07h") or {}
checar("a programação semanal dele",
       (r.get("destino"), r.get("horario"), r.get("dias_semana")),
       ("comercial", datetime.time(7, 0), [1, 3, 6]))

print()
print("--- horário de UM imóvel: AGENDA no grupo (Tel, 27/09) ---")
# Ele pediu: "posta no grupo comercial o 5763 segunda, quarta e sexta as 08h
# ... coloca várias variantes ... quero colocar dias diferentes de dia".
#
# Isto já postou NA HORA engolindo o horário, e depois virou recusa (o CHECK
# `vagas_imovel_ou_lista` exigia `destino IS NULL` na vaga de imóvel).
# `vaga_de_grupo.sql` afrouxou o CHECK e a recusa virou agendamento.
DIAS = {0: "dom", 1: "seg", 2: "ter", 3: "qua", 4: "qui", 5: "sex", 6: "sab"}


def agenda(frase):
    """(dias ou 'DIARIA', hora) da vaga -- ou a ação, quando não virou vaga."""
    r = ic(frase) or {}
    if r.get("acao") != "criar_vaga" or r.get("destino") != "comercial":
        return r.get("acao")
    d = r.get("dias_semana")
    return (",".join(DIAS[x] for x in d) if d else r.get("tipo_recorrencia"),
            str(r.get("horario")), r.get("codigos"))


# A FRASE EXATA que ele mandou, com o espaço duplo que o WhatsApp dele manda.
checar("a frase dele, com espaço duplo",
       agenda("posta no grupo comercial  o 5763 segunda, quarta e sexta as 08h"),
       ("seg,qua,sex", "08:00:00", ["5763"]))

for frase, esperado in [
    # as ordens e pontuações que ele usa
    ("posta no grupo comercial o 5763 segunda, quarta e sexta as 08h", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo comercial 5763 segunda, quarta e sexta as 08h", ("seg,qua,sex", "08:00:00")),
    ("Nay posta no grupo comercial o 5763 segunda quarta e sexta as 08h", ("seg,qua,sex", "08:00:00")),
    ("posta 5763 no grupo comercial segunda, quarta e sexta as 08h", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo comercial o 5763 toda segunda, quarta e sexta as 08h", ("seg,qua,sex", "08:00:00")),
    # PLURAL -- "às segundas, quartas e sextas". Sem o `s?` isto era "não reconheci".
    ("posta no grupo comercial o 5763 às segundas, quartas e sextas às 8h", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo comercial o 5763 seg, qua e sex as 8h", ("seg,qua,sex", "08:00:00")),
    # a HORA ANTES DOS DIAS. `as 08:00` vira os "códigos" 08 e 00, e por isso
    # a vaga tem que ser lida ANTES da contagem de códigos.
    ("posta no grupo comercial o 5763 as 08:00 segunda, quarta e sexta", ("seg,qua,sex", "08:00:00")),
    # HORA POR PERÍODO
    ("posta no grupo comercial o 5763 segunda, quarta e sexta as 8 da manha", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo comercial o 5763 sabado e domingo as 2 da tarde", ("dom,sab", "14:00:00")),
    ("posta no grupo comercial o 5763 as 7 da noite todo dia", ("diaria", "19:00:00")),
    # OUTROS VERBOS -- é como ele já fala com o Alto Padrão
    ("manda no grupo comercial o 5763 segunda e quarta as 8h", ("seg,qua", "08:00:00")),
    ("envia para o grupo comercial o 5763 terça e quinta as 14h", ("ter,qui", "14:00:00")),
    ("publica no grupo comercial o 5763 segunda e quarta as 8h", ("seg,qua", "08:00:00")),
    ("posta no comercial o 5763 segunda e quarta as 8h", ("seg,qua", "08:00:00")),
    # DIÁRIA e dia único
    ("posta no grupo comercial o 5763 todo dia as 08h", ("diaria", "08:00:00")),
    ("posta no grupo comercial o 5763 todos os dias as 8h", ("diaria", "08:00:00")),
    ("posta no grupo comercial o 5763 todo sabado as 10h", ("sab", "10:00:00")),
    ("posta no grupo comercial o 5763 domingo as 19h", ("dom", "19:00:00")),
    ("posta no grupo comercial o 5763 toda terça as 9h", ("ter", "09:00:00")),
]:
    checar(frase, agenda(frase), esperado + (["5763"],))

print()
print("--- INTERVALO de dias: 'de segunda a sexta' são CINCO dias ---")
# ERA UM BUG SILENCIOSO: o laço colhia só as duas pontas e a vaga saía
# SEGUNDA e SEXTA -- três dias a menos, confirmado na tela como se
# estivesse certo. Resultado errado calado é pior que recusa.
checar("de segunda a sexta",
       agenda("posta no grupo comercial o 5763 de segunda a sexta as 9h"),
       ("seg,ter,qua,qui,sex", "09:00:00", ["5763"]))
checar("de segunda a sabado",
       agenda("posta no grupo comercial o 5763 de segunda a sabado as 9h"),
       ("seg,ter,qua,qui,sex,sab", "09:00:00", ["5763"]))
# DÁ A VOLTA: sexta, sábado, domingo, segunda.
checar("de sexta a segunda dá a volta",
       agenda("posta no grupo comercial o 5763 de sexta a segunda as 9h"),
       ("dom,seg,sex,sab", "09:00:00", ["5763"]))

print()
print("--- e o Alto Padrão e o Easy ganharam o mesmo (tinham o mesmo furo) ---")
for frase, destino in [
    ("posta no grupo alto padrão 4567 todo dia as 08h", "alto_padrao"),
    ("posta no grupo alto padrão o 4567 segunda e quinta as 7h", "alto_padrao"),
    ("posta no anunciar easy o 5750 todo dia as 8h", "easy"),
]:
    r = ic(frase) or {}
    checar(frase, (r.get("acao"), r.get("destino")), ("criar_vaga", destino))

print()
print("--- sem horário, continua sendo postagem IMEDIATA ---")
# A porta nova não pode transformar o comando de sempre em agendamento.
for frase, esperado in [("posta no grupo comercial 5763", "postar_comercial"),
                        ("posta no grupo alto padrão 4567", "postar_alto_padrao"),
                        ("posta no grupo anunciar easy 5763", "postar_easy"),
                        ("posta o 5763", "postar_agora")]:
    checar(frase, (ic(frase) or {}).get("acao"), esperado)
# E a vaga SEM grupo continua sem destino -- os grupos de sempre.
r = ic("posta o 5763 todo dia as 14h") or {}
checar("vaga sem grupo não ganha destino",
       (r.get("acao"), r.get("destino")), ("criar_vaga", None))
# VÁRIOS CÓDIGOS num grupo de apelido não agenda: ele descreveu no singular,
# e uma vaga com vários postaria em cadeia todo dia.
checar("dois códigos no grupo não viram vaga",
       (ic("posta no grupo comercial 5763 e 4255 todo dia as 8h") or {}).get("acao"),
       "agenda_incompleta")

print()
print("--- o grupo resolve SEM `todas_fotos`, e só ele ---")
GRUPOS = [
    {"id_grupo": "g-easy", "nome": "IMÓVEIS PARA ANUNCIAR EASY",
     "todas_fotos": True, "apelido": "easy"},
    {"id_grupo": "g-ap", "nome": "IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY",
     "todas_fotos": True, "apelido": "alto_padrao"},
    {"id_grupo": "g-com", "nome": "🟢 Comercial - OFERTA e BUSCA 🔍",
     "todas_fotos": False, "apelido": "comercial", "so_comercial": True},
    {"id_grupo": "g-parc", "nome": "Parceria", "todas_fotos": False,
     "apelido": None},
]
_original = publicador.carregar_grupos_db
publicador.carregar_grupos_db = lambda conn: GRUPOS
try:
    checar("com a exigência ligada (o padrão) o Comercial NÃO resolve",
           publicador.grupos_com_apelido(None, "comercial"), [])
    checar("com ela desligada, resolve só ele",
           [g["id_grupo"] for g in
            publicador.grupos_com_apelido(None, "comercial",
                                          exige_todas_fotos=False)],
           ["g-com"])
    # E desligar a exigência NÃO pode arrastar o grupo de parceria para o Easy:
    # ele não tem apelido, e `coalesce` no 'easy' o tornaria "Easy".
    checar("o grupo sem apelido NÃO vira Easy por causa disso",
           [g["id_grupo"] for g in
            publicador.grupos_com_apelido(None, "easy", exige_todas_fotos=False)],
           ["g-easy", "g-parc"])
    checar("e com a exigência, o Easy continua como era",
           [g["id_grupo"] for g in publicador.grupos_com_apelido(None, "easy")],
           ["g-easy"])
finally:
    publicador.carregar_grupos_db = _original

print()
print("--- a parede: só imóvel comercial entra ---")


class ConnFake:
    def cursor(self):
        raise AssertionError("a parede não devia consultar o banco")


def parede(imovel, no_ar=True):
    """Devolve a recusa (ou None) para um imóvel fingido."""
    _b, _c = publicador.buscar_imovel, publicador._com_condominio_do_banco
    publicador.buscar_imovel = lambda c: imovel
    publicador._com_condominio_do_banco = lambda i, conn=None: i
    try:
        return publicador._nao_e_comercial(ConnFake(), "5763")
    finally:
        publicador.buscar_imovel, publicador._com_condominio_do_banco = _b, _c


for tipo in ["Sala", "Sala/Andar", "Loja/Ponto", "Galpão/Depósito", "Prédio"]:
    checar(f"{tipo} passa", parede({"tipo": tipo, "codigo": "5763"}), None)

for tipo in ["Apartamento", "Casa de condomínio", "Casa", "Cobertura", "Lote"]:
    r = parede({"tipo": tipo, "codigo": "5763"})
    checar(f"{tipo} é recusado", bool(r), True)
    checar(f"  e a recusa diz o tipo e que não postou",
           bool(r) and tipo in r and "não postei nada" in r, True)

r = parede({"tipo": "Apartamento", "codigo": "5763"})
checar("a recusa ensina o comando dos grupos de sempre",
       "Nay posta o 5763" in r, True)

print()
print("--- falha FECHADA: sem saber o tipo, não posta ---")
# `buscar_imovel` devolve dict TRUTHY com tudo None quando o anúncio saiu do
# ar -- a armadilha já registrada. E erro de rede não pode virar "pode postar".
r = parede({"tipo": None, "codigo": "5763", "fotos": []})
checar("anúncio fora do ar recusa", bool(r), True)


def _explodir(c):
    raise RuntimeError("timeout")


_b = publicador.buscar_imovel
publicador.buscar_imovel = _explodir
try:
    r = publicador._nao_e_comercial(ConnFake(), "5763")
finally:
    publicador.buscar_imovel = _b
checar("erro ao buscar recusa", bool(r) and "não postei nada" in r, True)

print()
print("--- os três grupos de apelido, num lugar só ---")
# O "sim" da repostagem chamava `_postar_easy` SEM parâmetro: quem respondesse
# "sim" a uma pergunta do Alto Padrão postava no EASY, grupo errado e sem
# desfazer. A tabela é o que impede o quarto grupo de repetir isso.
# ASSERÇÕES DE INVARIANTE, não de contagem: o dicionário cresce (o Comercial
# entrou em 27/09 de manhã, o "lotado" à tarde), e um teste que conta fica
# vermelho a cada grupo novo sem ter achado defeito nenhum.
checar("o Comercial está lá", "comercial" in publicador.GRUPOS_DE_APELIDO, True)
checar("e o Easy e o Alto Padrão continuam",
       {"easy", "alto_padrao"} <= set(publicador.GRUPOS_DE_APELIDO), True)
# CADA APELIDO COM SUA TABELA DE RESERVA. Duas apontando para a mesma fariam
# "já foi postado no Easy" barrar uma postagem no Comercial.
tabelas = [g["tabela"] for g in publicador.GRUPOS_DE_APELIDO.values()]
checar("cada apelido com uma tabela só dele",
       len(set(tabelas)), len(tabelas))
# TODO apelido precisa dos três campos -- faltar um estoura só na hora de
# postar, que é tarde.
checar("todos têm tabela, rótulo e regra de foto",
       all({"tabela", "rotulo", "exige_todas_fotos"} <= set(g)
           for g in publicador.GRUPOS_DE_APELIDO.values()), True)
# E TODO APELIDO TEM NOME EM PORTUGUÊS para as respostas ao Tel: sem isso a
# frase sairia "agendado no alto_padrao", com o nome interno.
checar("todos têm nome legível para as respostas",
       set(publicador.GRUPOS_DE_APELIDO) <= set(publicador.NOME_DO_GRUPO_DE_APELIDO),
       True)
checar("o Comercial dispensa `todas_fotos`",
       publicador.GRUPOS_DE_APELIDO["comercial"]["exige_todas_fotos"], False)
checar("e o Easy continua exigindo",
       publicador.GRUPOS_DE_APELIDO["easy"]["exige_todas_fotos"], True)

print()
print("--- o DISPARO da vaga vai para o grupo certo ---")
# A vaga criada não vale nada se a grade postar no lugar de sempre. Aqui o
# `_postar_easy` e o `_postar_codigo` são substituídos por espiões: prova o
# ROTEAMENTO sem mandar nada para grupo nenhum.
import agendador

chamadas = []
_pe, _pc, _nc = (publicador._postar_easy, publicador._postar_codigo,
                 publicador._nao_e_comercial)
# A parede de FAIXA entrou no disparo em 27/09 (o valor pode cair no cadastro
# entre criar a vaga e ela disparar). Aqui ela é dublada: o que se prova neste
# bloco é o ROTEAMENTO, e a faixa tem o teste dela em teste_grupo_alto_padrao.
_af = publicador._abaixo_da_faixa
publicador._abaixo_da_faixa = lambda conn, cod, apelido: None
publicador._postar_easy = (lambda cod, conn, de_novo=False, apelido="easy":
                           chamadas.append(("easy", cod, apelido, de_novo)) or "ok")
publicador._postar_codigo = (lambda cod, grupos, conn=None, negocio=None:
                             chamadas.append(("todos", cod, None, None))
                             or {"codigo": cod, "sucesso": True})
publicador._nao_e_comercial = lambda conn, cod: None
try:
    publicador._postar_da_vaga("5763", [], None, "comercial")
    checar("vaga do Comercial -> _postar_easy com apelido comercial",
           chamadas[-1], ("easy", "5763", "comercial", True))
    publicador._postar_da_vaga("4567", [], None, "alto_padrao")
    checar("vaga do Alto Padrão -> apelido alto_padrao",
           chamadas[-1], ("easy", "4567", "alto_padrao", True))
    # SEM destino nada muda: é o caminho de sempre, todos os grupos elegíveis.
    publicador._postar_da_vaga("3210", [], None, None)
    checar("vaga sem destino -> todos os grupos elegíveis",
           chamadas[-1], ("todos", "3210", None, None))
    # `de_novo=True` é o que permite a vaga DIÁRIA postar no segundo dia:
    # a reserva do `_postar_easy` é por código, para sempre.
    checar("sempre de_novo (senão o 2º dia diz 'já foi postado')",
           all(c[3] for c in chamadas if c[0] == "easy"), True)
    # A PAREDE DO COMERCIAL vale no disparo também: o tipo pode ter mudado
    # no cadastro entre criar a vaga e ela disparar.
    publicador._nao_e_comercial = lambda conn, cod: "não é comercial"
    r = publicador._postar_da_vaga("5760", [], None, "comercial")
    checar("imóvel que deixou de ser comercial não sai",
           r.get("resposta"), "não é comercial")
finally:
    (publicador._postar_easy, publicador._postar_codigo,
     publicador._nao_e_comercial) = _pe, _pc, _nc
    publicador._abaixo_da_faixa = _af

# E o agendador tem que RECONHECER a vaga nova como algo a disparar -- vaga
# sem categoria e com código não pode ser lida como "vaga livre".
import datetime
vaga = {"codigos": ["5763"], "categoria": None, "destino": "comercial",
        "horario": datetime.time(8, 0), "tipo_recorrencia": "semanal",
        "dias_semana": [1, 3, 5], "data_unica": None}
# 28/09/2026 é uma SEGUNDA (DOW 1 no Postgres).
checar("dispara na segunda às 08:00",
       agendador.vaga_deve_disparar(vaga, datetime.datetime(2026, 9, 28, 8, 0)),
       True)
checar("não dispara na terça",
       agendador.vaga_deve_disparar(vaga, datetime.datetime(2026, 9, 29, 8, 0)),
       False)
checar("nem um minuto depois",
       agendador.vaga_deve_disparar(vaga, datetime.datetime(2026, 9, 28, 8, 1)),
       False)


print()
print("--- a vaga repetida vira aviso, não exceção (Tel, 27/09) ---")
# "a Nay está repetindo. o soberane duas vezes ... se ela fizer duas postagens
# assim já não permite isso". O índice do banco barra; aqui se prova que o
# publicador TRADUZ a violação em frase, em vez de estourar um 500 -- e que
# qualquer outro erro continua subindo, senão um bug de banco viraria
# "essa vaga já existe" para sempre.
class ConnQueRecusa:
    def __init__(self, erro):
        self.erro = erro
        self.rollbacks = 0

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                raise RuntimeError(conn.erro)
        return C()

    def commit(self):
        pass

    def rollback(self):
        self.rollbacks += 1


import datetime as _dt
cmd = {"horario": _dt.time(17, 0), "tipo_recorrencia": "semanal",
       "dias_semana": [1, 3, 6], "codigos": ["5749"], "destino": None}
conn = ConnQueRecusa('duplicate key value violates unique constraint '
                     '"vagas_imovel_unica"')
r = publicador._criar_vaga(cmd, conn)
checar("diz que já existe", "essa vaga já existe" in r, True)
checar("nomeia o imóvel", "5749" in r, True)
checar("ensina onde ver", 'Nay VAGAS' in r, True)
checar("e desfaz a transação", conn.rollbacks, 1)

# COM destino, a frase diz o grupo -- senão ele não sabe QUAL das duas vagas
# do mesmo imóvel já existe.
r = publicador._criar_vaga(dict(cmd, destino="comercial"),
                           ConnQueRecusa('... "vagas_imovel_unica"'))
checar("com grupo, a frase nomeia o grupo", "no grupo comercial" in r, True)

# QUALQUER OUTRO ERRO SOBE. Sem isto, um banco fora do ar responderia "essa
# vaga já existe" e ele passaria a tarde tentando entender.
try:
    publicador._criar_vaga(cmd, ConnQueRecusa("connection refused"))
    checar("erro de verdade continua subindo", "não subiu", "subiu")
except RuntimeError as exc:
    checar("erro de verdade continua subindo", "connection refused" in str(exc),
           True)


print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO GRUPO COMERCIAL PASSARAM")
