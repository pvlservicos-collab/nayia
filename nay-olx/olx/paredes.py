"""AS PAREDES DE SAÍDA (Pedro, 25/10/2026: "analise a infraestrutura [da Nay Parceria] ... veja as redundâncias e funções
que fazem ela melhor, e aplique nas outras"). Na Parceria o texto nunca sai sem passar pelo validador (nay-core
validador/regras.yaml: codigo_so_de_ferramenta, valor_so_de_ferramenta, parceria_nunca, negou_imovel_que_existe...);
aqui na Nay Leads e na Nay da OLX o modelo escreve o balão inteiro e só o emoji, o link e o telefone eram barrados.

Cada parede confere o balão contra o que o modelo RECEBEU no turno (a ficha, os imóveis da conversa, o que o cliente
disse): um valor em reais ou um código de imóvel que não está lá foi inventado. Quem chama decide o que fazer com o furo:
na Nay Leads a resposta volta ao modelo UMA vez com o aviso (como o "regenera" da Parceria) e o que ainda furar é cortado.
"""
from __future__ import annotations

import re
import unicodedata

VALOR = re.compile(r"R\$\s*([\d.]+(?:,\d{1,2})?)(\s*(?:mil|milh[õo]es|milh[ãa]o)\b)?", re.I)
CODIGO = re.compile(r"(?:#|\bc[óo]d(?:igo)?\.?\s*:?\s*)(\d{3,5})\b", re.I)
PARCERIA = re.compile(r"\b(parceri[ao]s?|parceir[oa]s?|outra imobili[áa]ria|de terceiros)\b", re.I)
NEGATIVA = re.compile(r"\b(n[ãa]o temos|n[ãa]o tenho (nenhum|nenhuma|nada|op[çc])|n[ãa]o consigo|n[ãa]o [ée] poss[íi]vel|"
                      r"n[ãa]o d[áa] (para|pra)|infelizmente,? n[ãa]o)\b", re.I)
BASTIDOR = re.compile(r"\b(rob[ôo]|intelig[êe]ncia artificial|sou uma ia|ficha|cat[áa]logo|sistema interno|nay da olx)\b", re.I)
OLX = re.compile(r"\b(olx|an[úu]ncio)\b", re.I)
# 26/10 (o lead 20: "o CRECI da imobiliária é PJ 482", que não está em lugar nenhum): número de documento só do turno
DOCUMENTO = re.compile(r"\b(CRECI|CNPJ|CPF|inscri[çc][ãa]o)\b[^\d\n]{0,30}((?:PJ|F)?\s*\d[\d./-]{1,18})", re.I)
# 26/10 (os leads 25 e 51: "a equipe me informou que..." sem nenhuma resposta da equipe na conversa): o que a equipe ou o
# dono disse só vale se a fala da equipe (EQUIPE:) ou a resposta da fila ("Sobre a sua pergunta") está no turno
EQUIPE_DISSE = re.compile(r"\b(a equipe|o tel|o propriet[áa]rio|a propriet[áa]ria|o corretor|a corretora)\s+(me\s+|j[áa]\s+)?"
                          r"(informou|confirmou|disse|respondeu|falou|passou|garantiu|avisou)\b", re.I)
RESPOSTA_DA_EQUIPE = re.compile(r"^EQUIPE|Sobre a sua pergunta|Sobre o #\d+", re.M)

AVISO = {
    "valor": "você escreveu {x}, que NÃO está na ficha nem na conversa: use só valores que o sistema deu",
    "codigo": "você citou o código {x}, que NÃO está entre os imóveis desta conversa: nunca invente código",
    "parceria": "você escreveu \"{x}\": para o cliente todo imóvel é da Imob Easy (nunca parceria/parceiro)",
    "negativa": "você deu uma negativa (\"{x}\"): nunca diga que não tem ou que não dá; diga que vai separar/confirmar",
    "bastidor": "você falou de \"{x}\": para ela você é só a Nay, da Imob Easy (sem robô, ficha, catálogo, sistema)",
    "olx": "ela escreveu direto para este número: nunca fale de OLX nem de anúncio (\"{x}\")",
    "documento": "você citou \"{x}\", que NÃO está na ficha nem na conversa: nunca invente CRECI, CNPJ ou documento; diga que confirma com a equipe",
    "equipe_disse": "você escreveu \"{x}\", mas NENHUMA resposta da equipe está na conversa: nunca invente o que a equipe ou o dono disse; diga que vai confirmar",
}


def _sem_acento(t: str) -> str:
    return unicodedata.normalize("NFKD", t or "").encode("ascii", "ignore").decode()


