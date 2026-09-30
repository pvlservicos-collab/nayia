"""
Prova que quem NÃO falou com a Nay hoje recebe saudação, e quem está no meio
de uma conversa não recebe.

O PEDIDO (Tel, 23/09): mandando o MESMO imóvel para duas corretoras no mesmo
comando, ele separou os casos com as próprias palavras -- "o da Geina ela já
está em contato então ela tem que mandar normal o imóvel, mas no segundo
92 8644-8395 ... não foi falado nada de mensagem no dia, então ela manda:
oi boa tarde! segue a opção de imóvel que fiquei de te enviar".

Os dois erros que isto evita são opostos e os dois já foram reclamados:
  * card caindo sem uma palavra em volta (31/08, o caso do Gustavo);
  * cumprimento formal no meio de uma conversa viva, que soa telegrama.

O DIA É O DE MANAUS. O servidor roda em UTC: entre 20h e meia-noite daqui, a
data de lá já virou, e quem acabou de falar com ela seria tratado como quem
sumiu há dias. Foi o mesmo tropeço da agenda de visitas em 11/09.

Uso:
    .venv/bin/python teste_saudacao_do_envio.py
"""
import datetime
from zoneinfo import ZoneInfo

import publicador

FUSO = ZoneInfo("America/Manaus")
falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = str(obtido) == str(esperado)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


print("--- a saudação sai pela hora de MANAUS, não do servidor ---")
for h, esperado in ((0, "bom dia"), (8, "bom dia"), (11, "bom dia"),
                    (12, "boa tarde"), (13, "boa tarde"), (17, "boa tarde"),
                    (18, "boa noite"), (23, "boa noite")):
    checar(f"{h:02d}h em Manaus",
           publicador._saudacao(datetime.datetime(2026, 9, 23, h, 0, tzinfo=FUSO)),
           esperado)

# 23h em Manaus é 03h do DIA SEGUINTE em UTC. Se a saudação olhasse o relógio
# do servidor, sairia "bom dia" para quem está de madrugada.
checar("23h de Manaus não vira 'bom dia' (o servidor está em UTC)",
       publicador._saudacao(
           datetime.datetime(2026, 9, 24, 3, 0, tzinfo=datetime.timezone.utc)),
       "boa noite")


class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        self.linhas = []
        # AS DUAS CONSULTAS LEEM `mensagens`, e o falso precisa separá-las.
        # Enquanto ele respondia pelo prefixo comum, a de "pediu fotos"
        # herdava a resposta de `falou_hoje` -- e os dois casos de conversa
        # viva passaram a receber a frase de quem pediu. Falso que não
        # distingue as consultas testa a si mesmo, não o código.
        if "nai_pede_foto" in s:
            assert "America/Manaus" in s, "a consulta perdeu o fuso de Manaus"
            self.linhas = [{"?column?": 1}] if self.conn.pediu else []
        elif "FROM mensagens" in s:
            # A CONSULTA TEM QUE COMPARAR O DIA DE MANAUS. Sem isto o teste
            # passaria com uma consulta que usa `current_date` do servidor.
            assert "America/Manaus" in s, "a consulta perdeu o fuso de Manaus"
            self.linhas = [{"?column?": 1}] if self.conn.falou_hoje else []

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class ConnFake:
    def __init__(self, falou_hoje, pediu=False):
        self.falou_hoje = falou_hoje
        self.pediu = pediu

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass


print()
print("--- quem falou hoje NÃO é cumprimentado de novo ---")
checar("conversa viva", publicador._falou_com_ela_hoje(ConnFake(True), "559291824643"), True)
checar("silêncio hoje", publicador._falou_com_ela_hoje(ConnFake(False), "559286448395"), False)

print()
print("--- a abertura de cada uma, de ponta a ponta ---")
enviados = []
publicador.enviar_texto = lambda d, t: enviados.append((d, t))
publicador.buscar_imovel = lambda c: None        # o laço para antes de enviar imóvel


def abertura(falou_hoje, nome, codigos=("5747",)):
    enviados.clear()
    publicador._mandar_os_codigos(ConnFake(falou_hoje), "559200000000", nome,
                                  list(codigos))
    return enviados[0][1] if enviados else "(nada)"


