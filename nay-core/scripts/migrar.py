"""Aplica as migrações de nay-core/migrations em ordem, uma vez cada.

Uso:
    python scripts/migrar.py            # aplica o que falta
    python scripts/migrar.py --ensaio   # roda tudo numa transação e desfaz (ROLLBACK)
    python scripts/migrar.py --status   # só lista o que está aplicado e o que falta

Regras:
- a tabela core_migracao guarda arquivo e md5 de cada migração aplicada;
- arquivo já aplicado cujo md5 mudou é RECUSADO: migração aplicada não se
  edita, se escreve outra (entrevista, pergunta 45);
- cada arquivo roda na sua transação, com lock_timeout curto: se o banco
  vivo estiver ocupado, falha em vez de travar a Nay.
"""
from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

import psycopg

PASTA = Path(__file__).resolve().parent.parent / "migrations"
LOCK_TIMEOUT = "3s"


def arquivos() -> list[Path]:
    lista = sorted(PASTA.glob("[0-9][0-9][0-9]_*.sql"))
    numeros = [p.name[:3] for p in lista]
    if len(numeros) != len(set(numeros)):
        raise SystemExit(f"número de migração repetido em {PASTA}")
    return lista


def md5(p: Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()


def aplicadas(cur: psycopg.Cursor) -> dict[str, str]:
    cur.execute("SELECT to_regclass('core_migracao') IS NOT NULL")
    if not cur.fetchone()[0]:
        return {}
    cur.execute("SELECT arquivo, md5 FROM core_migracao")
    return dict(cur.fetchall())


def pendentes(ja: dict[str, str]) -> list[Path]:
    falta = []
    for p in arquivos():
        if p.name in ja:
            if ja[p.name] != md5(p):
                raise SystemExit(f"{p.name} foi editada depois de aplicada: escreva uma migração nova")
            continue
        falta.append(p)
    return falta


def aplicar(conn: psycopg.Connection, p: Path) -> None:
    with conn.cursor() as cur:
        cur.execute(f"SET LOCAL lock_timeout = '{LOCK_TIMEOUT}'")
        cur.execute(p.read_text(encoding="utf-8"))
        cur.execute(
            "INSERT INTO core_migracao (arquivo, md5) VALUES (%s, %s)",
            (p.name, md5(p)),
        )


def main(argv: list[str]) -> int:
    url = os.environ.get("DATABASE_URL_MIGRACAO") or os.environ["DATABASE_URL"]
    ensaio, status = "--ensaio" in argv, "--status" in argv
    with psycopg.connect(url, autocommit=False) as conn:
        with conn.cursor() as cur:
            falta = pendentes(aplicadas(cur))
        if status or not falta:
            print("pendentes:", [p.name for p in falta] or "nenhuma")
            return 0
        for p in falta:
            aplicar(conn, p)
            print(("ensaiada " if ensaio else "aplicada ") + p.name)
            if not ensaio:
                conn.commit()
        if ensaio:
            conn.rollback()
            print("ensaio: tudo desfeito (ROLLBACK)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
