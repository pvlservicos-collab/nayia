"""
Testa o detector que põe na grade a visita que o corretor pediu.

O CASO (12/09): a Renata agendou para segunda e a Nay não colocou na grade.
A causa não foi ela falhar em achar -- é que NADA escrevia na tabela `visita`.
A tabela, o cron de alertas e o comando existiam desde 11/09; a ENTRADA, não.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * a mensagem literal da Renata vira linha na grade. É o caso que ele
    reclamou, e é a única mensagem com DATA CHEIA em 34 dias;

  * o que NÃO é pedido novo não entra. Medido: de 54 mensagens que casariam um
    detector ingênuo, 36 (67%) não são agendamento -- pergunta sobre visita
    que já existe, passado, cancelamento, negociação. Cada exclusão aqui é uma
    família contada no corpus real;

  * a saída do PRÓPRIO `alertar_visitas.py` está na tabela e casa o detector
    inteiro ("☀️ Visitas de HOJE (12/09): - ✓ 10h00 — Acquarelle..."). Sem o
    filtro de direção, o cron lê a própria agenda e a reescreve -- o bug do
    portão de fotos lendo o envelope de áudio, com o texto já pronto na mesa;

  * o Tel escapa pelo `@lid` e os comandos de grade dele casam ("posta o 2943
    todo dia às 08h"). Filtrar só pelo telefone não basta;

  * REMARCAR TROCA, não empilha. A Amanda pediu "as 09horas" e 72 min depois
    "A visita vai ser as 11 horas": duas linhas fariam o Tel ir às 9h e não
    ter ninguém;

  * sem o dia, PERGUNTA. 64% das mensagens com hora não dizem o dia, e assumir
    "hoje" acerta 69% -- erraria 3 em 10, e ele iria no dia errado;

  * a primeira rodada não processa histórico. Sem a parede, subir o detector
    mandaria as ações de 34 dias de uma vez, e os cancelamentos antigos
    apagariam visita de hoje.

Uso:
    .venv/bin/python teste_detectar_visitas.py
"""
import datetime
from zoneinfo import ZoneInfo

import detectar_visitas
from quando_da_visita import quando

FUSO = ZoneInfo("America/Manaus")
AGORA = datetime.datetime(2026, 9, 12, 10, 0, tzinfo=FUSO)   # um sábado

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = str(obtido) == str(esperado)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.linhas = []
        s = " ".join(sql.split())
        if "FROM mensagens m" in s:
            # O FALSO HONRA A DIREÇÃO. Sem isto o teste da "própria saída
            # dela" não provava nada: a parede de verdade é o
            # `direcao = 'recebida'` da consulta, e um falso que devolve tudo
            # passa por cima dela. Suíte que não exercita a parede é a mesma
            # suíte verde que não prova nada do bug 18.
            assert "m.direcao = 'recebida'" in s, "a consulta perdeu o filtro de direcao"
            self.linhas = [x for x in self.conn.mensagens
                           if x.get("direcao", "recebida") == "recebida"]
        elif "chave = 'visita_detector_ate_id'" in s and s.startswith("SELECT"):
            self.linhas = [{"valor": self.conn.carimbo}] if self.conn.carimbo else []
        elif "max(id) AS ultimo" in s:
            self.linhas = [{"ultimo": self.conn.ultimo_id}]
        # A ORDEM IMPORTA: a consulta que apaga CONTÉM a frase da que lê.
        # Com a leitura antes, o apagar caía no ramo errado e o teste dizia
        # que nada tinha sido apagado enquanto o código apagava certo.
        elif "DELETE FROM visita" in s:
            self.conn.apagadas.append(params)
        elif "INSERT INTO visita" in s:
            self.conn.inseridas.append(params)
        elif "UPDATE visita" in s:
            self.conn.atualizadas.append(params)
        elif "FROM visita" in s:
            self.linhas = list(self.conn.visitas)
        elif "INSERT INTO config" in s:
            self.conn.carimbo = params[0]

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class ConnFake:
    def __init__(self, mensagens=None, visitas=None, carimbo="1"):
        self.mensagens = mensagens or []
        self.visitas = visitas or []
        self.carimbo = carimbo
        self.ultimo_id = 9999
        self.inseridas, self.atualizadas, self.apagadas = [], [], []

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass

    def close(self):
        pass


