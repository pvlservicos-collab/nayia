"""Texto como chave: a MESMA conta de `site_captacao_chave` no banco (migração 336)."""
from __future__ import annotations

import re
import unicodedata


def normal(s: str | None) -> str:
    """Sem acento, minúsculo, só letra e número, um espaço entre as palavras."""
    sem = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", " ", sem.lower()).strip()


def reais(v) -> str:
    """4000 -> 'R$ 4.000'."""
    try:
        return "R$ " + f"{float(v):,.0f}".replace(",", ".")
    except (TypeError, ValueError):
        return "R$ ?"


# Pedro, 15/10/2026: uma casa saía com 100% para "casa ... que aceite financiamento" e ela não aceita. A IA passou a
# ler o campo `financiamento`; esta frase é a reserva para os pedidos lidos antes disso (e se a IA deixar escapar).
_FINANCIAMENTO = re.compile(r"financ|(?<![a-z])fgts(?![a-z])|minha casa,? minha vida|(?<![a-z])mcmv(?![a-z])|carta de cr[eé]dito")


# 19/10 (Pedro: "teve um cliente que pediu com elevador e o Parque dos Ingleses não tem elevador"): a IA lia "Elevador"
# solto no fim como "próximo ao elevador". O trecho decide quando a leitura não trouxe o campo.
_ELEVADOR = re.compile(r"(?<!sem )(?<!nao precisa de )(?<!não precisa de )\belevador(es)?\b")


SEMI = re.compile(r"\b(modulad|planejad|semi[\s-]?mobil|semimobil)", re.I)
SEM_MOBILIA = re.compile(r"\b(sem mob[ií]lia|sem m[oó]veis|n[aã]o mobiliad|vazio\b|\bcru\b)", re.I)
MOBILIADO = re.compile(r"\b(mobiliad|porteira fechada)", re.I)
CLIMATIZADO = re.compile(r"\b(climatizad|ar[\s-]condicionado|com ar\b)", re.I)


def mobilia_pedida(frase: str | None, do_modelo=None) -> str | None:
    """'mobiliado' | 'semi' | 'climatizado' | 'sem' | None. A frase decide; o modelo só vale quando ela não diz nada.
    20/10 (Júlio): "modulados e climatizado" virava "não disse" e o 9003 MOBILIADO foi com nota 100; "N serve
    totalmente mobiliado, só quer modulados e climatização" é semi (o modulado ganha do "mobiliado" negado)."""
    t = frase or ""
    if SEMI.search(t):
        return "semi"
    if SEM_MOBILIA.search(t):
        return "sem"
    if MOBILIADO.search(t):
        return "mobiliado"
    if CLIMATIZADO.search(t):
        return "climatizado"
    if do_modelo is True:
        return "mobiliado"
    if do_modelo is False:
        return "sem"
    return do_modelo if do_modelo in ("mobiliado", "semi", "climatizado", "sem") else None


def pede_elevador(texto: str | None) -> bool:
    """O pedido pede elevador ("com elevador", "Elevador" solto)?"""
    return bool(_ELEVADOR.search(str(texto or "").lower()))


def pede_financiamento(texto: str | None) -> bool:
    """O pedido fala em financiamento (bancário, FGTS, Minha Casa Minha Vida)?"""
    return bool(_FINANCIAMENTO.search(str(texto or "").lower()))
