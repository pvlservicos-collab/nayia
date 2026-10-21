"""Projetos do Agente Claude: um chat por assunto da empresa (Visitas, Nay, Financeiro, Métricas, Respostas, Estratégia).

Pedro/Tel, 20/10/2026: "um projeto para cada um desses contextos que vai analisar uma parte da minha empresa ... vários
quadrados estilo este que estou digitando ... deixa um campo para eu digitar ... a que revisa a Nay de uma forma
otimizada porque no futuro eu vou subir todas as conversas da Nay para ele".

Cada projeto é uma pasta em projetos/<id>/:
    projeto.json         nome, descrição, modelo, esforço, importador ("nay" mostra o botão de importar)
    contexto.md          o contexto escrito pelo Tel (editável no painel)
    como-ler-os-dados.md (opcional) como o Claude deve ler ./dados, somado ao CLAUDE.md
    CLAUDE.md            refeito antes de cada mensagem: cabeçalho do painel + data de hoje + contexto
    dados/               o que o Claude lê (anexos; na Nay, conversas/ do importar_nay.py)

Cada conversa é uma sessão do Claude Code (--session-id na primeira mensagem, --resume nas outras): o histórico
fica com o Claude e o prompt fica em cache. As mensagens também vão para metricas.db (tabelas conversas e
mensagens), para a tela abrir rápido e para as métricas. O Claude do projeto só tem Read, Glob e Grep, e só dentro
da pasta do projeto.
"""
import json, os, re, subprocess, threading, time, uuid, zipfile
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

import agente

BASE = os.path.join(agente.BASE, "projetos")
NOME_OK = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
ANEXO_OK = re.compile(r"^[\w.\- ()À-ÿ]{1,120}$")
TIPOS_ANEXO = {".txt", ".md", ".csv", ".tsv", ".json", ".jsonl", ".pdf", ".png", ".jpg", ".jpeg", ".xlsx"}
MAX_ANEXO = 50 * 1024 * 1024
PENDENTES = {}  # conversa_id -> {"desde": t}
IMPORTANDO = {}  # projeto -> {"desde": t, "dias": n}
ULTIMA_IMPORTACAO = {}  # projeto -> {"em", "ok", "texto"}
TRAVA = threading.Lock()
MANAUS = timezone(timedelta(hours=-4))
DIAS_SEMANA = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]


def banco():
    con = agente.banco()
    con.execute("""CREATE TABLE IF NOT EXISTS conversas (
        id INTEGER PRIMARY KEY, projeto TEXT NOT NULL, sessao TEXT NOT NULL, titulo TEXT,
        criada_em TEXT NOT NULL, atualizada_em TEXT NOT NULL)""")
    con.execute("""CREATE TABLE IF NOT EXISTS mensagens (
        id INTEGER PRIMARY KEY, conversa_id INTEGER NOT NULL, papel TEXT NOT NULL, texto TEXT, inicio TEXT NOT NULL,
        ok INTEGER, ms_total INTEGER, ms_api INTEGER, tokens_entrada INTEGER, tokens_saida INTEGER,
        cache_lido INTEGER, custo_usd REAL, erro TEXT)""")
    if "origem" not in {r[1] for r in con.execute("PRAGMA table_info(mensagens)")}:
        con.execute("ALTER TABLE mensagens ADD COLUMN origem TEXT")  # 'agenda' = mandada pelo horário marcado
    con.execute("CREATE INDEX IF NOT EXISTS mensagens_conversa ON mensagens(conversa_id, id)")
    con.execute("CREATE INDEX IF NOT EXISTS conversas_projeto ON conversas(projeto, atualizada_em)")
    con.row_factory = lambda c, r: {d[0]: v for d, v in zip(c.description, r)}
    return con


def agora():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def pasta(pid):
    if not NOME_OK.match(pid or ""):
        raise KeyError("projeto inválido")
    p = os.path.join(BASE, pid)
    if not os.path.isfile(os.path.join(p, "projeto.json")):
        raise KeyError(f"projeto não existe: {pid}")
    return p