def msg(texto, nome="Renata Guimarães", telefone="559281121282",
        quando_em=None, id=100, direcao="recebida"):
    return {"id": id, "telefone": telefone, "nome": nome, "texto": texto,
            "criada_em": quando_em or AGORA, "origem": "texto",
            "direcao": direcao}


def rodar(mensagens, visitas=None, agora=AGORA):
    conn = ConnFake(mensagens=mensagens, visitas=visitas)
    enviados = []
    acoes = detectar_visitas.detectar_visitas(
        conexao=conn, agora=agora, escrever=True, tel_whatsapp="tel",
        enviar=lambda d, t: enviados.append(t))
    return conn, acoes, enviados


# --------------------------------------------------------------------
print("--- O CASO DA RENATA: a mensagem literal vira grade ---")
RENATA = ("Agendado para segunda-feira dia 14/09/2026 as 14:00hrs\n"
          "Imóvel do Novo Aleixo de 499Mil\n"
          "Cliente: Carla Zurra\n"
          "Confirmado?")
conn, acoes, enviados = rodar([msg(RENATA)])
checar("vira uma linha na grade", len(conn.inseridas), 1)
checar("na segunda 14/09 às 14h", conn.inseridas[0][3].strftime("%d/%m %H:%M"),
       "14/09 14:00")
checar("no nome da corretora", conn.inseridas[0][1], "Renata Guimarães")
checar("e ela avisa o Tel", len(enviados), 1)
checar("dizendo que não está confirmada", "não confirmada" in enviados[0], True)

print()
print("--- as formas que os corretores usam de verdade ---")
for texto, esperado in [
    ("Podemos marcar a visita amanhã as 14:00", "13/09 14:00"),
    ("Pode visita hoje 15:30?", "12/09 15:30"),
    ("Quero agendar edif Rio Amazonas amanhã às 9:30 HS pode ser?", "13/09 09:30"),
    ("agendar visita Estilo Golfe hj as 16hs ?", "12/09 16:00"),
    ("Tem outro cliente pra visitar a casa do Nova Cidade hoje às 15h", "12/09 15:00"),
    ("VISITA AGENDADA PRA AMANHÃ AS 17:30 NO LIVERPOOL", "13/09 17:30"),
    ("Tem um cliente querendo ir visitar amanhã às 13", "13/09 13:00"),
]:
    conn, _, _ = rodar([msg(texto)])
    veio = (conn.inseridas[0][3].strftime("%d/%m %H:%M")
            if conn.inseridas else "(nao entrou)")
    checar(f"{texto[:46]!r}", veio, esperado)

print()
print("--- SEM O DIA ela PERGUNTA, nunca chuta ---")
# 64% das mensagens com hora não dizem o dia. Assumir "hoje" acerta 69% --
# erraria 3 em 10 e o Tel iria no dia errado.
for texto in ["Tem como agendar uma visita as 09horas na casa do nova cidade",
              "A visita vai ser as 11 horas",
              "Vamos visitar as 10:30 tá",
              "Posso marcar às 11:00?"]:
    conn, _, enviados = rodar([msg(texto)])
    checar(f"{texto[:42]!r} não entra", len(conn.inseridas), 0)
    checar("  e ela pergunta o dia", "que dia?" in (enviados[0] if enviados else ""), True)