# A Geina está em contato: vai direto, com o vocativo de sempre.
a = abertura(True, "Geina Almeida")
checar("quem está em contato não recebe 'oi'", "oi," in a, False)
checar("  e mantém o vocativo", a.startswith("Geina, segue"), True)

# A Wal não falou hoje: recebe a saudação. O vocativo sai, porque "oi, boa
# tarde! Wal, segue" empilha dois cumprimentos na mesma linha.
b = abertura(False, "Wal Pimenta")
checar("quem não falou hoje recebe 'oi'", b.startswith("oi, "), True)
checar("  com a saudação da hora", any(x in b for x in
       ("bom dia", "boa tarde", "boa noite")), True)
checar("  e sem empilhar vocativo", "Wal," in b, False)
checar("  dizendo o que vem", "que fiquei de te enviar" in b, True)

# Mais de um imóvel muda o plural nos dois caminhos.
checar("plural com conversa viva",
       "as opções que fiquei" in abertura(True, "Geina", ("5747", "5748")), True)
checar("plural sem conversa",
       "as opções que fiquei" in abertura(False, "Wal", ("5747", "5748")), True)

print()
print()
print("--- QUEM PEDIU RECEBE RESPOSTA, não anúncio (Tel, 27/09) ---")
# A Adriana Farias escreveu "Manda as fotos por gentileza. Obrigada" e oito
# minutos depois ele mandou o comando. A frase de quem manda sem ser pedido
# ("segue o imóvel que fiquei de te enviar") soa estranha para quem acabou de
# pedir -- ele escreveu a que quer, e ela começa com "claro".
enviados.clear()
publicador._mandar_os_codigos(ConnFake(falou_hoje=False, pediu=True),
                              "559281101119", "Adriana Farias Ramos", ["3210"])
checar("1a do dia + pediu: saudação em linha própria",
       enviados[0][1], "Oi, boa tarde!\nclaro, segue as informações e as fotos."
       if "tarde" in enviados[0][1] else enviados[0][1])
checar("  a saudação abre com maiúscula", enviados[0][1][0], "O")
checar("  e a segunda linha é a resposta ao pedido",
       enviados[0][1].split("\n")[1], "claro, segue as informações e as fotos.")
checar("  sem o 👇 de quem manda sem ser pedido", "👇" in enviados[0][1], False)

# NO MEIO DA CONVERSA não cumprimenta de novo -- é a regra de 23/09, e ela
# continua valendo; muda só a frase, que passa a responder ao pedido.
enviados.clear()
publicador._mandar_os_codigos(ConnFake(falou_hoje=True, pediu=True),
                              "559281101119", "Adriana Farias Ramos", ["3210"])
checar("conversa viva + pediu: sem saudação",
       enviados[0][1], "Claro, segue as informações e as fotos.")

# E QUEM NÃO PEDIU continua recebendo a frase de sempre, nos dois casos --
# é o que protege a regra de 23/09 de ser atropelada por esta.
enviados.clear()
publicador._mandar_os_codigos(ConnFake(falou_hoje=True, pediu=False),
                              "559281101119", "Adriana Farias Ramos", ["3210"])
checar("conversa viva, não pediu: frase de sempre",
       enviados[0][1], "Adriana, segue o imóvel que fiquei de te enviar 👇")

enviados.clear()
publicador._mandar_os_codigos(ConnFake(falou_hoje=False, pediu=False),
                              "559281101119", "Adriana Farias Ramos", ["3210"])
checar("1a do dia, não pediu: saudação + frase de sempre",
       enviados[0][1].endswith("segue o imóvel que fiquei de te enviar 👇"), True)
checar("  e cumprimenta", enviados[0][1].startswith("oi, "), True)

print()
print("--- banco fora do ar não impede o envio ---")
# A saudação é cortesia: se a consulta falhar, manda sem ela em vez de não
# mandar. É a mesma regra da frase de cortesia, que já era assim.
class ConnQuebrada:
    def cursor(self):
        raise RuntimeError("banco fora do ar")


enviados.clear()
publicador._mandar_os_codigos(ConnQuebrada(), "559200000000", "Wal", ["5747"])
checar("manda mesmo assim", len(enviados), 1)
checar("  sem saudação", enviados[0][1].startswith("Wal, segue"), True)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA SAUDAÇÃO PASSARAM")
