"""
Testa o ciclo da pendência sem banco, sem Z-API e sem relógio de parede.

O QUE PRECISA SER PROVADO:

  * a JANELA de horário vale para os dois lados. Resposta que o Tel deu à
    meia-noite não pode acordar corretor à meia-noite e um.
  * a RESERVA. Zero reservado = outra execução pegou = não envia.
    `postar_agora` já mandou duas vezes neste projeto por falta disso.
  * FALHA DE ENVIO devolve para 'devendo'. Sem isso, uma queda da Z-API
    engole a resposta e o corretor nunca recebe -- que é exatamente o bug
    que este arquivo veio consertar.
  * a COBRANÇA ao Tel tem teto próprio: uma a cada 6 horas, senão vira 24
    mensagens por dia com a mesma lista e ele para de ler.
  * SIMULAÇÃO não manda nada e não grava carimbo.
  * SILÊNCIO quando não há nada.

Uso:
    .venv/bin/python teste_ciclo_pendencias.py
"""
import datetime
from zoneinfo import ZoneInfo

import ciclo_pendencias as cp

FUSO = ZoneInfo("America/Manaus")
MEIO_DIA = datetime.datetime(2026, 8, 31, 12, 0, tzinfo=FUSO)
MADRUGADA = datetime.datetime(2026, 8, 31, 3, 0, tzinfo=FUSO)

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
    def __init__(self, conexao):
        self.c = conexao
        self.resultado = None
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append((sql, params))
        if "nay_respostas_a_entregar" in sql:
            self.linhas = self.c.devidas
        elif "nay_reservar_respostas" in sql:
            self.resultado = {"n": self.c.reserva}
        elif "nay_devolver_respostas" in sql:
            self.resultado = {"n": 1}
        elif "nay_pendencias_esquecidas" in sql:
            self.resultado = self.c.esquecidas
        elif "atendimento_pausado" in sql:
            # A pausa geral. Sem esta linha o cursor caía no ramo genérico
            # de `config` e devolvia None, que o `atendimento_pausado`
            # lê como PAUSADO (falha fechada) -- e todo teste ficava mudo.
            self.resultado = {"pausado": self.c.pausado}
        elif "FROM config" in sql:
            self.resultado = ({"valor": self.c.ultima_cobranca}
                              if self.c.ultima_cobranca else None)
        else:
            self.resultado = None

    def fetchone(self):
        return self.resultado

    def fetchall(self):
        return self.linhas


class ConexaoFalsa:
    def __init__(self, devidas=None, reserva=1, esquecidas=None,
                 ultima_cobranca=None, pausado=False):
        self.devidas = devidas or []
        self.pausado = pausado
        self.reserva = reserva
        self.esquecidas = esquecidas
        self.ultima_cobranca = ultima_cobranca
        self.sql = []
        self.commits = 0

    def cursor(self):
        return CursorFalso(self)

    def commit(self):
        self.commits += 1


UMA_DEVIDA = [{"telefone": "559286034966", "ids": [7],
               "texto": "Sobre o 5717: aceita sim, até 10kg"}]
UMA_ESQUECIDA = {"quantas": 3, "texto": "Ficaram sem resposta:\n• 17 — ..."}


def enviar_ok(tel, msg):
    enviados.append((tel, msg))


def enviar_que_falha(tel, msg):
    raise RuntimeError("Z-API fora do ar")


cp.enviar_texto = enviar_ok

print("--- a janela vale para os dois lados ---")
c = ConexaoFalsa(devidas=UMA_DEVIDA, esquecidas=UMA_ESQUECIDA)
enviados.clear()
checar("03h não entrega resposta",
       cp.entregar_respostas(c, enviar=True, agora=MADRUGADA) == [] and enviados == [])
checar("03h não cobra o Tel",
       cp.cobrar_o_tel(c, enviar=True, agora=MADRUGADA, destino="559") is None
       and enviados == [],
       "resposta dada à meia-noite não pode acordar ninguém à meia-noite e um")

print()
print("--- entrega no horário ---")
c = ConexaoFalsa(devidas=UMA_DEVIDA)
enviados.clear()
r = cp.entregar_respostas(c, enviar=True, agora=MEIO_DIA)
checar("manda uma vez", len(enviados) == 1 and r[0][2] == "entregue")
checar("para o telefone certo", enviados[0][0] == "559286034966")
checar("com o texto da resposta", "até 10kg" in enviados[0][1])
checar("registra o contato do dia",
       any("contato_corretor" in s for s, _ in c.sql),
       "sem isto o teto de 1 por dia não conta esta mensagem")

print()
print("--- reserva atômica ---")
c = ConexaoFalsa(devidas=UMA_DEVIDA, reserva=0)
enviados.clear()
cp.entregar_respostas(c, enviar=True, agora=MEIO_DIA)
checar("reserva zero NÃO envia", enviados == [],
       "outra execução já pegou; enviar aqui manda duas vezes")

print()
print("--- falha de envio devolve para 'devendo' ---")
cp.enviar_texto = enviar_que_falha
c = ConexaoFalsa(devidas=UMA_DEVIDA)
r = cp.entregar_respostas(c, enviar=True, agora=MEIO_DIA)
checar("devolve a resposta para a fila",
       any("nay_devolver_respostas" in s for s, _ in c.sql),
       "sem isso a queda da Z-API engole a resposta e o corretor nunca recebe")
