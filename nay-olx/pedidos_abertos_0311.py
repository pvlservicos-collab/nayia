"""03/11/2026 (Pedro): os pedidos em aberto dos leads numa lista só, nos grupos de busca do 8595.

"desses pedidos abertos vê quais não nos responderam mais e tire, o resto se eles já estão falando conosco a 3 dias
deixa, mas se não manda uma mensagem perguntando se ainda estão buscando imóvel, e se a resposta for sim você pega a
busca dele e joga nos grupos".

Roda UMA vez, à mão, depois do ensaio:

    cd /root/nay-olx && set -a && . ./.env && set +a && nohup .venv/bin/python pedidos_abertos_0311.py \\
        > /root/pedidos_abertos_0311.log 2>&1 &          (--ensaio: só mostra o que sairia, sem esperar e sem mandar)

1. Manda a pergunta aos 3 que falaram por último e ficaram sem resposta (Gleise, Hellen, …5140), 3 a 5 min entre uma e
   outra, pela Nay (whatsapp.mandar_texto), com as mesmas travas da reativação (telefone confere, nada nas últimas 36 h,
   texto parecido não repete).
2. Às 17h30 de Manaus posta a lista nos grupos de busca (privado.busca_grupo), pela regra de cada grupo
   (buscas.grupo_aceita), uma mensagem por grupo, 2 min entre um grupo e outro: os 10 que falaram nos últimos 3 dias + quem
   respondeu SIM (os 3 perguntados e os 4 da reativação desta manhã que ainda não tinham respondido). Só pedido com valor.
   O perfil é relido do banco na hora (a Nay pode ter aprendido o valor na conversa).
3. Depois disso, até as 12h de 04/11: o SIM que chegar tarde ativa a busca da pessoa (estado 'buscando'), e a busca
   automática pede nos grupos, uma por mensagem.
Resposta que não é um sim claro fica no registro para a equipe olhar. Parar: touch /root/pedidos_abertos_0311.parar
"""
import argparse
import json
import os
import random
import re
import time
import unicodedata
from datetime import datetime
from zoneinfo import ZoneInfo

from olx import banco, buscas, whatsapp

MANAUS = ZoneInfo("America/Manaus")
PARAR = "/root/pedidos_abertos_0311.parar"
POSTAR_EM = datetime(2026, 11, 3, 17, 30, tzinfo=MANAUS)
ATE = datetime(2026, 11, 4, 12, 0, tzinfo=MANAUS)

# falaram conosco nos últimos 3 dias: ficam na lista (busca_cliente.id)
ATIVOS = [85, 59, 109, 8, 50, 105, 112, 95, 52, 103]
# a última palavra foi deles e ficou sem resposta: (busca, lead, últimos 8 dígitos, a pergunta)
PERGUNTAR = [
    (94, 119, "93784265", "Boa tarde, Sra. Gleise! A senhora ainda está procurando casa de 2 ou 3 quartos na Zona Sul, até "
                          "R$ 200 mil? Se sim, já peço aos nossos corretores parceiros e te mando as opções por aqui."),
    (7, 7, "87574320", "Boa tarde, Sra. Hellen! Tudo bem? A senhora ainda está procurando apartamento de 2 quartos no "
                       "Japiim? Se sim, me diz até que valor que eu busco novas opções para a senhora."),
    (22, 28, "81685140", "Boa tarde! Desculpe a demora no retorno. Você ainda está procurando apartamento mobiliado de 2 "
                         "quartos para alugar, no Terra Nova, até R$ 5 mil? Se sim, já peço aos nossos corretores parceiros "
                         "e te mando as opções."),
]
# reativados hoje de manhã (reativacao_0311.py) e que ainda não responderam: entram só se disserem sim
REATIVADOS = [(55, 63, "82517640"), (57, 65, "85960606"), (6, 6, "94756680"), (72, 83, "84011447")]

SIM = re.compile(r"\b(sim|ainda|estou|to|continuo|procurando|buscando|quero|pode|claro|isso|com certeza|aguardo)\b")
NAO = re.compile(r"\b(nao|nem|desisti|achei|encontrei|aluguei|comprei|fechei|parei)\b")

# ── a lista (o molde do Tel, o mesmo de buscas.bloco; o que o Pedro aprovou em 03/11) ──
TIPO = (("lote", "LOTE EM CONDOMÍNIO"), ("condom", "CS EM CONDOMÍNIO"), ("cobertura", "COBERTURA"), ("apart", "AP"),
        ("flat", "FLAT"), ("kitnet", "KITNET"), ("casa", "CASA"), ("sala", "SALA"), ("terreno", "TERRENO"))
BAIRRO = {"parque dez": "Parque 10", "aleixo": "Aleixo", "adrianopolis": "Adrianópolis",
          "nossa sra. das graças": "Nossa Senhora das Graças"}


