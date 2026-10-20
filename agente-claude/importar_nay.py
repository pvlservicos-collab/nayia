#!/usr/bin/env python3
"""Importa as conversas da Nay Parceria (a Nay nova, nay-core) para o projeto "Nay" do painel. Só leitura no banco.

  importar_nay.py --dias 7 --saida /opt/agente-claude/projetos/nay/dados/conversas
  importar_nay.py --desde 2026-10-13 --ate 2026-10-20 --saida ...

Pedro/Tel, 20/10/2026: "a que revisa a Nay eu quero de uma forma otimizada porque no futuro eu vou subir todas as
conversas da Nay para ele". Em vez de colar conversa no chat, o Claude do projeto lê arquivos:

  conversas/indice.tsv                     uma linha por conversa (dia + corretor): números e RESULTADO, para filtrar
  conversas/AAAA-MM-DD/_resumo.txt         o topo do dia: conversas, visitas marcadas, escaladas
  conversas/AAAA-MM-DD/<tel4>-<id>.txt     a conversa do dia, turno a turno, com o RESULTADO no fim

De onde vem (naydb, VPS1, read only): core_turno (o que o corretor escreveu, modo 'real', papel 'corretor'),
core_saida (o que a Nay mandou, só 'enviado': texto, card, fotos; papel 'tel' = aviso ao Tel). Os rótulos do
RESULTADO saem dos motivos que a própria Nay grava: visita marcada = visita_anotada/visita_entregue; escalada =
escalado (o motivo é o que o corretor escreveu naquele turno); corretor sumiu = a última leva de falas da Nay para ele
pergunta algo ("?") e ele não voltou a escrever em 24 h. O motivo vai entre chaves no fim da fala da Nay ({card}, {lista_vazia}...), para busca.
Telefone: só os 4 últimos dígitos, inclusive dentro dos textos. Horários em Manaus. Reimportar um dia sobrescreve só ele.
"""
import argparse, hashlib, json, os, re, subprocess, sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

VPS1 = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-i", "/root/.ssh/agente_claude_vps1",
        "root@100.86.114.74"]
PSQL = ("docker exec -i -e PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=300000' "
        "nay-postgres psql -U nay -d naydb -X -A -t -v ON_ERROR_STOP=1")
VISITA = {"visita_anotada", "visita_entregue"}

SQL = """
WITH t AS (
  SELECT id, chave, texto, intencao, criado_em FROM core_turno
   WHERE modo = 'real' AND papel = 'corretor'
     AND criado_em >= ('{desde}'::date)::timestamp AT TIME ZONE 'America/Manaus'
     AND criado_em <  ('{ate_mais}'::date)::timestamp AT TIME ZONE 'America/Manaus')
SELECT json_build_object('q', 'corretor', 'turno', t.id, 'chave', t.chave, 'texto', t.texto, 'intencao', t.intencao,
         'em', to_char(t.criado_em AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'))::text FROM t
UNION ALL
SELECT json_build_object('q', CASE WHEN s.papel_destino = 'tel' THEN 'tel' ELSE 'nay' END, 'turno', s.turno_id,
         'chave', t.chave, 'tipo', s.tipo, 'texto', s.texto, 'motivo', s.motivo, 'codigo', s.codigo, 'ordem', s.ordem,
         'em', to_char(coalesce(s.enviado_em, s.criado_em) AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'))::text
  FROM core_saida s JOIN t ON t.id = s.turno_id
 WHERE s.estado = 'enviado';
"""

TELEFONE = re.compile(r"\+?\d[\d\s().-]{7,}\d")


def tel4(chave):
    d = re.sub(r"\D", "", (chave or "").split("@")[0])
    return d[-4:] or "0000"


def mascarar(s):
    """Telefone dentro de texto vira …1234 (só os 4 últimos dígitos)."""
    def troca(m):
        d = re.sub(r"\D", "", m.group(0))
        return "…" + d[-4:] if len(d) >= 8 else m.group(0)
    return TELEFONE.sub(troca, s or "")