def ler(caminho, padrao=""):
    try:
        with open(caminho, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return padrao


def gravar(caminho, texto):
    tmp = caminho + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)
    os.replace(tmp, caminho)


def config(pid):
    return {"modelo": "sonnet", "esforco": "", **json.loads(ler(os.path.join(pasta(pid), "projeto.json"), "{}"))}


def listar():
    con = banco()
    saida = []
    for pid in sorted(os.listdir(BASE)) if os.path.isdir(BASE) else []:
        try:
            c = config(pid)
        except (KeyError, ValueError):
            continue
        r = con.execute("SELECT COUNT(*) n, MAX(atualizada_em) ultima FROM conversas WHERE projeto = ?", (pid,)).fetchone()
        ids = {x["id"] for x in con.execute("SELECT id FROM conversas WHERE projeto = ?", (pid,))}
        saida.append({"id": pid, "nome": c.get("nome", pid), "descricao": c.get("descricao", ""),
                      "modelo": c["modelo"], "ordem": c.get("ordem", 99), "importador": c.get("importador"),
                      "conversas": r["n"], "ultima": r["ultima"], "anexos": len(anexos(pid)),
                      "agenda": c.get("agenda"), "cor": c.get("cor"), "pendente": any(k in ids for k in PENDENTES)})
    con.close()
    return sorted(saida, key=lambda p: (p["ordem"], p["nome"]))


def anexos(pid):
    d = os.path.join(pasta(pid), "dados", "anexos")
    if not os.path.isdir(d):
        return []
    return [{"nome": n, "bytes": os.path.getsize(os.path.join(d, n)),
             "em": datetime.fromtimestamp(os.path.getmtime(os.path.join(d, n)), timezone.utc).isoformat(timespec="seconds")}
            for n in sorted(os.listdir(d)) if os.path.isfile(os.path.join(d, n))]


def detalhe(pid):
    c = config(pid)
    con = banco()
    conversas = con.execute("SELECT id, titulo, criada_em, atualizada_em FROM conversas WHERE projeto = ? "
                            "ORDER BY atualizada_em DESC", (pid,)).fetchall()
    con.close()
    p = pasta(pid)
    extra = {}
    if c.get("importador") == "nay":
        indice = os.path.join(p, "dados", "conversas", "indice.tsv")
        linhas = ler(indice).splitlines()[1:]
        dias = sorted({l.split("\t")[0] for l in linhas if l})
        extra["nay"] = {"conversas": len(linhas), "de": dias[0] if dias else None, "ate": dias[-1] if dias else None,
                        "importando": IMPORTANDO.get(pid), "ultima_importacao": ULTIMA_IMPORTACAO.get(pid)}
    return {"id": pid, **c, "contexto": ler(os.path.join(p, "contexto.md")), "conversas": conversas,
            "anexos": anexos(pid), "pendentes": [k for k in PENDENTES if k in {x["id"] for x in conversas}], **extra}


def salvar(pid, dados, novo=False):
    if novo:
        if not NOME_OK.match(pid or ""):
            raise ValueError("o id do projeto: letras minúsculas, números e hífen")
        p = os.path.join(BASE, pid)
        if os.path.exists(p):
            raise ValueError(f"já existe o projeto {pid}")
        os.makedirs(os.path.join(p, "dados", "anexos"))
        c = {"nome": pid, "ordem": 50}
    else:
        p = pasta(pid)
        c = json.loads(ler(os.path.join(p, "projeto.json"), "{}"))
    for k in ("nome", "descricao", "modelo", "esforco"):
        if k in dados:
            v = str(dados[k] or "").strip()
            if v:
                c[k] = v[:400]
            else:
                c.pop(k, None)
    if "cor" in dados:  # a cor do quadro (Pedro/Tel, 20/10: "cada um com uma cor que faça sentido")
        if dados["cor"] and not re.fullmatch(r"#[0-9a-fA-F]{6}", str(dados["cor"])):
            raise ValueError("cor no formato #rrggbb")
        c.pop("cor", None)
        if dados["cor"]:
            c["cor"] = dados["cor"]
    if "agenda" in dados:
        c.pop("agenda", None)
        ag = agenda_valida(dados["agenda"])
        if ag:
            c["agenda"] = ag
    gravar(os.path.join(p, "projeto.json"), json.dumps(c, ensure_ascii=False, indent=2) + "\n")
    if "contexto" in dados:
        gravar(os.path.join(p, "contexto.md"), str(dados["contexto"] or ""))
    return detalhe(pid)


