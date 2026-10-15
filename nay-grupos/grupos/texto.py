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


def pede_financiamento(texto: str | None) -> bool:
    """O pedido fala em financiamento (bancário, FGTS, Minha Casa Minha Vida)?"""
    return bool(_FINANCIAMENTO.search(str(texto or "").lower()))
