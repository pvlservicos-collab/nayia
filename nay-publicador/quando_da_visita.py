"""
Que DIA e que HORA o corretor disse, no português que ele escreve de verdade.

POR QUE EXISTE SEPARADO: dois caminhos precisam da mesma leitura -- o detector
que varre as mensagens dos corretores (`detectar_visitas.py`) e o comando que
o Tel digita quando ela pergunta (`Nay visita ...`). Duas leituras de data
lado a lado divergem na primeira edição, que é o padrão 4.3 do HISTORICO.

AS FORMAS SÃO MEDIDAS, não imaginadas. Levantamento de 12/09 sobre 6.114
mensagens reais (34 dias, `direcao='recebida'`):

  hora, por frequência:  HH:MM (50), HHh (37), HHhs (24), HH horas (19),
                         HHhrs (10), HH:MMhrs (9), HHhMM (5, quase só o
                         Leonardo Toledo), HH.MM (2, só a Lily), "as HH" solto
  dia, por frequência:   amanhã (40), hoje/hj (30), dia da semana (9),
                         data cheia (1 -- a da Renata), convite de
                         calendário (1 -- o do Valois)

**64% das mensagens com hora NÃO trazem dia nenhum**, e em 74% o dia não está
nem nas mensagens vizinhas. Por isso `dia_do_texto` devolve None sem
constrangimento: quem chama PERGUNTA, não chuta. Foi a decisão do Tel em
12/09, e o número que a sustenta é que assumir "hoje" acerta só 69%.

AS DUAS ARMADILHAS MEDIDAS, e as duas custam caro:

  * FAIXA DE PREÇO parece hora. "de 2.500 a 3.000", "Fecha a 4 mil?",
    "chega a 3.700" -- 11 dos 19 casos de "as HH" eram dinheiro. É a mesma
    lição do `valor_nao_e_codigo.sql`, agora contra a hora.
  * "14:30/15 hs" e "13/13:30 hs" batem no padrão DD/MM. Dois dos três
    casos de DD/MM em contexto de visita eram HORA, não data.
"""
import datetime
import re
import unicodedata

DIAS_DA_SEMANA = {
    "segunda": 0, "segunda-feira": 0, "segundafeira": 0, "seg": 0,
    "terca": 1, "terca-feira": 1, "tercafeira": 1, "ter": 1,
    "quarta": 2, "quarta-feira": 2, "quartafeira": 2, "qua": 2,
    "quinta": 3, "quinta-feira": 3, "quintafeira": 3, "qui": 3,
    "sexta": 4, "sexta-feira": 4, "sextafeira": 4, "sex": 4,
    "sabado": 5, "sab": 5,
    "domingo": 6, "dom": 6,
}

MESES = {
    "janeiro": 1, "jan": 1, "fevereiro": 2, "fev": 2, "marco": 3, "mar": 3,
    "abril": 4, "abr": 4, "maio": 5, "mai": 5, "junho": 6, "jun": 6,
    "julho": 7, "jul": 7, "agosto": 8, "ago": 8, "setembro": 9, "set": 9,
    "outubro": 10, "out": 10, "novembro": 11, "nov": 11,
    "dezembro": 12, "dez": 12,
}


def sem_acento(texto):
    t = unicodedata.normalize("NFD", str(texto or ""))
    return "".join(c for c in t if unicodedata.category(c) != "Mn").lower()


# DINHEIRO SAI ANTES DE PROCURAR HORA. "de 2.500 a 3.000" traz "a 3.000", e
# "Fecha a 4 mil?" traz "a 4" -- os dois virariam horário. Medido: 11 dos 19
# casos de "as HH" no corpus eram preço. Tirar antes de ler é o que o
# `valor_nao_e_codigo.sql` já faz com o código.
_DINHEIRO_RE = re.compile(
    r"r\$\s*[\d.,]+"
    r"|\b\d{1,3}[.,]\d{3}\b"          # 2.500, 3.700
    r"|\b\d+[.,]?\d*\s*(?:mil|k|m)\b"  # 4 mil, 2.5k, 1.2M
    r"|\b\d{4,}\b",                    # 3000, 450000 -- e o codigo do imovel
    re.IGNORECASE,
)

# A hora, nas nove grafias medidas. A ordem importa: as formas com minuto vêm
# antes das sem, senão "17h40" seria lido como 17h e o 40 viraria lixo.
_HORA_RE = re.compile(
    r"\b(?P<h1>\d{1,2})\s*[:.]\s*(?P<m1>[0-5]\d)\s*(?:h|hs|hrs|hr|horas?)?\b"
    r"|\b(?P<h2>\d{1,2})\s*h\s*(?P<m2>[0-5]\d)\b"
    r"|\b(?P<h3>\d{1,2})\s*(?:h|hs|hrs|hr|horas?)\b"
    r"|\b(?P<meia>\d{1,2})\s+e\s+meia\b"
    r"|\b(?P<meiodia>meio[\s-]?dia)\b",
    re.IGNORECASE,
)

