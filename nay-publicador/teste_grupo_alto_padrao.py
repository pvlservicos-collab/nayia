"""
Prova o comando do grupo IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY.

O PEDIDO (Tel, 25/09): "esse grupo foi criado só para enviar imóvel alto
padrão para alguns corretores, eles anunciam esses imóveis que vamos colocar
lá. quando o comando for: Nay envia para o grupo alto padrão 4567, ela só vai
enviar este imóvel que pedir".

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * A ORDEM NO DISPATCH. O nome do grupo CONTÉM "anunciar easy", então sem a
    regra na frente o `EASY_RE` casa e o imóvel vai para o grupo Easy de
    sempre. E "posta no grupo alto padrão 4567" casaria o `POSTAR_RE` e sairia
    nos 17 grupos de uma vez. MEDIDO em 25/09, antes de escrever: "Nay publica
    no alto padrão easy o 4567" caía em `postar_agora`.

  * DUAS MARCAS SÃO EXIGIDAS, "alto padrão" E grupo/easy/anunciar. Sem a
    segunda, "envia o 5750 pro corretor do alto padrão" -- uma PESSOA --
    viraria postagem num grupo de 11 corretores, e isso não desfaz.

  * UM CÓDIGO SÓ. Ele descreveu no singular ("é um código que vou colocar
    lá"); aceitar vários postaria em cadeia, cada um com todas as fotos.

  * A RECUSA POR FAIXA, e a frase dela sendo LIDA DE VOLTA. Ela responde "me
    manda: ... mesmo assim", e a lição de 12/09 é que toda frase que a Nay
    escreve faz parte da gramática -- lá ela ofereceu "ou os dois?", ele
    copiou, e a resposta caiu no agente.

  * BASTA UM LADO PASSAR na faixa: 1,2 milhão de venda que também aluga por
    4 mil é alto padrão. Recusar pelo aluguel seria ler o valor errado.

Uso:
    .venv/bin/python teste_grupo_alto_padrao.py
"""
from interpretar_comando import interpretar_comando as ic

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


# DOIS GRUPOS SE CHAMAM "ALTO PADRÃO" (27/09), e qual recebe mudou:
#
#   🟢 Alto Padrão - OFERTA e BUSCA 🔍      uma foto, só condomínio
#   IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY  todas as fotos
#
# Até 27/09 "no grupo alto padrão" ia para o de ANUNCIAR EASY e o outro não
# tinha comando nenhum. O Tel pediu o segundo, e escolheu a separação quando
# perguntei: "alto padrão" passa a ser o OFERTA e BUSCA, e o de Anunciar Easy
# exige dizer "anunciar" ou "easy". Perguntei porque as duas leituras eram
# plausíveis e postagem em grupo não desfaz.
print("--- 'alto padrão' agora é o OFERTA e BUSCA ---")
for frase in [
    "posta 5750 no grupo alto padrão todo dia as 12:30",  # a frase dele
    "Nay envia para o grupo alto padrão 4567",
    "envia para o grupo alto padrao o 4567",
    "Nay manda para o grupo alto padrão o 4567",
    "posta no grupo alto padrão 4567",
    "publica no grupo alto padrão o 4567",
    "Nay encaminha para o grupo alto padrão 4567",
    # SEM O "ALTO" -- quatro das cinco frases dele são assim, e o espaço
    # duplo é o que o WhatsApp dele manda.
    "posta no grupo  padrão o 4567",
    "posta 4567 no grupo padrão",
    "posta nos grupos padrão o 4567",
]:
    r = ic(frase)
    if r["acao"] == "criar_vaga":
        checar(repr(frase[:48]), (r["acao"], r.get("destino")),
               ("criar_vaga", "alto_padrao"))
    else:
        checar(repr(frase[:48]), (r["acao"], r.get("codigo")),
               ("postar_alto_padrao", "4567"))

