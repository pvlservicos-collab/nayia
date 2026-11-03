"""A NAY DAS DÚVIDAS (Pedro, 03/11/2026): o grupo "Dúvidas Imobeasy", no número da Parceria, com a equipe (Pedro, Diego,
Rayssa, Lucas). "Quero uma Nay tirando dúvida de todos que perguntarem, com um delayzinho para aguardar a mensagem de cada
... 5 segundos ... junta as mensagens que o contato enviou e manda para a Nay, a Nay checa no sistema e devolve a resposta
e ainda sempre um conselho baseado no atendimento do Tel, mas coisas rápidas, pontuais e pequenas".

O caminho, a cada segundo:
  1. as mensagens novas do grupo (privado.grupo_conversa, o espelho do CRM), menos as do próprio número e as já respondidas
     (privado.duvida_grupo_resposta, 575);
  2. por pessoa: espera ela ficar 5 s sem mandar nada e junta tudo o que mandou (o áudio é transcrito);
  3. o sistema: os imóveis citados pelo código, pelo condomínio e pelo bairro (a ficha, o interno e o que a casa já sabe);
  4. uma chamada ao modelo (nó olx.duvidas_grupo), com as regras do Tel (guia_do_tel.txt, do Guia de atendimento do CRM);
  5. a resposta no grupo, marcando a última mensagem da pessoa, pela Z-API da Parceria.

Rodar: python -m olx.grupo_duvidas (systemd nay-duvidas). É a equipe: a Nay pode falar o interno (dono, observação interna).
"""
from __future__ import annotations

import json
import logging
import os
import re
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from olx import banco, duvidas, grupo, modelo

log = logging.getLogger("olx.grupo_duvidas")

NOME_DO_GRUPO = os.environ.get("DUVIDAS_GRUPO_NOME", "duvidas imobeasy")
ESPERA_S = float(os.environ.get("DUVIDAS_ESPERA_S", "5"))          # o "delayzinho" de cada pessoa
VOLTA_S = 1.0                                                       # de quanto em quanto tempo olha o grupo
NO = "olx.duvidas_grupo"                                            # o lugar na página admin › Modelos
MAX_IMOVEIS = 25
GUIA = (Path(__file__).with_name("guia_do_tel.txt")).read_text(encoding="utf-8")

PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus, no grupo interno de WhatsApp "Dúvidas Imobeasy". Quem pergunta
é a EQUIPE (Pedro, Diego, Rayssa, Lucas e o Tel): corretores nossos tirando dúvida rápida de imóvel e de atendimento.