DIAS_AGENDA = {"todos": range(7), "seg-sex": range(5), "seg-sab": range(6)}


def agenda_valida(ag):
    """{"horario": "HH:MM" (Brasília), "dias": todos|seg-sex|seg-sab, "mensagem"}; sem horário ou mensagem = sem agenda."""
    if not isinstance(ag, dict) or not ag.get("horario") or not str(ag.get("mensagem") or "").strip():
        return None
    if not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", str(ag["horario"])):
        raise ValueError("horário no formato HH:MM")
    dias = ag.get("dias") or "todos"
    if dias not in DIAS_AGENDA:
        raise ValueError("dias: todos, seg-sex ou seg-sab")
    return {"horario": ag["horario"], "dias": dias, "mensagem": str(ag["mensagem"]).strip()}


def conversa_atual(pid):
    """A conversa mais recente do projeto (a que aparece no quadrado); cria uma se não houver."""
    con = banco()
    r = con.execute("SELECT id FROM conversas WHERE projeto = ? ORDER BY atualizada_em DESC, id DESC LIMIT 1",
                    (pid,)).fetchone()
    con.close()
    return r["id"] if r else nova_conversa(pid)


def claude_md(pid):
    """O CLAUDE.md que o Claude lê sozinho ao abrir a pasta: refeito a cada mensagem para a data estar certa."""
    p = pasta(pid)
    c = config(pid)
    m = datetime.now(MANAUS)
    b = m + timedelta(hours=1)
    cab = (f"# Projeto {c.get('nome', pid)} (painel Agente Claude da Imob Easy)\n\n"
           f"Agora: {DIAS_SEMANA[m.weekday()]}, {m:%d/%m/%Y %H:%M} em Manaus ({b:%H:%M} em Brasília).\n\n"
           "Você conversa pelo painel agentes.imobeasy.online com quem é da Imob Easy (o Tel, dono, ou o Pedro).\n"
           "Neste projeto você só LÊ e não muda nada. Read, Glob e Grep valem dentro desta pasta. Para o resto, as "
           "ferramentas do MCP leitura: consultar_banco (naydb: Nay, imóveis, visitas, captação; crmdb: o CRM), "
           "ler_arquivo, listar e procurar (códigos da vps1: site, CRM, Nay nova, n8n; e da vps2: este painel). "
           "Não tem terminal, não manda WhatsApp e não abre arquivo de senha ou chave. Antes de consultar uma "
           "tabela, confira as colunas no information_schema.columns.\n"
           "Os arquivos anexados pela equipe ficam em ./dados/anexos (uma planilha .xlsx vira um .csv por aba, ao "
           "lado, com o nome da aba). Quando a pergunta citar um arquivo, leia antes de responder.\n"
           "O contexto abaixo foi escrito pelo Tel: siga as regras dele, inclusive o formato das respostas.\n")
    leitura = ler(os.path.join(p, "como-ler-os-dados.md")).strip()
    texto = cab + ("\n" + leitura + "\n" if leitura else "") + "\n---\n\n" + ler(os.path.join(p, "contexto.md"))
    gravar(os.path.join(p, "CLAUDE.md"), texto)


def nova_conversa(pid, titulo=None):
    pasta(pid)
    con = banco()
    t = agora()
    cur = con.execute("INSERT INTO conversas (projeto, sessao, titulo, criada_em, atualizada_em) VALUES (?, ?, ?, ?, ?)",
                      (pid, str(uuid.uuid4()), (titulo or "Conversa nova")[:80], t, t))
    con.commit()
    cid = cur.lastrowid
    con.close()
    return cid