print()
print("--- e o de ANUNCIAR EASY exige dizer 'anunciar' ou 'easy' ---")
for frase in [
    "Nay publica no alto padrão easy o 4567",
    "Nay posta no alto padrao para anunciar easy 4567",
    "posta no grupo alto padrao easy 4567",
]:
    r = ic(frase)
    checar(repr(frase[:48]), (r["acao"], r.get("codigo")),
           ("postar_alto_padrao_easy", "4567"))
# E a vaga dele carrega o apelido certo: destino trocado postaria no grupo
# errado todo dia, e é o erro mais caro desta mudança.
r = ic("posta no alto padrão anunciar easy o 4567 todo dia as 9h")
checar("a vaga do Anunciar Easy tem o destino dele",
       (r["acao"], r.get("destino")), ("criar_vaga", "alto_padrao_easy"))

print()
print("--- e o que NÃO pode entrar por essa porta ---")
# PESSOA, não grupo. Sem a exigência da segunda marca isto postaria em 11
# corretores de uma vez.
checar("'pro corretor do alto padrão' é envio privado",
       ic("Nay envia o 5750 pro corretor do alto padrão")["acao"],
       "enviar_para_corretor")
# O Easy de sempre continua dele.
checar("'no anunciar easy' continua indo para o Easy",
       ic("Nay publica no anunciar easy o 4567")["acao"], "postar_easy")
# O posta normal continua nos grupos de parceria.
checar("'posta o 5750' continua sendo o posta de sempre",
       ic("Nay posta o 5750")["acao"], "postar_agora")
# Sem código não posta nada.
checar("sem código, não reconhece",
       ic("Nay envia para o grupo alto padrão")["acao"], "nao_reconhecido")
# DOIS códigos não postam dois imóveis.
checar("dois códigos não viram dois posts",
       ic("Nay envia para o grupo alto padrão 4567 e 5664")["acao"],
       "nao_reconhecido")
# Tirar é tirar, não postar.
checar("'remove' continua tirando da grade",
       ic("remove o 4567 do grupo alto padrão")["acao"], "remover_da_grade")

print()
print("--- o telefone não vira código (um grupo de 11 pessoas) ---")
# Um telefone cujos 4 dígitos casem um código real postaria o imóvel errado.
r = ic("Nay envia para o grupo alto padrão (92) 98478-7190 o 3210")
checar("só o 3210 vira código", (r["acao"], r.get("codigo")),
       ("postar_alto_padrao", "3210"))

print()
print("--- 'de novo' e 'mesmo assim' ---")
r = ic("posta no grupo alto padrão 5664 de novo")
checar("'de novo' pede repostagem", r.get("de_novo"), True)
checar("e não é lido como forçar faixa", r.get("forcar"), False)
# A FRASE DA RECUSA TEM QUE SER LIDA DE VOLTA. Ela responde "me manda: envia
# para o grupo alto padrão NNNN mesmo assim" -- se o parser não lê isso, a
# recusa vira laço fechado.
for frase in ["envia para o grupo alto padrão 4567 mesmo assim",
              "Nay envia para o grupo alto padrão 4567, confirmo",
              "posta no grupo alto padrão 4567 assim mesmo",
              "envia para o grupo alto padrão 4567, é alto padrão sim"]:
    r = ic(frase)
    checar(f"{frase[:44]!r} força",
           (r["acao"], r.get("forcar")), ("postar_alto_padrao", True))


# ----------------------------------------------------- a recusa por faixa --
class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linha = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        if "FROM grupos" in s:
            self.linha = self.conn.grupo
        elif "FROM imoveis" in s:
            self.linha = self.conn.imovel

    def fetchone(self):
        return self.linha


class ConnFake:
    def __init__(self, grupo, imovel):
        self.grupo = grupo
        self.imovel = imovel

    def cursor(self):
        return CursorFake(self)


import publicador

GRUPO = {"nome": "IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY",
         "aluguel_minimo": 6500, "venda_minima": 1000000}


