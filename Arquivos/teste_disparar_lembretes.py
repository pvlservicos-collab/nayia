"""
Testa o disparador de lembretes sem tocar banco, Z-API nem rede.

O QUE IMPORTA PROVAR AQUI, e por que cada um já custou caro:

  * a PAUSA é respeitada. O cron é um caminho de saída que não passa pelo
    n8n, então o porteiro de lá não o alcança. Se ele ignorar a pausa, o
    Tel pausa a Nay e mesmo assim corretor recebe mensagem.
  * o HORÁRIO. O Tel recusou janela por dia da semana (domingo vale), mas
    nada pode sair de madrugada.
  * a RESERVA. `postar_agora` já mandou duas vezes neste projeto por não
    ter reserva atômica. Reserva devolvendo zero tem que abortar o envio.
  * a FALHA DE ENVIO devolve o lembrete para 'agendado'. Sem isso, uma
    queda da Z-API consome a tentativa e o corretor nunca é cobrado.
  * SILÊNCIO quando não há nada: roda 1.440x por dia.

Uso:
    .venv/bin/python teste_disparar_lembretes.py
"""
import datetime
from zoneinfo import ZoneInfo

import disparar_lembretes as dl

# Relogio FIXO nos testes de envio: sem isto a suite passa de dia e
# falha a noite, porque `dentro_do_horario` olha o relogio de verdade.
MEIO_DIA = datetime.datetime(2026, 8, 31, 12, 0, tzinfo=ZoneInfo('America/Manaus'))

FUSO = ZoneInfo("America/Manaus")
falhas = 0


def checar(rotulo, condicao, detalhe=""):
    global falhas
    ok = bool(condicao)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {rotulo}")
    if not ok and detalhe:
        print(f"         {detalhe}")


class CursorFalso:
    def __init__(self, conexao):
        self.conexao = conexao
        self.resultado = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.conexao.sql.append((sql, params))
        if "atendimento_pausado" in sql:
            self.resultado = {"pausado": self.conexao.pausado}
        elif "nay_lembretes_devidos" in sql:
            self.resultado = None
        elif "nay_reservar_lembretes" in sql:
            self.resultado = {"n": self.conexao.reserva}
        elif "nay_proximo_toque" in sql:
            self.resultado = {"n": 1}
        else:
            self.resultado = None

    def fetchone(self):
        return self.resultado

    def fetchall(self):
        return self.conexao.devidos


class ConexaoFalsa:
    def __init__(self, pausado=False, devidos=None, reserva=1, sem_config=False):
        self.pausado = pausado
        self.devidos = devidos or []
        self.reserva = reserva
        self.sem_config = sem_config
        self.sql = []
        self.commits = 0

    def cursor(self):
        cur = CursorFalso(self)
        if self.sem_config:
            original = cur.execute

            def execute(sql, params=None):
                original(sql, params)
                if "atendimento_pausado" in sql:
                    cur.resultado = None
            cur.execute = execute
        return cur

    def commit(self):
        self.commits += 1


UM_DEVIDO = [{"telefone": "559286034966", "ids": [1],
              "mensagem": "sobre o 1327, a cliente já te deu retorno?"}]

enviados = []


def enviar_falso(telefone, mensagem):
    enviados.append((telefone, mensagem))


def enviar_que_falha(telefone, mensagem):
    raise RuntimeError("Z-API fora do ar")


dl.enviar_texto = enviar_falso

print("--- horário: o piso e o teto do dia ---")
for hora, esperado in [(7, False), (8, True), (12, True), (19, True), (20, False), (23, False), (3, False)]:
    momento = datetime.datetime(2026, 8, 31, hora, 30, tzinfo=FUSO)
    checar(f"{hora:02d}h30 -> {'pode' if esperado else 'nao'}",
           dl.dentro_do_horario(momento) == esperado)

print()
print("--- domingo VALE (o Tel recusou janela por dia da semana) ---")
domingo = datetime.datetime(2026, 8, 30, 9, 0, tzinfo=FUSO)  # domingo
checar("domingo 09h pode disparar", dl.dentro_do_horario(domingo))

print()
print("--- a pausa corta tudo ---")
c = ConexaoFalsa(pausado=True, devidos=UM_DEVIDO)
enviados.clear()
r = dl.disparar(c, enviar=True, agora=MEIO_DIA)
checar("pausado nao envia nada", r == [] and enviados == [])

print()
print("--- config ausente = PAUSADO (falha fechada) ---")
c = ConexaoFalsa(sem_config=True, devidos=UM_DEVIDO)
enviados.clear()
r = dl.disparar(c, enviar=True, agora=MEIO_DIA)
checar("sem a linha de config, nao envia", r == [] and enviados == [])

print()
print("--- simulacao nao envia ---")
c = ConexaoFalsa(devidos=UM_DEVIDO)
enviados.clear()
r = dl.disparar(c, enviar=False, agora=MEIO_DIA)
checar("simulacao lista mas nao manda", len(r) == 1 and r[0][3] == "simulado" and enviados == [])

print()
print("--- reserva atomica ---")
c = ConexaoFalsa(devidos=UM_DEVIDO, reserva=0)
enviados.clear()
r = dl.disparar(c, enviar=True, agora=MEIO_DIA)
checar("reserva devolvendo zero NAO envia", enviados == [],
       "outra execucao ja pegou; enviar aqui manda duas vezes")

c = ConexaoFalsa(devidos=UM_DEVIDO, reserva=1)
enviados.clear()
r = dl.disparar(c, enviar=True, agora=MEIO_DIA)
checar("reserva OK envia uma vez", len(enviados) == 1)
checar("mandou para o telefone certo", enviados and enviados[0][0] == "559286034966")

print()
print("--- falha de envio devolve para agendado ---")
dl.enviar_texto = enviar_que_falha
c = ConexaoFalsa(devidos=UM_DEVIDO, reserva=1)
r = dl.disparar(c, enviar=True, agora=MEIO_DIA)
devolveu = any("estado = 'agendado'" in s for s, _ in c.sql)
checar("falha da Z-API devolve o lembrete", devolveu,
       "sem isso a tentativa e consumida e o corretor nunca e cobrado")
checar("o resultado reporta o erro", r and r[0][3].startswith("erro:"))
dl.enviar_texto = enviar_falso

print()
print("--- silencio quando nao ha nada ---")
c = ConexaoFalsa(devidos=[])
enviados.clear()
r = dl.disparar(c, enviar=True, agora=MEIO_DIA)
checar("nada devido, nada enviado, nada impresso", r == [] and enviados == [])

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
