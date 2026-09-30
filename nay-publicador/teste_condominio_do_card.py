"""
Prova que o nome do condomínio volta ao título do card.

O CASO (Tel, 24/09): o 5749 (sala no Soberane, Adrianópolis) foi para 16
grupos como "📍 Sala bairro Adrianópolis". Ele queria "📍 Soberane".

A CAUSA: o card lê a página AO VIVO (`buscar_imovel`), e a página do 5749 não
publica o campo de condomínio -- devolve `condominio: None`. Quem sabe o nome
é a TABELA (`condominio_nome`), preenchida pela varredura, que lê a LISTAGEM.
Duas fontes para o mesmo dado, e o título usava só uma.

QUEM JULGA SE O NOME PRESTA É O BANCO, e isso é o mais importante daqui:
`nay_condominio_de_verdade(tipo, condominio_nome)` já existia e já é usada
pela busca da Nay. Medido em 24/09: de 14 imóveis sorteados cuja tabela tem
`condominio_nome`, DOIS não tinham o campo na página -- e nos dois o valor da
tabela era **"Casa"**, o tipo, não um condomínio. No catálogo inteiro são 77
linhas assim (59 "Casa", 8 "Apartamento", 5 "Prédio", 4 "Casa de Condomínio",
1 "Flat"). Sem o filtro, o card cairia de "Casa bairro Flores" para
"📍 Casa" -- que identifica MENOS -- em 55 imóveis ofertáveis.

Escrever esse julgamento de novo em Python seria a sexta cópia de uma regra de
casamento, o padrão que o HISTORICO registra. Por isso o teste **não** testa
uma cópia: testa que o helper PERGUNTA ao banco e obedece à resposta.

Uso:
    .venv/bin/python teste_condominio_do_card.py
"""
from montar_mensagem import _titulo
from publicador import _com_condominio_do_banco

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


class CursorFake:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        # A PERGUNTA TEM QUE SER AO BANCO. Se um dia alguém trocar isto por
        # uma cópia em Python, este teste fica vermelho -- que é o ponto.
        assert "nay_condominio_de_verdade(tipo, condominio_nome)" in s, s
        self.conn.perguntou.append(params[0])
        if self.conn.explode:
            raise RuntimeError("banco caiu")

    def fetchone(self):
        return {"nome": self.conn.resposta}


class ConnFake:
    def __init__(self, resposta=None, explode=False):
        self.resposta = resposta
        self.explode = explode
        self.perguntou = []

    def cursor(self):
        return CursorFake(self)

    def close(self):
        pass


SALA = {"codigo": "5749", "condominio": None, "tipo": "Sala",
        "bairro": "Adrianópolis"}


def card(imovel):
    return _titulo(imovel)


print("--- a página não publica o condomínio: o banco completa ---")
conn = ConnFake(resposta="Soberane")
i = _com_condominio_do_banco(dict(SALA), conn)
checar("perguntou ao banco pelo código certo", conn.perguntou, ["5749"])
checar("o condomínio entrou", i["condominio"], "Soberane")
checar("e o título é o do Tel", card(i), "Soberane")

print()
print("--- o banco diz que o nome NÃO presta: o título não piora ---")
# É o que `nay_condominio_de_verdade` devolve para "Casa", "Apartamento",
# "Prédio" e os outros 77 rótulos do catálogo: NULL.
conn = ConnFake(resposta=None)
i = _com_condominio_do_banco(dict(SALA), conn)
checar("nada foi posto", i["condominio"], None)
checar("o título segue identificando pelo bairro",
       card(i), "Sala bairro Adrianópolis")

print()
print("--- string vazia do banco também não vira título ---")
conn = ConnFake(resposta="   ")
i = _com_condominio_do_banco(dict(SALA), conn)
checar("continua sem condomínio", i["condominio"], None)

print()
print("--- quando a PÁGINA já traz o nome, o banco nem é consultado ---")
# A página é a fonte mais fresca: o Tel renomeia lá e o card acompanha na
# hora, sem esperar a varredura da hora seguinte.
conn = ConnFake(resposta="Nome Velho Do Banco")
i = _com_condominio_do_banco(
    {"codigo": "5718", "condominio": "Arezzo Residencial",
     "tipo": "Apartamento", "bairro": "Flores"}, conn)
checar("não perguntou nada", conn.perguntou, [])
checar("manteve o da página", i["condominio"], "Arezzo Residencial")

print()
print("--- FALHA FECHADA: banco fora do ar não derruba o disparo ---")
# Título é cosmética. Deixar de postar em 16 grupos por causa dele seria pior
# que o título feio -- e este caminho roda no meio de um envio já começado.
conn = ConnFake(resposta="Soberane", explode=True)
i = _com_condominio_do_banco(dict(SALA), conn)
checar("devolveu o imóvel inteiro", i["codigo"], "5749")
checar("sem condomínio, como antes do patch", i["condominio"], None)
checar("e o card ainda sai", card(i), "Sala bairro Adrianópolis")

print()
print("--- imóvel vazio ou sem código não quebra ---")
checar("None", _com_condominio_do_banco(None, ConnFake()), None)
checar("dict vazio", _com_condominio_do_banco({}, ConnFake()), {})
conn = ConnFake(resposta="Soberane")
_com_condominio_do_banco({"condominio": None, "tipo": "Sala"}, conn)
checar("sem código, pergunta com string vazia e não explode",
       conn.perguntou, [""])

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO CONDOMÍNIO DO CARD PASSARAM")
