#!/usr/bin/env python3
"""A fila da revisão da Nay: toda conversa em que a Nay Parceria ENVIOU UM IMÓVEL vai para o projeto
"Nay Parceria (revisão)" do painel, de 3 em 3 horas. Às 22h (Brasília) sai o pedido do relatório do dia.

22/10 (o limite da conta do Claude estourou; a fila era ~60% do gasto): cada lote abre uma CONVERSA NOVA, com só as
conversas novas, em vez de entrar na conversa longa da equipe (a 5, desde 20/10), que o Claude relia inteira a cada
passo. O que o Pedro combinou naquela conversa passou para projetos/nay/como-ler-os-dados.md, que toda conversa lê.
O relatório das 22h também nasce numa conversa nova, com o arquivo das respostas do dia. O modelo é o do
projeto.json (Sonnet 5.5, antes Opus). Pedro: "executa só A, enviando só as conversas novas, executa B mas um Sonnet
bom ... vou só aumentar o tempo das consultas para a cada 3 horas".

Pedro, 20/10/2026: "preciso que mande para elas as conversas que formos tendo em que a nay envia um imóvel, sempre
que ela enviar um imóvel essa conversa vai para a fila de envio para essa nay parceria revisão, as filas vão ocorrer a
cada 20 minutos, nosso sistema vai criar algo que salve esses históricos". Depois: "se a fila estiver vazia ele não
manda nada, e às 22 hrs ele vai mandar um pedido 'Manda o relatório de hoje no grupo' mas não precisa pôr as fotos".

Como anda, a cada volta (o painel chama `laco()` numa thread; olha o relógio a cada 20 s):
  1. ENFILEIRAR: lê no naydb (VPS1, só leitura, a mesma chave do importar_nay.py) as saídas da Nay ao corretor com
     motivo card ou foto (imóvel enviado) desde a última leitura, e põe a conversa na fila (`fila_nay`, uma linha
     pendente por corretor; um imóvel novo na mesma conversa só soma o código).
  2. ENVIAR (às 06, 09, 12, 15, 18 e 21 h de Brasília; 00 e 03 caem na madrugada): fila vazia = nada. Com gente na
     fila: monta cada conversa (a das últimas 24 h, ou só o que veio depois do último envio daquele corretor), grava o
     histórico em projetos/nay/dados/fila/AAAA-MM-DD/HHMM.txt e manda a mensagem do lote numa conversa NOVA do projeto.
     Se não sair, a fila espera a próxima volta (nada se perde: só sai da fila o que foi mandado).
  3. RELATÓRIO: às 22:00 de Brasília, uma vez por dia, numa conversa nova: o pedido RELATORIO e o arquivo
     dados/fila/AAAA-MM-DD/respostas-do-dia.txt (o que o agente respondeu hoje em cada conversa do projeto).

Estado em metricas.db: fila_nay (a fila e o que já foi), fila_nay_lote (cada envio), fila_nay_estado (marcadores).
Desligar sem mexer no código: /opt/agente-claude/fila_nay.json com {"ativa": false}.

  fila_nay.py                  o que está na fila e os últimos lotes (só leitura)
  painel: GET /api/fila_nay (o mesmo) e POST /api/fila_nay/agora (uma volta já, em segundo plano)
"""
import json, os, subprocess, threading, time
from datetime import datetime, timedelta, timezone

import agente, importar_nay, projetos

PROJETO = "nay"
A_CADA_MIN = 180          # 22/10 (Pedro): "a cada 3 horas"; antes 20
RELATORIO_HORA = "22:00"   # Brasília (o relógio do Pedro)
RELATORIO_ATE = "22:59"    # depois disso não sai mais naquele dia: painel que subiu tarde não manda o pedido fora de hora
RELATORIO = "Manda o relatório de hoje no grupo. Não precisa pôr as fotos."
# o que o agente respondeu hoje no projeto, para o relatório (que nasce numa conversa nova e não viu os lotes)
SQL_RESPOSTAS_DO_DIA = """
SELECT c.id, c.titulo, m.inicio, m.texto FROM mensagens m JOIN conversas c ON c.id = m.conversa_id
 WHERE c.projeto = ? AND m.papel = 'claude' AND m.ok = 1 AND m.inicio >= ? ORDER BY m.id"""
BRASILIA = timezone(timedelta(hours=-3))
MANAUS = timezone(timedelta(hours=-4))
CONFIG = os.path.join(agente.BASE, "fila_nay.json")
TRAVA = threading.Lock()

