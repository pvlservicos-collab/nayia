"""A NAY LEADS NOVA NAS CONVERSAS DA SEMANA (Pedro, 25/10/2026: "só rodar a nova nas conversas da nay antiga e ver se o
resultado dela é melhor, tiveram várias conversas essa última semana que a nay antiga errou").

Cada turno da Nay Leads dos últimos dias (o que a pessoa escreveu até a Nay responder) é refeito pela Nay de AGORA com a
conversa real até ali, sem gravar nem enviar (o mesmo caminho do _responder_um: o mestre, a Luna, a segunda chamada
avisada, as paredes, os atalhos do código e do valor, e a busca com o veto só lendo). Sem juiz de modelo (Pedro: "se eu
pedi para tu analisar, analisa tu"): o arquivo traz, turno a turno, o que a Nay ANTIGA respondeu de verdade e o que a NOVA
responderia, para ler. Turno sem resposta da Nay (a equipe respondeu) ou de cortesia fica de fora.

  python -m olx.agentes_semana              os últimos 7 dias
  python -m olx.agentes_semana --dias 3 --so 58,61
Saída: replay/semana_<carimbo>.json (lado a lado, por lead e turno).
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from olx import agentes, agentes_erros as ae, agentes_replay as ar, banco, modelo, paredes, whatsapp

def nova_resposta(conn, t: dict) -> dict:
    """A Nay de agora neste turno, como no _responder_um, sem gravar nem enviar."""
    ae._TL.agora = t["quando"]
    lead = ar.lead_no_turno(conn, t)
    ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
    conversa = t["ctx"]
    novas = [n for n in t["novas"] if n.strip()]
    nossas = [m for m in conversa if ar._quem(m) == "nay" and (m.get("texto") or "").strip()]
    pode_calar = bool(nossas) and not nossas[-1]["texto"].strip().endswith("?")
    turno = whatsapp.montar_turno(lead, ctx_olx, conversa)
    out = {"passos": []}
    agentes.novo_turno(lead)
    plano = agentes.planejar(whatsapp.PROMPT, lead, conversa, novas, whatsapp.organico(lead), pode_calar)
    if plano["calar"]:
        return {"baloes": [], "acoes": [], "passos": ["o mestre leu só cortesia: não responde"]}
    r = modelo.chamar(plano["prompt"], turno, no="olx.replay")
    aviso = " ".join(x for x in (whatsapp.pergunta_a_toa(r, conversa), whatsapp.equipe_a_toa(r, novas)) if x)
    if aviso:
        out["passos"].append("chamou de novo: " + aviso[9:120])
        r = modelo.chamar(plano["prompt"], turno + "\n\n" + aviso, no="olx.replay")
    furos = paredes.conferir(whatsapp._baloes_do(r), turno, whatsapp.organico(lead))
    if furos:
        out["passos"].append("parede: " + "; ".join(f"{p}: {x}" for _i, p, x in furos))
        r = modelo.chamar(plano["prompt"], turno + "\n\n" + paredes.aviso(furos), no="olx.replay")
        sobra, ainda = paredes.cortar(whatsapp._baloes_do(r), turno, whatsapp.organico(lead))
        if ainda:
            r["baloes"] = sobra
            out["passos"].append("parede cortou: " + "; ".join(f"{p}: {x}" for _i, p, x in ainda))
    # as camadas sem modelo, a MESMA função do _responder_um
    acoes, passos = whatsapp.depois_do_modelo(conn, lead, r, novas, nossas[-1]["texto"] if nossas else "")
    out["passos"] += [f"{n}: {d}" for n, d in passos]
    out.update({"baloes": whatsapp._baloes_do(r), "acoes": acoes})
    for k in ("fotos", "card", "visita", "motivo"):
        if k in ("motivo",) and not ({"perguntar", "equipe"} & set(acoes)):
            continue
        if r.get(k) and (k == "motivo" or k in acoes):
            out[k] = r[k]
    if "buscar" in acoes:
        lead["filtros"] = whatsapp._filtros(lead.get("filtros"), r.get("filtros"))
        out["busca"] = ae.buscar_sem_mandar(conn, lead, lead["filtros"])
    return out


def rodar_lead(item) -> dict:
    lid, turnos = item
    conn = banco.conectar()
    agentes.forcar_modo("sim", "replay")
    res = []
    try:
        for t in turnos:
            try:
                nova = nova_resposta(conn, t)
            except Exception as e:  # noqa: BLE001
                nova = {"baloes": [], "acoes": [], "falha": f"{type(e).__name__}: {e}"[:200]}
            res.append({"id": t["id"], "quando": str(t["quando"]), "cliente": t["novas"], "antiga": t["real"], "nova": nova})
    finally:
        agentes.forcar_modo(None, None)
        conn.close()
    # 25/10 (Pedro: "não é para mandar para o juiz ... se eu pedi para tu analisar analisa tu"): sem juiz de modelo; a
    # comparação lado a lado fica no arquivo para quem analisa ler
    return {"lead": lid, "turnos": res}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=7)
    ap.add_argument("--so", default="", help="ids de lead, separados por vírgula")
    ap.add_argument("--paralelo", type=int, default=5)
    a = ap.parse_args()
    conn = banco.conectar()
    ts = ar.turnos(conn, ar._manaus_dia(a.dias), ar._manaus_dia(-1))
    conn.close()
    ts = [t for t in ts if t["real"] and not whatsapp.so_agradeceu([n for n in t["novas"] if n.strip()])]
    so = {int(x) for x in a.so.split(",") if x.strip()}
    por_lead = defaultdict(list)
    for t in ts:
        if not so or t["lead"]["id"] in so:
            por_lead[t["lead"]["id"]].append(t)
    with ThreadPoolExecutor(a.paralelo) as ex:
        res = list(ex.map(rodar_lead, sorted(por_lead.items())))
    s = {"leads": len(res), "turnos": sum(len(r["turnos"]) for r in res),
         "turnos_com_falha": sum(1 for r in res for t in r["turnos"] if t["nova"].get("falha"))}
    ar.PASTA.mkdir(exist_ok=True)
    arq = ar.PASTA / f"semana_{datetime.now(whatsapp.MANAUS):%Y-%m-%d_%H%M}.json"
    arq.write_text(json.dumps({"resumo": s, "leads": res}, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(json.dumps(s, ensure_ascii=False, indent=1))
    print(f"arquivo: {arq}")


if __name__ == "__main__":
    main()
