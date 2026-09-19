"""
Testa o alarme de varredura parada, sem banco nem Z-API.

O QUE PRECISA SER PROVADO:

  * SILÊNCIO quando está em dia. Roda de hora em hora; alarme que toca
    sempre vira ruído e o Tel para de ler.
  * AVISA quando atrasou. É o ponto todo.
  * FALHA FECHADA: sem conseguir ler o carimbo, avisa. "Não sei se está
    atualizado" é notícia ruim, não silêncio -- mesmo princípio do
    porteiro e da pausa.
  * UM AVISO POR DIA. Uma semana quebrada não pode virar 168 mensagens.
  * SIMULAÇÃO não manda nada.

Uso:
    .venv/bin/python teste_alarme_varredura.py
"""
import datetime
from zoneinfo import ZoneInfo

import alarme_varredura as av

FUSO = ZoneInfo("America/Manaus")
AGORA = datetime.datetime(2026, 8, 31, 12, 0, tzinfo=FUSO)

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
        self.conexao = conexao
        self.resultado = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.conexao.sql.append((sql, params))
        if "varredura_rodou_em" in sql:
            self.resultado = ({"valor": self.conexao.rodou_em}
                              if self.conexao.rodou_em else None)
        elif "max(sincronizado_em)" in sql:
            self.resultado = ({"quando": self.conexao.varrido_em}
                              if self.conexao.tem_carimbo else None)
        elif "FROM config" in sql:
            self.resultado = ({"valor": self.conexao.ultimo_aviso}
                              if self.conexao.ultimo_aviso else None)
        else:
            self.resultado = None

    def fetchone(self):
        return self.resultado


class ConexaoFalsa:
    def __init__(self, varrido_em=None, ultimo_aviso=None, tem_carimbo=True,
                 rodou_em=None):
        self.rodou_em = rodou_em
        self.varrido_em = varrido_em
        self.ultimo_aviso = ultimo_aviso
        self.tem_carimbo = tem_carimbo
        self.sql = []
        self.commits = 0

    def cursor(self):
        return CursorFalso(self)

    def commit(self):
        self.commits += 1


av.enviar_texto = lambda tel, msg: enviados.append((tel, msg))

print("--- em dia: silêncio ---")
c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(minutes=40))
enviados.clear()
checar("varredura de 40 min atrás não alarma",
       av.verificar(c, enviar=True, agora=AGORA, destino="559") is None
       and enviados == [])

print()
print("--- atrasou: avisa ---")
c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(hours=8))
enviados.clear()
aviso = av.verificar(c, enviar=True, agora=AGORA, destino="559")
checar("8 horas de atraso manda mensagem", len(enviados) == 1)
checar("a mensagem diz quantas horas", aviso and "8 horas" in aviso, aviso)
checar("e diz o que isso significa na prática",
       aviso and "não encontrou o código" in aviso, aviso)
checar("gravou o carimbo do aviso", c.commits == 1)

print()
print("--- três dias, como aconteceu de verdade ---")
c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(days=3))
enviados.clear()
aviso = av.verificar(c, enviar=True, agora=AGORA, destino="559")
checar("avisa", len(enviados) == 1)
checar("conta as 72 horas", aviso and "72 horas" in aviso, aviso)

print()
print("--- catálogo estável NÃO é varredura parada ---")
# O falso alarme das 03h20 de 01/09: a varredura tinha rodado às 00h17,
# 01h17, 02h17 e 03h17, todas em silêncio porque nada mudou -- e
# `max(sincronizado_em)` só avança nas linhas tocadas.
c = ConexaoFalsa(rodou_em=(AGORA - datetime.timedelta(minutes=20)).isoformat(),
                 varrido_em=AGORA - datetime.timedelta(hours=6))
enviados.clear()
checar("rodou há 20 min sem mudar nada: silêncio",
       av.verificar(c, enviar=True, agora=AGORA, destino="559") is None
       and enviados == [],
       "alarme que toca à toa ensina a ignorar")

c = ConexaoFalsa(rodou_em=(AGORA - datetime.timedelta(hours=9)).isoformat(),
                 varrido_em=AGORA - datetime.timedelta(minutes=5))
enviados.clear()
av.verificar(c, enviar=True, agora=AGORA, destino="559")
checar("parada há 9h mesmo com dado recente: avisa", len(enviados) == 1,
       "o que importa é a varredura ter rodado, não o dado ter mudado")

c = ConexaoFalsa(rodou_em="isso não é data",
                 varrido_em=AGORA - datetime.timedelta(minutes=30))
enviados.clear()
checar("carimbo ilegível cai para max(sincronizado_em)",
       av.verificar(c, enviar=True, agora=AGORA, destino="559") is None
       and enviados == [])

print()
print("--- FALHA FECHADA: sem carimbo, avisa ---")
c = ConexaoFalsa(tem_carimbo=False)
enviados.clear()
aviso = av.verificar(c, enviar=True, agora=AGORA, destino="559")
checar("não conseguir ler o carimbo também é alarme", len(enviados) == 1,
       "'não sei se está atualizado' é notícia ruim, não silêncio")

print()
print("--- um aviso por dia ---")
c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(hours=8),
                 ultimo_aviso=(AGORA - datetime.timedelta(hours=2)).isoformat())
enviados.clear()
checar("já avisou há 2 horas: não repete",
       av.verificar(c, enviar=True, agora=AGORA, destino="559") is None
       and enviados == [])

c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(hours=8),
                 ultimo_aviso=(AGORA - datetime.timedelta(hours=30)).isoformat())
enviados.clear()
av.verificar(c, enviar=True, agora=AGORA, destino="559")
checar("passado um dia, avisa de novo", len(enviados) == 1)

c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(hours=8),
                 ultimo_aviso="isso não é uma data")
enviados.clear()
av.verificar(c, enviar=True, agora=AGORA, destino="559")
checar("carimbo ilegível não vira silêncio", len(enviados) == 1)

print()
print("--- simulação não manda ---")
c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(hours=8))
enviados.clear()
aviso = av.verificar(c, enviar=False, agora=AGORA, destino="559")
checar("simulação mostra o texto e não envia", aviso and enviados == [])
checar("e não grava carimbo nenhum", c.commits == 0)

print()
print("--- sem TEL_WHATSAPP: erro alto, não silêncio ---")
c = ConexaoFalsa(varrido_em=AGORA - datetime.timedelta(hours=8))
try:
    av.verificar(c, enviar=True, agora=AGORA, destino="")
    checar("levanta erro de configuração", False)
except RuntimeError as exc:
    checar("levanta erro de configuração", "TEL_WHATSAPP" in str(exc))

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
