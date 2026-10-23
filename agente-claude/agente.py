#!/usr/bin/env python3
"""Agente Claude: manda a mensagem pré-setada de uma regra ao Claude (claude -p, conta do Pedro) no servidor da regra
e grava tempo, tokens e custo em metricas.db. Só biblioteca padrão, para subir rápido.

  agente disparar <regra> [<regra> ...]   manda a(s) mensagem(ns); várias rodam em paralelo
  agente regras                           lista as regras de regras.json
  agente metricas [dias]                  resumo por regra (padrão: 7 dias)
  agente ultimas [n]                      as n últimas execuções com a resposta

Cada regra diz o servidor (vps2, onde isto mora, ou vps1) e o modo: "responder" (só texto) ou "alterar" (o Claude
mexe no servidor como root). Quem roda o Claude é o claude-agente de cada servidor; a vps1 é alcançada por ssh no
Tailscale. Quem dispara: o terminal, o painel (agentes.imobeasy.online) ou o Hermes do Claude (mcp_agente.py).
"""
import json, os, sqlite3, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import conta

BASE = os.path.dirname(os.path.abspath(__file__))
REGRAS = os.path.join(BASE, "regras.json")
DB = os.path.join(BASE, "metricas.db")
EXECUTOR = "/usr/local/sbin/claude-agente"
SERVIDORES = {
    "vps2": [],
    "vps1": ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-i", "/root/.ssh/agente_claude_vps1",
             "root@100.86.114.74"],
}
MODOS = ("responder", "alterar")
PADRAO = {"modelo": "sonnet", "servidor": "vps2", "modo": "responder", "ativa": True}
LIMITE_S = {"responder": 300, "alterar": 1800}


def regras():
    with open(REGRAS, encoding="utf-8") as f:
        return json.load(f)


def banco():
    con = sqlite3.connect(DB, timeout=30)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("""CREATE TABLE IF NOT EXISTS execucoes (
        id INTEGER PRIMARY KEY, regra TEXT NOT NULL, inicio TEXT NOT NULL, modelo TEXT,
        ok INTEGER NOT NULL, ms_total INTEGER, ms_claude INTEGER, ms_api INTEGER,
        tokens_entrada INTEGER, tokens_saida INTEGER, cache_lido INTEGER, cache_criado INTEGER,
        custo_usd REAL, mensagem TEXT, resposta TEXT, erro TEXT, sessao TEXT)""")
    tem = {r[1] for r in con.execute("PRAGMA table_info(execucoes)")}
    for col in ("servidor", "modo", "origem", "conta"):
        if col not in tem:
            con.execute(f"ALTER TABLE execucoes ADD COLUMN {col} TEXT")
    con.execute("CREATE INDEX IF NOT EXISTS execucoes_regra_inicio ON execucoes(regra, inicio)")
    return con


def disparar(nome, r, origem):
    r = {**PADRAO, **r}
    limite = r.get("timeout_s") or LIMITE_S.get(r["modo"], 300)
    pedido = {k: r.get(k) for k in ("mensagem", "modelo", "sistema", "esforco", "modo")}
    pedido["timeout_s"] = limite
    inicio = datetime.now(timezone.utc).isoformat(timespec="seconds")
    t0 = time.monotonic()
    linha = {"regra": nome, "inicio": inicio, "modelo": r["modelo"], "mensagem": r["mensagem"], "ok": 0,
             "servidor": r["servidor"], "modo": r["modo"], "origem": origem}
    try:
        # 23/10: assinatura ou API (conta.py); na API sem saldo a regra não roda
        pedido.update(conta.para_o_pedido())
    except ValueError as e:
        linha.update(ms_total=0, erro=str(e))
        return linha
    linha["conta"] = pedido["conta"]
    try:
        if r["servidor"] not in SERVIDORES:
            raise OSError(f"servidor desconhecido: {r['servidor']}")
        p = subprocess.run(SERVIDORES[r["servidor"]] + [EXECUTOR], input=json.dumps(pedido), capture_output=True,
                           text=True, timeout=limite + 60)
        linha["ms_total"] = round((time.monotonic() - t0) * 1000)
        try:
            j = json.loads(p.stdout)
        except ValueError:
            linha["erro"] = (p.stderr or p.stdout or f"saida {p.returncode}").strip()[:2000]
        else:
            u = j.get("usage") or {}
            linha.update(
                ok=0 if j.get("is_error") or p.returncode else 1,
                ms_claude=j.get("duration_ms"), ms_api=j.get("duration_api_ms"),
                tokens_entrada=u.get("input_tokens"), tokens_saida=u.get("output_tokens"),
                cache_lido=u.get("cache_read_input_tokens"), cache_criado=u.get("cache_creation_input_tokens"),
                custo_usd=j.get("total_cost_usd"), resposta=j.get("result"), sessao=j.get("session_id"))
            if not linha["ok"]:
                linha["erro"] = (j.get("result") or p.stderr or "").strip()[:2000]
    except subprocess.TimeoutExpired:
        linha["ms_total"] = round((time.monotonic() - t0) * 1000)
        linha["erro"] = f"passou de {limite} s"
    except OSError as e:
        linha["ms_total"] = round((time.monotonic() - t0) * 1000)
        linha["erro"] = f"não rodou o claude: {e}"
    return linha


