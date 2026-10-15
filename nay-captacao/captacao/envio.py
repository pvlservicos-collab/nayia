"""A saída pelo NÚMERO OFICIAL (8456-0874): tudo passa pelo CRM.

O CRM é quem tem o token da Meta e quem grava a conversa na aba Oficial (a Meta não devolve em webhook o que a gente
manda). Por isso a resposta e o modelo saem por `POST /api/webhooks/captacao-oficial`, com o segredo da ponte no
cabeçalho -- o mesmo caminho que o fluxo do n8n usa.

Sem id de mensagem na volta, o envio NÃO aconteceu: quem chama grava 'Falhou', nunca 'Enviado'.
"""
from __future__ import annotations

import logging
import re

import requests

from captacao import config

log = logging.getLogger("captacao.envio")


# o pedido saiu daqui e a resposta não voltou: NÃO dá para saber se a pessoa recebeu. Quem chama não repete sozinho.
INCERTO = "sem confirmação do CRM"


def _chamar(corpo: dict) -> dict:
    try:
        r = requests.post(f"{config.CRM_URL}/api/webhooks/captacao-oficial", json=corpo, timeout=40,
                          headers={"x-captacao-segredo": config.SEGREDO})
    except requests.ConnectTimeout as e:   # nem chegou ao CRM: não saiu
        return {"ok": False, "erro": f"o CRM não atendeu: {e}"}
    except requests.RequestException as e:
        return {"ok": False, "erro": f"{INCERTO}: {e}"}
    try:
        j = r.json()
        return j if isinstance(j, dict) else {}
    except ValueError:
        # 502/503 é o CRM reiniciando (o pedido não entrou); o resto pode ter saído antes de a resposta se perder
        return {"ok": False, "erro": (f"o CRM está fora do ar (HTTP {r.status_code})" if r.status_code in (502, 503)
                                      else f"{INCERTO}: HTTP {r.status_code} sem resposta legível")}


def so_digitos(telefone: str) -> str:
    return re.sub(r"\D", "", telefone or "")


def texto(telefone: str, mensagem: str) -> str | None:
    """Manda um balão. Devolve o id da mensagem na Meta, ou None se não saiu."""
    j = _chamar({"telefone": so_digitos(telefone), "texto": mensagem})
    if not j.get("ok") or not j.get("messageId"):
        log.warning("a resposta não saiu para …%s: %s", so_digitos(telefone)[-4:], j.get("erro") or "sem id da mensagem")
        return None
    return str(j["messageId"])


def modelo(telefone: str, nome: str, idioma: str, valores: list[str]) -> tuple[str | None, str, str | None]:
    """Manda um modelo (template) aprovado. Devolve (id da mensagem, o texto que a pessoa recebeu, erro)."""
    j = _chamar({"telefone": so_digitos(telefone), "template": {"nome": nome, "idioma": idioma, "valores": valores}})
    if not j.get("ok") or not j.get("messageId"):
        return None, str(j.get("texto") or ""), str(j.get("erro") or "sem id da mensagem")
    return str(j["messageId"]), str(j.get("texto") or ""), None


# ── a saída pela PARCERIA (Z-API, 92 9445-3618) ─────────────────────────────────────────────────────────────────
# Pedro, 15/10/2026: "essa Nay vai responder no WhatsApp Parceria" (a Nay proprietários da OLX, migração 374). Não há
# modelo nem janela: a mensagem entra na caixa da Nay (nai_saida, papel 'entrega') e o nay-enviador-manual entrega
# pela Z-API da Parceria, como a Mensagem de negociação da captação ativa.
PARCERIA = """
WITH t AS (
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
          left('Nay proprietários da OLX para ' || %(tel)s || ': ' || %(texto)s, 500))
  RETURNING id
), s AS (
  SELECT t.id AS turno,
         nai_enfileirar_texto(t.id, NULL, nai_contato_do_cadastro(%(tel)s, nullif(%(nome)s, '')), 'entrega', %(texto)s,
                              'olx_proprietario', %(ordem)s) AS saida
    FROM t
)
SELECT turno, saida FROM s
"""


def parceria(conn, telefone: str, nome: str, mensagem: str, ordem: int = 1) -> str | None:
    """Põe o balão na fila da Parceria. Devolve 'fila:<id>' (o id da Z-API chega depois, em nai_saida), ou None."""
    from captacao import banco   # aqui: banco não depende deste módulo, mas o envio oficial não precisa do banco
    r = banco.linhas(conn, PARCERIA, {"tel": so_digitos(telefone), "nome": nome or "", "texto": mensagem, "ordem": ordem})
    if not r or not r[0]["saida"]:
        log.warning("a mensagem não entrou na fila da Parceria para …%s", so_digitos(telefone)[-4:])
        return None
    banco.linhas(conn, "UPDATE nai_saida SET enviar_apos = now() WHERE id = %s AND estado = 'pendente'", (r[0]["saida"],))
    banco.linhas(conn, "UPDATE nai_turno SET fechado_em = now() WHERE id = %s", (r[0]["turno"],))
    return f"fila:{r[0]['saida']}"