def _reais(numero: str, escala: str | None) -> int | None:
    """'2.500' -> 2500; '2.500,00' -> 2500; '3' + 'mil' -> 3000; '1,2' + 'milhão' -> 1200000."""
    n = numero.strip(".")
    if not n:
        return None
    if "," in n:
        inteiro, dec = n.split(",", 1)
        v = float(inteiro.replace(".", "") + "." + dec)
    else:
        v = float(n.replace(".", ""))
    e = _sem_acento(escala or "").strip().lower()
    if e.startswith("mil") and not e.startswith("milh"):
        v *= 1000
    elif e.startswith("milh"):
        v *= 1_000_000
    return int(round(v))


def numeros_do_turno(turno: str) -> set[int]:
    """Todos os números que o modelo recebeu, em reais inteiros, em toda forma que costumam vir: 2500, 2.500, 2500.0,
    R$ 2.500,00, 3 mil, 1,2 milhão. É contra eles que valor e código do balão são conferidos."""
    nums: set[int] = set()
    for m in re.finditer(r"(\d[\d.]*(?:,\d+)?)(\s*(?:mil|milh[õo]es|milh[ãa]o)\b)?", turno or "", re.I):
        bruto, escala = m.group(1), m.group(2)
        try:
            nums.add(_reais(bruto, escala))
            if re.fullmatch(r"\d+\.\d+", bruto):            # 2500.0 (o float do banco) e 2.500 (o milhar) valem os dois
                nums.add(int(float(bruto)))
        except (TypeError, ValueError):
            continue
    nums.discard(None)
    return nums


def _dela(turno: str) -> str:
    """O que a pessoa escreveu (as linhas CLIENTE: do turno): a palavra que ELA usou a Nay pode usar de volta."""
    return "\n".join(l for l in (turno or "").split("\n") if l.startswith("CLIENTE:"))


def conferir(baloes: list[str], turno: str, organico: bool) -> list[tuple[int, str, str]]:
    """Os furos: [(índice do balão, parede, o trecho)]. Vazio = tudo passou."""
    furos = []
    nums = numeros_do_turno(turno)
    dela = _dela(turno)
    # o documento só vale se o MESMO número aparece junto da palavra (CRECI, CNPJ...) no turno, não solto num preço ou área
    docs = {re.sub(r"\D", "", m.group(2)) for m in DOCUMENTO.finditer(turno or "")}
    for i, b in enumerate(baloes or []):
        b = str(b or "")
        for m in VALOR.finditer(b):
            v = _reais(m.group(1), m.group(2))
            # "até 420" na venda é R$ 420.000 e "3" no aluguel é R$ 3.000: a escala que a Parceria também usa
            if v and v >= 100 and v not in nums and not (v % 1000 == 0 and v // 1000 in nums):
                furos.append((i, "valor", m.group(0).strip()))
        for m in CODIGO.finditer(b):
            if int(m.group(1)) not in nums:
                furos.append((i, "codigo", m.group(1)))
        for m in DOCUMENTO.finditer(b):
            if re.sub(r"\D", "", m.group(2)) not in docs:
                furos.append((i, "documento", m.group(0).strip()))
        m = EQUIPE_DISSE.search(b)
        if m and not RESPOSTA_DA_EQUIPE.search(turno or ""):
            furos.append((i, "equipe_disse", m.group(0)))
        for parede, rx in (("parceria", PARCERIA), ("negativa", NEGATIVA), ("bastidor", BASTIDOR)):
            m = rx.search(b)
            if m and not (parede == "parceria" and rx.search(dela)):      # ela perguntou de parceria: responder não fura
                furos.append((i, parede, m.group(0)))
        if organico:
            m = OLX.search(b)
            if m and not OLX.search(dela):                                # ela mesma falou da OLX ou do anúncio
                furos.append((i, "olx", m.group(0)))
    return furos


def aviso(furos: list[tuple[int, str, str]]) -> str:
    """O aviso da segunda chamada (como o pergunta_a_toa): o que furou, em uma linha por parede."""
    vistos, linhas = set(), []
    for _i, parede, x in furos:
        if (parede, x) in vistos:
            continue
        vistos.add((parede, x))
        linhas.append("- " + AVISO[parede].format(x=x))
    return ("ATENÇÃO, a sua resposta não pode sair assim:\n" + "\n".join(linhas)
            + "\nEscreva de novo a resposta inteira (o mesmo JSON), sem esses pontos.")


def cortar(baloes: list[str], turno: str, organico: bool) -> tuple[list[str], list[tuple[int, str, str]]]:
    """Os balões que passam (o que fura sai inteiro) e os furos que sobraram."""
    furos = conferir(baloes, turno, organico)
    ruins = {i for i, _p, _x in furos}
    return [b for i, b in enumerate(baloes or []) if i not in ruins], furos