def recusa(imovel, grupo=GRUPO):
    return publicador._abaixo_da_faixa(ConnFake(grupo, imovel), "4567",
                                       "alto_padrao")


print()
print("--- a faixa: quem passa ---")
checar("venda de 1,2 milhão passa",
       recusa({"valor_aluguel": None, "valor_venda": 1200000,
               "condominio_nome": "X"}), None)
checar("aluguel de 8 mil passa",
       recusa({"valor_aluguel": 8000, "valor_venda": None,
               "condominio_nome": "X"}), None)
checar("exatamente no piso passa -- o piso ENTRA",
       recusa({"valor_aluguel": 6500, "valor_venda": None,
               "condominio_nome": "X"}), None)
# BASTA UM LADO. Recusar pelo aluguel um imóvel de 1,2 milhão seria ler o
# valor errado: ele é alto padrão pela venda.
checar("1,2 milhão de venda com aluguel de 4 mil passa",
       recusa({"valor_aluguel": 4000, "valor_venda": 1200000,
               "condominio_nome": "X"}), None)

print()
print("--- a faixa: quem é recusado, e a recusa ensina a resposta ---")
r = recusa({"valor_aluguel": 2000, "valor_venda": None,
            "condominio_nome": "Vila das Flores"})
checar("recusa o aluguel de 2 mil", r is not None, True)
checar("diz o imóvel pelo nome", "4567 (Vila das Flores)" in (r or ""), True)
checar("diz o valor dele", "2.000" in (r or ""), True)
checar("diz a faixa do grupo", "6.500" in (r or ""), True)
checar("não postou nada", "não postei nada" in (r or ""), True)
checar("e ENSINA a frase que libera",
       "mesmo assim" in (r or ""), True)
# A frase que ela ensina tem que ser lida de volta pelo parser.
ensinada = (r or "").split("me manda: ")[-1].strip()
checar("e essa frase, colada de volta, é entendida",
       (ic(ensinada)["acao"], ic(ensinada).get("forcar")),
       ("postar_alto_padrao", True))

print()
print("--- falha ABERTA: sem dado, o comando segue ---")
# Ao contrário dos portões de acesso, aqui barrar é pior que deixar passar:
# quem mandou o código foi o Tel, e isto é cortesia contra engano.
checar("grupo sem piso não recusa",
       recusa({"valor_aluguel": 100, "valor_venda": None, "condominio_nome": "X"},
              {"nome": "g", "aluguel_minimo": None, "venda_minima": None}), None)
checar("imóvel sem valor nenhum não recusa",
       recusa({"valor_aluguel": None, "valor_venda": None,
               "condominio_nome": "X"}), None)
checar("imóvel que não existe no banco não recusa", recusa(None), None)
checar("grupo que não existe não recusa",
       recusa({"valor_aluguel": 100, "valor_venda": None,
               "condominio_nome": "X"}, None), None)

print()
print("--- O APELIDO SEPARA OS TRÊS CAMINHOS (o estrago de 25/09) ---")
# Eu consertei só o COMANDO e deixei os outros dois selecionando por
# `todas_fotos`. O Tel disse "ALUGOU 2943" e o aviso saiu nos DOIS grupos --
# "é para ela postar somente no grupo imóveis para anunciar easy quando não
# estiver mais disponível". O disparo de lista tinha o mesmo defeito e ninguém
# tinha visto. Por isso a regra virou UMA função.
GRUPOS = [
    {"id_grupo": "g-easy", "nome": "IMÓVEIS PARA ANUNCIAR EASY",
     "todas_fotos": True, "apelido": "easy"},
    {"id_grupo": "g-ap", "nome": "IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY",
     "todas_fotos": True, "apelido": "alto_padrao"},
    {"id_grupo": "g-parc", "nome": "Parceria", "todas_fotos": False,
     "apelido": None},
    # quem ainda não tiver apelido gravado continua sendo o Easy
    {"id_grupo": "g-velho", "nome": "grupo antigo", "todas_fotos": True,
     "apelido": None},
]


