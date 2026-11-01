"""O REPLAY DOS AGENTES (489, Pedro 24/10/2026): "rode as conversas de ontem e hoje e veja se elas obtêm resultados melhores
ou pelo menos iguais do que é hoje, e se der algo errado você já corrige e roda novamente só essa que deu erro".

Cada TURNO das conversas da Nay Leads no período (as mensagens do cliente até a Nay responder) é reconstruído com a conversa
até ali e roda duas vezes, sem mandar nada a ninguém:
  ANTIGO  o prompt inteiro (whatsapp.PROMPT), como é hoje
  NOVO    o mestre (JEV) escolhe o caminho e o atendimento recebe só aquelas regras (ou cala, se for só cortesia)
Um juiz (a Luna) compara as duas respostas às cegas (A e B sorteados) pelas regras da Nay e diz qual é melhor ou empate.
Mede também tokens, tempo e a concordância das ações. O que o NOVO perdeu vai para a lista `perdeu`, para rodar de novo
só esses turnos depois de corrigir: --so <id,id>.

  python -m olx.agentes_replay                      ontem e hoje (Manaus)
  python -m olx.agentes_replay --so 123:45678,...   só esses turnos
  python -m olx.agentes_replay --limite 20          os 20 primeiros (ensaio)
Resultado: replay/<carimbo>.jsonl (um turno por linha) e uma linha 'replay_resumo' em privado.agente_evento (modo replay),
que a aba Arquitetura do CRM mostra.
"""
from __future__ import annotations

import argparse
import json
import random
import re
import time
from datetime import datetime, timedelta
from pathlib import Path

from olx import agentes, banco, modelo, whatsapp

JUIZ = """Você avalia duas respostas candidatas (A e B) da Nay, a atendente de WhatsApp de uma imobiliária de Manaus, para a
MESMA situação. Cada resposta tem os balões (o texto que vai ao cliente) e as ações (o que o sistema faz depois).

As regras que a Nay tem de seguir:
- O roteiro de quem procura imóvel: UMA pergunta por vez (valor, bairros, quartos, mobília só na locação, escada só na venda
  até R$ 500 mil, crédito só na venda), pulando o que o cliente já disse; respondido o que cabe, fecha e pede a ação "buscar".
- Nunca repetir uma pergunta ou frase que já mandou; se perguntou e o cliente não respondeu, esperar.
- Nunca pedir o código do imóvel; nunca negar ("não temos", "não consigo"); nunca inventar o que não está na ficha.
- Visita: só dia e hora exatos; com imóvel, dia e hora, ação "visita"; o "sim" do cliente à confirmação é "confirmou_visita".
- "perguntar" quando precisa da equipe para responder (foto de cômodo, desconto, algo fora da ficha); "equipe" só para
  documentos, contrato, reclamação, falar com uma pessoa, corretor oferecendo parceria.
- Se o cliente só agradeceu ou disse "ok" sem pergunta pendente, NÃO responder (balões vazios) é o certo.
- Português do Brasil natural, curto (um ou dois balões), sem emoji, sem "Como posso te ajudar?".
- Quem veio direto (orgânico) nunca ouve falar de OLX ou anúncio.

Julgue qual resposta segue melhor as regras e atende melhor o cliente NESTE momento. Se as duas forem igualmente boas ou
igualmente ruins, ou só mudarem palavras, é "empate". Responda só este JSON:
{"melhor": "A" | "B" | "empate", "nota_A": 0-10, "nota_B": 0-10, "motivo": "uma frase curta"}"""

PASTA = Path(__file__).resolve().parent.parent / "replay"


def _manaus_dia(dias_atras: int) -> datetime:
    agora = datetime.now(whatsapp.MANAUS)
    return (agora - timedelta(days=dias_atras)).replace(hour=0, minute=0, second=0, microsecond=0)


def _quem(m: dict) -> str:
    if m.get("direcao") == "recebida":
        return "cliente"
    return "nay" if (m.get("nossa") or m.get("origem") == "resposta") else "equipe"