# Os instantes andam todos em UTC, sem fuso no texto ("2026-10-20T22:05:01.123456"): assim compara como texto e
# não depende do fuso da sessão do banco nem da versão do Python.
UTC_FMT = "%Y-%m-%dT%H:%M:%S.%f"

# o que a Nay mandou ao corretor que é IMÓVEL (card ou fotos), depois do marcador; o now() do banco vira o marcador novo
SQL_ENVIOS = """
SELECT json_build_object('agora', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))::text
UNION ALL
SELECT json_build_object('saida', s.id, 'chave', t.chave, 'codigo', s.codigo, 'motivo', s.motivo,
         'em', to_char(s.enviado_em AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))::text
  FROM core_saida s JOIN core_turno t ON t.id = s.turno_id
 WHERE s.estado = 'enviado' AND s.papel_destino = 'turno' AND s.motivo IN ('card', 'foto') AND s.codigo IS NOT NULL
   AND t.modo = 'real' AND t.papel = 'corretor'
   AND s.enviado_em > ('{desde}'::timestamp AT TIME ZONE 'UTC') AND s.enviado_em <= now();
"""

# a conversa de alguns corretores a partir de um instante (o mesmo formato do importar_nay.py)
SQL_CONVERSA = """
WITH t AS (
  SELECT id, chave, texto, intencao, criado_em FROM core_turno
   WHERE modo = 'real' AND papel = 'corretor' AND chave = ANY ('{chaves}'::text[])
     AND criado_em > ('{desde}'::timestamp AT TIME ZONE 'UTC'))
SELECT json_build_object('q', 'corretor', 'turno', t.id, 'chave', t.chave, 'texto', t.texto, 'intencao', t.intencao,
         'em', to_char(t.criado_em AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'),
         'em_utc', to_char(t.criado_em AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))::text FROM t
UNION ALL
SELECT json_build_object('q', CASE WHEN s.papel_destino = 'tel' THEN 'tel' ELSE 'nay' END, 'turno', s.turno_id,
         'chave', t.chave, 'tipo', s.tipo, 'texto', s.texto, 'motivo', s.motivo, 'codigo', s.codigo, 'ordem', s.ordem,
         'em', to_char(coalesce(s.enviado_em, s.criado_em) AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'),
         'em_utc', to_char(coalesce(s.enviado_em, s.criado_em) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))::text
  FROM core_saida s JOIN t ON t.id = s.turno_id
 WHERE s.estado = 'enviado';
"""


def ativa():
    try:
        with open(CONFIG, encoding="utf-8") as f:
            return json.load(f).get("ativa", True) is not False
    except (FileNotFoundError, ValueError):
        return True


def banco():
    con = projetos.banco()
    con.execute("""CREATE TABLE IF NOT EXISTS fila_nay (
        id INTEGER PRIMARY KEY, chave TEXT NOT NULL, tel4 TEXT NOT NULL, codigos TEXT NOT NULL,
        primeiro_envio TEXT NOT NULL, ultimo_envio TEXT NOT NULL, entrou_em TEXT NOT NULL,
        enviado_em TEXT, lote_id INTEGER, ate TEXT)""")
    con.execute("CREATE INDEX IF NOT EXISTS fila_nay_pendente ON fila_nay(enviado_em, chave)")
    con.execute("""CREATE TABLE IF NOT EXISTS fila_nay_lote (
        id INTEGER PRIMARY KEY, em TEXT NOT NULL, conversas INTEGER NOT NULL, arquivo TEXT NOT NULL,
        conversa_id INTEGER, enviado INTEGER NOT NULL DEFAULT 0, erro TEXT)""")
    con.execute("CREATE TABLE IF NOT EXISTS fila_nay_estado (chave TEXT PRIMARY KEY, valor TEXT)")
    return con


def _estado(con, k, padrao=None):
    r = con.execute("SELECT valor FROM fila_nay_estado WHERE chave = ?", (k,)).fetchone()
    return r["valor"] if r else padrao


def _gravar_estado(con, k, v):
    con.execute("INSERT INTO fila_nay_estado (chave, valor) VALUES (?, ?) "
                "ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor", (k, v))


def _naydb(sql):
    p = subprocess.run(importar_nay.VPS1 + [importar_nay.PSQL], input=sql, capture_output=True, text=True, timeout=300)
    if p.returncode:
        raise RuntimeError("o banco recusou: " + (p.stderr or p.stdout).strip()[:300])
    return [json.loads(l) for l in p.stdout.split("\n") if l.startswith("{")]


