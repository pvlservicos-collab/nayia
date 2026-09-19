"""Painel de saude da Nay -- só leitura.

Conecta em naydb com a role `nay_leitura`: SELECT apenas, com
`default_transaction_read_only=on`, `statement_timeout=5s` e limite de 5
conexões definidos na própria role (não em código). Mesmo com um bug
aqui, o Postgres recusa qualquer escrita.

Cada seção roda sua própria query dentro de um try/except -- uma consulta
falhando não derruba as outras nem quebra a página (aparece "--" no
lugar do número, e um aviso discreto no rodapé).

Sem login de propósito (pedido assim). Por isso: nenhuma query aqui
devolve telefone, nome, texto de mensagem ou endereço -- só contagem,
status e carimbo de tempo.
"""
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import psycopg2
import psycopg2.extras
from flask import Flask, render_template_string

FUSO = ZoneInfo("America/Manaus")
DATABASE_URL = os.environ["DATABASE_URL"]
HEARTBEAT_DIR = os.environ.get("HEARTBEAT_DIR", "/heartbeats")

# nome do arquivo de batimento -> (rótulo, minutos de folga antes de virar alerta)
CRONS = {
    "disparar_grade": ("Grade de postagem", 15),
    "disparar_lembretes": ("Lembretes de retorno", 15),
    "entregar_pendentes": ("Entrega do que ficou de mandar", 15),
    "ciclo_pendencias": ("Ciclo de pendências", 15),
}

app = Flask(__name__)


