"""As mensagens que chegam no chat da OLX vão para o grupo da equipe no WhatsApp.

Pedro, 15/10/2026: "enquanto o suporte da olx está bloqueando a nay de conversar, quero que as mensagens que cheguem
da olx apareçam para nós lá no grupo".

Quem escreve no nosso anúncio da OLX (o webhook do CRM grava em privado.olx_chat_mensagem, de = 'comprador') vira um
aviso no grupo da equipe: o MESMO grupo do vigia do WhatsApp, pelo número da Parceria (ou pelo da captação, se a
Parceria estiver fora). Mensagens seguidas da mesma pessoa esperam `grupo_silencio_s` e vão num aviso só.

As chaves (privado.olx_config, migração 372):
  avisar_grupo       sim | nao
  grupo_silencio_s   quanto esperar a pessoa terminar de escrever (20)
  grupo_ultimo_id    a última mensagem já avisada; o serviço grava sozinho

A instância da Z-API e o id do grupo NÃO moram aqui nem no banco: são lidos do config.json do vigia
(/root/vigia_whatsapp/config.json, só root lê). Nada disso vai para o log.

Pela linha de comando (no servidor, com o .env carregado):
  python -m olx.grupo ver        o que iria agora para o grupo (não manda nada)
"""
from __future__ import annotations

import json
import logging
import os
import sys
import time
import urllib.error
import urllib.request

log = logging.getLogger("olx.grupo")

CONF_DO_VIGIA = os.environ.get("OLX_GRUPO_CONF", "/root/vigia_whatsapp/config.json")
# esperou isto e a pessoa não parou de escrever: manda assim mesmo
ESPERA_MAXIMA_S = 120
CONTAS = {"proprietarios": "Proprietários", "corretores": "Corretores"}


def telefone_bonito(t: str | None) -> str:
    d = "".join(c for c in (t or "") if c.isdigit())
    if d.startswith("55") and len(d) in (12, 13):
        d = d[2:]
    if len(d) == 11:
        return f"({d[:2]}) {d[2:7]}-{d[7:]}"
    if len(d) == 10:
        return f"({d[:2]}) {d[2:6]}-{d[6:]}"
    return t or ""


def montar_aviso(conversa: dict, mensagens: list[dict]) -> str:
    """Um aviso por conversa: quem é, de qual anúncio, e o que a pessoa escreveu (na ordem)."""
    conta = CONTAS.get(conversa.get("conta") or "", conversa.get("conta") or "")
    quem = (conversa.get("nome") or "").strip() or "alguém sem nome"
    fone = telefone_bonito(conversa.get("telefone"))
    linhas = [f"📩 *Mensagem na OLX* (conta {conta})", f"*{quem}*" + (f" · {fone}" if fone else "")]
    anuncio = []
    if conversa.get("codigo"):
        anuncio.append(f"imóvel {conversa['codigo']}")
    if conversa.get("list_id"):
        anuncio.append(f"anúncio {conversa['list_id']}")
    if anuncio:
        linhas.append(", ".join(anuncio).capitalize())
    linhas.append("")
    for m in mensagens:
        texto = (m.get("texto") or "").strip() or "(sem texto)"
        linhas.append(f"{m.get('hora') or ''} — {texto}".strip(" —"))
    linhas += ["", "Responder pelo CRM › Chat OLX."]
    return "\n".join(linhas)


def agrupar(pendentes: list[dict]) -> list[tuple[dict, list[dict]]]:
    """As mensagens novas, juntas por conversa, na ordem em que a primeira de cada uma chegou."""
    por_chat: dict[int, tuple[dict, list[dict]]] = {}
    for m in pendentes:
        if m["chat"] not in por_chat:
            por_chat[m["chat"]] = (m, [])
        por_chat[m["chat"]][1].append(m)
    return list(por_chat.values())


def pronto_para_mandar(pendentes: list[dict], silencio_s: int) -> bool:
    """Ninguém escreveu nos últimos `silencio_s`, ou a mais antiga já esperou demais."""
    if not pendentes:
        return False
    return (max(m["idade_s"] for m in pendentes) >= ESPERA_MAXIMA_S
            or min(m["idade_s"] for m in pendentes) >= silencio_s)


def pendentes_desde(conn, ultimo: int) -> list[dict]:
    from olx import banco  # aqui dentro: as partes puras (e os testes) rodam sem o psycopg2
    return banco.linhas(conn, """
        SELECT m.id, m.chat, m.texto, to_char(m.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') AS hora,
               extract(epoch FROM now() - m.quando)::int AS idade_s,
               h.conta, h.nome, h.telefone, h.list_id,
               (SELECT a.codigo FROM privado.olx_anuncio a WHERE a.list_id = h.list_id ORDER BY a.id DESC LIMIT 1) AS codigo
          FROM privado.olx_chat_mensagem m
          JOIN privado.olx_chat h ON h.id = m.chat
         WHERE m.id > %s AND m.de = 'comprador'
         ORDER BY m.id
         LIMIT 50""", (ultimo,))