def mensagens(cid):
    con = banco()
    conv = con.execute("SELECT * FROM conversas WHERE id = ?", (cid,)).fetchone()
    if not conv:
        con.close()
        raise KeyError("conversa não existe")
    linhas = con.execute("SELECT id, papel, texto, datetime(inicio, '-3 hours') inicio, ok, ms_total, tokens_entrada, "
                         "tokens_saida, cache_lido, custo_usd, erro, origem FROM mensagens WHERE conversa_id = ? "
                         "ORDER BY id",
                         (cid,)).fetchall()
    con.close()
    pend = PENDENTES.get(cid)
    return {"conversa": conv, "mensagens": linhas,
            "pendente": {"segundos": round(time.time() - pend["desde"])} if pend else None}


def enviar(cid, texto, origem=None):
    """Grava a mensagem e põe o Claude para responder em segundo plano. Uma resposta por vez em cada conversa.
    origem 'agenda' = mandada pelo horário marcado no projeto."""
    texto = (texto or "").strip()
    if not texto:
        raise ValueError("mensagem vazia")
    con = banco()
    conv = con.execute("SELECT * FROM conversas WHERE id = ?", (cid,)).fetchone()
    if not conv:
        con.close()
        raise KeyError("conversa não existe")
    with TRAVA:
        if cid in PENDENTES:
            con.close()
            raise ValueError("o Claude ainda está respondendo a mensagem anterior desta conversa")
        PENDENTES[cid] = {"desde": time.time()}
    primeira = not con.execute("SELECT 1 FROM mensagens WHERE conversa_id = ? AND papel = 'claude' AND ok = 1",
                               (cid,)).fetchone()
    t = agora()
    con.execute("INSERT INTO mensagens (conversa_id, papel, texto, inicio, origem) VALUES (?, 'voce', ?, ?, ?)",
                (cid, texto, t, origem))
    if conv["titulo"] == "Conversa nova":
        con.execute("UPDATE conversas SET titulo = ? WHERE id = ?", (texto.splitlines()[0][:80], cid))
    con.execute("UPDATE conversas SET atualizada_em = ? WHERE id = ?", (t, cid))
    con.commit()
    con.close()
    threading.Thread(target=_responder, args=(cid, conv, texto, primeira), daemon=True).start()


def _responder(cid, conv, texto, primeira):
    inicio = agora()
    t0 = time.monotonic()
    linha = {"ok": 0}
    try:
        pid = conv["projeto"]
        c = config(pid)
        claude_md(pid)
        pedido = {"modo": "projeto", "mensagem": texto, "modelo": c["modelo"], "esforco": c.get("esforco") or None,
                  "pasta": pasta(pid), "sessao": conv["sessao"], "nova": primeira, "timeout_s": 900}
        p = subprocess.run([agente.EXECUTOR], input=json.dumps(pedido), capture_output=True, text=True, timeout=960)
        j = json.loads(p.stdout) if p.stdout.strip().startswith("{") else {"is_error": True,
                                                                            "result": (p.stderr or p.stdout)[:2000]}
        u = j.get("usage") or {}
        linha.update(ok=0 if j.get("is_error") or p.returncode else 1, texto=j.get("result"),
                     ms_api=j.get("duration_api_ms"), tokens_entrada=u.get("input_tokens"),
                     tokens_saida=u.get("output_tokens"), cache_lido=u.get("cache_read_input_tokens"),
                     custo_usd=j.get("total_cost_usd"))
        if not linha["ok"]:
            linha["erro"], linha["texto"] = (j.get("result") or p.stderr or "erro sem texto").strip()[:2000], None
    except Exception as e:  # noqa: BLE001 - a resposta sempre volta para a tela, mesmo com erro
        linha["erro"] = f"{type(e).__name__}: {e}"[:2000]
    finally:
        linha["ms_total"] = round((time.monotonic() - t0) * 1000)
        con = banco()
        cols = ["conversa_id", "papel", "inicio"] + list(linha)
        con.execute(f"INSERT INTO mensagens ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})",
                    [cid, "claude", inicio] + list(linha.values()))
        con.execute("UPDATE conversas SET atualizada_em = ? WHERE id = ?", (agora(), cid))
        con.commit()
        con.close()
        PENDENTES.pop(cid, None)


