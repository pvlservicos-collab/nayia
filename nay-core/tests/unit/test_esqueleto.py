"""O esqueleto se sustenta: todo setor importa, as migrações estão em ordem e as
paredes que valem desde a sessão 1 estão escritas onde devem estar."""
import importlib
import pkgutil
import re
from pathlib import Path

import nay

RAIZ = Path(__file__).resolve().parents[2]
MIGRACOES = sorted((RAIZ / "migrations").glob("[0-9][0-9][0-9]_*.sql"))


def test_todo_modulo_do_nay_importa():
    for m in pkgutil.walk_packages(nay.__path__, "nay."):
        importlib.import_module(m.name)


def test_migracoes_numeradas_sem_buraco_nem_repeticao():
    numeros = [int(p.name[:3]) for p in MIGRACOES]
    assert numeros == list(range(1, len(numeros) + 1))


def test_so_cria_objetos_core():
    criados = []
    for p in MIGRACOES:
        padrao = r"CREATE (?:UNIQUE )?(?:INDEX|TABLE|(?:MATERIALIZED )?VIEW)(?: IF NOT EXISTS)? (\w+)"
        criados += re.findall(padrao, p.read_text(encoding="utf-8"))
    assert criados and all(n.startswith("core_") for n in criados), criados


def test_caixa_de_saida_so_aceita_simulado():
    sql = (RAIZ / "migrations" / "004_core_turno_trace_saida.sql").read_text(encoding="utf-8")
    assert "CHECK (estado = 'simulado')" in sql


def test_limites_de_tamanho():
    import subprocess
    import sys
    r = subprocess.run([sys.executable, str(RAIZ / "scripts" / "limites.py")], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout
