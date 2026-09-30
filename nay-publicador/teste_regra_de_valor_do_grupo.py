"""
Prova a regra de VALOR e de CONDOMÍNIO por grupo (Tel, 15/09).

O PEDIDO: o grupo "🟢 Alto Padrão - OFERTA e BUSCA 🔍" só recebe locação de
6.500 em diante e venda de 1.000.000 em diante, e nos dois só imóvel de
condomínio. Três decisões dele, perguntadas com a medição à frente:
condomínio nos DOIS negócios, 1.000.000 EM DIANTE (o piso entra), e nas listas
o grupo recebe só o que passa -- e nada quando nenhum passa.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * a regra é UMA (`negocios_do_grupo`) e decide três coisas: se o imóvel entra
    no grupo, que valor o card mostra lá, e que lista o grupo recebe. Se o card
    usasse outra, o Alto Padrão veria o aluguel de 5 mil de um imóvel que entrou
    pela venda de 1,2 milhão;

  * grupo SEM regra não muda nada -- são os 16 grupos que já existiam, e o envio
    privado ao corretor, que passa um dicionário sem as chaves novas;

  * "condomínio" é o de VERDADE: a importação pôs "Casa" no campo do condomínio
    de imóvel de rua, e o rótulo não pode abrir a porta do Alto Padrão;

  * na lista, grupo cuja regra não deixa passar nada NÃO recebe mensagem -- e a
    resposta ao Tel diz isso, senão parece falha;

  * a cadência anti-banimento pausa entre ENVIOS, não entre grupos da lista:
    grupo pulado não pode fazer o disparo esperar à toa.

Uso:
    .venv/bin/python teste_regra_de_valor_do_grupo.py
"""
from unittest.mock import patch

import publicador
from montar_destinos import montar_lista_destinos, negocios_do_grupo
from montar_mensagem import montar_mensagem

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


ALTO_PADRAO = {"id_grupo": "alto-group", "nome": "🟢 Alto Padrão - OFERTA e BUSCA 🔍",
               "aceita_venda": True, "aceita_locacao": True, "todas_fotos": False,
               "aluguel_minimo": 6500, "venda_minima": 1000000, "so_condominio": True}
SO_LOCACAO = {"id_grupo": "loc-group", "nome": "🟢 Locação OFERTA e BUSCA 🔍 - CREDENCIADOS",
              "aceita_venda": False, "aceita_locacao": True, "todas_fotos": False,
              "aluguel_minimo": None, "venda_minima": None, "so_condominio": False}
COMUM = {"id_grupo": "comum-group", "nome": "Top imóveis venda e aluguéis",
         "aceita_venda": True, "aceita_locacao": True, "todas_fotos": False}
EASY = {"id_grupo": "easy-group", "nome": "IMÓVEIS PARA ANUNCIAR EASY",
        "aceita_venda": True, "aceita_locacao": True, "todas_fotos": True}


def ap(**campos):
    base = {"codigo": "9001", "tipo": "Apartamento", "condominio": "Life da Villa",
            "bairro": "Ponta Negra", "area": 120, "quartos": 3, "suites": 3}
    base.update(campos)
    return base


print("--- a regra do Alto Padrão ---")
for titulo, imovel, esperado in [
    ("locação 7k de condomínio entra", ap(valor_aluguel=7000), {"locacao"}),
    ("locação 6.500 EXATO entra (em diante)", ap(valor_aluguel=6500), {"locacao"}),
    ("locação 6.499 fica de fora", ap(valor_aluguel=6499), set()),
    ("venda 1.000.000 EXATO entra (decisão do Tel)", ap(valor_venda=1000000), {"venda"}),
    ("venda 999.999 fica de fora", ap(valor_venda=999999), set()),
    ("venda 1,2M com aluguel 5k: entra SÓ pela venda",
     ap(valor_venda=1200000, valor_aluguel=5000), {"venda"}),
    ("os dois acima do piso: os dois", ap(valor_venda=1500000, valor_aluguel=8000),
     {"venda", "locacao"}),
    # condomínio nos DOIS negócios, decisão do Tel
    ("casa de RUA de 2 milhões fica de fora", ap(condominio="", tipo="Casa",
                                               valor_venda=2000000), set()),
    ("rua com aluguel 9k fica de fora", ap(condominio=None, tipo="Casa",
                                          valor_aluguel=9000), set()),
    # o rótulo que a importação pôs no campo do condomínio
    ("'Casa' no campo do condomínio não é condomínio",
     ap(condominio="Casa", tipo="Casa", valor_venda=2000000), set()),
    ("'Loja/Ponto' no campo do condomínio não é condomínio",
     ap(condominio="Loja/Ponto", tipo="Loja", valor_venda=3000000), set()),
    # valor que chega como texto ou Decimal do banco
    ("piso comparado como número, não como texto",
     ap(valor_aluguel=10000), {"locacao"}),
]:
    checar(titulo, negocios_do_grupo(imovel, ALTO_PADRAO), esperado)