print()
print("--- o que NÃO é pedido novo (67% do que um detector ingênuo pega) ---")
for texto, porque in [
    # pergunta sobre visita que já existe
    ("Nay, queria confirmar com você se está tudo certo para a visita das 11h",
     "pergunta sobre a que existe"),
    ("Passando para confirmar a visita às 17h40 no Edifício Piedade Gavinho",
     "informa sobre a que existe"),
    ("Esta confirmado as 13hs. De lá ela ja segue para a estrada",
     "confirma a que existe"),
    # passado
    ("Não o de hj que eu agendei contigo às 16 hrs lembra", "passado"),
    ("Um tinha me confirmado mais cedo 17h", "passado"),
    ("Vê aí pq tenho outra visita marcada 12:30", "compromisso que ja existe"),
    # o Tel escapando pelo @lid
    ("Nay posta o 2943 todo dia às 08h", "comando do Tel"),
    ("Dispara apartamentos para locação todo dia às 7H", "comando do Tel"),
    ("agenda de visitas", "comando do Tel"),
    # contagem, não hora -- virava visita fantasma às 02h00
    ("As 2 visitas de sábado não deram certo", "contagem, nao hora"),
]:
    conn, _, enviados = rodar([msg(texto)])
    checar(f"{porque}: {texto[:34]!r}",
           len(conn.inseridas) + len(conn.apagadas) + len(conn.atualizadas), 0)

print()
print("--- a PRÓPRIA saída dela não vira visita ---")
# O `alertar_visitas.py` escreve na tabela como 'enviada', e o texto dele casa
# o detector inteiro. Sem o filtro de direção, o cron lê a própria agenda e a
# reescreve -- o bug do portão de fotos lendo o envelope de áudio, agora com o
# texto já pronto na mesa.
for texto in ["☀️ Visitas de HOJE (12/09):\n- ✓ 10h00 — Acquarelle cod:2943 (Marlúcia)",
              "⏰ Visitas pedidas há mais de 1 hora sem resposta:\n"
              "- Casa Novo Aleixo para 14/09 14h00 (Renata)",
              "📌 pus na agenda: 14/09 14h00 — Renata\nnão confirmada ainda.",
              "📋 Visitas de AMANHÃ (14/09):\n- ⏳ 14h00 — Casa Novo Aleixo (Renata)"]:
    conn, _, enviados = rodar([msg(texto, direcao="enviada")])
    checar(f"{texto[:38]!r} é ignorada",
           len(conn.inseridas) + len(conn.apagadas) + len(conn.atualizadas), 0)

print()
print("--- CANCELAMENTO tira da grade ---")
ABERTA = [{"id": 7, "descricao": "casa nova cidade",
           "data_hora": AGORA + datetime.timedelta(days=1)}]
for texto in ["Nay cancela a visita???! Já são 13:17",
              "Cancela visita ele não gostou do local do condominio",
              "CLIENTE CANCELOU A VISITA DEVIDO COMPROMISSO DO TRABALHO",
              "Amiga cancela a visita ele já viu um outro lá e não gostou"]:
    conn, _, enviados = rodar([msg(texto)], visitas=ABERTA)
    checar(f"{texto[:42]!r} apaga", len(conn.apagadas), 1)
    checar("  e ela avisa qual saiu", "tirei da agenda" in (enviados[0] if enviados else ""), True)

# "Eu tinha cancelado uma visita para ele" fala do PASSADO: apagar por causa
# disso tiraria da grade uma visita que nada tem a ver.
conn, _, _ = rodar([msg("Eu tinha cancelado uma visita para ele")], visitas=ABERTA)
checar("cancelamento no passado NÃO apaga", len(conn.apagadas), 0)

print()
print("--- REMARCAR troca, não empilha ---")
# Medido: a Amanda pediu "as 09horas" e 72 min depois "A visita vai ser as 11
# horas". Duas linhas fariam o Tel ir às 9h e não ter ninguém.
conn, _, enviados = rodar(
    [msg("Podemos remarcar a visita amanhã as 11:00", nome="Amanda")],
    visitas=ABERTA)
checar("atualiza a linha que já existe", len(conn.atualizadas), 1)
checar("e NÃO cria outra", len(conn.inseridas), 0)
checar("avisando que mudou", "mudou a visita" in (enviados[0] if enviados else ""), True)

# MESMO DIA sem a palavra também é remarcação: é o caso medido da Amanda,
# que pediu "as 09horas" e 72 min depois "as 11 horas".
conn, _, _ = rodar([msg("Podemos marcar a visita amanhã as 11:00")], visitas=ABERTA)
checar("mesmo dia, sem a palavra, também troca", len(conn.atualizadas), 1)

