#!/usr/bin/env python3
"""Agente Claude: manda a mensagem pré-setada de uma regra ao Claude (claude -p, conta do Pedro)
e grava tempo, tokens e custo em metricas.db. Só biblioteca padrão, para subir rápido.

  agente disparar <regra> [<regra> ...]   manda a(s) mensagem(ns); várias rodam em paralelo
  agente regras                           lista as regras de regras.json
  agente metricas [dias]                  resumo por regra (padrão: 7 dias)
  agente ultimas [n]                      as n últimas execuções com a resposta
"""
import json, os, sqlite3, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

BASE = os.path.dirname(os.path.abspath(__file__))
REGRAS = os.path.join(BASE, "regras.json")
DB = os.path.join(BASE, "metricas.db")
CLAUDE = os.path.expanduser("~/.local/bin/claude")
VAZIO = os.path.join(BASE, "vazio")  # cwd sem CLAUDE.md nem configuração para ler

PADRAO = {"modelo": "sonnet", "timeout_s": 300, "ativa": True}

# o login (CLAUDE_CODE_OAUTH_TOKEN) mora no .env, para o cron não precisar carregar nada
if os.path.exists(os.path.join(BASE, ".env")):
    for l in open(os.path.join(BASE, ".env"), encoding="utf-8"):
        if "=" in l and not l.lstrip().startswith("#"):
            k, v = l.strip().split("=", 1)
            os.environ.setdefault(k, v.strip().strip('"'))


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
    con.execute("CREATE INDEX IF NOT EXISTS execucoes_regra_inicio ON execucoes(regra, inicio)")
    return con


def disparar(nome, r):
    r = {**PADRAO, **r}
    cmd = [CLAUDE, "-p", r["mensagem"], "--output-format", "json", "--model", r["modelo"],
           "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
    if r.get("sistema"):
        cmd += ["--system-prompt", r["sistema"]]
    if r.get("esforco"):
        cmd += ["--effort", r["esforco"]]
    env = {**os.environ, "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1"}
    inicio = datetime.now(timezone.utc).isoformat(timespec="seconds")
    t0 = time.monotonic()
    linha = {"regra": nome, "inicio": inicio, "modelo": r["modelo"], "mensagem": r["mensagem"], "ok": 0}
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=r["timeout_s"], cwd=VAZIO, env=env)
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
        linha["erro"] = f"passou de {r['timeout_s']} s"
    return linha


def cmd_disparar(nomes):
    todas = regras()
    faltam = [n for n in nomes if n not in todas]
    if faltam:
        sys.exit(f"regra não existe: {', '.join(faltam)}")
    alvo = [(n, todas[n]) for n in nomes if todas[n].get("ativa", True)]
    with ThreadPoolExecutor(max_workers=max(1, len(alvo))) as ex:
        linhas = list(ex.map(lambda nr: disparar(*nr), alvo))
    con = banco()
    for l in linhas:
        cols = ", ".join(l)
        con.execute(f"INSERT INTO execucoes ({cols}) VALUES ({', '.join('?' * len(l))})", list(l.values()))
        estado = "ok" if l["ok"] else "ERRO"
        print(f"[{l['regra']}] {estado} {l.get('ms_total')} ms")
        print(l.get("resposta") or l.get("erro") or "")
    con.commit()
    sys.exit(0 if all(l["ok"] for l in linhas) else 1)


def cmd_regras():
    for n, r in regras().items():
        r = {**PADRAO, **r}
        print(f"{n:24} {'ativa' if r['ativa'] else 'parada':7} {r['modelo']:8} {r['mensagem'][:70]!r}")


def cmd_metricas(dias):
    con = banco()
    linhas = con.execute("""
        SELECT regra, COUNT(*), SUM(ok), ROUND(AVG(ms_total)), MAX(ms_total),
               SUM(tokens_entrada), SUM(tokens_saida), SUM(cache_lido), ROUND(SUM(custo_usd), 4), datetime(MAX(inicio), '-3 hours')
        FROM execucoes WHERE inicio >= datetime('now', ?) GROUP BY regra ORDER BY regra""",
        (f"-{dias} days",)).fetchall()
    print(f"últimos {dias} dias (hora de Brasília)")
    print(f"{'regra':24} {'vezes':>5} {'ok':>4} {'ms méd':>7} {'ms máx':>7} {'tok ent':>8} {'tok saí':>8} "
          f"{'cache':>8} {'US$ eq':>8}  última")
    for r in linhas:
        print(f"{r[0]:24} {r[1]:5} {r[2]:4} {r[3] or 0:7.0f} {r[4] or 0:7} {r[5] or 0:8} {r[6] or 0:8} "
              f"{r[7] or 0:8} {r[8] or 0:8}  {r[9]}")


def cmd_ultimas(n):
    for r in banco().execute("SELECT datetime(inicio, '-3 hours'), regra, ok, ms_total, resposta, erro FROM execucoes "
                             "ORDER BY id DESC LIMIT ?", (n,)):
        print(f"{r[0]} [{r[1]}] {'ok' if r[2] else 'ERRO'} {r[3]} ms\n  {(r[4] or r[5] or '')[:500]}\n")


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