def enfileirar():
    """Põe na fila as conversas com imóvel enviado desde a última leitura. Devolve quantos imóveis entraram."""
    con = banco()
    desde = _estado(con, "lido_ate")
    if not desde:
        # primeira vez: começa de agora (o histórico de antes já está no botão "Importar conversas da Nay")
        linhas = _naydb("SELECT json_build_object('agora', to_char(now() AT TIME ZONE 'UTC', "
                        "'YYYY-MM-DD\"T\"HH24:MI:SS.US'))::text;")
        _gravar_estado(con, "lido_ate", linhas[0]["agora"])
        con.commit()
        con.close()
        return 0
    linhas = _naydb(SQL_ENVIOS.format(desde=desde))
    agora_banco = next(l["agora"] for l in linhas if "agora" in l)
    envios = sorted((l for l in linhas if "saida" in l), key=lambda l: l["em"])
    t = projetos.agora()
    for e in envios:
        r = con.execute("SELECT id, codigos FROM fila_nay WHERE chave = ? AND enviado_em IS NULL", (e["chave"],)).fetchone()
        if r:
            cods = r["codigos"].split(",")
            if str(e["codigo"]) not in cods:
                cods.append(str(e["codigo"]))
            con.execute("UPDATE fila_nay SET codigos = ?, ultimo_envio = ? WHERE id = ?", (",".join(cods), e["em"], r["id"]))
        else:
            con.execute("INSERT INTO fila_nay (chave, tel4, codigos, primeiro_envio, ultimo_envio, entrou_em) "
                        "VALUES (?, ?, ?, ?, ?, ?)",
                        (e["chave"], importar_nay.tel4(e["chave"]), str(e["codigo"]), e["em"], e["em"], t))
    _gravar_estado(con, "lido_ate", agora_banco)
    con.commit()
    con.close()
    return len(envios)


def _dia_antes(it):
    return (datetime.strptime(it["primeiro_envio"], UTC_FMT) - timedelta(hours=24)).strftime(UTC_FMT)


def _conversas(itens):
    """O texto de cada conversa da fila: o que veio depois do último envio daquele corretor (ou das últimas 24 h)."""
    con = banco()
    desde_de = {}
    for it in itens:
        r = con.execute("SELECT max(ate) ate FROM fila_nay WHERE chave = ? AND enviado_em IS NOT NULL", (it["chave"],)).fetchone()
        desde_de[it["chave"]] = max(filter(None, [r["ate"] if r else None, _dia_antes(it)]))
    con.close()
    chaves = "{" + ",".join(it["chave"].replace('"', "") for it in itens) + "}"
    eventos = _naydb(SQL_CONVERSA.format(chaves=chaves, desde=min(desde_de.values())))
    ordem = {"corretor": 0, "nay": 1, "tel": 2}
    blocos, ate = [], {}
    for it in itens:
        evs = [e for e in eventos if e["chave"] == it["chave"] and e["em_utc"] > desde_de[it["chave"]]]
        evs.sort(key=lambda e: (e["em"], e["turno"], ordem[e["q"]], e.get("ordem") or 0))
        fs = importar_nay.falas(evs)
        if not fs:
            continue
        continuacao = desde_de[it["chave"]] != _dia_antes(it)
        cab = (f"=== CONVERSA corretor …{it['tel4']} · imóveis enviados: {it['codigos']} · "
               f"{fs[0]['em'][:16]} a {fs[-1]['em'][11:16]} (Manaus)"
               + (" · CONTINUAÇÃO: o começo já foi num lote anterior" if continuacao else "") + " ===")
        blocos.append("\n".join([cab] + [importar_nay.linha(f) for f in fs]))
        ate[it["id"]] = max(e["em_utc"] for e in evs)
    return blocos, ate


def conversa_da_equipe(pid):
    """A conversa mais recente do projeto em que alguém da equipe escreveu (o que os envios automáticos mandam não
    conta); sem nenhuma, a do quadro. Vale para a fila da Nay e para as rotinas dos outros agentes (rotinas.py)."""
    con = banco()
    r = con.execute("SELECT m.conversa_id FROM mensagens m JOIN conversas c ON c.id = m.conversa_id "
                    "WHERE c.projeto = ? AND m.papel = 'voce' AND coalesce(m.origem, '') NOT IN ('fila', 'agenda', 'rotina') "
                    "ORDER BY m.id DESC LIMIT 1", (pid,)).fetchone()
    con.close()
    return r["conversa_id"] if r else projetos.conversa_atual(pid)


