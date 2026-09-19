"""
Testa a entrega automática sem banco, sem Z-API e sem relógio de parede.

POR QUE ESTE ARQUIVO EXISTE: era o único dos crons sem suíte, e foi
justamente nele que a auditoria de 01/09 achou o pior bug do dia --
falha no meio da entrega devolvia a dívida INTEIRA, e como o cron roda de
minuto em minuto o corretor recebia a frase de abertura e os cards já
entregues de novo, a cada minuto. Até 720 vezes por dia.

O QUE PRECISA SER PROVADO:

  * JANELA de horário: dívida criada às 23h50 não vira card às 23h53.
  * RESERVA: zero reservado = outra execução pegou = não envia.
  * FALHA NA ABERTURA devolve tudo -- nada saiu.
  * FALHA NO MEIO devolve SÓ o que não saiu. É o bug de 01/09.
  * o que saiu fica em `envios`, senão a dívida renasce.
  * SILÊNCIO quando não há nada.

Uso:
    .venv/bin/python teste_entregar_pendentes.py
"""
import datetime
from zoneinfo import ZoneInfo

import entregar_pendentes as ep

FUSO = ZoneInfo("America/Manaus")
MEIO_DIA = datetime.datetime(2026, 9, 1, 12, 0, tzinfo=FUSO)
MADRUGADA = datetime.datetime(2026, 9, 1, 3, 0, tzinfo=FUSO)

falhas = 0
enviados = []


def checar(rotulo, condicao, detalhe=""):
    global falhas
    ok = bool(condicao)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {rotulo}")
    if not ok and detalhe:
        print(f"         {detalhe}")


class CursorFalso:
    def __init__(self, c):
        self.c = c
        self.r = None
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append((sql, params))
        if "atendimento_pausado" in sql:
            # A pausa geral. Sem esta linha o cursor devolvia None, que o
            # `atendimento_pausado` lê como PAUSADO (falha fechada) -- e
            # toda entrega ficava muda no teste.
            self.r = {"pausado": self.c.pausado}
        elif "nay_entregas_devidas" in sql:
            self.linhas = self.c.devidas
        elif "nay_reservar_entregas" in sql:
            self.r = {"n": self.c.reserva}
        elif "nay_devolver_entregas" in sql:
            self.c.devolvidos.append(params[0])
            self.r = {"n": len(params[0])}
        else:
            self.r = None

    def fetchone(self):
        return self.r

    def fetchall(self):
        return self.linhas


class ConexaoFalsa:
    def __init__(self, devidas=None, reserva=1, pausado=False):
        self.pausado = pausado
        self.devidas = devidas or []
        self.reserva = reserva
        self.sql = []
        self.devolvidos = []
        self.commits = 0

    def cursor(self):
        return CursorFalso(self)

    def commit(self):
        self.commits += 1


DUAS = [{"telefone": "559286034966", "ids": [11, 12], "codigos": "4946,3471",
         "abertura": "Gustavo, segue as opções que fiquei de te enviar 👇"}]

ep.buscar_imovel = lambda cod: {"codigo": cod, "fotos": ["u1", "u2"]}
ep.montar_mensagem = lambda imovel, neg: "card do " + str(imovel["codigo"])


def texto_ok(tel, msg):
    enviados.append(("texto", tel, msg))


def imovel_ok(tel, msg, fotos):
    enviados.append(("imovel", tel, msg))


ep.enviar_texto = texto_ok
ep.enviar_imovel = imovel_ok

print("--- fora da janela não entrega ---")
c = ConexaoFalsa(devidas=DUAS)
enviados.clear()
checar("03h não manda card nenhum",
       ep.entregar(c, enviar=True, agora=MADRUGADA) == [] and enviados == [],
       "dívida criada às 23h50 não pode virar 15 fotos às 23h53")

print()
print("--- reserva atômica ---")
c = ConexaoFalsa(devidas=DUAS, reserva=0)
enviados.clear()
ep.entregar(c, enviar=True, agora=MEIO_DIA)
checar("reserva zero NÃO envia", enviados == [])

print()
print("--- entrega completa ---")
c = ConexaoFalsa(devidas=DUAS)
enviados.clear()
r = ep.entregar(c, enviar=True, agora=MEIO_DIA)
checar("manda a abertura uma vez",
       sum(1 for e in enviados if e[0] == "texto") == 1)
checar("manda os dois cards",
       sum(1 for e in enviados if e[0] == "imovel") == 2)
checar("registra os dois em envios",
       sum(1 for s, _ in c.sql if "INSERT INTO envios" in s) == 2)
checar("nada devolvido", c.devolvidos == [])
checar("marca o contato do dia",
       any("contato_corretor" in s for s, _ in c.sql))

print()
print("--- a ABERTURA falha: devolve tudo ---")
def texto_falha(tel, msg):
    raise RuntimeError("Z-API fora do ar")

ep.enviar_texto = texto_falha
c = ConexaoFalsa(devidas=DUAS)
enviados.clear()
r = ep.entregar(c, enviar=True, agora=MEIO_DIA)
checar("devolve os dois ids", c.devolvidos == [[11, 12]], str(c.devolvidos))
checar("nenhum card saiu", not any(e[0] == "imovel" for e in enviados))
ep.enviar_texto = texto_ok

print()
print("--- falha NO MEIO devolve só o que não saiu ---")
# O bug de 01/09: devolvia [11,12] e no minuto seguinte o corretor recebia
# a abertura e o card do 4946 outra vez, e outra, e outra.
estado = {"n": 0}


def imovel_falha_no_segundo(tel, msg, fotos):
    estado["n"] += 1
    if estado["n"] == 2:
        raise RuntimeError("Z-API caiu no segundo")
    enviados.append(("imovel", tel, msg))


ep.enviar_imovel = imovel_falha_no_segundo
c = ConexaoFalsa(devidas=DUAS)
enviados.clear()
r = ep.entregar(c, enviar=True, agora=MEIO_DIA)
checar("o primeiro card saiu", sum(1 for e in enviados if e[0] == "imovel") == 1)
checar("devolve SÓ o segundo id", c.devolvidos == [[12]],
       f"devolveu {c.devolvidos} — devolver [11,12] reenvia a abertura e o "
       f"card já entregue a cada minuto")
checar("o entregue ficou em envios",
       sum(1 for s, _ in c.sql if "INSERT INTO envios" in s) == 1)
checar("o resultado diz que foi parcial",
       r and r[0][2].startswith("parcial"))
ep.enviar_imovel = imovel_ok

print()
print("--- silêncio quando não há nada ---")
c = ConexaoFalsa()
enviados.clear()
checar("nada devido, nada enviado",
       ep.entregar(c, enviar=True, agora=MEIO_DIA) == [] and enviados == [])

print()
print("--- simulação não manda ---")
c = ConexaoFalsa(devidas=DUAS)
enviados.clear()
r = ep.entregar(c, enviar=False, agora=MEIO_DIA)
checar("lista mas não envia",
       len(r) == 1 and r[0][2] == "simulado" and enviados == [])

print("--- a pausa geral vale aqui também ---")
# O CLAUDE.md sempre disse que pausada "nenhum corretor recebe nada", e não
# era verdade: este cron ignorava a chave. Em 02/09 o Tel pausou porque ela
# estava respondendo mal, e continuou saindo imóvel por aqui.
c = ConexaoFalsa(devidas=DUAS, pausado=True)
enviados.clear()
checar("pausada, nada é entregue",
       ep.entregar(c, enviar=True, agora=MEIO_DIA) == [] and enviados == [])

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
