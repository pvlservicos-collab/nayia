"""AS CAMPANHAS QUE O PEDRO LIBERA À MÃO (migração 595). Linha própria (thread) dentro do serviço nay-olx.

Pedro, 03-04/11/2026: "preparar essas 3 listas e as mensagens que combinam para elas, dos modelos, e a Nay para atender
os diferentes tipos; vou liberar manualmente amanhã" (parceiros com imóvel Disponível, donos de imóveis parados, o
feedback dos donos dos Disponíveis; e avisar quem recebeu o imóvel quando o dono baixar o preço).

  1. ENVIO      só o que está 'liberada' (crm_campanha_liberar; ninguém mais põe na fila), um por vez, no horário comercial
                (`campanha_horario`, segunda a sexta, Manaus), com `campanha_intervalo_s` entre um e outro e no máximo
                `campanha_teto_dia` por dia. A reserva (campanha_reservar) refaz as garantias na hora: número da casa,
                imóvel que saiu de Disponível, outra campanha nos últimos 7 dias, conversa nas últimas
                `campanha_espera_conversa_h` horas (espera) e outra Nay com o contato (espera ou só anota; ver abaixo).
                Pela linha da preparação: Parceria (nay_leads_mandar_pela_parceria: a fila do núcleo, a conversa fica
                roxa no CRM), 8595 (a Z-API da captação) ou o número oficial (o MODELO aprovado, pela ponte do CRM).
  2. RESPOSTAS  olx/campanhas_respostas.py: lê, classifica com o modelo, responde curto (no "disponível", as métricas),
                anota e avisa a equipe. NUNCA muda situação nem valor de imóvel.
  3. BAIXA      olx/campanhas_baixa.py: a baixa confirmada pela equipe vai a quem recebeu o imóvel (chave própria, nasce
                desligada).
Chave `campanha_envio` (privado.olx_config): nao | teste (só os números de `whatsapp_teste`) | sim.
"""
from __future__ import annotations

import logging
import os
import random
import re
import threading
import time
from datetime import datetime, timedelta, timezone

import requests

from olx import banco, grupo

log = logging.getLogger("olx.campanhas")
MANAUS = timezone(timedelta(hours=-4))
A_CADA_S = 15
CRM_URL = os.environ.get("CRM_URL", "https://crm.imobeasy.online").rstrip("/")
ENV_DA_CAPTACAO = os.environ.get("OLX_ENV_DA_CAPTACAO", "/root/nay-captacao/.env")
IDIOMA = "pt_BR"
INCERTO = "sem confirmação"      # o pedido saiu e a resposta não voltou: não dá para saber se chegou (não repete)
LISTAS = {"parceiros_disponivel": "corretores parceiros", "donos_parados": "donos de imóveis parados",
          "feedback_disponiveis": "feedback dos disponíveis"}
_PROXIMO = [0.0]


# ── horário, faixas e chaves ──
def _hora(t: str) -> float:
    h, _, m = t.strip().partition(":")
    return int(h) + (int(m) / 60 if m else 0)


def faixas(texto: str | None) -> list[tuple[float, float]]:
    """'8-12,13:30-18' -> [(8, 12), (13.5, 18)]. Faixa ilegível é ignorada."""
    out = []
    for parte in (texto or "").split(","):
        m = re.fullmatch(r"\s*(\d{1,2}(?::\d{2})?)\s*-\s*(\d{1,2}(?::\d{2})?)\s*", parte)
        if m:
            out.append((_hora(m.group(1)), _hora(m.group(2))))
    return out


def no_horario(texto: str | None, agora: datetime | None = None, so_dia_util: bool = True) -> bool:
    agora = (agora or datetime.now(MANAUS)).astimezone(MANAUS)
    if so_dia_util and agora.weekday() >= 5:
        return False
    h = agora.hour + agora.minute / 60
    return any(a <= h < b for a, b in faixas(texto))


def intervalo(texto: str | None, padrao: tuple[int, int] = (120, 300)) -> tuple[int, int]:
    m = re.fullmatch(r"\s*(\d+)\s*-\s*(\d+)\s*", texto or "")
    if not m:
        return padrao
    a, b = int(m.group(1)), int(m.group(2))
    return (min(a, b), max(a, b))


def modo(cfg: dict, chave: str, padrao: str = "nao") -> str:
    v = (cfg.get(chave) or padrao).strip().lower()
    return v if v in ("nao", "teste", "sim") else "nao"


def numero(cfg: dict, chave: str, padrao: int) -> int:
    try:
        return int(re.sub(r"\D", "", cfg.get(chave) or "") or padrao)
    except ValueError:
        return padrao


# ── o número oficial: pela ponte do CRM (o mesmo caminho do nay-captacao, captacao/envio.py) ──
def _da_captacao(chave: str) -> str:
    """Do ambiente ou, se não estiver nele, do .env do nay-captacao (só root lê; o valor nunca vai para o log)."""
    s = os.environ.get(chave, "")
    if s:
        return s
    try:
        with open(ENV_DA_CAPTACAO, encoding="utf-8") as f:
            for linha in f:
                if linha.startswith(chave + "="):
                    return linha.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