# ---------------------------------------------------------------- Z-API (o mesmo jeito do vigia)
def _zapi(inst: dict, metodo: str, caminho: str, corpo=None, timeout: int = 20):
    """Nunca devolve nem registra a URL: ela carrega a instância e o token."""
    dados = json.dumps(corpo).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request(inst["base"] + caminho, data=dados, method=metodo,
                                 headers={"Client-Token": inst["client_token"], "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"_erro": f"HTTP {e.code}"}
    except Exception as e:  # noqa: BLE001 -- rede ou tempo: só o tipo (a mensagem pode trazer a URL)
        return {"_erro": type(e).__name__}


def _conf_do_vigia() -> dict | None:
    try:
        with open(CONF_DO_VIGIA, encoding="utf-8") as f:
            c = json.load(f)
        return c if c.get("grupo") and c.get("instancias") else None
    except (OSError, ValueError):
        return None


def mandar_ao_grupo(texto: str) -> str | None:
    """Pela Parceria; fora do ar, pela captação. Só por número conectado (desconectado, a Z-API aceitaria e o aviso
    ficaria preso na fila dela). Devolve por qual número saiu, ou None."""
    conf = _conf_do_vigia()
    if not conf:
        log.warning("não achei o grupo nem a Z-API em %s", CONF_DO_VIGIA)
        return None
    for nome in ("parceria", "captacao"):
        inst = conf["instancias"].get(nome)
        if not inst:
            continue
        st = _zapi(inst, "GET", "/status")
        if not (isinstance(st, dict) and st.get("connected")):
            continue
        r = _zapi(inst, "POST", "/send-text", {"phone": conf["grupo"], "message": texto})
        if isinstance(r, dict) and (r.get("messageId") or r.get("id") or r.get("zaapId")):
            return nome
        log.warning("o grupo recusou o aviso pelo número %s: %s", nome, (r or {}).get("_erro") or "sem id")
    return None


def mandar_ao_tel(telefone: str | None, texto: str) -> str | None:
    """16/10 (Pedro): o recado direto no WhatsApp do Tel ("tal cliente não quer falar pelo WhatsApp"). Como o aviso do
    grupo: pela Parceria; fora do ar, pela captação; só por número conectado. Devolve por qual número saiu, ou None."""
    fone = "".join(c for c in str(telefone or "") if c.isdigit())
    conf = _conf_do_vigia()
    if not conf or len(fone) < 12:
        log.warning("recado ao Tel sem número ou sem a Z-API")
        return None
    for nome in ("parceria", "captacao"):
        inst = conf["instancias"].get(nome)
        if not inst:
            continue
        st = _zapi(inst, "GET", "/status")
        if not (isinstance(st, dict) and st.get("connected")):
            continue
        r = _zapi(inst, "POST", "/send-text", {"phone": fone, "message": texto})
        if isinstance(r, dict) and (r.get("messageId") or r.get("id") or r.get("zaapId")):
            return nome
        log.warning("o recado ao Tel não saiu pelo número %s: %s", nome, (r or {}).get("_erro") or "sem id")
    return None


# ---------------------------------------------------------------- o laço
_proxima_tentativa = 0.0


def avisar(conn, cfg: dict[str, str]) -> int:
    """Chamado a cada volta do worker. Devolve quantas conversas foram avisadas."""
    global _proxima_tentativa
    from olx import banco
    if cfg.get("avisar_grupo") != "sim" or time.time() < _proxima_tentativa:
        return 0
    ultimo = int(cfg.get("grupo_ultimo_id") or 0)
    pendentes = pendentes_desde(conn, ultimo)
    if not pronto_para_mandar(pendentes, int(cfg.get("grupo_silencio_s") or 20)):
        return 0
    feitos = 0
    for conversa, mensagens in agrupar(pendentes):
        por = mandar_ao_grupo(montar_aviso(conversa, mensagens))
        if not por:
            # nenhum número conseguiu: tenta de novo daqui a 1 minuto (pode repetir o aviso de uma conversa já mandada)
            _proxima_tentativa = time.time() + 60
            break
        feitos += 1
        log.info("conversa %s: %d mensagem(ns) avisada(s) no grupo pela %s", conversa["chat"], len(mensagens), por)
    else:
        banco.um(conn, "SELECT olx_cfg_gravar('grupo_ultimo_id', %s, 'nay-olx')", (str(pendentes[-1]["id"]),))
    return feitos


def main(argv: list[str]) -> int:
    if argv[:1] != ["ver"]:
        print(__doc__)
        return 2
    from olx import banco
    conn = banco.conectar()
    cfg = banco.chaves(conn)
    print(f"avisar_grupo = {cfg.get('avisar_grupo') or '(sem a chave)'}; última avisada = {cfg.get('grupo_ultimo_id') or 0}")
    pendentes = pendentes_desde(conn, int(cfg.get("grupo_ultimo_id") or 0))
    if not pendentes:
        print("nada novo para o grupo")
    for conversa, mensagens in agrupar(pendentes):
        print("-" * 40)
        print(montar_aviso(conversa, mensagens))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
