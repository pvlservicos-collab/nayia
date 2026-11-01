"""O que a Nay Leads responderia nas mensagens que a EQUIPE respondeu (Pedro, 01/11/2026: "rode as conversas que foram
assumidas por humanos nas Nays, se fossem elas atender, para comparar o que elas teriam respondido, para ver se elas
teriam bugado").

O agentes_replay.py deixa de fora o turno que só a equipe respondeu (ali a Nay estava fora). Aqui são só esses: cada um
é reconstruído com a conversa até ali (as falas da equipe entram como EQUIPE, como a Nay lê de verdade) e passa pelo
caminho de produção (o mestre, se a chave `agentes` está em 'sim'; o prompt e as duas conferências: a pergunta à toa e as
paredes), sem mandar nada a ninguém.

  python -m olx.replay_humanos                 ontem e hoje (Manaus)
  python -m olx.replay_humanos --dias 2        anteontem, ontem e hoje
Resultado: replay/humanos_<carimbo>.jsonl e o texto lado a lado na saída.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta

from olx import agentes, banco, modelo, paredes, whatsapp
from olx.agentes_replay import PASTA, _manaus_dia, _quem, lead_no_turno, turnos


def rodar_um(conn, t: dict, modo: str) -> dict:
    lead = lead_no_turno(conn, t)
    ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
    turno = whatsapp.montar_turno(lead, ctx_olx, t["ctx"])
    nossas = [m for m in t["ctx"] if _quem(m) != "cliente" and (m.get("texto") or "").strip()]
    pode_calar = bool(nossas) and not nossas[-1]["texto"].strip().endswith("?")
    prompt, rotas = whatsapp.PROMPT, None
    if modo == "sim":
        agentes.forcar_modo("sim", "replay")
        try:
            agentes.novo_turno(lead)
            plano = agentes.planejar(whatsapp.PROMPT, lead, t["ctx"], t["novas"], whatsapp.organico(lead), pode_calar)
        finally:
            agentes.forcar_modo(None, None)
        if plano["calar"]:
            return {"baloes": [], "acoes": [], "calou": True, "rotas": plano.get("rotas")}
        prompt, rotas = plano["prompt"], plano.get("rotas")
    r = modelo.chamar(prompt, turno, no="olx.replay")
    conferiu = []
    aviso = " ".join(x for x in (whatsapp.pergunta_a_toa(r, t["ctx"]), whatsapp.equipe_a_toa(r, t["novas"])) if x)
    if aviso:
        conferiu.append("perguntou o que já se sabe: " + aviso[:120])
        r = modelo.chamar(prompt, turno + "\n\n" + aviso, no="olx.replay")
    furos = paredes.conferir(whatsapp._baloes_do(r), turno, whatsapp.organico(lead))
    if furos:
        conferiu.append("parede: " + "; ".join(f"{p}: {x}" for _i, p, x in furos)[:160])
        r = modelo.chamar(prompt, turno + "\n\n" + paredes.aviso(furos), no="olx.replay")
        sobra, ainda = paredes.cortar(whatsapp._baloes_do(r), turno, whatsapp.organico(lead))
        if ainda:
            conferiu.append("parede cortou: " + "; ".join(f"{p}: {x}" for _i, p, x in ainda)[:160])
            r["baloes"] = sobra
    return {"baloes": whatsapp._baloes_do(r), "acoes": whatsapp.acoes_da(r), "motivo": r.get("motivo") or "",
            "visita": r.get("visita"), "calou": False, "rotas": rotas, "conferiu": conferiu}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=1)
    a = ap.parse_args()
    conn = banco.conectar()
    desde, ate = _manaus_dia(a.dias), datetime.now(whatsapp.MANAUS) + timedelta(minutes=1)
    lista = [t for t in turnos(conn, desde, ate) if t["equipe"] and not t["real"]]
    modo = agentes.modo()
    PASTA.mkdir(exist_ok=True)
    arq = PASTA / f"humanos_{datetime.now(whatsapp.MANAUS):%Y-%m-%d_%H%M}.jsonl"
    print(f"{len(lista)} turno(s) que só a equipe respondeu, de {desde:%d/%m} até agora (agentes={modo}) -> {arq}", flush=True)
    with arq.open("w", encoding="utf-8") as f:
        for t in lista:
            try:
                r = rodar_um(conn, t, modo)
            except Exception as e:  # noqa: BLE001
                r = {"erro": f"{type(e).__name__}: {e}"[:300]}
            linha = {"id": t["id"], "lead": t["lead"]["id"], "quando": str(t["quando"]), "cliente": t["novas"],
                     "equipe": t["equipe"], **r}
            f.write(json.dumps(linha, ensure_ascii=False, default=str) + "\n")
            f.flush()
            quem = whatsapp.quem(t["lead"])
            print(f"\n{'=' * 90}\n{t['quando']:%d/%m %H:%M} lead {t['lead']['id']} ({quem})", flush=True)
            print("  CLIENTE: " + " / ".join(x for x in t["novas"] if x)[:400])
            for x in t["equipe"][:5]:
                print("  EQUIPE:  " + " ".join(x.split())[:300])
            if r.get("erro"):
                print("  NAY:     ERRO " + r["erro"])
                continue
            for x in r["baloes"] or ["(calaria)" if r.get("calou") else "(nada)"]:
                print("  NAY:     " + " ".join(str(x).split())[:300])
            if r.get("acoes"):
                print("  AÇÕES:   " + ", ".join(r["acoes"]) + (f" · visita {r['visita']}" if r.get("visita") else ""))
            for x in r.get("conferiu") or []:
                print("  (conferência) " + x)


if __name__ == "__main__":
    main()