def buscar(desde, ate):
    # um dia a mais de turnos do corretor, para saber se ele voltou a escrever depois da última fala da Nay
    sql = SQL.format(desde=desde.isoformat(), ate_mais=(ate + timedelta(days=2)).isoformat())
    p = subprocess.run(VPS1 + [PSQL], input=sql, capture_output=True, text=True, timeout=900)
    if p.returncode:
        sys.exit("o banco recusou: " + (p.stderr or p.stdout).strip()[:500])
    # split("\n") e não splitlines(): este também corta em U+2028 e outros que o JSON deixa dentro do texto
    return [json.loads(l) for l in p.stdout.split("\n") if l.startswith("{")]


def falas(eventos):
    """Junta as fotos seguidas do mesmo turno e imóvel numa linha só: [5 fotos do 9045]."""
    saida = []
    for e in eventos:
        foto = e["q"] == "nay" and e.get("motivo") == "foto"
        ultimo = saida[-1] if saida else None
        if foto and ultimo and ultimo.get("fotos") and ultimo["turno"] == e["turno"] and ultimo["codigo"] == e.get("codigo"):
            ultimo["fotos"] += 1
            continue
        saida.append({**e, "fotos": 1 if foto else 0})
    return saida


def linha(f):
    hora = f["em"][11:16]
    if f["q"] == "corretor":
        return recuo(f"{hora} Corretor: {mascarar(f.get('texto'))}")
    motivo = f.get("motivo") or ""
    if f["fotos"]:
        corpo = f"[{f['fotos']} foto{'s' if f['fotos'] > 1 else ''} do {f.get('codigo') or '?'}]"
    elif motivo == "card" or (f.get("tipo") == "imagem" and not f.get("texto")):
        corpo = f"[card do {f.get('codigo') or '?'}]" + (f" {mascarar(f['texto'])}" if f.get("texto") else "")
    else:
        corpo = mascarar(f.get("texto"))
    quem = "Nay → Tel" if f["q"] == "tel" else "Nay"
    return recuo(f"{hora} {quem}: {corpo}" + (f" {{{motivo}}}" if motivo and not f["fotos"] else ""))


