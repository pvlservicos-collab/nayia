"""03/11/2026 (Pedro, 02/11: reativação a partir das 19h, "ela precisa olhar a conversa e ver o histórico do dia para saber
se não tem nenhuma visita agendada e olhar a agenda"). Os 9 follow-ups dos corretores da Parceria estão em
followups_agendados (criado_por_nome 'Nay (reativação 03/11)'), e quem envia é o cron do CRM, sem conferir nada. Este
vigia confere cada um ~2 min ANTES da hora e CANCELA (estado 'cancelado', com o motivo em `erro`) se:
  - o corretor tem visita na agenda (nay_agenda_de_visitas, de hoje a +30 dias, pela chave do telefone);
  - a conversa dele no CRM teve QUALQUER mensagem nas últimas 24 h (de qualquer lado: a Nay, a Rayssa ou ele);
  - o agendamento já não está 'agendado' (alguém cancelou ou já saiu).
Só lê o naydb e o crmdb; a única escrita é o cancelamento. Parar o vigia: touch /root/reativacao_parceria_0311.parar
(os agendamentos continuam valendo; para cancelar todos: UPDATE ... estado='cancelado').

    cd /root/nay-olx && set -a && . ./.env && set +a && TZ=America/Manaus setsid nohup .venv/bin/python -u reativacao_parceria_0311.py \\
        > /root/reativacao_parceria_0311.log 2>&1 < /dev/null &        (--ensaio: confere agora, sem cancelar nada)
"""
import argparse
import os
import subprocess
import time
from datetime import datetime, timedelta, timezone

from olx import banco

PARAR = "/root/reativacao_parceria_0311.parar"
ANTES_S = 120
QUEM = "Nay (reativação 03/11)"


def crm(sql: str, escreve: bool = False) -> str:
    pre = "SET ROLE crm;\n" if escreve else ""
    r = subprocess.run(["docker", "exec", "-i", "nay-postgres", "psql", "-U", "nay", "-d", "crmdb", "-X", "-A", "-t",
                        "-v", "ON_ERROR_STOP=1"], input=pre + sql, capture_output=True, text=True, timeout=60)
    if r.returncode:
        raise RuntimeError(r.stderr.strip()[:300])
    return "\n".join(l for l in r.stdout.splitlines() if l and l != "SET").strip()


def pendentes() -> list[dict]:
    out = crm(f"""SELECT f.id || '|' || f.lead_id || '|' || extract(epoch FROM f.enviar_em)::bigint || '|' ||
                         regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g') || '|' || coalesce(l.title, '')
                    FROM followups_agendados f JOIN leads l ON l.id = f.lead_id
                   WHERE f.criado_por_nome = '{QUEM}' AND f.estado = 'agendado' ORDER BY f.enviar_em""")
    res = []
    for linha in out.splitlines():
        fid, lead, ts, fone, nome = linha.split("|", 4)
        res.append({"id": fid, "lead": lead, "quando": datetime.fromtimestamp(int(ts), timezone.utc), "fone": fone, "nome": nome})
    return res


def conflito(conn, f: dict) -> str | None:
    if crm(f"SELECT estado FROM followups_agendados WHERE id = '{f['id']}'") != "agendado":
        return "já não estava agendado (cancelado ou enviado por outro caminho)"
    if len(f["fone"]) < 10:
        return "telefone inválido"
    if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM nay_agenda_de_visitas(
                            date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus',
                            now() + interval '30 days') a WHERE a.chave = nai_chave(%s))""", (f["fone"],)):
        return "tem visita na agenda"
    n = crm(f"""SELECT count(*) FROM lead_activities WHERE lead_id = '{f['lead']}' AND type = 'whatsapp'
                   AND created_at > now() - interval '24 hours'""")
    if n not in ("", "0"):
        return f"a conversa teve {n} mensagem(ns) nas últimas 24 h"
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ensaio", action="store_true")
    a = ap.parse_args()
    conn = banco.conectar()
    fila = pendentes()
    print(f"{len(fila)} agendamentos para vigiar", flush=True)
    for f in fila:
        if not a.ensaio:
            while datetime.now(timezone.utc) < f["quando"] - timedelta(seconds=ANTES_S):
                if os.path.exists(PARAR):
                    print("parado (os agendamentos que faltam continuam valendo)")
                    return
                time.sleep(20)
            if datetime.now(timezone.utc) > f["quando"] + timedelta(minutes=30):
                print(f"{f['nome'][:20]} (…{f['fone'][-4:]}): passou da hora; não conferi", flush=True)
                continue
        try:
            motivo = conflito(conn, f)
        except Exception as e:  # noqa: BLE001 -- sem conseguir conferir, não deixa sair
            motivo = f"não consegui conferir ({e})"
        hora = f["quando"].astimezone().strftime("%H:%M")
        if motivo is None:
            print(f"{hora} {f['nome'][:20]} (…{f['fone'][-4:]}): OK, vai sair", flush=True)
        elif a.ensaio:
            print(f"{hora} {f['nome'][:20]} (…{f['fone'][-4:]}): seria CANCELADO — {motivo}", flush=True)
        else:
            crm(f"""UPDATE followups_agendados SET estado = 'cancelado', erro = '{motivo.replace("'", " ")[:200]}'
                     WHERE id = '{f['id']}' AND estado = 'agendado'""", escreve=True)
            print(f"{hora} {f['nome'][:20]} (…{f['fone'][-4:]}): CANCELADO — {motivo}", flush=True)
    print("fim")


if __name__ == "__main__":
    main()