checar("e reporta o erro", r and r[0][2].startswith("erro:"))
cp.enviar_texto = enviar_ok

print()
print("--- a cobrança ao Tel tem teto próprio ---")
c = ConexaoFalsa(esquecidas=UMA_ESQUECIDA)
enviados.clear()
cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="559")
checar("cobra quando há pendência atrasada", len(enviados) == 1)
checar("grava o carimbo", c.commits == 1)

c = ConexaoFalsa(esquecidas=UMA_ESQUECIDA,
                 ultima_cobranca=(MEIO_DIA - datetime.timedelta(hours=2)).isoformat())
enviados.clear()
cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="559")
checar("cobrou há 2h: não repete", enviados == [],
       "24 mensagens por dia com a mesma lista e ele para de ler")

c = ConexaoFalsa(esquecidas=UMA_ESQUECIDA,
                 ultima_cobranca=(MEIO_DIA - datetime.timedelta(hours=7)).isoformat())
enviados.clear()
cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="559")
checar("passadas 6h, cobra de novo", len(enviados) == 1)

c = ConexaoFalsa(esquecidas=UMA_ESQUECIDA, ultima_cobranca="isso não é data")
enviados.clear()
cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="559")
checar("carimbo ilegível não vira silêncio", len(enviados) == 1)

print()
print("--- simulação ---")
c = ConexaoFalsa(devidas=UMA_DEVIDA, esquecidas=UMA_ESQUECIDA)
enviados.clear()
r = cp.entregar_respostas(c, enviar=False, agora=MEIO_DIA)
texto = cp.cobrar_o_tel(c, enviar=False, agora=MEIO_DIA, destino="559")
checar("não manda nada", enviados == [])
checar("mas mostra o que faria", len(r) == 1 and r[0][2] == "simulado" and texto)
checar("e não grava carimbo", c.commits == 0)

print()
print("--- mensagem engolida pelo fluxo vira aviso ---")
# 01/09: um `docker restart` do deploy matou a execução parada na janela
# de 25s, e o comando do Tel ficou em 'Recebido' sem ninguém saber.
ORFAS = [{"id": 2992, "telefone": "559294717316", "nome": "Tel Sobreira",
          "texto": "publica no nosso grupo anunciar easy código 5664", "minutos": 47}]


class ConexaoOrfa(ConexaoFalsa):
    def __init__(self, orfas=None, **kw):
        super().__init__(**kw)
        self.orfas = orfas or []

    def cursor(self):
        c = CursorFalso(self)
        original = c.execute

        def execute(sql, params=None):
            original(sql, params)
            if "status = 'Recebido'" in sql:
                c.linhas = self.orfas
        c.execute = execute
        return c


c = ConexaoOrfa(orfas=ORFAS)
enviados.clear()
texto = cp.avisar_orfas(c, enviar=True, destino="559")
checar("avisa o Tel", len(enviados) == 1)
checar("diz de quem e o que era",
       texto and "Tel Sobreira" in texto and "5664" in texto, texto)
checar("diz que NAO foi respondida", texto and "NÃO foram respondidas" in texto)
checar("marca como Perdida, nao como Processando",
       any("'Perdida'" in s for s, _ in c.sql)
       and not any("'Processando'" in s for s, _ in c.sql),
       "'Processando' faria parecer que alguem tratou")

c = ConexaoOrfa(orfas=[])
enviados.clear()
checar("sem orfa, silencio",
       cp.avisar_orfas(c, enviar=True, destino="559") is None and enviados == [])

c = ConexaoOrfa(orfas=ORFAS)
enviados.clear()
checar("simulacao mostra e nao manda",
       cp.avisar_orfas(c, enviar=False, destino="559") and enviados == [])

print()
print("--- silêncio quando não há nada ---")
c = ConexaoFalsa()
enviados.clear()
checar("nada devido, nada enviado",
       cp.entregar_respostas(c, enviar=True, agora=MEIO_DIA) == []
       and cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="559") is None
       and enviados == [])

print()
print("--- sem TEL_WHATSAPP: erro alto, não silêncio ---")
c = ConexaoFalsa(esquecidas=UMA_ESQUECIDA)
try:
    cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="")
    checar("levanta erro de configuração", False)
except RuntimeError as exc:
    checar("levanta erro de configuração", "TEL_WHATSAPP" in str(exc))

print("--- a pausa geral vale para as pendências também ---")
# O CLAUDE.md sempre disse que pausada "nenhum corretor recebe nada", e
# não era verdade: três dos quatro crons que falam com corretor ignoravam
# a chave. Em 02/09 o Tel pausou porque ela estava respondendo mal, e
# continuou saindo mensagem por aqui.
c = ConexaoFalsa(devidas=UMA_DEVIDA, esquecidas=UMA_ESQUECIDA, pausado=True)
enviados.clear()
checar("pausada, corretor não recebe resposta",
       cp.entregar_respostas(c, enviar=True, agora=MEIO_DIA) == [] and enviados == [])

# O que vai para o TEL não para junto: pausar não pode deixar ele cego.
enviados.clear()
checar("mas o Tel continua sendo cobrado",
       cp.cobrar_o_tel(c, enviar=True, agora=MEIO_DIA, destino="559") is not None
       and len(enviados) == 1,
       "pausar a Nay não pode esconder do Tel o que ficou sem resposta")

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