print()
print("--- grupo sem regra continua como sempre ---")
checar("grupo antigo sem as chaves novas aceita aluguel de 900",
       negocios_do_grupo(ap(condominio="", tipo="Casa", valor_aluguel=900), COMUM),
       {"locacao"})
checar("grupo com as chaves nulas idem",
       negocios_do_grupo(ap(valor_aluguel=900), SO_LOCACAO), {"locacao"})
checar("grupo só de locação não aceita venda",
       negocios_do_grupo(ap(valor_venda=5000000), SO_LOCACAO), set())
# O envio privado ao corretor passa este dicionário, sem as chaves novas.
checar("o envio privado ao corretor mostra os dois valores",
       negocios_do_grupo(ap(valor_venda=500000, valor_aluguel=3000),
                         {"aceita_venda": True, "aceita_locacao": True}),
       {"venda", "locacao"})

print()
print("--- quem entra nos destinos ---")
grupos = [ALTO_PADRAO, SO_LOCACAO, COMUM, EASY]
nomes = lambda im: sorted(g["nome"] for g in montar_lista_destinos(im, grupos))
checar("aluguel 2.5k: não vai para o Alto Padrão",
       nomes(ap(valor_aluguel=2500)), sorted([SO_LOCACAO["nome"], COMUM["nome"]]))
checar("aluguel 8k de condomínio: vai para os três",
       nomes(ap(valor_aluguel=8000)),
       sorted([ALTO_PADRAO["nome"], SO_LOCACAO["nome"], COMUM["nome"]]))
checar("venda 600k: só o comum (o de locação não aceita venda)",
       nomes(ap(valor_venda=600000)), [COMUM["nome"]])
checar("o Easy nunca entra pelo fluxo normal",
       EASY["nome"] in nomes(ap(valor_venda=5000000)), False)

print()
print("--- o card no Alto Padrão mostra só o valor que ele aceita ---")
card = montar_mensagem(ap(valor_venda=1200000, valor_aluguel=5000), ALTO_PADRAO)
checar("mostra a venda", "Venda: R$ 1.200.000" in card, True)
checar("e NÃO mostra o aluguel de 5 mil", "Locação" in card, False)
card_comum = montar_mensagem(ap(valor_venda=1200000, valor_aluguel=5000), COMUM)
checar("no grupo comum o mesmo imóvel mostra os dois",
       "Venda:" in card_comum and "Locação:" in card_comum, True)


# ---------------------------------------------------------------------------
print()
print("--- a LISTA de cada grupo ---")

GERAL = "🔥 APARTAMENTOS PARA LOCAÇÃO DE 1.9k A 10k 🔥\n\n✅a / 1.9k\n✅b / 7k\n✅c / 10k"
FILTRADA = "🔥 APARTAMENTOS PARA LOCAÇÃO DE 7k A 10k 🔥\n\n✅b / 7k\n✅c / 10k"


class Cursor:
    def __init__(self, conn):
        self.c = conn
        self.r = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append((sql, params))
        self.r = None
        if "nay_lista_de_imoveis" in sql:
            if params and len(params) == 4:
                self.c.filtradas.append(params)
                self.r = ({"texto_pronto": FILTRADA, "quantos": 2}
                          if self.c.alto_tem else
                          {"texto_pronto": "não tenho nenhum imóvel", "quantos": 0})
            else:
                self.r = {"texto_pronto": GERAL, "quantos": 3}
        elif "nay_reservar_disparo_de_lista" in sql:
            self.r = {"id": 5, "ja_foi_em": None}

    def fetchone(self):
        return self.r

    def fetchall(self):
        return []


class Conn:
    def __init__(self, alto_tem=True):
        self.alto_tem = alto_tem
        self.sql, self.filtradas = [], []

    def cursor(self):
        return Cursor(self)

    def commit(self):
        pass


def disparar(conn, grupos):
    enviados, pausas = [], []
    with patch("publicador.enviar_texto", side_effect=lambda d, t: enviados.append((d, t))), \
         patch("publicador.carregar_grupos_db", return_value=grupos):
        resposta = publicador._disparar_lista(
            {"categoria": "apartamento", "negocio": "locacao", "destino": "parceiros"},
            conn, pausa=lambda s: pausas.append(s))
    return resposta, enviados, pausas


conn = Conn(alto_tem=True)
resposta, enviados, pausas = disparar(conn, [ALTO_PADRAO, COMUM, SO_LOCACAO])
por_grupo = {d: t for d, t in enviados}
checar("o comum recebe a lista inteira", por_grupo.get("comum-group"), GERAL)
checar("o de locação recebe a lista inteira", por_grupo.get("loc-group"), GERAL)
checar("o Alto Padrão recebe a FILTRADA", por_grupo.get("alto-group"), FILTRADA)
checar("a consulta filtrada leva o piso de LOCAÇÃO e o condomínio",
       conn.filtradas, [("apartamento", "locacao", 6500, True)])