def recuo(s):
    """Fala de várias linhas: as de continuação vão recuadas, para toda fala começar pelo horário."""
    return "\n      ".join(l for l in (s or "").splitlines() if l.strip()) or s


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--dias", type=int, default=7, help="últimos N dias, contando hoje (Manaus)")
    a.add_argument("--desde")
    a.add_argument("--ate")
    a.add_argument("--saida", required=True)
    o = a.parse_args()
    hoje = (datetime.now(timezone.utc) - timedelta(hours=4)).date()
    ate = date.fromisoformat(o.ate) if o.ate else hoje
    desde = date.fromisoformat(o.desde) if o.desde else ate - timedelta(days=max(o.dias, 1) - 1)

    eventos = buscar(desde, ate)
    por_chave_turnos = defaultdict(list)  # todos os turnos do corretor, inclusive o dia seguinte
    conversas = defaultdict(list)          # (dia, chave) -> eventos
    for e in eventos:
        if e["q"] == "corretor":
            por_chave_turnos[e["chave"]].append(e["em"])
        dia = e["em"][:10]
        if desde.isoformat() <= dia <= ate.isoformat():
            conversas[(dia, e["chave"])].append(e)

    os.makedirs(o.saida, exist_ok=True)
    indice_arq = os.path.join(o.saida, "indice.tsv")
    cab = ["dia", "tel4", "arquivo", "primeira", "ultima", "msgs_corretor", "msgs_nay", "cards", "fotos",
           "avisos_tel", "visita_marcada", "escalada", "motivo_escalada", "corretor_sumiu", "imoveis", "intencoes"]
    dias_novos = {d for d, _ in conversas} | {(desde + timedelta(days=i)).isoformat()
                                               for i in range((ate - desde).days + 1)}
    velhas = []
    if os.path.exists(indice_arq):
        with open(indice_arq, encoding="utf-8") as f:
            velhas = [l.rstrip("\n").split("\t") for l in f.readlines()[1:] if l.strip()]
        velhas = [l for l in velhas if l[0] not in dias_novos]

    novas = []
    resumo = defaultdict(lambda: {"conversas": 0, "visitas": 0, "escaladas": 0, "sumiu": 0})
    for dia in sorted(dias_novos):
        pasta_dia = os.path.join(o.saida, dia)
        if os.path.isdir(pasta_dia):
            for n in os.listdir(pasta_dia):
                os.remove(os.path.join(pasta_dia, n))
    for (dia, chave), evs in sorted(conversas.items()):
        ordem = {"corretor": 0, "nay": 1, "tel": 2}
        evs.sort(key=lambda e: (e["em"], e["turno"], ordem[e["q"]], e.get("ordem") or 0))
        fs = falas(evs)
        corretor = [f for f in fs if f["q"] == "corretor"]
        nay = [f for f in fs if f["q"] == "nay"]
        motivos = [f.get("motivo") for f in fs if f["q"] == "nay"]
        visita = any(m in VISITA for m in motivos)
        turnos_escalados = {f["turno"] for f in fs if f.get("motivo") == "escalado"}
        motivo_esc = " | ".join(mascarar(f.get("texto"))[:120] for f in corretor if f["turno"] in turnos_escalados)
        ult = fs[-1]
        # sumiu = a última leva de falas da Nay para ele (depois da última dele) pergunta algo, e ele não voltou em 24 h
        depois = [f for f in fs[max((i for i, f in enumerate(fs) if f["q"] == "corretor"), default=-1) + 1:] if f["q"] == "nay"]
        limite = (datetime.fromisoformat(ult["em"]) + timedelta(hours=24)).isoformat(sep=" ")
        sumiu = (any("?" in (f.get("texto") or "") for f in depois)
                 and not any(ult["em"] < t <= limite for t in por_chave_turnos[chave]))
        imoveis = sorted({str(f["codigo"]) for f in fs if f.get("codigo")})
        intencoes = sorted({f.get("intencao") for f in corretor if f.get("intencao")})
        ident = f"{tel4(chave)}-{hashlib.sha1(chave.encode()).hexdigest()[:6]}"
        arquivo = f"{dia}/{ident}.txt"
        cards = sum(1 for f in nay if f.get("motivo") == "card")
        fotos = sum(f["fotos"] for f in nay)
        avisos = sum(1 for f in fs if f["q"] == "tel")
        texto = [f"CONVERSA {ident} · corretor …{tel4(chave)} · {dia} (horário de Manaus)",
                 f"{len(corretor)} mensagens do corretor, {len(nay)} da Nay, {cards} cards, {fotos} fotos, "
                 f"{avisos} avisos ao Tel", ""]
        texto += [linha(f) for f in fs]
        texto += ["", "RESULTADO",
                  f"visita marcada: {'sim' if visita else 'não'}",
                  f"escalada: {'sim, motivo: ' + motivo_esc if turnos_escalados else 'não'}",
                  f"corretor sumiu: {'sim' if sumiu else 'não'}"]
        os.makedirs(os.path.join(o.saida, dia), exist_ok=True)
        with open(os.path.join(o.saida, arquivo), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(texto) + "\n")
        novas.append([dia, tel4(chave), arquivo, corretor[0]["em"][11:16] if corretor else fs[0]["em"][11:16],
                      ult["em"][11:16], str(len(corretor)), str(len(nay)), str(cards), str(fotos), str(avisos),
                      "sim" if visita else "não", "sim" if turnos_escalados else "não",
                      motivo_esc.replace("\t", " ").replace("\n", " "), "sim" if sumiu else "não",
                      ",".join(imoveis), ",".join(intencoes)])
        r = resumo[dia]
        r["conversas"] += 1
        r["visitas"] += visita
        r["escaladas"] += bool(turnos_escalados)
        r["sumiu"] += sumiu

    for dia, r in resumo.items():
        with open(os.path.join(o.saida, dia, "_resumo.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write(f"NAY PARCERIA · {dia} (Manaus)\nconversas: {r['conversas']}\nvisitas marcadas pela Nay: "
                    f"{r['visitas']}\nconversas escaladas: {r['escaladas']}\ncorretor sumiu: {r['sumiu']}\n")
    todas = sorted(velhas + novas, key=lambda l: (l[0], l[3], l[1]))
    tmp = indice_arq + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(cab) + "\n" + "".join("\t".join(l) + "\n" for l in todas))
    os.replace(tmp, indice_arq)
    print(f"importadas {len(novas)} conversas de {desde:%d/%m} a {ate:%d/%m} · no índice: {len(todas)}")


if __name__ == "__main__":
    main()
