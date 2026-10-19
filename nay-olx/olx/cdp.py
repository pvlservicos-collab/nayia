"""O Chrome do Agente OLX, pelo protocolo de depuração (416, busca de imóvel de parceiro na OLX).

A OLX barra servidor e navegador sem janela (Cloudflare, medido em 13 e 18/10). O que passa é o Chrome normal, escondido,
do PC do Pedro (`nay-agentes/hermes-painel/navegador-olx.ps1`). O script abre um túnel que publica a porta dele em
127.0.0.1:9304 DESTE servidor (chave `busca_parceiro_cdp`). PC desligado = sem navegador: quem chama decide o que fazer.

Uso: `with Aba(base, url) as a: a.esperar(js)`. Cada página abre numa aba nova e fecha no fim (nunca mexe na aba que o
Pedro possa estar usando pela tela do admin).
"""
from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request

import websocket


class SemNavegador(Exception):
    """O Chrome do PC não respondeu (desligado, túnel caído)."""


def no_ar(base: str, timeout: float = 4.0) -> bool:
    try:
        with urllib.request.urlopen(base.rstrip("/") + "/json/version", timeout=timeout) as r:
            return r.status == 200
    except Exception:  # noqa: BLE001
        return False


class Aba:
    def __init__(self, base: str, url: str) -> None:
        self.base = base.rstrip("/")
        pedido = urllib.request.Request(self.base + "/json/new?" + urllib.parse.quote(url, safe=""), method="PUT")
        try:
            with urllib.request.urlopen(pedido, timeout=20) as r:
                alvo = json.load(r)
        except Exception as e:  # noqa: BLE001
            raise SemNavegador(type(e).__name__) from e
        self.id = alvo["id"]
        # o Chrome responde com a porta DELE (9377, no PC); daqui se fala pela porta do túnel
        porta_daqui = urllib.parse.urlparse(self.base).netloc
        ws_url = re.sub(r"^ws://[^/]+", "ws://" + porta_daqui, alvo["webSocketDebuggerUrl"])
        try:
            self.ws = websocket.create_connection(ws_url, timeout=90, suppress_origin=True)
        except Exception as e:  # noqa: BLE001
            self._fechar_aba()
            raise SemNavegador(type(e).__name__) from e
        self._n = 0

    def _cmd(self, metodo: str, params: dict | None = None, timeout: float = 90) -> dict:
        self._n += 1
        n = self._n
        self.ws.send(json.dumps({"id": n, "method": metodo, "params": params or {}}))
        fim = time.time() + timeout
        while time.time() < fim:
            m = json.loads(self.ws.recv())
            if m.get("id") == n:
                return m.get("result") or {"_erro": m.get("error")}
        raise TimeoutError(metodo)

    def avaliar(self, js: str, timeout: float = 90):
        r = self._cmd("Runtime.evaluate", {"expression": js, "awaitPromise": True, "returnByValue": True}, timeout)
        return ((r or {}).get("result") or {}).get("value")

    def esperar(self, js: str, ate_s: float = 25, passo: float = 0.7):
        """Roda `js` até devolver algo (a página carregando): o valor, ou None no fim do prazo."""
        fim = time.time() + ate_s
        while time.time() < fim:
            v = self.avaliar(js)
            if v:
                return v
            time.sleep(passo)
        return None

    def _fechar_aba(self) -> None:
        try:
            urllib.request.urlopen(urllib.request.Request(self.base + "/json/close/" + self.id), timeout=10).close()
        except Exception:  # noqa: BLE001
            pass

    def fechar(self) -> None:
        self._fechar_aba()
        try:
            self.ws.close()
        except Exception:  # noqa: BLE001
            pass

    def __enter__(self) -> "Aba":
        return self

    def __exit__(self, *exc) -> bool:
        self.fechar()
        return False