def turnos(conn, desde: datetime, ate: datetime) -> list[dict]:
    """Os turnos do período: um bloco de mensagens do cliente seguido do que veio depois (a Nay ou a equipe)."""
    leads = banco.linhas(conn, """
        SELECT w.* FROM privado.olx_lead_whatsapp w
         WHERE EXISTS (SELECT 1 FROM captacao_mensagens m
                        WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8)
                              = right(regexp_replace(coalesce(w.telefone, ''), '\\D', '', 'g'), 8)
                          AND m.direcao = 'recebida' AND m.criada_em >= %s AND m.criada_em < %s)""", (desde, ate))
    saida = []
    for lead in leads:
        conv = whatsapp._conversa(conn, lead)
        k = 0
        while k < len(conv):
            if conv[k].get("direcao") != "recebida":
                k += 1
                continue
            fim = k
            while fim + 1 < len(conv) and conv[fim + 1].get("direcao") == "recebida":
                fim += 1
            depois = []
            j = fim + 1
            while j < len(conv) and conv[j].get("direcao") != "recebida":
                depois.append(conv[j])
                j += 1
            quando = conv[fim].get("criada_em")
            if quando and desde <= quando < ate:
                saida.append({"id": f"{lead['id']}:{conv[fim].get('id') or fim}", "lead": lead, "ctx": conv[:fim + 1],
                              "novas": [(m.get("texto") or "").strip() for m in conv[k:fim + 1]],
                              "real": [(m.get("texto") or "").strip() for m in depois if _quem(m) == "nay"],
                              "equipe": [(m.get("texto") or "").strip() for m in depois if _quem(m) == "equipe"],
                              "quando": quando})
            k = fim + 1
    return saida


def lead_no_turno(conn, t: dict) -> dict:
    """O lead como estava naquele turno (o que dá para reconstruir): sem os filtros de depois, os imóveis já enviados até ali."""
    lead = dict(t["lead"])
    enviados = banco.linhas(conn, """SELECT DISTINCT codigo FROM privado.olx_cliente_enviada
                                      WHERE lead = %s AND codigo IS NOT NULL AND enviado_em < %s""", (lead["id"], t["quando"]))
    lead["enviados"] = [e["codigo"] for e in enviados]
    lead["filtros"] = {}
    tem_nay = any(_quem(m) == "nay" for m in t["ctx"])
    lead["etapa"] = "imoveis_enviados" if lead["enviados"] else ("filtrar" if tem_nay else "nova")
    lead["visita_aberta"] = None
    lead["imoveis_conhecidos"] = whatsapp.imoveis_da_conversa(conn, lead)
    lead["saber_dos_imoveis"] = whatsapp.saber_dos_imoveis(conn, lead)
    if whatsapp.organico(lead):
        lead["fichas_citadas"] = whatsapp._fichas_citadas(conn, t["ctx"], lead)
    return lead


def _resposta(r: dict) -> str:
    baloes = [str(b).strip() for b in (r.get("baloes") or []) if str(b).strip()]
    return json.dumps({"baloes": baloes, "acoes": whatsapp.acoes_da(r), "motivo": r.get("motivo") or "",
                       "visita": r.get("visita") if "visita" in whatsapp.acoes_da(r) else None}, ensure_ascii=False)


def julgar(turno: str, ref: dict, desafiante: dict) -> dict:
    """O juiz às cegas: a referência e o desafiante em A/B sorteados. resultado: desafiante | empate | referencia | erro."""
    desafiante_e_a = random.random() < 0.5
    a, b = (desafiante, ref) if desafiante_e_a else (ref, desafiante)
    caso = (turno.rsplit("Responda agora", 1)[0] + "\n=== RESPOSTA A ===\n" + _resposta(a) + "\n\n=== RESPOSTA B ===\n"
            + _resposta(b))
    try:
        j = modelo.chamar(JUIZ, caso, no="olx.replay")
    except Exception as e:  # noqa: BLE001
        return {"resultado": "erro", "motivo": str(e)[:200]}
    melhor = str(j.get("melhor") or "").strip().upper()
    resultado = ("empate" if melhor == "EMPATE" else
                 "desafiante" if (melhor == "A") == desafiante_e_a and melhor in ("A", "B") else
                 "referencia" if melhor in ("A", "B") else "erro")
    return {"resultado": resultado, "motivo": j.get("motivo"),
            "nota_desafiante": j.get("nota_A" if desafiante_e_a else "nota_B"),
            "nota_referencia": j.get("nota_B" if desafiante_e_a else "nota_A")}


