"""O CHECKLIST DA VISITA DA PARCERIA NO GRUPO DA EQUIPE (Altarquia Imobeasy). Pedro, 20/10/2026 (migrações 443 e 444).

"Põe aí uma opção dela avisar lá no grupo Altarquia Imobeasy quando ela não conseguir falar com o proprietário, e um
checklist de visita agendada mostrando se ela falou com todos, só nome de imóvel, aí uma lista marcada com o que ela
conseguiu falar (v) proprietário (v) corretor (v) motoboy." Perguntado, ele escolheu: o checklist vai no grupo, a Nay
passa a avisar o motoboy (443) e o proprietário sem resposta em 1 hora vira aviso.

A visita é a da Nay da Parceria (o corretor confirmou e ela passou à Rayssa: `nai_visita_para_a_rayssa`). O banco diz o
que saiu e o que voltou (`privado.visitas_parceria_situacao`, 444); daqui sai, pelo mesmo caminho do aviso do grupo
(olx/grupo.py):
  - o CHECKLIST: o nome do imóvel, o dia e ✅/❌ para proprietário, corretor e motoboy. Sai quando a visita nasce e de
    novo quando alguma coisa muda (o proprietário ou o motoboy respondeu);
  - o AVISO quando ela não conseguiu falar com o proprietário (sem telefone, mensagem barrada), quando ele não responde
    em `visita_dono_sem_resposta_min` (60), e quando a Nay nova anotou a visita e ela não entrou no sistema.
Chaves em privado.olx_config: `visitas_parceria_grupo` (sim | nao) e `visita_dono_sem_resposta_min`.
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta, timezone

from olx import banco, grupo

log = logging.getLogger("olx.visitas_parceria")
MANAUS = timezone(timedelta(hours=-4))
DIAS = ("segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo")
A_CADA_S = 60
DAS, ATE = 7, 22                 # no grupo só de dia; o da noite sai às 7h
FILA_MAX_MIN = 15                # mensagem que ficou na fila mais que isso: o checklist sai assim mesmo
MOTIVO = {"tel_assumiu": "o Tel tinha assumido a conversa e a mensagem ficou parada"}
_ULTIMA = [0.0]


def quando_texto(q: datetime | None) -> str:
    if not q:
        return "dia a combinar"
    q = q.astimezone(MANAUS)
    return f"{q:%d/%m} ({DIAS[q.weekday()]}) às {q:%H}h{q:%M}"


def _ok(estado: str) -> bool:
    return estado == "enviado"


def _linha(rotulo: str, estado: str, respondeu: bool) -> str:
    if _ok(estado):
        return f"✅ {rotulo}" + (" (respondeu)" if respondeu else "")
    if estado == "pendente":
        return f"⏳ {rotulo} (mensagem na fila)"
    return f"❌ {rotulo}"


def checklist(s: dict) -> str:
    """O checklist: só o nome do imóvel, o dia e a lista marcada."""
    return "\n".join([
        f"📋 Visita agendada: {s.get('imovel') or 'imóvel'}",
        f"📅 {quando_texto(s.get('quando'))}",
        _linha("Proprietário", s["dono"], bool(s.get("dono_respondeu"))),
        "✅ Corretor",
        _linha("Motoboy", s["moto"], bool(s.get("moto_respondeu"))),
    ])


def assinatura(s: dict) -> str:
    return f"{s['dono']}|{bool(s.get('dono_respondeu'))}|{s['moto']}|{bool(s.get('moto_respondeu'))}"


def motivo_do_dono(dono: str) -> str:
    """'bloqueado: tel_assumiu' -> o motivo em português; 'sem: sem telefone no cadastro' -> 'sem telefone no cadastro'."""
    o_que = dono.split(":", 1)[1].strip() if ":" in dono else dono
    return MOTIVO.get(o_que, o_que)


def aviso_sem_dono(s: dict) -> str:
    return (f"⚠️ Não consegui falar com o proprietário do {s.get('imovel') or 'imóvel'} (visita {quando_texto(s.get('quando'))}, "
            f"corretor {s.get('corretor') or ''}): {motivo_do_dono(s['dono'])}. Falem com ele, por favor.")


def aviso_sem_resposta(s: dict, minutos: int) -> str:
    tempo = "1 hora" if minutos == 60 else f"{minutos} minutos"
    dono = f" ({s['dono_nome']})" if s.get("dono_nome") else ""
    return (f"⚠️ O proprietário do {s.get('imovel') or 'imóvel'}{dono} não respondeu em {tempo} sobre a visita de "
            f"{quando_texto(s.get('quando'))} (corretor {s.get('corretor') or ''}). Liguem para ele, por favor.")


def aviso_sem_visita(p: dict) -> str:
    return (f"⚠️ A Nay anotou a visita do corretor {p.get('corretor') or ''} ao {p.get('imovel') or 'imóvel'} e a visita "
            f"não entrou no sistema: o proprietário não foi chamado. Falem com ele, por favor.")


def _marcar(conn, vid: int, **campos) -> None:
    cols = ", ".join(campos)
    sets = ", ".join(f"{k} = EXCLUDED.{k}" for k in campos)
    banco.um(conn, f"""INSERT INTO privado.visita_parceria_grupo (visita_id, {cols}) VALUES (%s, {', '.join(['%s'] * len(campos))})
                       ON CONFLICT (visita_id) DO UPDATE SET {sets}, atualizado_em = now()""", (vid, *campos.values()))


def atender(conn, cfg: dict, agora: datetime | None = None) -> int:
    """Uma passada (no máximo uma por minuto). Devolve quantas mensagens foram ao grupo."""
    if cfg.get("visitas_parceria_grupo") != "sim" or time.time() - _ULTIMA[0] < A_CADA_S:
        return 0
    _ULTIMA[0] = time.time()
    agora = agora or datetime.now(MANAUS)
    if not (DAS <= agora.astimezone(MANAUS).hour < ATE):
        return 0
    minutos = max(1, int(cfg.get("visita_dono_sem_resposta_min") or 60))
    feitas = 0
    for s in banco.linhas(conn, """SELECT s.*, g.assinatura, g.alerta_dono_em, g.alerta_sem_resposta_em
                                    FROM privado.visitas_parceria_situacao() s
                                    LEFT JOIN privado.visita_parceria_grupo g USING (visita_id)"""):
        if s.get("assinatura") == "antes da 444":
            continue                         # a visita já andava quando o checklist ligou
        na_fila = "pendente" in (s["dono"], s["moto"])
        velha = s.get("criada_em") and s["criada_em"] < agora - timedelta(minutes=FILA_MAX_MIN)
        if (not na_fila or velha) and assinatura(s) != s.get("assinatura"):
            if grupo.mandar_ao_grupo(checklist(s)):
                _marcar(conn, s["visita_id"], assinatura=assinatura(s), checklist_em=agora)
                feitas += 1
        if s["dono"].startswith(("sem", "bloqueado")) and not s.get("alerta_dono_em"):
            if grupo.mandar_ao_grupo(aviso_sem_dono(s)):
                _marcar(conn, s["visita_id"], alerta_dono_em=agora)
                feitas += 1
        elif (_ok(s["dono"]) and not s.get("dono_respondeu") and not s.get("alerta_sem_resposta_em")
              and s.get("dono_enviado_em") and s["dono_enviado_em"] < agora - timedelta(minutes=minutos)):
            if grupo.mandar_ao_grupo(aviso_sem_resposta(s, minutos)):
                _marcar(conn, s["visita_id"], alerta_sem_resposta_em=agora)
                feitas += 1
        conn.commit()
    for p in banco.linhas(conn, "SELECT * FROM privado.visitas_parceria_sem_visita()"):
        if grupo.mandar_ao_grupo(aviso_sem_visita(p)):
            banco.um(conn, "INSERT INTO privado.visita_ponte_aviso (core_saida_id) VALUES (%s) ON CONFLICT DO NOTHING",
                     (p["core_saida_id"],))
            feitas += 1
        conn.commit()
    # 466 (Pedro, 22/10: "1 hora antes ele vai lembrar a gente no grupo"; e, depois do limite do Claude estourado, sem o
    # agente): o card padrão (visita_card, 464) de toda visita aberta que começa entre 50 e 70 min, uma vez
    if cfg.get("visitas_lembrete_1h", "sim") != "nao":
        for v in banco.linhas(conn, """
                SELECT v.id, visita_card(v.id)->>'texto' AS card FROM nai_visita v
                 WHERE v.excluida_em IS NULL AND v.estado NOT IN ('cancelada', 'expirada', 'encerrada', 'realizada')
                   AND v.quando BETWEEN now() + interval '50 minutes' AND now() + interval '70 minutes'
                   AND NOT EXISTS (SELECT 1 FROM privado.visita_lembrete_grupo l WHERE l.visita_id = v.id)"""):
            if v.get("card") and grupo.mandar_ao_grupo(lembrete(v["card"])):
                banco.um(conn, "INSERT INTO privado.visita_lembrete_grupo (visita_id) VALUES (%s) ON CONFLICT DO NOTHING",
                         (v["id"],))
                feitas += 1
            conn.commit()
    if feitas:
        log.info("visitas da Parceria: %d mensagem(ns) no grupo", feitas)
    return feitas


def lembrete(card: str) -> str:
    """O card e, se o checklist tem ❌, o que falta: "falar com o proprietário", "avisar o motoboy"."""
    falta = []
    for linha in card.splitlines():
        if linha.startswith("❌ Proprietário"):
            falta.append("falar com o proprietário")
        elif linha.startswith("❌ Motoboy"):
            falta.append("avisar o motoboy")
    return "⏰ *Daqui a 1 hora*\n\n" + card + (f"\n\n⚠️ Falta: {' e '.join(falta)}." if falta else "")