def _ponte(corpo: dict) -> dict:
    segredo = _da_captacao("CAPTACAO_OFICIAL_SEGREDO")
    if not segredo:
        return {"ok": False, "erro": "sem o segredo da ponte do número oficial"}
    url = (_da_captacao("CRM_URL") or CRM_URL).rstrip("/")
    try:
        r = requests.post(f"{url}/api/webhooks/captacao-oficial", json=corpo, timeout=40,
                          headers={"x-captacao-segredo": segredo})
    except requests.ConnectTimeout as e:
        return {"ok": False, "erro": f"o CRM não atendeu: {type(e).__name__}"}
    except requests.RequestException as e:
        return {"ok": False, "erro": f"{INCERTO}: {type(e).__name__}"}
    try:
        j = r.json()
        return j if isinstance(j, dict) else {}
    except ValueError:
        return {"ok": False, "erro": (f"o CRM está fora do ar (HTTP {r.status_code})" if r.status_code in (502, 503)
                                      else f"{INCERTO}: HTTP {r.status_code}")}


def oficial_modelo(telefone: str, nome: str, valores: list[str]) -> tuple[str | None, str | None]:
    j = _ponte({"telefone": telefone, "template": {"nome": nome, "idioma": IDIOMA, "valores": valores}})
    return (str(j["messageId"]), None) if j.get("ok") and j.get("messageId") else (None, str(j.get("erro") or "sem id"))


def oficial_texto(telefone: str, texto: str) -> tuple[str | None, str | None]:
    j = _ponte({"telefone": telefone, "texto": texto})
    return (str(j["messageId"]), None) if j.get("ok") and j.get("messageId") else (None, str(j.get("erro") or "sem id"))


# ── o 8595 (Z-API da captação), para quem não é lead da Nay Leads ──
def captacao_texto(conn, telefone: str, texto: str) -> tuple[str | None, str | None]:
    from olx import whatsapp
    if not whatsapp.conectada():
        return None, "o 8595 está desconectado"
    r = grupo._zapi(whatsapp._instancia(), "POST", "/send-text", {"phone": telefone, "message": texto}, timeout=40)
    mid = str((r or {}).get("messageId") or (r or {}).get("id") or "") if isinstance(r, dict) else ""
    if not mid:
        return None, str((r or {}).get("_erro") if isinstance(r, dict) else "sem resposta da Z-API")
    # a conversa do CRM e o "quem falou" (falou_conosco): como a Nay Leads grava (whatsapp._mandar). O eco que chegar
    # antes vira 'resposta' (não é gente da equipe escrevendo: a Nay Corretores não cala por ele)
    banco.um(conn, """
        WITH ja AS (UPDATE captacao_mensagens SET origem = 'resposta' WHERE message_id = %(mid)s AND direcao = 'enviada'
                    RETURNING 1)
        INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status, message_id)
        SELECT %(tel)s, 'enviada', 'resposta', %(texto)s, 'Enviado', %(mid)s WHERE NOT EXISTS (SELECT 1 FROM ja)""",
             {"mid": mid, "tel": telefone, "texto": texto})
    return mid, None


# ── a Parceria: a fila do núcleo (o enviador do core manda; a conversa fica roxa no CRM por 24 h) ──
def parceria_texto(conn, c: dict, texto: str) -> tuple[int | None, str | None]:
    sid = banco.um(conn, "SELECT nay_leads_mandar_pela_parceria(%s, %s, %s, %s, NULL, 24)",
                   (c["telefone"], texto, c.get("nome"), f"campanha {c['lista']} #{c['id']}"))
    return (int(sid), None) if sid else (None, "a Parceria não aceitou (sem contato no núcleo)")


def mandar(conn, c: dict, texto: str, primeira: bool = False) -> dict:
    """Pela linha do contato. No oficial a 1ª é o MODELO (fora da janela de 24 h só modelo); depois, texto livre."""
    if c["linha"] == "oficial":
        mid, erro = (oficial_modelo(c["telefone"], c["modelo"], list(c["modelo_valores"] or []))
                     if primeira else oficial_texto(c["telefone"], texto))
        return {"ok": bool(mid), "mid": mid, "erro": erro}
    if c["linha"] == "parceria":
        sid, erro = parceria_texto(conn, c, texto)
        return {"ok": bool(sid), "saida": sid, "erro": erro}
    mid, erro = captacao_texto(conn, c["telefone"], texto)
    return {"ok": bool(mid), "mid": mid, "erro": erro}


def evento(conn, contato: int, tipo: str, texto: str | None = None, mid: str | None = None, saida: int | None = None,
           dados: dict | None = None) -> None:
    banco.um(conn, """INSERT INTO privado.campanha_evento (contato, tipo, texto, message_id, saida_id, dados)
                      VALUES (%s, %s, %s, %s, %s, %s::jsonb)""",
             (contato, tipo, texto, mid, saida, banco.js(dados) if dados is not None else None))