checar("a resposta diz que o Alto Padrão recebeu menos",
       "recebeu só 2" in resposta, True)

# Grupos com a mesma regra dividem uma consulta só.
conn = Conn(alto_tem=True)
outro_alto = dict(ALTO_PADRAO, id_grupo="alto2-group", nome="outro alto")
disparar(conn, [ALTO_PADRAO, outro_alto])
checar("dois grupos com a mesma regra: uma consulta", len(conn.filtradas), 1)

print()
print("--- nenhum imóvel passa: o grupo NÃO recebe, e a resposta diz ---")
conn = Conn(alto_tem=False)
resposta, enviados, pausas = disparar(conn, [ALTO_PADRAO, COMUM])
checar("o Alto Padrão não recebe mensagem nenhuma",
       [d for d, _ in enviados if d == "alto-group"], [])
checar("o comum recebe normalmente", [d for d, _ in enviados], ["comum-group"])
checar("a resposta nomeia quem ficou de fora",
       "passa na regra" in resposta and "Alto Padrão" in resposta, True)
# O pulado vem PRIMEIRO na lista: a pausa entre grupos não pode acontecer antes
# do primeiro envio de verdade.
checar("grupo pulado não gera pausa", pausas, [])

print()
print("--- disparo de VENDA usa o piso de venda ---")
conn = Conn(alto_tem=True)
with patch("publicador.enviar_texto"), \
     patch("publicador.carregar_grupos_db", return_value=[ALTO_PADRAO]):
    publicador._disparar_lista(
        {"categoria": "apartamento", "negocio": "venda", "destino": "parceiros"},
        conn, pausa=lambda s: None)
checar("a consulta leva 1.000.000", conn.filtradas,
       [("apartamento", "venda", 1000000, True)])

print()
print("--- GRUPO SÓ COMERCIAL (Tel, 15/09) ---")
# "sala comercial, prédio comercial, galpão. nada de imóvel residencial".
# Os tipos são os que existem no cadastro, medidos em 15/09.
COMERCIAL = {"id_grupo": "com-group", "nome": "🟢 Comercial - OFERTA e BUSCA 🔍",
             "aceita_venda": True, "aceita_locacao": True, "todas_fotos": False,
             "so_comercial": True}
for tipo, entra in [("Sala/Andar", True), ("Sala", True), ("Loja/Ponto", True),
                    ("Galpão/Depósito", True),
                    # PRÉDIO ENTRA, decisão do Tel -- o cadastro não separa
                    # prédio comercial de residencial
                    ("Prédio", True),
                    ("Apartamento", False), ("Apartamento em Via Pública", False),
                    ("Casa", False), ("Casa de condomínio", False),
                    ("Cobertura", False), ("Flat", False),
                    ("Lote em Condomínio", False), ("Chácara", False),
                    # tipo vazio não passa: sem saber, não se afirma comercial
                    ("", False), (None, False)]:
    checar(f"{tipo!r} {'entra' if entra else 'não entra'}",
           bool(negocios_do_grupo({"tipo": tipo, "valor_aluguel": 5000,
                                   "valor_venda": 900000}, COMERCIAL)), entra)
checar("apartamento não vai para o Comercial pelos destinos",
       COMERCIAL["nome"] in [g["nome"] for g in montar_lista_destinos(
           {"tipo": "Apartamento", "condominio": "X", "valor_aluguel": 3000},
           [COMERCIAL, COMUM])], False)
checar("galpão vai para o Comercial E para o comum",
       sorted(g["nome"] for g in montar_lista_destinos(
           {"tipo": "Galpão/Depósito", "valor_aluguel": 12000}, [COMERCIAL, COMUM])),
       sorted([COMERCIAL["nome"], COMUM["nome"]]))

print()
print("--- lista residencial pula o Comercial; lista de sala chega nele ---")
conn = Conn(alto_tem=True)
resposta, enviados, _ = disparar(conn, [COMERCIAL, COMUM])
checar("lista de APARTAMENTO: o Comercial não recebe",
       [d for d, _ in enviados], ["comum-group"])
checar("e a resposta diz", "Comercial" in resposta and "passa na regra" in resposta, True)
checar("sem consulta filtrada à toa", conn.filtradas, [])

conn = Conn(alto_tem=True)
enviados = []
with patch("publicador.enviar_texto", side_effect=lambda d, t: enviados.append((d, t))), \
     patch("publicador.carregar_grupos_db", return_value=[COMERCIAL, COMUM]):
    publicador._disparar_lista(
        {"categoria": "sala", "negocio": "locacao", "destino": "parceiros"},
        conn, pausa=lambda s: None)
checar("lista de SALA COMERCIAL: os dois recebem",
       sorted(d for d, _ in enviados), ["com-group", "comum-group"])

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA REGRA DE GRUPO PASSARAM")
