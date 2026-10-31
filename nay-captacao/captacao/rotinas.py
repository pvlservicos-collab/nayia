"""As rotinas da captação que eram do n8n da VPS2 (Pedro, 31/10/2026: "tire tudo do n8n"; migração 550).

  VIGIA DO NÚMERO (a cada 2 min; era "Cron da fila parada -> Vigia do numero -> Pausou agora? -> Telegram")
    captacao_vigiar('python') é o disjuntor do disparo antigo: devolve o motivo SÓ quando acabou de pausar. O aviso
    vai às Notificações do CRM (nay_aviso_equipe, 508). Telegram desligado (Pedro, 31/10).
  RELATÓRIO DO DIA (a cada 10 min; era o fluxo "Nay - relatorio da captacao (18h)")
    captacao_relatorio_da_vez('python') decide a hora e devolve a linha UMA vez por dia; sai ao Tel pela Z-API da
    captação, como no fluxo. Se não sair, vai às Notificações do CRM (o dia já foi marcado no banco).

CHAVE: captacao_config.rotinas_de = n8n | python. Com 'n8n' este laço não faz nada; a guarda está no banco (550),
então os dois chamadores podem rodar juntos sem avisar duas vezes. Voltar atrás = a chave em 'n8n'.
"""
from __future__ import annotations

import logging
import threading
import time

from captacao import banco, envio

log = logging.getLogger("captacao.rotinas")
QUEM = "python"
VIGIA_A_CADA_S = 120
RELATORIO_A_CADA_S = 600
CHAVE = "SELECT coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'rotinas_de')), ''), 'n8n') AS quem"
AVISO = ("O disparo parou; a Nay continua respondendo quem escrever. Confira o número e religue pelo painel: "
         "Captação > Captação WhatsApp > Disparo.")


def vigiar(conn) -> str | None:
    r = banco.linhas(conn, "SELECT captacao_vigiar(%s) AS motivo", (QUEM,))
    motivo = r[0]["motivo"] if r else None
    if motivo:
        banco.linhas(conn, "SELECT nay_aviso_equipe('nay-captacao', 'outro', %s, %s, NULL) AS id",
                     ("🛑 Captação (8595-6408) pausou sozinha", f"{motivo}\n\n{AVISO}"))
        log.warning("vigia: a captação pausou sozinha: %s", motivo)
    return motivo


def relatorio(conn) -> int:
    saidas = banco.linhas(conn, 'SELECT phone, message, "delayMessage" AS delay FROM captacao_relatorio_da_vez(%s)', (QUEM,))
    for r in saidas:
        if envio.pela_captacao(r["phone"], r["message"], r["delay"]):
            log.info("relatório do dia enviado ao …%s", str(r["phone"])[-4:])
            continue
        banco.linhas(conn, "SELECT nay_aviso_equipe('nay-captacao', 'relatorio', 'Relatório da captação', %s, NULL) AS id",
                     (r["message"],))
        log.warning("o relatório não saiu pela Z-API; foi às Notificações do CRM")
    return len(saidas)


def uma_volta(conn, ultimo: dict[str, float]) -> None:
    if banco.linhas(conn, CHAVE)[0]["quem"] != QUEM:
        return
    agora = time.monotonic()
    if agora - ultimo.get("vigia", -1e9) >= VIGIA_A_CADA_S:
        ultimo["vigia"] = agora
        vigiar(conn)
    if agora - ultimo.get("relatorio", -1e9) >= RELATORIO_A_CADA_S:
        ultimo["relatorio"] = agora
        relatorio(conn)


def rodar(parar: threading.Event) -> None:
    """O laço, numa linha do serviço nay-captacao. Olha a chave a cada minuto."""
    ultimo: dict[str, float] = {}
    while not parar.is_set():
        conn = None
        try:
            conn = banco.conectar()
            uma_volta(conn, ultimo)
        except Exception:  # noqa: BLE001 -- uma volta ruim não derruba o serviço
            log.exception("as rotinas falharam; tento de novo no próximo minuto")
        finally:
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
        parar.wait(60)