def nossos_textos(conn, contato: int) -> list[str]:
    return [r["texto"] for r in banco.linhas(conn, """SELECT texto FROM privado.campanha_evento
                                                       WHERE contato = %s AND tipo = 'enviada' AND texto IS NOT NULL""", (contato,))]


# ── o envio ──
def enviados_hoje(conn) -> int:
    return int(banco.um(conn, """SELECT count(*) FROM privado.campanha_contato
                                  WHERE enviada_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'""") or 0)


def pode_enviar(cfg: dict, agora: datetime | None = None) -> str | None:
    """None = pode; senão o porquê (para o log)."""
    if modo(cfg, "campanha_envio") == "nao":
        return "campanha_envio = nao"
    if not no_horario(cfg.get("campanha_horario") or "8-12,13:30-18", agora):
        return "fora do horário comercial"
    if time.time() < _PROXIMO[0]:
        return "intervalo"
    return None


def enviar_um(conn, cfg: dict) -> bool:
    if pode_enviar(cfg):
        return False
    if enviados_hoje(conn) >= numero(cfg, "campanha_teto_dia", 60):
        return False
    # o intervalo vale também depois de reiniciar o serviço
    a, b = intervalo(cfg.get("campanha_intervalo_s"))
    if banco.um(conn, "SELECT max(enviada_em) > now() - make_interval(secs => %s) FROM privado.campanha_contato", (a,)):
        return False
    r = banco.linhas(conn, "SELECT * FROM campanha_reservar(%s)", (modo(cfg, "campanha_envio") == "teste",))
    if not r:
        return False
    c = r[0]
    if c["linha"] == "oficial" and not c.get("modelo"):
        banco.um(conn, "UPDATE privado.campanha_contato SET estado = 'erro', erro = 'oficial sem modelo' WHERE id = %s", (c["id"],))
        return False
    try:
        s = mandar(conn, c, c["mensagem"], primeira=True)
    except Exception as e:  # noqa: BLE001 -- pode ter saído: não repete sozinho
        s = {"ok": False, "erro": f"{INCERTO}: {type(e).__name__}"}
    _PROXIMO[0] = time.time() + random.uniform(a, b)
    if s["ok"]:
        banco.um(conn, """UPDATE privado.campanha_contato SET estado = 'enviada', enviada_em = now(), message_id = %s,
                                 nossas = nossas + 1, atualizado_em = now() WHERE id = %s""",
                 (s.get("mid") or (f"core_saida:{s['saida']}" if s.get("saida") else None), c["id"]))
        evento(conn, c["id"], "enviada", c["mensagem"], s.get("mid"), s.get("saida"),
               {"linha": c["linha"], "modelo": c.get("modelo") if c["linha"] == "oficial" else None})
        log.info("campanha %s #%s: 1ª mensagem a …%s pela %s", c["lista"], c["id"], c["tel8"][-4:], c["linha"])
        return True
    erro = s.get("erro") or "não saiu"
    if erro.startswith(("o 8595 está desconectado", "o CRM não atendeu", "o CRM está fora do ar")):
        # com certeza não saiu: volta para a fila e tenta na próxima volta
        banco.um(conn, """UPDATE privado.campanha_contato SET estado = 'liberada', adiada_em = now(), adiada_motivo = %s,
                                 atualizado_em = now() WHERE id = %s""", (erro[:200], c["id"]))
    else:
        banco.um(conn, "UPDATE privado.campanha_contato SET estado = 'erro', erro = %s, atualizado_em = now() WHERE id = %s",
                 ((erro + (": conferir na conversa antes de mandar de novo" if INCERTO in erro else ""))[:300], c["id"]))
        evento(conn, c["id"], "erro", erro[:300])
    log.warning("campanha #%s não saiu: %s", c["id"], erro)
    return False


def soltar_presos(conn) -> None:
    """Reservado e o serviço caiu no meio: pode ter saído. Vai para 'erro' (conferir), nunca de volta à fila."""
    banco.um(conn, """UPDATE privado.campanha_contato SET estado = 'erro', atualizado_em = now(),
                             erro = 'ficou em enviando (o serviço parou no meio): conferir na conversa antes de mandar de novo'
                       WHERE estado = 'enviando' AND atualizado_em < now() - interval '10 minutes'""")


def atender(conn, cfg: dict) -> None:
    from olx import campanhas_baixa, campanhas_respostas

    def parte(nome, f, *a):
        try:
            f(*a)
        except Exception:  # noqa: BLE001 -- uma parte não derruba as outras
            log.exception("campanhas: %s falhou", nome)
    parte("os presos", soltar_presos, conn)
    parte("o envio", enviar_um, conn, cfg)
    parte("as respostas", campanhas_respostas.atender, conn, cfg)
    parte("o aviso de baixa", campanhas_baixa.atender, conn, cfg)


def laco(a_cada_s: float = A_CADA_S) -> None:
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            atender(conn, banco.chaves(conn))
        except Exception:  # noqa: BLE001
            log.exception("a volta das campanhas falhou; reconecto em 30 s")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(30)
        time.sleep(a_cada_s)


def iniciar() -> threading.Thread:
    t = threading.Thread(target=laco, name="nay-campanhas", daemon=True)
    t.start()
    return t