# "as 10", "às 9" -- sem marca nenhuma depois do número. Só vale COLADO na
# preposição, senão qualquer número da frase vira horário.
# E NÃO PODE VIR SUBSTANTIVO DEPOIS. "As 2 visitas de sábado não deram certo"
# tem "as 2" seguido de "visitas": ali o número é a CONTAGEM, não a hora --
# e sem esta parede virava uma visita fantasma às 02h00 de sábado na agenda
# do Tel. Medido no corpus real.
_HORA_NUA_RE = re.compile(
    r"\ba+s?\s+(?P<h>\d{1,2})(?!\s*[:.hms\d])\b"
    r"(?!\s*(?:visitas?|imoveis|imovel|casas?|aptos?|apartamentos?|"
    r"opcoes|pessoas?|clientes?|corretor\w*|quartos?|vagas?|dias?|semanas?))",
    re.IGNORECASE)


def hora_do_texto(texto):
    """(hora, minuto) ou None. Devolve a PRIMEIRA hora plausível do texto.

    A primeira, e não a última, porque a frase real põe o horário cedo
    ("Pode visita hoje 15:30?") e o que vem depois costuma ser outra coisa
    ("o cliente tem renda de 3x").
    """
    t = _DINHEIRO_RE.sub(" ", sem_acento(texto))

    for m in _HORA_RE.finditer(t):
        if m.group("meiodia"):
            return (12, 0)
        if m.group("meia"):
            h = int(m.group("meia"))
            return (h, 30) if 0 <= h <= 23 else None
        for hg, mg in (("h1", "m1"), ("h2", "m2"), ("h3", None)):
            if m.group(hg):
                h = int(m.group(hg))
                minuto = int(m.group(mg)) if mg and m.group(mg) else 0
                if 0 <= h <= 23:
                    return (h, minuto)
        # hora fora de 0-23 não é hora; segue procurando
    m = _HORA_NUA_RE.search(t)
    if m:
        h = int(m.group("h"))
        # "as 8" é 8h; "as 45" não é hora nenhuma.
        if 0 <= h <= 23:
            return (h, 0)
    return None


_DATA_CHEIA_RE = re.compile(
    r"\b(?P<d>\d{1,2})\s*/\s*(?P<m>\d{1,2})(?:\s*/\s*(?P<a>\d{2,4}))?\b")
_DATA_POR_EXTENSO_RE = re.compile(
    r"\b(?P<d>\d{1,2})\s+de\s+(?P<mes>[a-z]+)(?:\s+de\s+(?P<a>\d{4}))?\b")


def dia_do_texto(texto, hoje):
    """A data, ou None quando ele não disse.

    NONE É RESPOSTA, não falha: 64% das mensagens com hora não trazem dia, e
    assumir "hoje" acerta 69% -- ou seja erraria 3 em 10 e o Tel iria no dia
    errado. A decisão dele em 12/09 foi PERGUNTAR.
    """
    t = sem_acento(texto)

    if re.search(r"\bdepois\s+de\s+amanha\b", t):
        return hoje + datetime.timedelta(days=2)
    if re.search(r"\bamanha\b|\bamanha\b|\bamnha\b|\bamahna\b", t):
        return hoje + datetime.timedelta(days=1)
    if re.search(r"\bhoje\b|\bhj\b|\bagora\b", t):
        return hoje

    # Data cheia. O dinheiro e a HORA saem antes: "14:30/15 hs" e "13/13:30 hs"
    # batem em DD/MM, e dois dos três casos de DD/MM no corpus eram hora.
    limpo = _DINHEIRO_RE.sub(" ", t)
    limpo = _HORA_RE.sub(" ", limpo)
    m = _DATA_CHEIA_RE.search(limpo)
    if m:
        d, mes = int(m.group("d")), int(m.group("m"))
        ano = int(m.group("a") or hoje.year)
        if ano < 100:
            ano += 2000
        try:
            return datetime.date(ano, mes, d)
        except ValueError:
            return None

    m = _DATA_POR_EXTENSO_RE.search(limpo)
    if m:
        mes = MESES.get(m.group("mes"))
        if mes:
            try:
                return datetime.date(int(m.group("a") or hoje.year),
                                     mes, int(m.group("d")))
            except ValueError:
                return None

    # Dia da semana: SEMPRE o próximo, nunca o que passou. "segunda" dito numa
    # terça é a segunda que vem, não a de ontem -- e visita no passado seria
    # apagada pelo cron no minuto seguinte, sem deixar rastro.
    for nome, alvo in DIAS_DA_SEMANA.items():
        if re.search(r"\b" + re.escape(nome) + r"\b", t):
            adiante = (alvo - hoje.weekday()) % 7
            return hoje + datetime.timedelta(days=adiante or 7)
    return None


def quando(texto, agora):
    """(data_hora, o_que_faltou). `o_que_faltou` é 'dia', 'hora' ou None."""
    h = hora_do_texto(texto)
    d = dia_do_texto(texto, agora.date())
    if h is None:
        return None, "hora"
    if d is None:
        return None, "dia"
    return agora.replace(year=d.year, month=d.month, day=d.day,
                         hour=h[0], minute=h[1], second=0,
                         microsecond=0), None
