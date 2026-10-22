"""O modelo de cada nó e o registro do uso (470, Pedro 22/10/2026: a página admin › Modelos).

"Dando a opção de substituirmos esses modelos por lá, e um contador de quanto estamos gastando em cada modelo, por nó".
  modelo(nó, padrão)        o modelo escolhido na página (privado.ia_no_modelo), lido de 60 em 60 s; sem banco, o padrão
  registrar(nó, modelo, r)  grava os tokens do `usage` que a OpenAI devolve (ia_uso_registrar calcula o custo)
Conexão própria, em autocommit, e falha calada: medir nunca derruba o atendimento nem entra na transação do ensaio.
"""
from __future__ import annotations

import logging
import time

from olx import banco

log = logging.getLogger("olx.ia")
CACHE_S = 60
_CONN: list = [None]
_CACHE: dict[str, tuple[float, str]] = {}
_SEM_BANCO = [0.0]          # a última vez que o banco falhou: espera CACHE_S antes de tentar de novo


def _conn():
    if time.time() - _SEM_BANCO[0] < CACHE_S:
        return None
    c = _CONN[0]
    if c is None or c.closed:
        try:
            c = _CONN[0] = banco.conectar()
        except Exception:  # noqa: BLE001
            _SEM_BANCO[0] = time.time()
            return None
    return c


def _falhou() -> None:
    _SEM_BANCO[0] = time.time()
    try:
        if _CONN[0] is not None:
            _CONN[0].close()
    except Exception:  # noqa: BLE001
        pass
    _CONN[0] = None


def modelo(no: str, padrao: str) -> str:
    guardado = _CACHE.get(no)
    if guardado and time.time() - guardado[0] < CACHE_S:
        return guardado[1]
    c = _conn()
    m = padrao
    if c is not None:
        try:
            r = banco.linhas(c, "SELECT ia_modelo_do_no(%s, %s) AS m", (no, padrao))
            m = (r[0]["m"] if r else None) or padrao
        except Exception:  # noqa: BLE001
            log.warning("não li o modelo do nó %s; sigo com %s", no, padrao)
            _falhou()
    _CACHE[no] = (time.time(), m)
    return m


def registrar(no: str, modelo_usado: str, resposta: dict | None) -> None:
    u = (resposta or {}).get("usage") or {}
    if not u:
        return
    c = _conn()
    if c is None:
        return
    try:
        banco.linhas(c, "SELECT ia_uso_registrar(%s, %s, %s, %s, %s)",
                     (no, (resposta or {}).get("model") or modelo_usado, u.get("input_tokens"),
                      (u.get("input_tokens_details") or {}).get("cached_tokens"), u.get("output_tokens")))
    except Exception:  # noqa: BLE001
        log.warning("não registrei o uso do nó %s", no)
        _falhou()