def rodar_um(conn, t: dict) -> dict:
    lead = lead_no_turno(conn, t)
    ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
    turno = whatsapp.montar_turno(lead, ctx_olx, t["ctx"])
    nossas = [m for m in t["ctx"] if _quem(m) == "nay" and (m.get("texto") or "").strip()]
    pode_calar = bool(nossas) and not nossas[-1]["texto"].strip().endswith("?")

    # ANTIGO: como é hoje
    r_old = modelo.chamar(whatsapp.PROMPT, turno, no="olx.replay")
    u_old = modelo.ultimo_uso()
    # O RUÍDO (24/10): a mesma versão antiga de novo. O modelo não responde igual duas vezes; o quanto a antiga "perde"
    # para ela mesma é a régua: a nova está aprovada se não perder mais que isso.
    r_old2 = modelo.chamar(whatsapp.PROMPT, turno, no="olx.replay")

    # NOVO: o mestre e o atendimento com as regras do caminho
    agentes.forcar_modo("sim", "replay")
    try:
        agentes.novo_turno(lead)
        plano = agentes.planejar(whatsapp.PROMPT, lead, t["ctx"], t["novas"], whatsapp.organico(lead), pode_calar)
    finally:
        agentes.forcar_modo(None, None)
    if plano["calar"]:
        r_new, u_new = {"baloes": [], "acoes": []}, {"tokens_entrada": 0, "tokens_saida": 0, "ms": 0}
    else:
        r_new = modelo.chamar(plano["prompt"], turno, no="olx.replay")
        u_new = modelo.ultimo_uso()

    # OS DOIS JULGAMENTOS: a nova contra a antiga, e a antiga contra ela mesma (o ruído)
    jn = julgar(turno, r_old, r_new)
    jr = julgar(turno, r_old, r_old2)
    resultado = {"desafiante": "novo", "referencia": "antigo"}.get(jn["resultado"], jn["resultado"])
    ruido = {"desafiante": "antigo2", "referencia": "antigo"}.get(jr["resultado"], jr["resultado"])
    return {"id": t["id"], "lead": lead["id"], "quando": str(t["quando"]), "novas": t["novas"], "real": t["real"],
            "equipe": t["equipe"], "rotas": plano.get("rotas"), "calar": plano.get("calar"), "geral": plano.get("geral"),
            "secoes": plano.get("secoes"), "antigo": json.loads(_resposta(r_old)), "novo": json.loads(_resposta(r_new)),
            "acoes_iguais": whatsapp.acoes_da(r_old) == whatsapp.acoes_da(r_new),
            "tokens_antigo": u_old.get("tokens_entrada"), "tokens_novo": u_new.get("tokens_entrada"),
            "ms_antigo": u_old.get("ms"), "ms_novo": u_new.get("ms"),
            "custo_antigo": agentes.custo_luna(u_old), "custo_novo": agentes.custo_luna(u_new),
            "resultado": resultado, "nota_novo": jn.get("nota_desafiante"), "nota_antigo": jn.get("nota_referencia"),
            "motivo": jn.get("motivo"), "ruido": ruido, "motivo_ruido": jr.get("motivo"),
            "antigo2": json.loads(_resposta(r_old2))}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=1, help="quantos dias para trás além de hoje (1 = ontem e hoje)")
    ap.add_argument("--so", default="", help="ids de turno (lead:mensagem) separados por vírgula")
    ap.add_argument("--limite", type=int, default=0)
    a = ap.parse_args()
    conn = banco.conectar()
    desde, ate = _manaus_dia(a.dias), datetime.now(whatsapp.MANAUS) + timedelta(minutes=1)
    lista = turnos(conn, desde, ate)
    so = {x.strip() for x in a.so.split(",") if x.strip()}
    if so:
        lista = [t for t in lista if t["id"] in so]
    # turno que só a equipe respondeu: ali a Nay estava fora (gap da equipe); não entra na comparação
    lista = [t for t in lista if not (t["equipe"] and not t["real"])]
    if a.limite:
        lista = lista[:a.limite]
    PASTA.mkdir(exist_ok=True)
    arq = PASTA / f"{datetime.now(whatsapp.MANAUS):%Y-%m-%d_%H%M}{'_so' if so else ''}.jsonl"
    print(f"{len(lista)} turno(s) de {desde:%d/%m} até agora -> {arq}", flush=True)
    res = []
    with arq.open("w", encoding="utf-8") as f:
        for n, t in enumerate(lista, 1):
            try:
                r = rodar_um(conn, t)
            except Exception as e:  # noqa: BLE001
                r = {"id": t["id"], "resultado": "erro", "motivo": f"{type(e).__name__}: {e}"[:300]}
            res.append(r)
            f.write(json.dumps(r, ensure_ascii=False, default=str) + "\n")
            f.flush()
            print(f"[{n}/{len(lista)}] {r['id']}: {r['resultado']} {r.get('rotas') or ''}{' (calou)' if r.get('calar') else ''}"
                  f" · {r.get('motivo') or ''}"[:220], flush=True)
    cont = {k: sum(1 for r in res if r["resultado"] == k) for k in ("novo", "empate", "antigo", "erro")}
    ruido = {k: sum(1 for r in res if r.get("ruido") == k) for k in ("antigo2", "empate", "antigo")}
    # a antiga contra ela mesma: o juiz escolhe um lado em antigo2 + antigo turnos; metade disso é o quanto qualquer
    # versão "perde" só por acaso. A nova passa se perder no máximo isso (com folga de 1 turno).
    ruido_perde = (ruido["antigo2"] + ruido["antigo"]) / 2
    aprovado = cont["antigo"] <= ruido_perde + 1 and cont["erro"] == 0
    ok = [r for r in res if r["resultado"] != "erro"]
    soma = lambda k: sum((r.get(k) or 0) for r in ok)  # noqa: E731
    resumo = {"turnos": len(res), **cont, "acoes_iguais": sum(1 for r in ok if r.get("acoes_iguais")),
              "calou": sum(1 for r in ok if r.get("calar")), "geral": sum(1 for r in ok if r.get("geral")),
              "tokens_antigo": soma("tokens_antigo"), "tokens_novo": soma("tokens_novo"),
              "custo_antigo": round(soma("custo_antigo"), 5), "custo_novo": round(soma("custo_novo"), 5),
              "ms_antigo_medio": round(soma("ms_antigo") / max(1, len(ok))), "ms_novo_medio": round(soma("ms_novo") / max(1, len(ok))),
              "perdeu": [r["id"] for r in res if r["resultado"] in ("antigo", "erro")], "arquivo": arq.name,
              "so": bool(so), "ruido": ruido, "ruido_perde": ruido_perde, "aprovado": aprovado,
              "resumo": (f"{cont['novo']} melhor, {cont['empate']} igual, {cont['antigo']} pior, {cont['erro']} erro; "
                         f"ruído (antiga x antiga): perde {ruido_perde:g} por acaso; {'APROVADO' if aprovado else 'NÃO aprovado'}")}
    agentes.forcar_modo(None, "replay")
    agentes.registrar({"id": None, "telefone": ""}, "mestre", "replay_resumo", resumo)
    agentes.forcar_modo(None, None)
    print(json.dumps(resumo, ensure_ascii=False, indent=1), flush=True)


if __name__ == "__main__":
    main()