def conectar():
    conn = psycopg2.connect(DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def uma_linha(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchone()


def todas_linhas(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def agora_manaus():
    return datetime.now(FUSO)


def inicio_do_dia(agora):
    return agora.replace(hour=0, minute=0, second=0, microsecond=0)


def minutos_desde(quando, agora):
    if quando is None:
        return None
    if quando.tzinfo is None:
        quando = quando.replace(tzinfo=FUSO)
    return int((agora - quando).total_seconds() // 60)


def formatar_ha(minutos):
    if minutos is None:
        return "nunca"
    if minutos < 1:
        return "agora mesmo"
    if minutos < 60:
        return f"há {minutos} min"
    horas = minutos // 60
    if horas < 48:
        return f"há {horas}h"
    return f"há {horas // 24}d"


def semaforo(ok):
    return "ok" if ok else "alerta"


def coletar_heartbeats(agora):
    linhas = []
    for arquivo, (rotulo, folga) in CRONS.items():
        caminho = os.path.join(HEARTBEAT_DIR, f".batimento_{arquivo}")
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(caminho), tz=FUSO)
            mins = minutos_desde(mtime, agora)
            status = semaforo(mins is not None and mins <= folga)
        except OSError:
            mins = None
            status = "alerta"
        linhas.append({"rotulo": rotulo, "ha": formatar_ha(mins), "status": status})
    return linhas


def montar_dado(conn, chave_secao, fn):
    """Roda fn(conn) isolado: se quebrar, devolve None e registra o erro."""
    try:
        return fn(conn), None
    except Exception as exc:  # noqa: BLE001 -- painel de leitura, nunca deve propagar
        conn.rollback()
        return None, f"{chave_secao}: {exc.__class__.__name__}"


@app.route("/")
def painel():
    agora = agora_manaus()
    hoje = inicio_do_dia(agora)
    erros = []

    try:
        conn = conectar()
    except Exception as exc:  # noqa: BLE001
        return render_template_string(
            TEMPLATE_ERRO, erro=f"{exc.__class__.__name__}: banco inacessível"
        ), 200

    def secao(nome, fn):
        valor, erro = montar_dado(conn, nome, fn)
        if erro:
            erros.append(erro)
        return valor

    config = secao("config", lambda c: {
        r["chave"]: r["valor"] for r in todas_linhas(
            c, "SELECT chave, valor FROM config WHERE chave IN "
               "('atendimento_pausado','varredura_rodou_em')"
        )
    }) or {}

    pausado = config.get("atendimento_pausado") == "sim"

    varredura_em = None
    if config.get("varredura_rodou_em"):
        try:
            varredura_em = datetime.fromisoformat(config["varredura_rodou_em"])
        except ValueError:
            varredura_em = None
    varredura_mins = minutos_desde(varredura_em, agora)

    heartbeats = secao("heartbeats", lambda c: coletar_heartbeats(agora)) or []

    pendencias = secao("pendencias", lambda c: uma_linha(c, """
        SELECT count(*) AS total, min(criada_em) AS mais_antiga
        FROM pendencias WHERE status = 'aberta'
    """)) or {}

    represadas = secao("represadas", lambda c: uma_linha(c, """
        SELECT count(*) AS total FROM (
            SELECT pi.pendencia_id
            FROM pendencia_interessado pi
            JOIN pendencias p ON p.id = pi.pendencia_id AND p.status = 'aberta'
            GROUP BY pi.pendencia_id HAVING count(*) > 1
        ) x
    """)) or {}

    escalacoes = secao("escalacoes", lambda c: uma_linha(c, """
        SELECT count(*) AS total, min(criada_em) AS mais_antiga
        FROM escalacoes WHERE status = 'aberta'
    """)) or {}

    nao_aprovados = secao("nao_aprovados", lambda c: uma_linha(c, """
        SELECT count(*) AS total FROM corretores WHERE aprovado = false
    """)) or {}

    devendo = secao("devendo", lambda c: uma_linha(c, """
        SELECT count(*) AS total FROM entrega_pendente WHERE estado = 'devendo'
    """)) or {}

    lembretes_escalados = secao("lembretes_escalados", lambda c: uma_linha(c, """
        SELECT count(*) AS total FROM lembrete
        WHERE estado = 'escalado' AND atualizado_em >= %s
    """, (hoje,))) or {}

    msgs_hoje = secao("msgs_hoje", lambda c: uma_linha(c, """
        SELECT count(*) AS total, count(DISTINCT telefone) AS corretores
        FROM mensagens WHERE direcao = 'recebida' AND criada_em >= %s
    """, (hoje,))) or {}

    msgs_status = secao("msgs_status", lambda c: todas_linhas(c, """
        SELECT status, count(*) AS total FROM mensagens GROUP BY status ORDER BY status
    """)) or []

    envios_hoje = secao("envios_hoje", lambda c: todas_linhas(c, """
        SELECT destino, count(*) AS total FROM envios
        WHERE enviado_em >= %s GROUP BY destino
    """, (hoje,))) or []
    envios_map = {r["destino"]: r["total"] for r in envios_hoje}

    catalogo = secao("catalogo", lambda c: uma_linha(c, """
        SELECT
            count(*) AS total,
            count(*) FILTER (WHERE publicado_no_site) AS publicados,
            count(*) FILTER (WHERE sincronizado_em >= now() - interval '2 hours') AS sync_recente
        FROM imoveis
    """)) or {}

    conn.close()

    dados = {
        "agora": agora.strftime("%d/%m %H:%M"),
        "pausado": pausado,
        "varredura_ha": formatar_ha(varredura_mins),
        "varredura_status": semaforo(varredura_mins is not None and varredura_mins <= 90),
        "heartbeats": heartbeats,
        "pendencias_total": pendencias.get("total", 0),
        "pendencias_ha": formatar_ha(minutos_desde(pendencias.get("mais_antiga"), agora)),
        "represadas_total": represadas.get("total", 0),
        "escalacoes_total": escalacoes.get("total", 0),
        "escalacoes_ha": formatar_ha(minutos_desde(escalacoes.get("mais_antiga"), agora)),
        "nao_aprovados_total": nao_aprovados.get("total", 0),
        "devendo_total": devendo.get("total", 0),
        "lembretes_escalados_total": lembretes_escalados.get("total", 0),
        "msgs_hoje_total": msgs_hoje.get("total", 0),
        "corretores_hoje": msgs_hoje.get("corretores", 0),
        "msgs_status": msgs_status,
        "envios_grupo": envios_map.get("grupo", 0),
        "envios_corretor": envios_map.get("corretor", 0),
        "catalogo_total": catalogo.get("total", 0),
        "catalogo_publicados": catalogo.get("publicados", 0),
        "catalogo_despublicados": (catalogo.get("total") or 0) - (catalogo.get("publicados") or 0),
        "catalogo_sync_recente": catalogo.get("sync_recente", 0),
        "erros": erros,
    }
    return render_template_string(TEMPLATE, **dados)


TEMPLATE_ERRO = """
<!doctype html><html><head><meta charset="utf-8">
<title>Painel Nay</title>
<style>
body{background:#0a0a0b;color:#e4e4e7;font-family:ui-monospace,monospace;
     display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
.caixa{border:1px solid #dc2626;padding:24px 32px;text-align:center}
.rotulo{color:#8a8a92;font-size:12px;letter-spacing:.08em;text-transform:uppercase;margin-bottom:8px}
</style></head>
<body><div class="caixa"><div class="rotulo">Painel de saúde</div>{{ erro }}</div></body></html>
"""

TEMPLATE = """
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="60">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Painel Nay</title>
<style>
  :root{
    --bg:#0a0a0b; --painel:#131316; --borda:#232329;
    --texto:#e4e4e7; --dim:#8a8a92;
    --roxo:#8b5cf6; --verde:#16a34a; --ambar:#d97706; --vermelho:#dc2626;
  }
  *{box-sizing:border-box}
  body{
    background:var(--bg); color:var(--texto); margin:0; padding:32px 24px 60px;
    font-family:ui-monospace,"SF Mono","Cascadia Code","JetBrains Mono",Consolas,monospace;
    font-size:14px;
  }
  header{display:flex; justify-content:space-between; align-items:baseline;
         border-bottom:1px solid var(--borda); padding-bottom:16px; margin-bottom:24px;
         max-width:1100px; margin-left:auto; margin-right:auto;}
  h1{font-size:15px; letter-spacing:.12em; text-transform:uppercase; margin:0; font-weight:600;
     color:var(--texto)}
  h1 span{color:var(--roxo)}
  .relogio{color:var(--dim); font-size:12px}
  main{max-width:1100px; margin:0 auto; display:grid; gap:20px}
  section{border:1px solid var(--borda); background:var(--painel); padding:18px 20px}
  .titulo-secao{font-size:11px; letter-spacing:.1em; text-transform:uppercase;
                color:var(--dim); margin:0 0 14px; border-left:2px solid var(--roxo); padding-left:8px}
  .grade{display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:16px}
  .item{display:flex; flex-direction:column; gap:6px}
  .rotulo{color:var(--dim); font-size:11px; text-transform:uppercase; letter-spacing:.06em}
  .valor{font-size:26px; font-weight:600}
  .sub{font-size:12px; color:var(--dim)}
  .pill{display:inline-block; padding:2px 8px; font-size:11px; text-transform:uppercase;
        letter-spacing:.06em; font-weight:700; color:#fff}
  .pill.ok{background:var(--verde)}
  .pill.alerta{background:var(--vermelho)}
  .lista{display:grid; gap:8px}
  .linha{display:flex; justify-content:space-between; align-items:center;
         border-bottom:1px solid var(--borda); padding-bottom:8px}
  .linha:last-child{border-bottom:none; padding-bottom:0}
  .linha .rotulo{font-size:13px; color:var(--texto); text-transform:none; letter-spacing:0}
  footer{max-width:1100px; margin:24px auto 0; color:var(--dim); font-size:11px}
  footer .erro{color:var(--ambar)}
</style></head>
<body>
<header>
  <h1>Nay <span>/</span> painel de saúde</h1>
  <div class="relogio">{{ agora }} — Manaus</div>
</header>
<main>

  <section>
    <p class="titulo-secao">Semáforo</p>
    <div class="grade">
      <div class="item">
        <span class="rotulo">Atendimento</span>
        <span class="pill {{ 'alerta' if pausado else 'ok' }}">{{ 'pausado' if pausado else 'ativo' }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Varredura do catálogo</span>
        <span class="pill {{ varredura_status }}">{{ varredura_ha }}</span>
      </div>
      {% for h in heartbeats %}
      <div class="item">
        <span class="rotulo">{{ h.rotulo }}</span>
        <span class="pill {{ h.status }}">{{ h.ha }}</span>
      </div>
      {% endfor %}
    </div>
  </section>

  <section>
    <p class="titulo-secao">Fila de decisão</p>
    <div class="lista">
      <div class="linha">
        <span class="rotulo">Pendências abertas aguardando resposta</span>
        <span>{{ pendencias_total }}{% if pendencias_total %} · mais antiga {{ pendencias_ha }}{% endif %}</span>
      </div>
      <div class="linha">
        <span class="rotulo">Pendências represadas (mais de 1 pessoa perguntou)</span>
        <span>{{ represadas_total }}</span>
      </div>
      <div class="linha">
        <span class="rotulo">Escalações abertas</span>
        <span>{{ escalacoes_total }}{% if escalacoes_total %} · mais antiga {{ escalacoes_ha }}{% endif %}</span>
      </div>
      <div class="linha">
        <span class="rotulo">Corretores aguardando aprovação</span>
        <span>{{ nao_aprovados_total }}</span>
      </div>
      <div class="linha">
        <span class="rotulo">Imóveis que ficaram de mandar e não mandou</span>
        <span>{{ devendo_total }}</span>
      </div>
      <div class="linha">
        <span class="rotulo">Lembretes escalados hoje (3 toques sem resposta)</span>
        <span>{{ lembretes_escalados_total }}</span>
      </div>
    </div>
  </section>

  <section>
    <p class="titulo-secao">Volume de hoje</p>
    <div class="grade">
      <div class="item">
        <span class="rotulo">Mensagens recebidas</span>
        <span class="valor">{{ msgs_hoje_total }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Corretores únicos hoje</span>
        <span class="valor">{{ corretores_hoje }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Imóveis postados em grupo</span>
        <span class="valor">{{ envios_grupo }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Envios privados a corretor</span>
        <span class="valor">{{ envios_corretor }}</span>
      </div>
    </div>
    {% if msgs_status %}
    <p class="sub" style="margin-top:14px">Mensagens por status (histórico total): {% for s in msgs_status %}{{ s.status }} {{ s.total }}{% if not loop.last %} · {% endif %}{% endfor %}</p>
    {% endif %}
  </section>

  <section>
    <p class="titulo-secao">Catálogo</p>
    <div class="grade">
      <div class="item">
        <span class="rotulo">Total no banco</span>
        <span class="valor">{{ catalogo_total }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Publicados no site</span>
        <span class="valor">{{ catalogo_publicados }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Despublicados</span>
        <span class="valor">{{ catalogo_despublicados }}</span>
      </div>
      <div class="item">
        <span class="rotulo">Sincronizados nas últimas 2h</span>
        <span class="valor">{{ catalogo_sync_recente }}</span>
      </div>
    </div>
  </section>

</main>
<footer>
  Somente leitura — este painel nunca escreve no banco. Atualiza sozinho a cada 60s.
  {% if erros %}<div class="erro">Não consegui ler: {{ erros|join(', ') }}</div>{% endif %}
</footer>
</body></html>
"""

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8091)
