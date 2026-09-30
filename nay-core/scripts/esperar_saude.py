"""Espera o container nay-core ficar saudável depois do deploy (até 60 s).

Sai com erro se não ficar: o `make deploy` para ali e ninguém acha que subiu.
"""
from __future__ import annotations

import subprocess
import sys
import time

LIMITE_S = 60


def estado() -> str:
    r = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Health.Status}}", "nay-core"],
        capture_output=True, text=True, check=False,
    )
    return r.stdout.strip() or r.stderr.strip()


def main() -> int:
    fim = time.monotonic() + LIMITE_S
    while time.monotonic() < fim:
        e = estado()
        if e == "healthy":
            print("nay-core saudável")
            return 0
        time.sleep(2)
    print(f"nay-core NÃO ficou saudável em {LIMITE_S} s (último estado: {estado()})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
