"""O contrato de locação dito como COMEÇO + DURAÇÃO (Pedro, 09/10/2026).

"Quando o proprietário disser que foi contratado em uma data ela não pergunta até quando vai e sim quanto tempo é a
duração do contrato, tipo 12 meses, 36 meses, 24 meses."

A ferramenta do fluxo (guardar_situacao) só conhece "até quando vai" (`prazo`). Aqui o serviço aceita mais dois campos,
`inicio` e `duracao`, lembra o que ele já disse (captacao_contrato_dito, 325) e, com os dois, faz a conta do fim e a
entrega ao fluxo como `prazo`, escrito do jeito que `captacao_data_do_contrato` (321) transforma em data:
    "fevereiro de 2028 (começou em fev/2026, 24 meses)"
Quem faz a conta é o sistema: a Nay não calcula nem diz a data ao proprietário.

As partes puras (ler a duração, ler o começo, somar) não tocam no banco: são testadas em tests/test_captacao.py.
"""
from __future__ import annotations

import re
import unicodedata
from datetime import date

MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro",
         "novembro", "dezembro"]
ABREV = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
NUMEROS = {"um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8,
           "nove": 9, "dez": 10, "onze": 11, "doze": 12, "dezoito": 18, "vinte": 20, "trinta": 30, "quarenta": 40,
           "cinquenta": 50, "sessenta": 60}

PERGUNTA_DA_DURACAO = "E o contrato é de quanto tempo: 12, 24 ou 36 meses?"
PERGUNTA_DO_COMECO = "E o contrato começou em que mês e ano?"


def _limpo(texto: str) -> str:
    sem = unicodedata.normalize("NFD", (texto or "").lower())
    return re.sub(r"\s+", " ", "".join(c for c in sem if unicodedata.category(c) != "Mn")).strip()


def _numero(palavras: str) -> int | None:
    """'24', 'dois', 'vinte e quatro', 'trinta e seis' -> o número; None quando não é número."""
    palavras = palavras.strip()
    if palavras.isdigit():
        return int(palavras)
    partes = [p for p in palavras.split() if p != "e"]
    if not partes or any(p not in NUMEROS for p in partes):
        return None
    return sum(NUMEROS[p] for p in partes)


def _antes_de(t: str, unidade: str) -> int | None:
    """O número escrito logo antes de 'anos' ou 'meses': '24 meses', 'vinte e quatro meses', 'de dois anos'."""
    m = re.search(r"((?:\d{1,3}|[a-z]+)(?: e [a-z]+)?) " + unidade + r"\b", t)
    if not m:
        return None
    inteiro = _numero(m.group(1))
    if inteiro is not None:
        return inteiro
    # "contrato de dois anos": o grupo pegou só "dois"; "vinte e quatro" já veio inteiro acima
    return _numero(m.group(1).split()[-1])


def meses_da_duracao(texto: str) -> int | None:
    """'24 meses', '2 anos', 'dois anos', 'um ano e meio', '36' -> meses. None quando não dá para saber."""
    t = _limpo(texto)
    if not t:
        return None
    total = None
    anos = _antes_de(t, "anos?")
    if anos is not None:
        total = anos * 12 + (6 if re.search(r"anos? e mei[oa]\b", t) else 0)
    elif re.search(r"\bano e mei[oa]\b", t):
        total = 18
    else:
        meses = _antes_de(t, "mes(?:es)?")
        if meses is not None:
            total = meses
        elif re.fullmatch(r"\d{1,3}", t):          # respondeu só "24" à pergunta dos 12, 24 ou 36 meses
            total = int(t)
    return total if total is not None and 1 <= total <= 120 else None


def inicio_do_contrato(texto: str, hoje: date) -> tuple[int, int] | None:
    """Quando o contrato começou -> (ano, mês). Sem o ano, vale a última vez que aquele mês passou.

    'fevereiro', 'fev/2026', 'em março do ano passado', '02/2026', 'fevereiro ou março' (vale o primeiro)."""
    t = _limpo(texto)
    if not t:
        return None
    ano = None
    # "dez" também é o número: "há dez meses" não é dezembro
    achado = re.search(r"\b(" + "|".join(_limpo(m) for m in MESES) + "|" + "|".join(ABREV)
                       + r")\b(?! (?:mes|meses|anos?|dias?)\b)", t)
    if achado:
        mes = next(i for i, a in enumerate(ABREV, 1) if achado.group(1).startswith(a))
        depois = re.match(r"\s*(?:de|/|-)?\s*(20\d\d|\d\d)\b", t[achado.end():])
        if depois:
            ano = int(depois.group(1))
    else:
        numerico = re.search(r"\b(0?[1-9]|1[0-2])\s*/\s*(20\d\d|\d\d)\b", t)
        if not numerico:
            return None
        mes, ano = int(numerico.group(1)), int(numerico.group(2))
    if ano is not None and ano < 100:
        ano += 2000
    if ano is None:
        if "ano passado" in t:
            ano = hoje.year - 1
        elif re.search(r"\b(este|esse|deste|desse|neste|nesse) ano\b", t):
            ano = hoje.year
        else:
            ano = hoje.year if mes <= hoje.month else hoje.year - 1
    if not hoje.year - 15 <= ano <= hoje.year or (ano, mes) > (hoje.year, hoje.month):
        return None     # começo no futuro, ou longe demais para ser confiável: quem resolve é gente
    return ano, mes


def fim_do_contrato(inicio: tuple[int, int], meses: int) -> tuple[int, int]:
    indice = inicio[0] * 12 + (inicio[1] - 1) + meses
    return indice // 12, indice % 12 + 1


def prazo_ou_pergunta(inicio: str, duracao: str, hoje: date) -> tuple[str | None, str | None]:
    """Com o começo e a duração: (o `prazo` para o fluxo, None). Faltando um: (None, a instrução do que perguntar)."""
    quando = inicio_do_contrato(inicio, hoje)
    meses = meses_da_duracao(duracao)
    if quando and meses:
        ano, mes = fim_do_contrato(quando, meses)
        return f"{MESES[mes - 1]} de {ano} (começou em {ABREV[quando[1] - 1]}/{quando[0]}, {meses} meses)", None
    if meses and not quando:
        return None, ("Ele disse a duracao do contrato, mas falta saber quando comecou. NAO pergunte ate quando vai: "
                      f'pergunte, com estas palavras: "{PERGUNTA_DO_COMECO}" Quando ele responder, chame '
                      "guardar_situacao com inicio = o que ele disse.")
    # disse quando começou (ou algo que não deu para ler): a pergunta é a da duração
    return None, ("Ele disse QUANDO o contrato comecou. NAO pergunte ate quando vai o contrato: pergunte a DURACAO, "
                  f'com estas palavras: "{PERGUNTA_DA_DURACAO}" Quando ele responder, chame guardar_situacao com '
                  "duracao = o que ele disse. Voce NAO faz a conta do fim do contrato e NAO diz data nenhuma a ele.")


LEMBRAR = """
WITH l AS (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave(%(tel)s))
INSERT INTO captacao_contrato_dito (lead_id, inicio, duracao)
SELECT l.id, nullif(%(inicio)s, ''), nullif(%(duracao)s, '') FROM l
ON CONFLICT (lead_id) DO UPDATE
   -- o que ele disse há mais de 30 dias é de outra rodada da campanha: não se mistura com a de agora
   SET inicio  = coalesce(EXCLUDED.inicio,  CASE WHEN captacao_contrato_dito.atualizado_em > now() - interval '30 days'
                                                THEN captacao_contrato_dito.inicio END),
       duracao = coalesce(EXCLUDED.duracao, CASE WHEN captacao_contrato_dito.atualizado_em > now() - interval '30 days'
                                                THEN captacao_contrato_dito.duracao END),
       atualizado_em = now()
RETURNING coalesce(inicio, '') AS inicio, coalesce(duracao, '') AS duracao
"""


def lembrar(conn, telefone: str, inicio: str, duracao: str) -> dict:
    """Guarda o que ele disse agora e devolve o começo e a duração juntos (um pode ter vindo em outra mensagem)."""
    from captacao import banco   # aqui dentro: as partes puras acima são testadas sem o driver do banco
    r = banco.linhas(conn, LEMBRAR, {"tel": telefone, "inicio": inicio[:120], "duracao": duracao[:120]})
    return r[0] if r else {"inicio": inicio, "duracao": duracao}
