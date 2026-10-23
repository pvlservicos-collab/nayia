"""A saída pela PARCERIA (Z-API, 92 9445-3618) e, para quem já conversava lá, pelo número de LEADS (8595).

- PRIVADO: pela caixa da Nay (nai_saida, papel 'entrega', turno do Tel), entregue pelo nay-enviador-manual. É o caminho
  da Nay proprietários da OLX (nay-captacao/captacao/envio.py): passa pelas paredes da caixa, sai a qualquer hora e o
  eco não vira "o Tel escreveu pelo celular" (nai_tel_assumiu reconhece o que está em nai_saida).
- GRUPO: não existe fila para grupo no banco (nai_chave não aceita id de grupo). Vai direto pela Z-API, como o publicador,
  com o id inteiro ("...-group", nunca só os dígitos), e o id da mensagem fica em saida_do_sistema e em
  privado.cadastro_whats_postada: o eco volta para o grupo e não pode ser lido como imóvel novo.
- LEADS (479, Tel, 23/10): o corretor que respondeu à busca pelo 8595 é perguntado pelo 8595, pela Z-API da captação
  (a do config do vigia, como o nay-olx). O texto fica em captacao_mensagens ('resposta'), que é a conversa do CRM.
"""
from __future__ import annotations

import json
import logging
import os
import re
import time

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


def privado(conn, telefone: str, nome: str | None, textos: list[str], canal: str = "parceria") -> bool:
    """Os balões, na ordem, para a pessoa. True se todos entraram na fila (ou saíram, pelo 8595)."""
    if canal == "leads":
        return leads(conn, telefone, textos)
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


def _captacao() -> dict:
    """A Z-API da captação (8595): base e client_token, do config do vigia (só root lê; nunca vai para o registro)."""
    with open(config.CONF_DO_VIGIA, encoding="utf-8") as f:
        inst = (json.load(f).get("instancias") or {}).get("captacao")
    if not inst or not inst.get("base"):
        raise RuntimeError("não achei a Z-API da captação no config do vigia")
    return inst


def leads(conn, telefone: str, textos: list[str]) -> bool:
    """Pelo 8595, um balão de cada vez. True se todos saíram."""
    inst = _captacao()
    fone = so_digitos(telefone)
    for i, texto in enumerate(textos):
        if i:
            time.sleep(2)
        try:
            r = requests.post(inst["base"] + "/send-text", json={"phone": fone, "message": texto},
                              headers={"Client-Token": inst["client_token"]}, timeout=40)
            j = r.json() if r.content else {}
        except (requests.RequestException, ValueError) as e:
            log.warning("o balão não saiu pelo 8595 para …%s: %s", fone[-4:], type(e).__name__)
            return False
        mid = j.get("messageId") or j.get("id") or j.get("zaapId")
        if r.status_code >= 400 or not mid:
            log.warning("o balão não saiu pelo 8595 para …%s: HTTP %s", fone[-4:], r.status_code)
            return False
        # a conversa do CRM é captacao_mensagens: se o eco da Z-API chegou antes, só vira 'resposta'
        banco.linhas(conn, """
            WITH ja AS (UPDATE captacao_mensagens SET origem = 'resposta' WHERE message_id = %(mid)s AND direcao = 'enviada'
                        RETURNING 1)
            INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status, message_id)
            SELECT coalesce((SELECT m.telefone FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = nay_fone_chave(%(tel)s)
                              ORDER BY m.id DESC LIMIT 1), %(tel)s),
                   'enviada', 'resposta', %(texto)s, 'Enviado', %(mid)s WHERE NOT EXISTS (SELECT 1 FROM ja)""",
                     {"mid": str(mid), "tel": fone, "texto": texto})
        banco.linhas(conn, "INSERT INTO saida_do_sistema (message_id, telefone, rota, quem) VALUES (%s, %s, 'nay-cadastro', "
                           "'nay-cadastro') ON CONFLICT DO NOTHING", (str(mid), fone))
    return True


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


def grupo(conn, texto: str, cadastro_id: int | None = None, citar: str | None = None,
          mencionar: list[str] | None = None) -> str | None:
    """Posta no grupo do cadastro. Devolve o id da mensagem (ou None se não saiu). `mencionar`: os telefones marcados
    com @ (o texto leva "@<telefone>")."""
    c = _zapi()
    url = f"https://api.z-api.io/instances/{c['ZAPI_INSTANCIA']}/token/{c['ZAPI_TOKEN']}/send-text"
    corpo = {"phone": config.GRUPO_ID, "message": texto}
    if citar:
        corpo["messageId"] = citar
    if mencionar:
        corpo["mentioned"] = [so_digitos(t) for t in mencionar if so_digitos(t)]
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