def obs(f: dict) -> str:
    p = []
    mob = {"mobiliado": "mobiliado", "semi": "com modulados e ar", "sem": "sem mobília"}.get(str(f.get("mobilia") or ""))
    if mob and buscas.finalidade(f) == "locacao":
        p.append(mob)
    fz = str(f.get("financiamento") or "").lower()
    if "financ" in fz or fz in ("sim", "aprovado"):
        p.append("aceitar financiamento")
    elif "vista" in fz:
        p.append("pagamento à vista")
    if f.get("condominio"):
        p.append(f"{'só' if f.get('so_condominio') else 'de preferência'} no {f['condominio']}")
    if f.get("perto_de") and f["perto_de"] not in (f.get("bairros") or []):
        p.append(f"perto do {f['perto_de']}")
    if f.get("pet") and "aceita" not in str(f["pet"]):
        p.append(f"aceitar pet ({f['pet']})")
    return "; ".join(p)


def bloco(f: dict) -> str:
    tipo = next((v for k, v in TIPO if k in str(f.get("tipo") or "").lower()), "IMÓVEL")
    bs = [BAIRRO.get(str(b).strip().lower(), str(b).strip()) for b in (f.get("bairros") or []) if str(b).strip()]
    linhas = [f"✅ PRECISO DE {tipo} P/ {'LOCAÇÃO' if buscas.finalidade(f) == 'locacao' else 'VENDA'}",
              "- bairros: " + (", ".join(bs) if bs and f.get("qualquer_bairro") is not True else "qualquer bairro")]
    if buscas.quartos_texto(f):
        linhas.append(f"- {buscas.quartos_texto(f)}")
    linhas.append(f"- até {buscas.valor_curto(f['teto'])}")
    if obs(f):
        linhas.append(f"- OBS: {obs(f)}")
    return "\n".join(linhas)


def lista(fs: list[dict]) -> str:
    fs = sorted(fs, key=lambda f: (buscas.finalidade(f) != "locacao", float(f["teto"])))
    return "🔎 *PEDIDOS DOS NOSSOS CLIENTES*\n\n" + "\n\n".join(bloco(f) for f in fs) + "\n\nTem algum? Me chama no privado."


def agora() -> datetime:
    return datetime.now(MANAUS)


def normal(t: str) -> str:
    return unicodedata.normalize("NFKD", (t or "").lower()).encode("ascii", "ignore").decode()


def respostas(conn, t8: str, desde) -> list[str]:
    return [r["texto"] for r in banco.linhas(conn, """
        SELECT texto FROM captacao_mensagens WHERE direcao = 'recebida' AND criada_em > %s AND texto IS NOT NULL
           AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s ORDER BY criada_em""", (desde, t8))]


def disse_sim(textos: list[str]) -> str:
    """'sim', 'nao' ou '' (não respondeu / não dá para saber: fica no registro)."""
    if not textos:
        return ""
    t = normal(" ".join(textos))
    if NAO.search(t):
        return "nao"
    return "sim" if SIM.search(t) else "?"


