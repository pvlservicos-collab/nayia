"""A saída pela PARCERIA (Z-API, 92 9445-3618).

- PRIVADO: pela caixa da Nay (nai_saida, papel 'entrega', turno do Tel), entregue pelo nay-enviador-manual. É o caminho
  da Nay proprietários da OLX (nay-captacao/captacao/envio.py): passa pelas paredes da caixa, sai a qualquer hora e o
  eco não vira "o Tel escreveu pelo celular" (nai_tel_assumiu reconhece o que está em nai_saida).
- GRUPO: não existe fila para grupo no banco (nai_chave não aceita id de grupo). Vai direto pela Z-API, como o publicador,
  com o id inteiro ("...-group", nunca só os dígitos), e o id da mensagem fica em saida_do_sistema e em
  privado.cadastro_whats_postada: o eco volta para o grupo e não pode ser lido como imóvel novo.
"""
from __future__ import annotations

import logging
import os
import re

import requests

from cadastro import banco, config

log = logging.getLogger("cadastro.envio")

PRIVADO = """
WITH t AS (
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
          left('Nay do cadastro para ' || %(tel)s || ': ' || %(texto)s, 500))
  RETURNING id
)
SELECT t.id AS turno,
       nai_enfileirar_texto(t.id, NULL, nai_contato_do_cadastro(%(tel)s, nullif(%(nome)s, '')), 'entrega', %(texto)s,
                            'cadastro_whats', %(ordem)s) AS saida
  FROM t
"""


def so_digitos(t: str | None) -> str:
    return re.sub(r"\D", "", t or "")


def privado(conn, telefone: str, nome: str | None, textos: list[str]) -> bool:
    """Os balões, na ordem, para a pessoa. True se todos entraram na fila."""
    ok = True
    for ordem, texto in enumerate(textos, start=1):
        r = banco.uma(conn, PRIVADO, {"tel": so_digitos(telefone), "nome": nome or "", "texto": texto, "ordem": ordem})
        if not r or not r["saida"]:
            log.warning("o balão não entrou na fila para …%s", so_digitos(telefone)[-4:])
            ok = False
            continue
        banco.linhas(conn, "UPDATE nai_saida SET enviar_apos = now() + make_interval(secs => %s) "
                           "WHERE id = %s AND estado = 'pendente'", (2 * (ordem - 1), r["saida"]))
        banco.linhas(conn, "UPDATE nai_turno SET fechado_em = now() WHERE id = %s", (r["turno"],))
    return ok


_credenciais: dict | None = None


def _zapi() -> dict:
    """As credenciais da Parceria, do .env do publicador (lidas uma vez; nunca vão para o registro)."""
    global _credenciais
    if _credenciais is None:
        valores = {}
        with open(config.ZAPI_ENV, encoding="utf-8") as f:
            for linha in f:
                linha = linha.strip()
                if "=" in linha and not linha.startswith("#"):
                    k, v = linha.split("=", 1)
                    valores[k.strip()] = v.strip().strip('"').strip("'")
        _credenciais = {k: os.environ.get(k) or valores.get(k, "") for k in ("ZAPI_INSTANCIA", "ZAPI_TOKEN", "ZAPI_CLIENT_TOKEN")}
    return _credenciais


def grupo(conn, texto: str, cadastro_id: int | None = None, citar: str | None = None) -> str | None:
    """Posta no grupo do cadastro. Devolve o id da mensagem (ou None se não saiu)."""
    c = _zapi()
    url = f"https://api.z-api.io/instances/{c['ZAPI_INSTANCIA']}/token/{c['ZAPI_TOKEN']}/send-text"
    corpo = {"phone": config.GRUPO_ID, "message": texto}
    if citar:
        corpo["messageId"] = citar
    try:
        r = requests.post(url, json=corpo, headers={"Client-Token": c["ZAPI_CLIENT_TOKEN"]}, timeout=30)
        j = r.json() if r.content else {}
    except (requests.RequestException, ValueError) as e:
        log.warning("o aviso não saiu no grupo: %s", type(e).__name__)   # a exceção pode trazer a URL com o token
        return None
    mid = j.get("messageId") or j.get("id") or j.get("zaapId")
    if r.status_code >= 400 or not mid:
        log.warning("o aviso não saiu no grupo: HTTP %s", r.status_code)
        return None
    banco.linhas(conn, "INSERT INTO privado.cadastro_whats_postada (message_id, cadastro_id, texto) VALUES (%s, %s, %s) "
                       "ON CONFLICT DO NOTHING", (mid, cadastro_id, texto[:2000]))
    banco.linhas(conn, "INSERT INTO saida_do_sistema (message_id, telefone, rota, quem) VALUES (%s, %s, 'nay-cadastro', "
                       "'nay-cadastro') ON CONFLICT DO NOTHING", (mid, config.GRUPO_ID))
    return str(mid)