def _junto():
    """22/10 (Pedro: "analisa você as conversas, manda as erradas pra ele somente e esperemos pelo próximo"): o que a
    equipe deixar em dados/fila/junto-do-proximo-lote.md vai no próximo lote, mesmo com a fila vazia. (caminho, texto)"""
    caminho = os.path.join(projetos.pasta(PROJETO), "dados", "fila", "junto-do-proximo-lote.md")
    texto = projetos.ler(caminho).strip()
    return (caminho, texto) if texto else (None, "")


def enviar_fila():
    """Fila vazia: nada. Com gente: grava o histórico do lote e manda ao projeto. Devolve um resumo."""
    con = banco()
    itens = con.execute("SELECT * FROM fila_nay WHERE enviado_em IS NULL ORDER BY primeiro_envio").fetchall()
    con.close()
    junto_arq, junto = _junto()
    if not itens and not junto:
        return "fila vazia: nada enviado"
    blocos, ate = _conversas(itens) if itens else ([], {})
    vazios = [it["id"] for it in itens if it["id"] not in ate]
    if vazios:   # nada de novo desde o último envio desse corretor: sai da fila sem lote
        con = banco()
        con.executemany("UPDATE fila_nay SET enviado_em = ? WHERE id = ?", [(projetos.agora(), i) for i in vazios])
        con.commit()
        con.close()
    if not blocos and not junto:
        return "fila só com conversas sem nada novo: nada enviado"
    agora_b, agora_m = datetime.now(BRASILIA), datetime.now(MANAUS)
    rel = os.path.join("dados", "fila", f"{agora_m:%Y-%m-%d}", f"{agora_m:%H%M}.txt")
    caminho = os.path.join(projetos.pasta(PROJETO), rel)
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    cab = (f"FILA DA REVISÃO · {agora_m:%d/%m/%Y %H:%M} em Manaus ({agora_b:%H:%M} em Brasília)\n"
           f"{len(blocos)} conversa(s) em que a Nay Parceria enviou imóvel desde a fila anterior. "
           "Telefones só com os 4 últimos dígitos; {motivo} no fim de cada fala da Nay.\n")
    with open(caminho, "w", encoding="utf-8", newline="\n") as f:
        f.write(cab + "\n" + "\n\n".join(blocos) + "\n")
    lista = "\n".join(f"- …{it['tel4']}: imóveis {it['codigos']}" for it in itens if it["id"] in ate)
    mensagem = (f"Fila da revisão das {agora_b:%H:%M}: {len(blocos)} conversa(s) em que a Nay enviou imóvel.\n"
                f"Elas estão no arquivo {rel}.\n{lista}\n\nRevise cada uma conforme o seu contexto (o CLAUDE.md: "
                "como-ler-os-dados e o contexto do Tel, inclusive o \"Combinado com o Pedro\"). Esta conversa é nova e "
                "o arquivo traz só o que é novo: \"CONTINUAÇÃO\" quer dizer que o começo daquela conversa já foi revisado "
                "num lote anterior (os arquivos de antes estão em dados/fila/). No fim, em poucas linhas: cada erro "
                "achado (corretor com 4 dígitos), o que você mandou ao lead e o que mudou na Nay. Esse texto vai para "
                "o relatório das 22h.")
    if junto:
        mensagem = (mensagem + "\n\n---\n\n" if blocos else "") + junto
    cid = projetos.nova_conversa(PROJETO, f"Fila da revisão {agora_m:%d/%m %H:%M}")
    con = banco()
    lote = con.execute("INSERT INTO fila_nay_lote (em, conversas, arquivo, conversa_id) VALUES (?, ?, ?, ?)",
                       (projetos.agora(), len(blocos), rel, cid)).lastrowid
    con.commit()
    try:
        projetos.enviar(cid, mensagem, origem="fila")
    except ValueError as e:   # o Claude ainda responde o lote anterior: a fila espera a próxima volta
        con.execute("UPDATE fila_nay_lote SET erro = ? WHERE id = ?", (str(e), lote))
        con.commit()
        con.close()
        return f"projeto ocupado ({e}): {len(blocos)} conversa(s) continuam na fila"
    t = projetos.agora()
    for it_id, quando in ate.items():
        con.execute("UPDATE fila_nay SET enviado_em = ?, lote_id = ?, ate = ? WHERE id = ?", (t, lote, quando, it_id))
    con.execute("UPDATE fila_nay_lote SET enviado = 1 WHERE id = ?", (lote,))
    con.commit()
    con.close()
    if junto_arq:   # foi: guarda com a hora, para não ir de novo
        os.replace(junto_arq, os.path.join(os.path.dirname(caminho), f"{agora_m:%H%M}-junto.md"))
    return f"lote {lote}: {len(blocos)} conversa(s) enviadas ({rel})" + (" + o recado da equipe" if junto else "")


