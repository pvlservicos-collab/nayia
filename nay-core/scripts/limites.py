"""Confere os limites do projeto: arquivo com até 300 linhas, função com até 60.

Roda no `make lint`. Sai com erro listando quem passou, para a divisão
acontecer antes do commit e não depois (princípio 7 do CLAUDE.md).
"""
from __future__ import annotations

import ast
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
MAX_ARQUIVO = 300
MAX_FUNCAO = 60
PASTAS = ("nay", "scripts", "tests")


def problemas_do_arquivo(p: Path) -> list[str]:
    texto = p.read_text(encoding="utf-8")
    achados = []
    n = len(texto.splitlines())
    if n > MAX_ARQUIVO:
        achados.append(f"{p.relative_to(RAIZ)}: {n} linhas (máximo {MAX_ARQUIVO})")
    for no in ast.walk(ast.parse(texto)):
        if isinstance(no, (ast.FunctionDef, ast.AsyncFunctionDef)):
            tamanho = no.end_lineno - no.lineno + 1
            if tamanho > MAX_FUNCAO:
                onde = f"{p.relative_to(RAIZ)}:{no.lineno} {no.name}"
                achados.append(f"{onde}: {tamanho} linhas (máximo {MAX_FUNCAO})")
    return achados


def main() -> int:
    achados = []
    for pasta in PASTAS:
        for p in sorted((RAIZ / pasta).rglob("*.py")):
            achados += problemas_do_arquivo(p)
    for a in achados:
        print(a)
    return 1 if achados else 0


if __name__ == "__main__":
    sys.exit(main())