Responda a dúvida de quem perguntou usando SÓ os DADOS DO SISTEMA abaixo e as REGRAS DO TEL. É a equipe: pode dizer o que é
interno (dono e telefone, observação interna, situação, parceiro).
- Curto e direto: de 1 a 4 linhas, português de gente, chame pelo primeiro nome. Sempre com o código do imóvel.
- Perguntou por opções: liste JÁ as que passam no que foi dito (no máximo 5), uma por linha:
  "cód. 1234 · Condomínio/bairro · 3 quartos · R$ 3.500 · mobiliado". NUNCA devolva pergunta de filtro ("prefere casa ou
  apartamento?"): os DADOS DO SISTEMA trazem os imóveis do lugar citado; escolha os que cabem e liste. Nenhum cabe? Diga
  que não tem e o mais perto que tem. Imóvel de parceiro, diga "(parceiro)". Alugado, vendido ou fora do ar, diga a situação.
- NUNCA invente: o que não está nos dados, diga que não achou no sistema e o que vale conferir (com quem: o dono é com a
  Rayssa). Não prometa ação ("vou ver", "já te mando"): você só responde aqui.
- Depois da resposta, UM conselho de no máximo uma frase, PARA quem perguntou (no imperativo: "Pergunte o porte do
  pet antes de levar ao dono"; nunca "eu vou"), prático e ligado ao caso, tirado das REGRAS DO TEL (ex.: pet -> perguntar
  o porte; desconto -> visita antes da proposta; "disponível?" -> mandar card e fotos e já pedir o horário).
  As REGRAS DO TEL são para o atendimento do cliente/corretor; aqui, quem pergunta é da equipe: não aplique as perguntas
  de filtro a ela.
- Se a mensagem não é dúvida (só "ok", "obrigado", "bom dia", conversa entre eles), responder = false.

Devolva SÓ JSON: {"responder": true|false, "resposta": "...", "conselho": "..."}

""" + GUIA

# "o 2944, consegue..." é código; "3.500", "4,5" e "4 mil" não (a vírgula só barra quando vem número depois)
CODIGO = re.compile(r"(?<![\d.,/])(\d{3,4})(?!\d|[.,]\d|\s*(?:mil|reais|k\b|m2|m²))", re.I)

FICHAS = """
SELECT i.codigo, i.status, i.e_parceiro AS parceiro, i.tipo, i.condominio_nome AS condominio, i.bairro, i.quartos, i.suites,
       i.area_util AS area, i.vagas, i.andar, i.mobilia, i.valor_aluguel AS aluguel, i.valor_venda AS venda,
       i.taxa_condominio AS taxa, i.iptu, i.observacao AS observacao_do_card, left(i.descricao, 500) AS descricao,
       i.extras->>'incluso no aluguel' AS incluso, i.extras->>'garantia de aluguel' AS garantia,
       i.extras->>'aceita financiamento' AS financiamento, i.extras->>'permuta' AS permuta,
       p.nome AS dono, p.telefone AS dono_telefone, left(f.observacoes, 500) AS interno,
       (SELECT jsonb_agg(jsonb_build_object(k.assunto, left(k.texto, 200)) ORDER BY k.atualizado_em DESC)
          FROM (SELECT * FROM imovel_conhecimento k WHERE k.codigo = i.codigo::text ORDER BY k.atualizado_em DESC LIMIT 8) k
       ) AS a_casa_sabe,
       'https://imobeasy.online/imovel/' || i.codigo AS link
  FROM imoveis i
  LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
  LEFT JOIN proprietarios p ON p.id = coalesce(ip.proprietario_id, i.proprietario_id)
  LEFT JOIN privado.imovel_ficha f ON f.codigo = i.codigo
 WHERE i.codigo = ANY(%s) AND i.status <> 'Excluído'
"""

# os condomínios e bairros que a pergunta cita (por semelhança de palavra, sem acento; "Acquarelle" acha "Condomínio Acquarelle")
LUGARES = """
WITH t AS (SELECT lower(unaccent(%(texto)s)) AS t),
c AS (SELECT DISTINCT i.condominio_nome AS nome,
             btrim(regexp_replace(lower(unaccent(i.condominio_nome)), '^(condominio|residencial|edificio|ed\\.?|cond\\.?)\\s+', '')) AS limpo
        FROM imoveis i
       WHERE i.status = 'Disponível' AND nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL),
b AS (SELECT DISTINCT i.bairro AS nome, lower(unaccent(i.bairro)) AS limpo FROM imoveis i
       WHERE i.status = 'Disponível' AND coalesce(i.bairro, '') <> '')
SELECT 'condominio' AS tipo, c.nome FROM c, t WHERE length(c.limpo) >= 4 AND word_similarity(c.limpo, t.t) >= 0.88
UNION ALL
-- "Parque 10" acha "Parque 10 de Novembro": vale também o nome até o primeiro " de "
SELECT 'bairro', b.nome FROM b, t WHERE length(b.limpo) >= 4
   AND greatest(word_similarity(b.limpo, t.t), word_similarity(split_part(b.limpo, ' de ', 1), t.t)) >= 0.85
"""

DO_LUGAR = """
SELECT i.codigo FROM imoveis i
 WHERE i.status = 'Disponível' AND (i.condominio_nome = ANY(%(condominios)s) OR i.bairro = ANY(%(bairros)s))
 ORDER BY (i.condominio_nome = ANY(%(condominios)s)) DESC, NOT i.e_parceiro DESC, coalesce(i.valor_aluguel, i.valor_venda)
 LIMIT %(limite)s
"""


def _manaus() -> datetime:
    return datetime.now(timezone(timedelta(hours=-4)))


def achar_grupo(conn) -> str | None:
    """O id do grupo pelo nome (o Pedro criou em 03/11; a primeira mensagem que chega diz o id)."""
    return banco.um(conn, """SELECT grupo_id FROM privado.grupo_conversa
                              WHERE lower(unaccent(coalesce(grupo_nome, ''))) LIKE %s
                              ORDER BY guardada_em DESC LIMIT 1""", (f"%{NOME_DO_GRUPO}%",))


def pendentes(conn, gid: str, desde: datetime) -> list[dict]:
    return banco.linhas(conn, """
        SELECT g.message_id, g.remetente, g.remetente_nome, g.tipo, g.texto, g.midia_url, g.enviada_em, g.guardada_em
          FROM privado.grupo_conversa g
         WHERE g.grupo_id = %s AND NOT g.de_mim AND g.guardada_em > %s
           AND NOT EXISTS (SELECT 1 FROM privado.duvida_grupo_resposta r WHERE r.mensagens @> ARRAY[g.message_id])
         ORDER BY g.enviada_em""", (gid, desde))


def prontos(msgs: list[dict], agora: datetime, espera_s: float = ESPERA_S) -> list[list[dict]]:
    """As levas de quem já ficou `espera_s` segundos sem mandar nada (uma por pessoa, na ordem em que escreveram)."""
    por = defaultdict(list)
    for m in msgs:
        por[m.get("remetente") or m.get("remetente_nome") or "?"].append(m)
    saida = []
    for leva in por.values():
        ultima = max(m["guardada_em"] for m in leva)
        if (agora - ultima).total_seconds() >= espera_s:
            saida.append(leva)
    return sorted(saida, key=lambda l: min(m["enviada_em"] for m in l))


def texto_da_leva(leva: list[dict]) -> str:
    partes = []
    for m in leva:
        t = (m.get("texto") or "").strip()
        if not t and m.get("tipo") in ("audio", "outro") and m.get("midia_url"):
            t = duvidas.transcrever(m["midia_url"])
            t = f"[áudio] {t}" if t else ""
        if not t and m.get("tipo") == "imagem":
            t = "[mandou uma foto]"
        if t:
            partes.append(t)
    return "\n".join(partes)


def codigos_do_texto(texto: str) -> list[int]:
    return list(dict.fromkeys(int(c) for c in CODIGO.findall(texto or "")))


def sistema(conn, texto: str) -> tuple[list[dict], list[int]]:
    """Os imóveis que a pergunta cita: pelo código (qualquer situação), pelo condomínio e pelo bairro (os disponíveis)."""
    citados = codigos_do_texto(texto)
    lugares = banco.linhas(conn, LUGARES, {"texto": texto}) if texto else []
    condos = [l["nome"] for l in lugares if l["tipo"] == "condominio"]
    bairros = [l["nome"] for l in lugares if l["tipo"] == "bairro"]
    do_lugar = []
    if condos or bairros:
        do_lugar = [r["codigo"] for r in banco.linhas(conn, DO_LUGAR, {"condominios": condos, "bairros": bairros,
                                                                       "limite": MAX_IMOVEIS})]
    codigos = list(dict.fromkeys(citados + do_lugar))[:MAX_IMOVEIS]
    fichas = banco.linhas(conn, FICHAS, (codigos,)) if codigos else []
    # o citado primeiro, na ordem em que apareceu
    ordem = {c: k for k, c in enumerate(codigos)}
    fichas.sort(key=lambda f: ordem.get(f["codigo"], 999))
    return fichas, [f["codigo"] for f in fichas]


def _limpo(v):
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def montar_turno(nome: str | None, pergunta: str, fichas: list[dict], agora: datetime | None = None) -> str:
    agora = agora or _manaus()
    dados = [{k: _limpo(v) for k, v in f.items() if v not in (None, "", [], {})} for f in fichas]
    return "\n".join([
        f"AGORA: {agora:%d/%m/%Y %H:%M} em Manaus.",
        f"QUEM PERGUNTOU: {nome or 'alguém da equipe'}",
        "A MENSAGEM (junta, na ordem):",
        pergunta,
        "",
        "DADOS DO SISTEMA (os imóveis que a mensagem cita pelo código, pelo condomínio ou pelo bairro; vazio = nenhum):",
        json.dumps(dados, ensure_ascii=False, default=str) if dados else "(nenhum imóvel citado ou achado)",
    ])


def mensagem_final(r: dict) -> str | None:
    if not r.get("responder"):
        return None
    resposta = str(r.get("resposta") or "").strip()
    if not resposta:
        return None
    conselho = str(r.get("conselho") or "").strip()
    return resposta + (f"\n\n💡 {conselho}" if conselho else "")


def enviar(gid: str, texto: str, citar: str | None) -> tuple[str | None, str | None]:
    """Pela Z-API da Parceria (o config do vigia, como o aviso ao grupo), marcando a mensagem da pessoa. (id, erro)"""
    conf = grupo._conf_do_vigia()
    inst = (conf or {}).get("instancias", {}).get("parceria")
    if not inst:
        return None, "sem a Z-API da Parceria no config do vigia"
    corpo = {"phone": gid, "message": texto}
    if citar:
        corpo["messageId"] = citar
    r = grupo._zapi(inst, "POST", "/send-text", corpo)
    mid = isinstance(r, dict) and (r.get("messageId") or r.get("id") or r.get("zaapId"))
    return (str(mid), None) if mid else (None, str((r or {}).get("_erro") or "sem id"))


def responder(conn, gid: str, leva: list[dict]) -> None:
    inicio = time.monotonic()
    nome = next((m["remetente_nome"] for m in reversed(leva) if m.get("remetente_nome")), None)
    pergunta = texto_da_leva(leva)
    ids = [m["message_id"] for m in leva]
    resposta, codigos, mid, erro = None, [], None, None
    try:
        if pergunta:
            fichas, codigos = sistema(conn, pergunta)
            r = modelo.chamar(PROMPT, montar_turno(nome, pergunta, fichas), no=NO)
            resposta = mensagem_final(r)
            if resposta:
                mid, erro = enviar(gid, resposta, ids[-1])
    except Exception as e:  # noqa: BLE001 -- uma pergunta que falha não para o grupo
        log.exception("dúvida de %s falhou", nome)
        erro = f"{type(e).__name__}: {e}"[:300]
    ultima = max(m["guardada_em"] for m in leva)
    banco.um(conn, """INSERT INTO privado.duvida_grupo_resposta
                        (grupo_id, remetente, remetente_nome, mensagens, pergunta, resposta, codigos, message_id, erro, ms)
                      VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
             (gid, leva[-1].get("remetente"), nome, ids, pergunta[:4000], resposta, codigos or None, mid, erro,
              int((datetime.now(timezone.utc) - ultima).total_seconds() * 1000)))
    conn.commit()
    log.info("dúvida de %s: %s em %.1fs (%s)", nome, "respondida" if mid else "sem resposta",
             time.monotonic() - inicio, erro or f"{len(codigos)} imóveis")


def rodar() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    # só o que chegou depois de ligar (com 2 min de folga): o histórico de antes não é respondido
    desde = datetime.now(timezone.utc) - timedelta(minutes=2)
    conn, gid = None, None
    log.info("Nay das Dúvidas ligada: grupo '%s', espera de %.0fs por pessoa", NOME_DO_GRUPO, ESPERA_S)
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            if not gid:
                gid = achar_grupo(conn)
                conn.commit()
                if gid:
                    log.info("achei o grupo: %s", gid)
            if gid:
                msgs = pendentes(conn, gid, desde)
                conn.commit()
                for leva in prontos(msgs, datetime.now(timezone.utc)):
                    responder(conn, gid, leva)
        except Exception:  # noqa: BLE001
            log.exception("a volta falhou; tento de novo")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(5)
        time.sleep(VOLTA_S)


if __name__ == "__main__":
    rodar()
