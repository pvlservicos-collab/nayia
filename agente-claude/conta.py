"""Por qual conta o Agente Claude roda: a assinatura (o login do Pedro) ou a API (a chave dele, com saldo).

Pedro, 23/10/2026: "quero um novo modo lá no agentes, hoje eles rodam logado, tem como eles rodarem pela minha api do
claude? tenho 100 dólares lá para usar ... quero uma alternância tipo um toggle, mas o de api tem um contador de gastos
lá, quando ultrapassa aquilo para".

- conta.json: {"modo": "assinatura" | "api", "limite_usd": 100}. O botão do painel grava aqui.
- O gasto é a soma do custo (total_cost_usd do claude -p) das execuções e mensagens marcadas conta='api' em
  metricas.db, desde sempre: pôs mais saldo no console, sobe o limite.
- Chegou no limite: nada novo roda pela API. As regras gravam o erro; os projetos recusam a mensagem com ValueError,
  e a fila da revisão e as rotinas já tratam isso como "ocupado" e tentam de novo depois (nada se perde). Cada
  chamada leva também --max-budget-usd com o que sobra, para uma resposta longa não passar do limite no meio.
- A chave fica em /etc/agente-claude/api.env (ANTHROPIC_API_KEY=...) nas duas VPS; quem a usa é o claude-agente.
"""
import json, os, threading

BASE = os.path.dirname(os.path.abspath(__file__))
CONTA = os.path.join(BASE, "conta.json")
CHAVE = "/etc/agente-claude/api.env"
MODOS = ("assinatura", "api")
PADRAO = {"modo": "assinatura", "limite_usd": 100.0}
TRAVA = threading.Lock()


def config():
    try:
        with open(CONTA, encoding="utf-8") as f:
            return {**PADRAO, **json.load(f)}
    except (FileNotFoundError, ValueError):
        return dict(PADRAO)


def gasto():
    import agente
    con = agente.banco()
    tem = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    total = con.execute("SELECT COALESCE(SUM(custo_usd), 0) FROM execucoes WHERE conta = 'api'").fetchone()[0]
    if "mensagens" in tem:
        total += con.execute("SELECT COALESCE(SUM(custo_usd), 0) FROM mensagens WHERE conta = 'api'").fetchone()[0]
    con.close()
    return round(total, 4)


def tem_chave():
    try:
        with open(CHAVE, encoding="utf-8") as f:
            return any(l.startswith("ANTHROPIC_API_KEY=") and len(l.strip()) > 30 for l in f)
    except OSError:
        return False


def estado():
    c = config()
    g = gasto()
    return {**c, "gasto_usd": g, "resta_usd": round(max(0.0, c["limite_usd"] - g), 4),
            "parado": c["modo"] == "api" and g >= c["limite_usd"], "tem_chave": tem_chave()}


def para_o_pedido():
    """O que vai no pedido ao claude-agente: {"conta": ..., "max_usd"?}. Na API sem saldo, ValueError."""
    e = estado()
    if e["modo"] != "api":
        return {"conta": "assinatura"}
    if e["parado"]:
        raise ValueError(f"API parada: gastou US$ {e['gasto_usd']:.2f} de US$ {e['limite_usd']:.2f} "
                         "(suba o limite ou volte para a assinatura no painel)")
    if not e["tem_chave"]:
        raise ValueError("modo API sem chave em " + CHAVE)
    return {"conta": "api", "max_usd": e["resta_usd"]}


def salvar(d):
    c = config()
    if "modo" in d:
        if d["modo"] not in MODOS:
            raise ValueError("modo tem de ser assinatura ou api")
        if d["modo"] == "api" and not tem_chave():
            raise ValueError("falta a chave da API em " + CHAVE)
        c["modo"] = d["modo"]
    if "limite_usd" in d:
        try:
            limite = float(d["limite_usd"])
        except (TypeError, ValueError):
            raise ValueError("limite em dólares, um número")
        if not 0 <= limite <= 10000:
            raise ValueError("limite entre 0 e 10.000 dólares")
        c["limite_usd"] = round(limite, 2)
    with TRAVA:
        tmp = CONTA + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"modo": c["modo"], "limite_usd": c["limite_usd"]}, f)
        os.replace(tmp, CONTA)
    return estado()