def perguntar(conn, cfg: dict, ensaio: bool) -> dict:
    """Manda as perguntas. Devolve {busca: (t8, quando perguntou)}."""
    feitos, primeiro = {}, True
    for bid, lid, f8, texto in PERGUNTAR:
        lead = whatsapp._lead(conn, lid)
        motivo = None
        if not lead:
            motivo = "lead não existe"
        elif whatsapp._so8(lead["telefone"]) != f8:
            motivo = f"telefone não confere (…{lead['telefone'][-8:]} ≠ …{f8})"
        elif lead.get("etapa") in ("fechamento", "finalizado"):
            motivo = f"etapa {lead.get('etapa')}"
        elif not whatsapp._pode(cfg, lead["telefone"]):
            motivo = "a Nay não pode falar com este número (config)"
        elif banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens WHERE criada_em > now() - interval '36 hours'
                               AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s)""", (f8,)):
            motivo = "houve conversa com ele nas últimas 36 h"
        elif any(whatsapp.parecida(texto, x, 0.8) for x in whatsapp.ja_mandou(conn, lead, horas=720)):
            motivo = "texto parecido com um que já foi para ele"
        elif not ensaio and not whatsapp.conectada():
            motivo = "8595 desconectado"
        if motivo:
            print(f"busca {bid} (…{f8}): pergunta NÃO SAIU — {motivo}", flush=True)
            continue
        if ensaio:
            print(f"busca {bid} (…{f8}) {lead.get('nome') or ''}: sairia: {texto}", flush=True)
            feitos[bid] = (f8, banco.um(conn, "SELECT now()"))
            continue
        if not primeiro:
            time.sleep(random.randint(3 * 60, 5 * 60))
        primeiro = False
        try:
            mid = whatsapp.mandar_texto(conn, lead, texto)
            conn.commit()
            feitos[bid] = (f8, banco.um(conn, "SELECT now()"))
            print(f"{agora():%H:%M:%S} busca {bid} (…{f8}): pergunta {'enviada ' + mid if mid else 'segurada (repetida)'}", flush=True)
        except Exception as e:  # noqa: BLE001
            conn.rollback()
            print(f"{agora():%H:%M:%S} busca {bid} (…{f8}): pergunta FALHOU — {e}", flush=True)
    return feitos


def a_esperar(conn, feitos: dict) -> dict:
    """Quem pode entrar se disser sim: {busca: (t8, desde)} (os perguntados + os reativados de hoje)."""
    w = dict(feitos)
    for bid, _lid, f8 in REATIVADOS:
        desde = banco.um(conn, """SELECT max(criada_em) FROM captacao_mensagens WHERE direcao = 'enviada'
                                   AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""", (f8,))
        if desde:
            w[bid] = (f8, desde)
    return w


def filtros(conn, ids: list[int]) -> dict[int, dict]:
    return {r["id"]: r["filtros"] or {} for r in banco.linhas(
        conn, "SELECT id, filtros FROM privado.busca_cliente WHERE id = ANY(%s) AND estado <> 'encerrada'", (ids,))}


def postar(conn, ids: list[int], ensaio: bool) -> None:
    c = buscas._cfg(conn)
    fs = filtros(conn, ids)
    bons = {b: f for b, f in fs.items() if buscas.pronto(f) and f.get("teto") and not buscas.abaixo_do_minimo(f, c)}
    for b in sorted(set(ids) - set(bons)):
        print(f"busca {b}: fora da lista (sem valor, abaixo do mínimo ou encerrada)", flush=True)
    primeiro = True
    for g in banco.linhas(conn, "SELECT * FROM privado.busca_grupo WHERE ativo ORDER BY nome"):
        sel = {b: f for b, f in bons.items() if buscas.grupo_aceita(g, f)}
        if not sel:
            continue
        texto = lista(list(sel.values()))
        if ensaio:
            print(f"\n===== iria para {g['nome']} ({len(sel)} pedidos: {sorted(sel)}) =====\n{texto}\n", flush=True)
            continue
        if not primeiro:
            time.sleep(120)
        primeiro = False
        try:
            mid = buscas._enviar(g["grupo_id"], texto)
        except Exception as e:  # noqa: BLE001
            print(f"{agora():%H:%M:%S} grupo {g['nome']}: FALHOU — {e}", flush=True)
            continue
        banco.um(conn, "UPDATE privado.busca_grupo SET ultimo_envio_em = now() WHERE grupo_id = %s", (g["grupo_id"],))
        item = {"grupo": g["grupo_id"], "nome": g["nome"], "em": agora().isoformat(timespec="minutes"), "mid": mid,
                "teste": False, "lista": True, "texto": texto}
        for b in sel:
            banco.um(conn, "UPDATE privado.busca_cliente SET grupos = grupos || %s::jsonb, grupos_em = now() WHERE id = %s",
                     (json.dumps([item], ensure_ascii=False), b))
            buscas.passo(conn, b, "grupos", f"Pedido no grupo {g['nome']}, na lista dos pedidos em aberto (Pedro, 03/11)")
        conn.commit()
        print(f"{agora():%H:%M:%S} grupo {g['nome']}: lista com {len(sel)} pedidos, {mid}", flush=True)


def ativar(conn, bid: int) -> str:
    r = banco.linhas(conn, "SELECT estado, filtros FROM privado.busca_cliente WHERE id = %s", (bid,))
    if not r:
        return "busca não existe"
    if not r[0]["filtros"].get("teto"):
        return "sem valor: a Nay precisa perguntar o valor antes de ir aos grupos"
    if r[0]["estado"] == "buscando":
        return "já estava buscando (a busca automática segue)"
    banco.um(conn, "UPDATE privado.busca_cliente SET estado = 'buscando', motivo = NULL, ativada_em = now() WHERE id = %s", (bid,))
    buscas.passo(conn, bid, "perfil", "Busca ativada: respondeu que ainda está procurando (Pedro, 03/11)")
    conn.commit()
    return "busca ativada: a busca automática pede nos grupos"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ensaio", action="store_true")
    a = ap.parse_args()
    conn = banco.conectar()
    cfg = banco.chaves(conn)
    feitos = perguntar(conn, cfg, a.ensaio)
    if not a.ensaio:
        while agora() < POSTAR_EM:
            if os.path.exists(PARAR):
                print("parado")
                return
            time.sleep(30)
    espera = a_esperar(conn, feitos)
    sim, vistos = [], {}
    for bid, (f8, desde) in espera.items():
        r = disse_sim(respostas(conn, f8, desde))
        vistos[bid] = r
        print(f"busca {bid} (…{f8}): resposta até agora = {r or 'nenhuma'}", flush=True)
        if r == "sim":
            sim.append(bid)
    if os.path.exists(PARAR):
        print("parado")
        return
    postar(conn, ATIVOS + sim, a.ensaio)
    if a.ensaio:
        return
    # 3. o sim que chega depois da lista ativa a busca
    while agora() < ATE and not os.path.exists(PARAR):
        for bid, (f8, desde) in espera.items():
            if vistos.get(bid) in ("sim", "nao"):
                continue
            r = disse_sim(respostas(conn, f8, desde))
            if r and r != vistos.get(bid):
                vistos[bid] = r
                print(f"{agora():%H:%M:%S} busca {bid} (…{f8}): respondeu = {r}"
                      + (f" — {ativar(conn, bid)}" if r == "sim" else ""), flush=True)
        time.sleep(60)
    print("fim", flush=True)


if __name__ == "__main__":
    main()