class ConnGrupos:
    def cursor(self):
        raise AssertionError("não devia consultar o banco aqui")


import montar_destinos
_original = montar_destinos.carregar_grupos_db
publicador.carregar_grupos_db = lambda conn: GRUPOS
try:
    checar("apelido 'easy' pega o Easy e o sem-apelido",
           sorted(g["id_grupo"] for g in publicador.grupos_com_apelido(None, "easy")),
           ["g-easy", "g-velho"])
    checar("apelido 'alto_padrao' pega SÓ o grupo novo",
           [g["id_grupo"] for g in publicador.grupos_com_apelido(None, "alto_padrao")],
           ["g-ap"])
    checar("grupo de parceria nunca entra por aqui",
           any(g["id_grupo"] == "g-parc"
               for g in publicador.grupos_com_apelido(None, "easy")), False)
    checar("o padrão é o Easy",
           sorted(g["id_grupo"] for g in publicador.grupos_com_apelido(None)),
           ["g-easy", "g-velho"])
finally:
    publicador.carregar_grupos_db = _original

print()
print("--- A FONTE UNICA: os mesmos casos que os nós do n8n rodam ---")
# A gramática vive em SETE cópias, em dois fluxos. `casos_alto_padrao.json` é
# lido por ESTE teste (Python) e por `teste_regex_telefone_na_frente.js` (o
# Node do container), então divergir vira teste vermelho em vez de comando
# morto -- que é como esta forma nasceu: reconhecida no Python e no roteador
# da NAI, e descartada pelo `Comando do Tel`.
import json as _json
from interpretar_comando import (ALTO_PADRAO_EASY_RE as _AP_EASY,
                                ALTO_PADRAO_BUSCA_RE as _AP_BUSCA,
                                _VERBO_DE_GRUPO_RE as _VERBO)


def _e_comando_de_alto_padrao(t):
    """A frase é um comando de ALGUM dos dois grupos de alto padrão?

    A COLUNA 2 DA FONTE ÚNICA PERGUNTA ISSO, não qual dos dois -- porque quem
    a lê do outro lado é o nó do n8n, e ele só decide "isto vai ao
    publicador". Qual grupo recebe é decisão de lá.

    Desde 27/09 são DUAS portas no Python (o de Anunciar Easy e o de Oferta e
    Busca), então a comparação é com a UNIÃO. Antes era uma regex só.
    """
    return bool(_AP_EASY.match(t)
                or (_AP_BUSCA.search(t) and _VERBO.match(t)))
# A TERCEIRA COLUNA diz se o ramo de POSTA do nó do n8n já pega a frase. O
# PYTHON casa todas -- ele é um dispatch só, não há o que duplicar. O literal
# do NÓ é que tem de ficar de fora dessas, senão o publicador é chamado duas
# vezes (o estrago de 25/09, ver `patch_telefone_na_frente_n8n.js`).
_casos = _json.load(open("casos_alto_padrao.json", encoding="utf-8"))
_maus = 0
for _t, _esp, _posta in _casos:
    _got = _e_comando_de_alto_padrao(_t)
    if _got != _esp:
        _maus += 1
        print(f"  FALHOU {_t!r} -> {_got}, esperava {_esp}")
assert not _maus, f"{_maus} divergencias entre o Python e os casos"
print(f"  OK   os {len(_casos)} casos da fonte unica batem no Python")

print()
print("--- AS CINCO FRASES DELE para o OFERTA e BUSCA, e as variantes ---")
# Tel, 27/09, com o espaço duplo que o WhatsApp dele manda.
import datetime as _dt
_DIAS = {0: "dom", 1: "seg", 2: "ter", 3: "qua", 4: "qui", 5: "sex", 6: "sab"}


def _agenda(frase):
    r = ic(frase) or {}
    if r.get("acao") != "criar_vaga" or r.get("destino") != "alto_padrao":
        return r.get("acao")
    d = r.get("dias_semana")
    return (",".join(_DIAS[x] for x in d) if d else r.get("tipo_recorrencia"),
            str(r.get("horario")), r.get("codigos"))