# MAS DIA DIFERENTE É OUTRA VISITA. A primeira versão trocava sempre que o
# corretor tivesse QUALQUER visita aberta, e isso apagou de verdade a visita de
# segunda da Renata quando ela marcou outra. Corretor que agenda dois imóveis
# em dias diferentes tem DUAS visitas, não uma que muda.
OUTRO_DIA = [{"id": 9, "descricao": "Casa Novo Aleixo",
              "data_hora": AGORA + datetime.timedelta(days=2)}]
conn, _, _ = rodar([msg("Podemos marcar a visita amanhã as 16:30")],
                   visitas=OUTRO_DIA)
checar("dia diferente CRIA outra linha", len(conn.inseridas), 1)
checar("e NÃO apaga a que existia", len(conn.atualizadas), 0)

print()
print("--- visita no PASSADO não entra ---")
# O alertador apagaria no minuto seguinte e o Tel nunca saberia que existiu.
conn, _, _ = rodar([msg("Podemos marcar a visita hoje as 08:00")])
checar("hora que já passou não vira linha", len(conn.inseridas), 0)

print()
print("--- 'amanhã' é relativo À MENSAGEM, não ao relógio ---")
# Sem isto, a primeira rodada sobre o histórico leria 34 dias de "amanhã" como
# amanhã e encheria a grade de visita que já aconteceu.
velha = msg("Podemos marcar a visita amanhã as 14:00",
            quando_em=AGORA - datetime.timedelta(days=30))
conn, _, _ = rodar([velha])
checar("mensagem de 30 dias atrás não entra", len(conn.inseridas), 0)

print()
print("--- a primeira rodada não processa histórico ---")
conn = ConnFake(mensagens=[msg(RENATA)], carimbo=None)
enviados = []
detectar_visitas.detectar_visitas(conexao=conn, agora=AGORA, escrever=True,
                                  tel_whatsapp="tel",
                                  enviar=lambda d, t: enviados.append(t))
checar("nada é escrito", len(conn.inseridas), 0)
checar("nenhum aviso é mandado", len(enviados), 0)
checar("mas o carimbo nasce no fim da fila", conn.carimbo, "9999")

print()
print("--- simulação não escreve nada ---")
conn = ConnFake(mensagens=[msg(RENATA)])
enviados = []
acoes = detectar_visitas.detectar_visitas(
    conexao=conn, agora=AGORA, escrever=False, tel_whatsapp="tel",
    enviar=lambda d, t: enviados.append(t))
checar("a ação é vista", len(acoes), 1)
checar("mas nada entra na grade", len(conn.inseridas), 0)
checar("e nada é mandado", len(enviados), 0)

print()
print("--- RESPOSTA AUTOMÁTICA DE COMÉRCIO não é visita (Tel, 28/09) ---")
# A grade amanheceu com "08h00 — Nancy Souza Corretora agradece seu contato. /
# Atendemos de segunda a sexta das 8h às 17h...". Era o WhatsApp Business dela
# respondendo sozinho, e o texto trazia as três coisas que o detector procura:
# a palavra VISITA ("Realizamos visitas com horário marcado"), uma HORA ("das
# 8h") e um DIA ("de segunda a sexta").
#
# MEDIDO em 10.172 mensagens recebidas: 178 teriam dia e hora entendidos, e
# esta guarda barra EXATAMENTE 3 -- as três cópias da resposta dela. Nenhum
# falso positivo no corpus inteiro.
from detectar_visitas import (_FAIXA_DE_HORARIO_RE as _FX,
                              _RESPOSTA_AUTOMATICA_RE as _AU)
from quando_da_visita import sem_acento as _sa


def _barra(t):
    st = _sa(t)
    return bool(_FX.search(st) or _AU.search(st))


NANCY = ("Nancy Souza Corretora agradece seu contato.\n\n"
         "Atendemos de segunda a sexta das 8h às 17h e aos sábados das 8h às 12h\n"
         "❌ Domingo fechado\n🏠 Realizamos visitas com horário marcado.\n"
         "Muito em breve retornaremos.\nObrigada!")