def relatorio():
    """O pedido do relatório do dia, uma vez por dia, numa conversa nova. True quando saiu."""
    agora_b, agora_m = datetime.now(BRASILIA), datetime.now(MANAUS)
    hoje = agora_b.strftime("%Y-%m-%d")
    con = banco()
    if _estado(con, "relatorio_dia") == hoje:
        con.close()
        return True
    # o dia de Brasília começa às 03:00 UTC; o inicio das mensagens é UTC em texto ISO
    desde = (datetime.strptime(hoje, "%Y-%m-%d") + timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%S")
    respostas = con.execute(SQL_RESPOSTAS_DO_DIA, (PROJETO, desde)).fetchall()
    con.close()
    rel = os.path.join("dados", "fila", f"{agora_m:%Y-%m-%d}", "respostas-do-dia.txt")
    caminho = os.path.join(projetos.pasta(PROJETO), rel)
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"O QUE O AGENTE RESPONDEU HOJE ({agora_b:%d/%m}) NO PROJETO NAY PARCERIA (REVISÃO), conversa por conversa\n\n"
                + "\n\n".join(f"=== conversa {r['id']} · {r['titulo']} · {r['inicio'][:16]} UTC ===\n{r['texto']}"
                              for r in respostas) + "\n")
    texto = (RELATORIO + f"\n\nEsta conversa é nova. O que foi revisado e corrigido hoje está em {rel} (as suas respostas "
             f"de cada lote e de cada pedido da equipe, {len(respostas)} no total); as conversas dos lotes, em "
             f"dados/fila/{agora_m:%Y-%m-%d}/. O formato é o de sempre: problema x solução aplicada, e a lista das "
             "sessões de correção do dia.")
    try:
        projetos.enviar(projetos.nova_conversa(PROJETO, f"Relatório {agora_b:%d/%m}"), texto, origem="fila")
    except ValueError:
        return False
    con = banco()
    _gravar_estado(con, "relatorio_dia", hoje)
    con.commit()
    con.close()
    return True


def volta():
    with TRAVA:
        n = enfileirar()
        return f"{n} imóvel(is) novo(s) na fila · " + enviar_fila()


def laco():
    """A thread do painel. Enfileira e manda de 3 em 3 horas (06, 09 ... 21 h de Brasília); às 22:00 o relatório."""
    while True:
        try:
            agora = datetime.now(BRASILIA)
            m = agora.hour * 60 + agora.minute
            m -= m % A_CADA_MIN
            slot = f"{agora:%Y-%m-%d} {m // 60:02d}:{m % 60:02d}"
            # 21/10: de madrugada (0h-6h de Brasília) nem lê o banco; o que entrou fica no marcador e sai às 6h.
            # 22/10: o horário feito fica no banco: reiniciar o painel no meio das 3 h não solta um lote fora de hora
            con = banco()
            feito = _estado(con, "slot")
            con.close()
            if ativa() and slot != feito and not projetos.madrugada():
                con = banco()
                _gravar_estado(con, "slot", slot)
                con.commit()
                con.close()
                print("fila_nay:", volta(), flush=True)
            if ativa() and RELATORIO_HORA <= agora.strftime("%H:%M") <= RELATORIO_ATE and not relatorio():
                pass   # ocupado: tenta de novo na próxima olhada (até 22:59)
        except Exception as e:  # noqa: BLE001 - a fila não pode derrubar o painel; tenta na próxima volta
            print("fila_nay:", type(e).__name__, e, flush=True)
        time.sleep(20)


def estado():
    con = banco()
    pend = con.execute("SELECT tel4, codigos, primeiro_envio FROM fila_nay WHERE enviado_em IS NULL ORDER BY primeiro_envio").fetchall()
    lotes = con.execute("SELECT id, em, conversas, arquivo, enviado, erro FROM fila_nay_lote ORDER BY id DESC LIMIT 5").fetchall()
    r = {"ativa": ativa(), "lido_ate": _estado(con, "lido_ate"), "relatorio_dia": _estado(con, "relatorio_dia"),
         "na_fila": pend, "ultimos_lotes": lotes}
    con.close()
    return r


if __name__ == "__main__":
    # só leitura: mandar daqui mataria a resposta do Claude junto com o comando (ela roda numa thread do painel)
    print(json.dumps(estado(), ensure_ascii=False, indent=2))