def executar(nomes, origem="terminal"):
    """Dispara as regras (em paralelo), grava em metricas.db e devolve as linhas. Terminal, painel e Hermes usam esta."""
    todas = regras()
    faltam = [n for n in nomes if n not in todas]
    if faltam:
        raise KeyError(f"regra não existe: {', '.join(faltam)}")
    alvo = [(n, todas[n]) for n in nomes if todas[n].get("ativa", True)]
    with ThreadPoolExecutor(max_workers=max(1, len(alvo))) as ex:
        linhas = list(ex.map(lambda nr: disparar(nr[0], nr[1], origem), alvo))
    con = banco()
    for l in linhas:
        cols = ", ".join(l)
        con.execute(f"INSERT INTO execucoes ({cols}) VALUES ({', '.join('?' * len(l))})", list(l.values()))
    con.commit()
    con.close()
    return linhas


def cmd_disparar(nomes):
    try:
        linhas = executar(nomes)
    except KeyError as e:
        sys.exit(e.args[0])
    for l in linhas:
        print(f"[{l['regra']}] {'ok' if l['ok'] else 'ERRO'} {l.get('ms_total')} ms")
        print(l.get("resposta") or l.get("erro") or "")
    sys.exit(0 if all(l["ok"] for l in linhas) else 1)


def cmd_regras():
    for n, r in regras().items():
        r = {**PADRAO, **r}
        print(f"{n:24} {'ativa' if r['ativa'] else 'parada':7} {r['servidor']:5} {r['modo']:9} {r['modelo']:8} "
              f"{r['mensagem'][:60]!r}")


def cmd_metricas(dias):
    con = banco()
    linhas = con.execute("""
        SELECT regra, COUNT(*), SUM(ok), ROUND(AVG(ms_total)), MAX(ms_total),
               SUM(tokens_entrada), SUM(tokens_saida), SUM(cache_lido), ROUND(SUM(custo_usd), 4),
               datetime(MAX(inicio), '-3 hours')
        FROM execucoes WHERE inicio >= datetime('now', ?) GROUP BY regra ORDER BY regra""",
        (f"-{dias} days",)).fetchall()
    print(f"últimos {dias} dias (hora de Brasília)")
    print(f"{'regra':24} {'vezes':>5} {'ok':>4} {'ms méd':>7} {'ms máx':>7} {'tok ent':>8} {'tok saí':>8} "
          f"{'cache':>8} {'US$ eq':>8}  última")
    for r in linhas:
        print(f"{r[0]:24} {r[1]:5} {r[2]:4} {r[3] or 0:7.0f} {r[4] or 0:7} {r[5] or 0:8} {r[6] or 0:8} "
              f"{r[7] or 0:8} {r[8] or 0:8}  {r[9]}")


def cmd_ultimas(n):
    for r in banco().execute("SELECT datetime(inicio, '-3 hours'), regra, origem, ok, ms_total, resposta, erro "
                             "FROM execucoes ORDER BY id DESC LIMIT ?", (n,)):
        print(f"{r[0]} [{r[1]}] ({r[2]}) {'ok' if r[3] else 'ERRO'} {r[4]} ms\n  {(r[5] or r[6] or '')[:500]}\n")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help", "ajuda"):
        print(__doc__)
    elif a[0] == "disparar" and len(a) > 1:
        cmd_disparar(a[1:])
    elif a[0] == "regras":
        cmd_regras()
    elif a[0] == "metricas":
        cmd_metricas(int(a[1]) if len(a) > 1 else 7)
    elif a[0] == "ultimas":
        cmd_ultimas(int(a[1]) if len(a) > 1 else 10)
    else:
        sys.exit(__doc__)