checar("a mensagem exata que virou visita", _barra(NANCY), True)
# Os DOIS sinais casam nela, e cada um sozinho já barraria -- é o que dá folga
# para a próxima automática, que não vai ter a mesma redação.
checar("  pela FAIXA de horário", bool(_FX.search(_sa(NANCY))), True)
checar("  e pela redação de automática", bool(_AU.search(_sa(NANCY))), True)

for _t in ["Atendemos de segunda a sexta das 8h às 18h",
           "nosso horário de atendimento é das 9h às 17h",
           "funcionamos das 8h as 12h",
           "Obrigado pelo contato, em breve retornaremos",
           "esta é uma mensagem automática",
           "Domingo fechado"]:
    checar(f"barra {_t[:44]!r}", _barra(_t), True)

print()
print("--- e NÃO barra agendamento de verdade ---")
# A guarda custaria caro se levasse visita junto: o corretor marca, a Nay
# cala, e o Tel só descobre quando o cliente chega na portaria.
for _t in ["Visita terça às 15h",
           "podemos marcar amanhã as 10h?",
           "confirmo a visita de sexta 14h",
           "vou levar o cliente segunda 9h",
           "amanha as 16h pode ser?"]:
    checar(f"deixa passar {_t[:40]!r}", _barra(_t), False)
# FAIXA DE QUANTIDADE E DE PREÇO não é faixa de horário -- por isso o segundo
# número da faixa precisa de "h" ou ":". Sem essa exigência, "de 2 a 3
# quartos" barraria a mensagem inteira.
checar("'de 2 a 3 quartos' não é faixa de horário",
       _barra("quero um de 2 a 4 quartos amanha as 9h"), False)
checar("'de 400 a 500 mil' também não",
       _barra("consigo entre 400 a 500 mil, visita sabado as 10h"), False)

print()
print("--- CÓPIA NO NÚMERO PESSOAL DA RAYSSA (Tel, 16/10): só os avisos de agenda ---")
# "esse tipo de mensagem consegue passar para o número pessoal da Rayssa?" --
# VISITAS_WHATSAPP recebe o "pus na agenda", o "mudou" e o "tirei". A pergunta
# do dia pede um comando que só vale dos números do Tel: essa fica com ele.


def rodar_com_copia(mensagens, visitas=None, falha_na_copia=False):
    conn = ConnFake(mensagens=mensagens, visitas=visitas)
    enviados = []

    def enviar(d, t):
        if falha_na_copia and d == "rayssa":
            raise RuntimeError("a Z-API recusou")
        enviados.append((d, t))
    detectar_visitas.detectar_visitas(
        conexao=conn, agora=AGORA, escrever=True, tel_whatsapp="tel",
        visitas_whatsapp="rayssa", enviar=enviar)
    return conn, enviados


conn, enviados = rodar_com_copia([msg(RENATA)])
checar("'pus na agenda' vai ao Tel e à Rayssa", [d for d, _ in enviados], ["tel", "rayssa"])
checar("  com o mesmo texto", len({t for _, t in enviados}), 1)
conn, enviados = rodar_com_copia([msg("Cancela visita ele não gostou do local do condominio")], visitas=ABERTA)
checar("'tirei da agenda' também vai aos dois", [d for d, _ in enviados], ["tel", "rayssa"])
conn, enviados = rodar_com_copia([msg("Posso marcar às 11:00?")])
checar("a pergunta do dia vai SÓ ao Tel", [d for d, _ in enviados], ["tel"])
conn, enviados = rodar_com_copia([msg(RENATA)], falha_na_copia=True)
checar("cópia recusada não derruba: a visita entra", len(conn.inseridas), 1)
checar("  e o Tel recebe", [d for d, _ in enviados], ["tel"])
conn, _, enviados = rodar([msg(RENATA)])
checar("sem VISITAS_WHATSAPP, só o Tel (como antes)", len(enviados), 1)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO DETECTOR DE VISITAS PASSARAM")