def anexar(pid, nome, corpo):
    nome = os.path.basename(nome or "").strip()
    ext = os.path.splitext(nome)[1].lower()
    if not ANEXO_OK.match(nome) or ext not in TIPOS_ANEXO:
        raise ValueError("arquivo aceito: " + ", ".join(sorted(TIPOS_ANEXO)) + " (nome sem barras)")
    d = os.path.join(pasta(pid), "dados", "anexos")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, nome), "wb") as f:
        f.write(corpo)
    gerados = xlsx_para_csv(os.path.join(d, nome)) if ext == ".xlsx" else []
    return {"anexos": anexos(pid), "gerados": gerados}


def apagar_anexo(pid, nome):
    nome = os.path.basename(nome or "")
    caminho = os.path.join(pasta(pid), "dados", "anexos", nome)
    if not ANEXO_OK.match(nome) or not os.path.isfile(caminho):
        raise KeyError("anexo não existe")
    os.remove(caminho)
    return anexos(pid)


def xlsx_para_csv(caminho):
    """Uma planilha .xlsx vira um .csv por aba (valores como o Excel salvou, inclusive o resultado das fórmulas)."""
    import csv
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
          "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
    base = os.path.splitext(caminho)[0]
    gerados = []
    with zipfile.ZipFile(caminho) as z:
        comp = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", ns):
                comp.append("".join(t.text or "" for t in si.iter("{%s}t" % ns["m"])))
        rels = {r.get("Id"): r.get("Target") for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))}
        for aba in ET.fromstring(z.read("xl/workbook.xml")).find("m:sheets", ns):
            alvo = rels[aba.get("{%s}id" % ns["r"])].lstrip("/")
            alvo = alvo if alvo.startswith("xl/") else "xl/" + alvo
            linhas = []
            for row in ET.fromstring(z.read(alvo)).iter("{%s}row" % ns["m"]):
                valores = {}
                for c in row.findall("m:c", ns):
                    col = re.match(r"[A-Z]+", c.get("r", "A")).group(0)
                    idx = 0
                    for ch in col:
                        idx = idx * 26 + ord(ch) - 64
                    v = c.find("m:v", ns)
                    if c.get("t") == "s" and v is not None:
                        valor = comp[int(v.text)]
                    elif c.get("t") == "inlineStr":
                        valor = "".join(t.text or "" for t in c.iter("{%s}t" % ns["m"]))
                    else:
                        valor = v.text if v is not None else ""
                    valores[idx] = valor
                if valores:
                    linhas.append([valores.get(i, "") for i in range(1, max(valores) + 1)])
            nome_aba = re.sub(r"[^\w\- ]", "_", aba.get("name"))[:40]
            saida = f"{base} - {nome_aba}.csv"
            with open(saida, "w", encoding="utf-8", newline="") as f:
                csv.writer(f).writerows(linhas)
            gerados.append(os.path.basename(saida))
    return gerados


def importar(pid, dias):
    """O botão "Importar conversas da Nay": roda o importar_nay.py em segundo plano para a pasta do projeto."""
    c = config(pid)
    if c.get("importador") != "nay":
        raise ValueError("este projeto não tem importador")
    with TRAVA:
        if pid in IMPORTANDO:
            raise ValueError("já está importando")
        IMPORTANDO[pid] = {"desde": time.time(), "dias": dias}

    def rodar():
        try:
            r = subprocess.run(["/usr/bin/python3", os.path.join(agente.BASE, "importar_nay.py"), "--dias", str(dias),
                                "--saida", os.path.join(pasta(pid), "dados", "conversas")],
                               capture_output=True, text=True, timeout=1800)
            fim = ((r.stdout if r.returncode == 0 else r.stderr) or "").strip().splitlines()
            ULTIMA_IMPORTACAO[pid] = {"em": agora(), "ok": r.returncode == 0, "texto": fim[-1] if fim else ""}
        except Exception as e:  # noqa: BLE001
            ULTIMA_IMPORTACAO[pid] = {"em": agora(), "ok": False, "texto": f"{type(e).__name__}: {e}"}
        finally:
            IMPORTANDO.pop(pid, None)
    threading.Thread(target=rodar, daemon=True).start()