for _f, _e in [
    ("posta 5750 no grupo alto padrão todo dia as 12:30", ("diaria", "12:30:00")),
    ("posta 5750 no grupo  padrão segunda, quarta e sexta as 08", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo  padrão o 5750 seg, qua e sex as 8h", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo  padrão o 5750 as 08:00 segunda, quarta e sexta", ("seg,qua,sex", "08:00:00")),
    ("posta no grupo  padrão o 5750 todo sabado as 10h", ("sab", "10:00:00")),
    # variantes
    ("posta no grupo padrão o 5750 todo dia as 12:30", ("diaria", "12:30:00")),
    ("posta nos grupos padrão o 5750 todo dia as 8h", ("diaria", "08:00:00")),
    ("Nay posta no alto padrão o 5750 terça e quinta as 14h", ("ter,qui", "14:00:00")),
    ("manda no grupo alto padrão o 5750 todo dia as 8h", ("diaria", "08:00:00")),
    ("envia para o grupo padrão o 5750 de segunda a sexta as 7h",
     ("seg,ter,qua,qui,sex", "07:00:00")),
    ("publica no grupo padrão o 5750 às segundas, quartas e sextas às 8h",
     ("seg,qua,sex", "08:00:00")),
    ("posta no grupo padrão o 5750 todo dia as 8 da manha", ("diaria", "08:00:00")),
    ("posta no grupo padrão o 5750 as 12:30 todo dia", ("diaria", "12:30:00")),
    ("posta no grupo padrão o 5750 todo dia as 19", ("diaria", "19:00:00")),
]:
    checar(_f[:56], _agenda(_f), _e + (["5750"],))

print()
print("--- a FAIXA vale nos dois grupos, lida do próprio grupo ---")
# Os dois têm 6.500 de aluguel e 1.000.000 de venda em `grupos`. Ler dali em
# vez de escrever o número aqui é o que impede duas definições de "alto
# padrão" divergindo -- e muda com UPDATE, sem deploy.
import publicador as _pub

_pedidos = []


class _ConnFaixa:
    def __init__(self, grupo, imovel):
        self.grupo, self.imovel = grupo, imovel

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                if "FROM grupos" in sql:
                    _pedidos.append(params[0])
                    s.r = conn.grupo
                else:
                    s.r = conn.imovel

            def fetchone(s):
                return s.r
        return C()


GRUPO = {"nome": "🟢 Alto Padrão - OFERTA e BUSCA 🔍",
         "aluguel_minimo": 6500, "venda_minima": 1000000}
checar("o 5750 (3,9M de venda) passa",
       _pub._abaixo_da_faixa(_ConnFaixa(GRUPO, {"valor_aluguel": None,
                                                "valor_venda": 3900000.0,
                                                "condominio_nome": "Alphaville 2"}),
                             "5750", "alto_padrao"),
       None)
_r = _pub._abaixo_da_faixa(_ConnFaixa(GRUPO, {"valor_aluguel": 2500.0,
                                              "valor_venda": None,
                                              "condominio_nome": "X"}),
                           "4255", "alto_padrao")
checar("e um de 2.500 de aluguel é recusado", bool(_r), True)
checar("  dizendo o valor e a faixa",
       bool(_r) and "2.500" in _r and "6.500" in _r, True)
# A PAREDE PERGUNTA AO GRUPO CERTO: com o apelido trocado ela leria os pisos
# do outro grupo, e os dois têm os mesmos números hoje -- o teste pegaria a
# troca só por este `assert`, não pelo resultado.
_pedidos.clear()
_pub._abaixo_da_faixa(_ConnFaixa(GRUPO, None), "5750", "alto_padrao_easy")
checar("consulta o grupo pelo apelido recebido", _pedidos, ["alto_padrao_easy"])

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO GRUPO ALTO PADRÃO PASSARAM")
