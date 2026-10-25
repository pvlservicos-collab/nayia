"""O modelo da Nay da OLX: o mesmo da Nay de captação (API de Responses da OpenAI, gpt-6-luna).

A chave é a MESMA do nay-captacao: lida do ambiente ou, se não estiver nele, do .env do nay-captacao no mesmo
servidor (só root lê). Nada de cópia da chave, e ela nunca vai para o log.
"""
from __future__ import annotations

import json
import os
import threading
import time

import requests

URL = "https://api.openai.com/v1/responses"
MODELO = os.environ.get("OLX_NAY_MODELO", "gpt-6-luna")
ENV_DA_CAPTACAO = os.environ.get("OLX_ENV_DA_CAPTACAO", "/root/nay-captacao/.env")


class FalhaDoModelo(Exception):
    pass


_ULTIMA = threading.local()


def ultimo_uso() -> dict:
    """489 (os agentes da Nay Leads): os tokens, o modelo e os ms da última chamada DESTA linha (thread)."""
    return dict(getattr(_ULTIMA, "uso", None) or {})


def _chave() -> str:
    k = os.environ.get("OPENAI_API_KEY", "")
    if k:
        return k
    try:
        with open(ENV_DA_CAPTACAO, encoding="utf-8") as f:
            for linha in f:
                if linha.startswith("OPENAI_API_KEY="):
                    return linha.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


def chamar(prompt: str, turno: str, no: str = "olx.chat") -> dict:
    """Manda o prompt e o turno; devolve o JSON que a Nay escreveu (ou levanta FalhaDoModelo).
    470: `no` é o lugar na página admin › Modelos (olx.chat, olx.whatsapp, olx.parceiro): o modelo é o escolhido lá e o
    uso de cada chamada fica registrado."""
    chave = _chave()
    if not chave:
        raise FalhaDoModelo("sem OPENAI_API_KEY")
    from olx import ia
    m = ia.modelo(no, MODELO)
    corpo = {"model": m, "input": [{"role": "system", "content": prompt}, {"role": "user", "content": turno}]}
    ultimo = ""
    inicio = time.monotonic()
    for tentativa in range(3):
        try:
            r = requests.post(URL, timeout=90, json=corpo,
                              headers={"Authorization": f"Bearer {chave}", "Content-Type": "application/json"})
            if r.status_code == 200:
                j = r.json()
                ia.registrar(no, m, j)
                u = j.get("usage") or {}
                _ULTIMA.uso = {"modelo": j.get("model") or m, "ms": int((time.monotonic() - inicio) * 1000),
                               "tokens_entrada": u.get("input_tokens"), "tokens_saida": u.get("output_tokens"),
                               "tokens_cache": (u.get("input_tokens_details") or {}).get("cached_tokens")}
                return ler_json(texto_da(j))
            ultimo = f"HTTP {r.status_code} {r.text[:200]}"
            if r.status_code < 500 and r.status_code != 429:
                break
        except requests.RequestException as e:
            ultimo = f"rede: {type(e).__name__}"
        except ValueError as e:
            ultimo = f"resposta sem JSON: {e}"
        time.sleep(2 + 3 * tentativa)
    raise FalhaDoModelo(ultimo)


def texto_da(resposta: dict) -> str:
    return "".join(c.get("text", "") for o in resposta.get("output") or [] if o.get("type") == "message"
                   for c in o.get("content") or [] if c.get("type") == "output_text")


def ler_json(texto: str) -> dict:
    """O modelo às vezes embrulha o JSON em ```json ... ```: pega do primeiro { ao último }."""
    t = (texto or "").strip()
    i, j = t.find("{"), t.rfind("}")
    if i < 0 or j <= i:
        raise ValueError("sem objeto JSON")
    d = json.loads(t[i:j + 1])
    if not isinstance(d, dict):
        raise ValueError("não é objeto")
    return d
