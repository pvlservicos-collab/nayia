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
