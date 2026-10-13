# -*- coding: utf-8 -*-
"""
Ponte do painel dos Hermes (admin › Agentes do site). Pedro, 13/10/2026: "um quadrado para cada agente do hermes
... controlar o navegador deles, mandar msg, tudo por essa mesma tela para cada um, todas as funções disponíveis".

Roda na VPS2 (srv1877774), só no endereço do Tailscale, e só responde a quem manda o X-Painel-Token. Quem chama é a
API do site (VPS1), na rota /admin/api/hermes/..., que fica atrás da senha do /admin. O navegador do Pedro nunca fala
com esta ponte direto e nenhum segredo daqui vai para a página.

Para cada perfil do Hermes (/etc/hermes-painel/perfis.json) ela junta:
  - o serviço (systemd): estado, memória, reiniciar/parar/iniciar;
  - a conversa: a API que o próprio Hermes traz (gateway/platforms/api_server.py), ligada em 127.0.0.1 pelo
    drop-in /etc/systemd/system/hermes-gateway-<perfil>.service.d/painel.conf;
  - o navegador: um Chrome por perfil (hermes-chrome-<perfil>.service), que sobe sozinho na primeira ligação
    (socket do systemd) e desliga depois de 20 min parado. O Hermes usa ESTE Chrome (BROWSER_CDP_URL) e a ponte tira
    a foto da tela e manda clique e tecla pelo mesmo CDP: o que o Pedro vê é o que o agente está fazendo;
  - tarefas agendadas, skills, memória e logs do perfil.
"""
import asyncio
import hashlib
import hmac
import json
import logging
import os
import re
import time
import urllib.parse
from pathlib import Path

import aiohttp
import websockets
import yaml
from aiohttp import web

PERFIS_DIR = Path(os.environ.get("HERMES_PERFIS", "/root/.hermes/profiles"))
ETC = Path(os.environ.get("PAINEL_ETC", "/etc/hermes-painel"))
TOKEN = os.environ.get("PAINEL_TOKEN", "")
PERFIS = json.loads((ETC / "perfis.json").read_text(encoding="utf-8"))   # a ordem do arquivo é a dos quadrados

log = logging.getLogger("ponte")
VIVOS = ("started", "queued", "running", "waiting_for_approval", "stopping")
EXEC = {}    # run_id -> a execução (linha do tempo, estado)
ATUAL = {}   # perfil -> run_id da última execução pedida pelo painel
NAV = {}     # perfil -> {"cdp": {aba: Cdp}, "aba": aba escolhida à mão}
_cache = {}


class Erro(Exception):
    def __init__(self, status, msg):
        super().__init__(msg)
        self.status, self.msg = status, msg


@web.middleware
async def porteiro(request, handler):
    if not TOKEN or not hmac.compare_digest(request.headers.get("X-Painel-Token", ""), TOKEN):
        return web.json_response({"erro": "não autorizado"}, status=401)
    try:
        return await handler(request)
    except Erro as e:
        return web.json_response({"erro": e.msg}, status=e.status)
    except web.HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        log.exception("falha em %s", request.path)
        return web.json_response({"erro": "falha na ponte (" + type(e).__name__ + ")"}, status=500)


def perfil(request):
    p = request.match_info["p"]
    if p not in PERFIS:
        raise Erro(404, "não conheço esse agente")
    return p


async def corpo_json(request):
    try:
        d = await request.json()
    except Exception:  # noqa: BLE001
        raise Erro(400, "corpo inválido")
    if not isinstance(d, dict):
        raise Erro(400, "corpo inválido")
    return d


def guardado(chave, segundos):
    v = _cache.get(chave)
    return v[1] if v and time.time() - v[0] < segundos else None


def guardar(chave, valor):
    _cache[chave] = (time.time(), valor)
    return valor


# ---------------------------------------------------------------- systemd
async def sh(*args, timeout=25):
    proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    try:
        saida, _ = await asyncio.wait_for(proc.communicate(), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return 124, ""
    return proc.returncode, saida.decode("utf-8", "replace")


async def unidade(nome, *props):
    args = ["systemctl", "show", nome, "--timestamp=unix"]
    for p in props:
        args += ["-p", p]
    _, saida = await sh(*args)
    return dict(l.split("=", 1) for l in saida.splitlines() if "=" in l)


def inteiro(v):
    try:
        return int(str(v).lstrip("@").strip())
    except (TypeError, ValueError):
        return 0


async def estado_servico(svc):
    u = await unidade(svc, "LoadState", "ActiveState", "SubState", "MemoryCurrent", "CPUUsageNSec",
                      "ActiveEnterTimestamp", "NRestarts")
    ativo = u.get("ActiveState") == "active"
    return {
        "nome": svc, "ativo": ativo, "estado": u.get("ActiveState") or "?", "sub": u.get("SubState") or "",
        # masked = alguém bloqueou o serviço de propósito: a ponte mostra e não liga
        "bloqueado": u.get("LoadState") == "masked", "existe": u.get("LoadState") not in ("not-found", ""),
        "mem": inteiro(u.get("MemoryCurrent")) if ativo else 0, "cpu_s": round(inteiro(u.get("CPUUsageNSec")) / 1e9, 1),
        "desde": inteiro(u.get("ActiveEnterTimestamp")) if ativo else 0, "reinicios": inteiro(u.get("NRestarts")),
    }


async def chrome_ligado(p):
    """(ligado, memória). Pergunta ao systemd: bater na porta acordaria o Chrome."""
    if not PERFIS[p].get("cdp_porta"):
        return False, 0
    v = guardado(("chrome", p), 2)
    if v is None:
        u = await unidade("hermes-chrome-%s.service" % p, "ActiveState", "MemoryCurrent")
        v = guardar(("chrome", p), (u.get("ActiveState") == "active", inteiro(u.get("MemoryCurrent"))))
    return v


# ---------------------------------------------------------------- arquivos do perfil
def ler(caminho, limite=200_000):
    try:
        return Path(caminho).read_text(encoding="utf-8", errors="replace")[:limite]
    except OSError:
        return ""


def resumo_perfil(p):
    pasta = PERFIS_DIR / p
    try:
        conf = yaml.safe_load(ler(pasta / "config.yaml")) or {}
    except yaml.YAMLError:
        conf = {}
    modelo = conf.get("model") if isinstance(conf.get("model"), dict) else {}
    try:
        estado = json.loads(ler(pasta / "gateway_state.json") or "{}")
    except ValueError:
        estado = {}
    plataformas = {n: (v or {}).get("state") for n, v in (estado.get("platforms") or {}).items() if n != "api_server"}
    return {"modelo": modelo.get("default"), "provedor": modelo.get("provider"), "plataformas": plataformas,
            "alma": ler(pasta / "SOUL.md", 420).strip()}


def tarefas_do_arquivo(p):
    try:
        d = json.loads(ler(PERFIS_DIR / p / "cron" / "jobs.json") or "{}")
    except ValueError:
        return []
    js = d.get("jobs", d) if isinstance(d, dict) else d
    if isinstance(js, dict):
        js = list(js.values())
    return [j for j in js if isinstance(j, dict)]


def tarefa_limpa(j):
    ag = j.get("schedule")
    return {
        "id": j.get("id"), "nome": j.get("name") or "(sem nome)", "pedido": (j.get("prompt") or "")[:1500],
        "quando": j.get("schedule_display") or (ag.get("display") if isinstance(ag, dict) else str(ag or "")),
        "ligada": bool(j.get("enabled", True)) and j.get("state") != "paused", "estado": j.get("state"),
        "proxima": j.get("next_run_at"), "ultima": j.get("last_run_at"), "resultado": j.get("last_status"),
        "erro": (j.get("last_error") or j.get("last_delivery_error") or "")[:300] or None, "entrega": j.get("deliver"),
    }


SEGREDO = re.compile(
    r"(sk-[A-Za-z0-9_\-]{12,}|\b\d{8,10}:[A-Za-z0-9_\-]{30,}|Bearer\s+[A-Za-z0-9._\-]{12,}"
    r"|((?:token|api[_-]?key|secret|password|senha)\w*[\"']?\s*[=:]\s*[\"']?)[^\s\"',}]{6,})", re.I)


def sem_segredo(texto):
    return SEGREDO.sub(lambda m: (m.group(2) or "") + "•••", texto)


def cauda(caminho, linhas):
    try:
        with open(caminho, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 400_000))
            txt = f.read().decode("utf-8", "replace")
    except OSError:
        return []
    return [sem_segredo(l)[:600] for l in txt.splitlines()[-linhas:]]


# ---------------------------------------------------------------- a API do próprio Hermes
def chave_api(p):
    for l in ler(ETC / ("gateway-%s.env" % p)).splitlines():
        if l.startswith("API_SERVER_KEY="):
            return l.split("=", 1)[1].strip()
    return ""


async def hermes(app, p, metodo, caminho, corpo=None, params=None, timeout=30):
    porta = PERFIS[p].get("api_porta")
    if not porta:
        raise Erro(409, "este agente não tem conversa pelo painel (o serviço dele está bloqueado)")
    try:
        async with app["http"].request(metodo, "http://127.0.0.1:%s%s" % (porta, caminho), json=corpo, params=params,
                                       headers={"Authorization": "Bearer " + chave_api(p)},
                                       timeout=aiohttp.ClientTimeout(total=timeout)) as r:
            txt = await r.text()
            try:
                return r.status, json.loads(txt)
            except ValueError:
                return r.status, {"texto": txt[:2000]}
    except (aiohttp.ClientConnectorError, asyncio.TimeoutError, aiohttp.ServerDisconnectedError):
        raise Erro(503, "o Hermes deste agente não respondeu (serviço parado ou reiniciando)")


def erro_do_hermes(st, d):
    e = d.get("error") if isinstance(d, dict) else None
    msg = e.get("message") if isinstance(e, dict) else (e or (d.get("texto") if isinstance(d, dict) else None))
    return Erro(st if 400 <= st < 600 else 502, "o Hermes respondeu %s: %s" % (st, str(msg or "sem detalhe")[:300]))


async def api_no_ar(app, p):
    if not PERFIS[p].get("api_porta"):
        return False
    v = guardado(("api", p), 5)
    if v is None:
        try:
            async with app["http"].get("http://127.0.0.1:%s/health" % PERFIS[p]["api_porta"],
                                       timeout=aiohttp.ClientTimeout(total=2)) as r:
                v = r.status == 200
        except Exception:  # noqa: BLE001
            v = False
        guardar(("api", p), v)
    return v


# ---------------------------------------------------------------- rotas: lista e serviço
async def r_agentes(request):
    app = request.app
    lista = []
    for p, conf in PERFIS.items():
        svc, ligado, no_ar = await asyncio.gather(estado_servico(conf["servico"]), chrome_ligado(p), api_no_ar(app, p))
        run = EXEC.get(ATUAL.get(p)) or {}
        item = {"id": p, "nome": conf.get("nome") or p, "faz": conf.get("faz") or "", "servico": svc,
                "conversa": bool(conf.get("api_porta")), "api_no_ar": no_ar,
                "navegador": {"tem": bool(conf.get("cdp_porta")), "ligado": ligado[0], "mem": ligado[1]},
                "tarefas": len(tarefas_do_arquivo(p)), "trabalhando": run.get("status") in VIVOS}
        item.update(resumo_perfil(p))
        if not svc["ativo"]:
            item["plataformas"] = {}      # o arquivo de estado é de quando ele rodou pela última vez
        lista.append(item)
    return web.json_response({"agentes": lista, "agora": int(time.time())})


async def r_servico(request):
    p = perfil(request)
    acao = (await corpo_json(request)).get("acao")
    verbo = {"iniciar": "start", "parar": "stop", "reiniciar": "restart"}.get(acao)
    if not verbo:
        raise Erro(400, "ação desconhecida")
    svc = PERFIS[p]["servico"]
    if (await estado_servico(svc))["bloqueado"]:
        raise Erro(409, "este serviço foi bloqueado de propósito no servidor (masked); a ponte não o liga")
    rc, saida = await sh("systemctl", "--no-block", verbo, svc)
    if rc != 0:
        raise Erro(500, "o systemd recusou: " + saida.strip()[:200])
    _cache.pop(("api", p), None)
    return web.json_response({"ok": True})


# ---------------------------------------------------------------- rotas: conversa
def texto_de(conteudo):
    if isinstance(conteudo, str):
        return conteudo
    if isinstance(conteudo, list):
        return " ".join(str(x.get("text", "")) for x in conteudo if isinstance(x, dict) and x.get("type") == "text")
    return "" if conteudo is None else str(conteudo)


async def r_sessoes(request):
    p = perfil(request)
    st, d = await hermes(request.app, p, "GET", "/api/sessions", params={"limit": "40"})
    if st != 200:
        raise erro_do_hermes(st, d)
    return web.json_response({"sessoes": [{
        "id": s.get("id"), "titulo": s.get("title") or (s.get("preview") or "")[:60] or "(sem título)",
        "origem": s.get("source"), "mensagens": s.get("message_count"), "ultima": s.get("last_active") or s.get("started_at"),
    } for s in d.get("data", [])]})


async def mensagens_da_sessao(app, p, sid):
    st, d = await hermes(app, p, "GET", "/api/sessions/%s/messages" % urllib.parse.quote(sid, safe=""))
    if st != 200:
        raise erro_do_hermes(st, d)
    return d.get("data", [])


async def r_mensagens(request):
    p = perfil(request)
    saida = []
    for m in await mensagens_da_sessao(request.app, p, request.match_info["sid"]):
        papel, txt = m.get("role"), texto_de(m.get("content"))
        if papel == "tool":
            saida.append({"papel": "ferramenta", "nome": m.get("tool_name"), "texto": sem_segredo(txt)[:500], "quando": m.get("timestamp")})
        elif papel in ("user", "assistant"):
            usou = [((c.get("function") or {}).get("name") or c.get("name")) for c in (m.get("tool_calls") or []) if isinstance(c, dict)]
            if txt.strip() or usou:
                saida.append({"papel": "voce" if papel == "user" else "agente", "texto": txt, "usou": [u for u in usou if u],
                              "quando": m.get("timestamp")})
    return web.json_response({"mensagens": saida[-300:]})


def registrar(run, ev):
    """Um evento do Hermes vira um item da linha do tempo que a tela desenha."""
    tipo, linha = ev.get("event"), run["linha"]
    if tipo == "message.delta":
        if linha and linha[-1]["t"] == "texto":
            linha[-1]["v"] += ev.get("delta") or ""
        else:
            linha.append({"t": "texto", "v": ev.get("delta") or ""})
    elif tipo == "tool.started":
        linha.append({"t": "ferramenta", "nome": ev.get("tool"), "previa": sem_segredo(str(ev.get("preview") or ""))[:300], "estado": "rodando"})
    elif tipo == "tool.completed":
        for item in reversed(linha):
            if item["t"] == "ferramenta" and item["nome"] == ev.get("tool") and item["estado"] == "rodando":
                item["estado"] = "erro" if ev.get("error") else "ok"
                item["dur"] = ev.get("duration")
                break
    elif tipo == "reasoning.available":
        pensou = (ev.get("text") or "").strip()
        # o Hermes repete a resposta final como "pensamento": isso não entra
        if pensou and not any(i["t"] == "texto" and pensou in i["v"] for i in linha[-2:]):
            linha.append({"t": "pensando", "v": pensou[:800]})
    elif tipo == "approval.request":
        run["status"] = "waiting_for_approval"
        linha.append({"t": "aprovacao", "comando": str(ev.get("command") or "")[:1200], "motivo": str(ev.get("description") or ev.get("reason") or "")[:400],
                      "escolhas": ev.get("choices") or ["once", "deny"], "pendente": True})
    elif tipo == "approval.responded":
        run["status"] = "running"
        for item in linha:
            if item["t"] == "aprovacao" and item.get("pendente"):
                item["pendente"], item["resposta"] = False, ev.get("choice")
    elif tipo == "run.completed":
        run["status"], run["saida"] = "completed", ev.get("output") or ""
    elif tipo == "run.failed":
        run["status"], run["erro"] = "failed", sem_segredo(str(ev.get("error") or "falhou"))[:600]
    elif tipo == "run.cancelled":
        run["status"] = "cancelled"
    else:
        return
    del linha[:-400]
    run["v"] += 1
    run["mexeu"] = time.time()


async def consumir(app, p, run):
    """Fica ouvindo os eventos da execução (SSE do Hermes) e guarda a linha do tempo para a tela buscar."""
    url = "http://127.0.0.1:%s/v1/runs/%s/events" % (PERFIS[p]["api_porta"], run["id"])
    try:
        async with app["http"].get(url, headers={"Authorization": "Bearer " + chave_api(p)},
                                   timeout=aiohttp.ClientTimeout(total=None, sock_read=None)) as r:
            async for bruto in r.content:
                l = bruto.decode("utf-8", "replace").strip()
                if l.startswith("data:"):
                    try:
                        registrar(run, json.loads(l[5:]))
                    except ValueError:
                        pass
    except Exception as e:  # noqa: BLE001
        log.warning("eventos de %s caíram: %s", run["id"], e)
    if run["status"] in VIVOS:      # o fio caiu antes do fim: o estado de verdade está no Hermes
        try:
            st, d = await hermes(app, p, "GET", "/v1/runs/" + run["id"], timeout=8)
            if st == 200 and d.get("status") not in VIVOS:
                run["status"], run["saida"], run["erro"] = d.get("status"), d.get("output") or run.get("saida"), d.get("error")
            elif st != 200:
                run["status"], run["erro"] = "failed", "perdi o contato com a execução"
        except Erro:
            run["status"], run["erro"] = "failed", "o Hermes parou de responder no meio da execução"
        run["v"] += 1
    run["fim"] = time.time()


async def r_enviar(request):
    app, p = request.app, perfil(request)
    corpo = await corpo_json(request)
    texto, sessao = str(corpo.get("texto") or "").strip(), corpo.get("sessao") or None
    if not texto:
        raise Erro(400, "escreva a mensagem")
    if len(texto) > 20_000:
        raise Erro(400, "mensagem grande demais")
    if (EXEC.get(ATUAL.get(p)) or {}).get("status") in VIVOS:
        raise Erro(409, "este agente ainda está trabalhando no pedido anterior; espere terminar ou pare")
    historico = []
    if sessao:
        for m in await mensagens_da_sessao(app, p, sessao):
            txt = texto_de(m.get("content")).strip()
            if m.get("role") in ("user", "assistant") and txt:
                historico.append({"role": m["role"], "content": txt})
    else:
        st, d = await hermes(app, p, "POST", "/api/sessions", {"title": texto[:70]})
        if st not in (200, 201):
            raise erro_do_hermes(st, d)
        sessao = (d.get("session") or d).get("id")
    pedido = {"input": texto, "session_id": sessao}
    if historico:
        pedido["conversation_history"] = historico[-60:]
    st, d = await hermes(app, p, "POST", "/v1/runs", pedido)
    if st not in (200, 202) or not d.get("run_id"):
        raise erro_do_hermes(st, d)
    run = {"id": d["run_id"], "perfil": p, "sessao": sessao, "status": "running", "linha": [], "v": 1, "saida": "",
           "erro": None, "pedido": texto, "inicio": time.time(), "mexeu": time.time(), "fim": None}
    EXEC[run["id"]] = run
    ATUAL[p] = run["id"]
    run["tarefa"] = asyncio.create_task(consumir(app, p, run))
    return web.json_response({"run": run["id"], "sessao": sessao})


def run_do_pedido(request, p):
    run = EXEC.get(request.match_info["rid"])
    if not run or run["perfil"] != p:
        raise Erro(404, "não achei essa execução")
    return run


async def r_parar(request):
    p = perfil(request)
    run = run_do_pedido(request, p)
    st, d = await hermes(request.app, p, "POST", "/v1/runs/%s/stop" % run["id"])
    if st == 200 and run["status"] in VIVOS:
        run["status"] = "stopping"
        run["v"] += 1
    return web.json_response({"ok": st == 200})


async def r_aprovar(request):
    p = perfil(request)
    run = run_do_pedido(request, p)
    escolha = (await corpo_json(request)).get("escolha")
    if escolha not in ("once", "session", "always", "deny"):
        raise Erro(400, "escolha inválida")
    st, d = await hermes(request.app, p, "POST", "/v1/runs/%s/approval" % run["id"], {"choice": escolha})
    if st != 200:
        raise erro_do_hermes(st, d)
    return web.json_response({"ok": True})


# ---------------------------------------------------------------- rotas: tarefas, skills, memória, logs
async def r_tarefas(request):
    p = perfil(request)
    if await api_no_ar(request.app, p):
        st, d = await hermes(request.app, p, "GET", "/api/jobs", params={"include_disabled": "true"})
        if st == 200:
            return web.json_response({"tarefas": [tarefa_limpa(j) for j in d.get("jobs", [])], "pode_mexer": True})
    return web.json_response({"tarefas": [tarefa_limpa(j) for j in tarefas_do_arquivo(p)], "pode_mexer": False})


async def r_tarefa_nova(request):
    p = perfil(request)
    c = await corpo_json(request)
    nome, quando, pedido = str(c.get("nome") or "").strip(), str(c.get("quando") or "").strip(), str(c.get("pedido") or "").strip()
    if not nome or not quando or not pedido:
        raise Erro(400, "preencha o nome, o horário e o pedido")
    st, d = await hermes(request.app, p, "POST", "/api/jobs",
                         {"name": nome, "schedule": quando, "prompt": pedido, "deliver": str(c.get("entrega") or "local")})
    if st != 200:
        raise Erro(400, str(d.get("error") or "o Hermes recusou a tarefa")[:300])
    return web.json_response({"ok": True})


async def r_tarefa_acao(request):
    p = perfil(request)
    jid, acao = urllib.parse.quote(request.match_info["jid"], safe=""), request.match_info["acao"]
    if acao == "excluir":
        st, d = await hermes(request.app, p, "DELETE", "/api/jobs/" + jid)
    else:
        verbo = {"pausar": "pause", "retomar": "resume", "rodar": "run"}.get(acao)
        if not verbo:
            raise Erro(400, "ação desconhecida")
        st, d = await hermes(request.app, p, "POST", "/api/jobs/%s/%s" % (jid, verbo))
    if st not in (200, 202):
        raise Erro(400, str((d or {}).get("error") or "o Hermes recusou")[:300])
    return web.json_response({"ok": True})


def skills_do_disco(p):
    saida = []
    raiz = PERFIS_DIR / p / "skills"
    for arq in sorted(raiz.glob("*/*/SKILL.md")) + sorted(raiz.glob("*/SKILL.md")):
        cab = ler(arq, 1500)
        desc = re.search(r"^description:\s*(.+)$", cab, re.M)
        partes = arq.relative_to(raiz).parts
        saida.append({"nome": partes[-2], "grupo": partes[0] if len(partes) > 2 else "",
                      "descricao": (desc.group(1).strip().strip("\"'") if desc else "")[:260]})
    return saida


async def r_skills(request):
    p = perfil(request)
    ferramentas = []
    if await api_no_ar(request.app, p):
        st, d = await hermes(request.app, p, "GET", "/v1/toolsets")
        if st == 200:
            for t in d.get("data") or d.get("toolsets") or []:
                if isinstance(t, dict):
                    ferramentas.append({"nome": t.get("name") or t.get("id"), "descricao": (t.get("description") or "")[:200],
                                        "ligada": t.get("enabled"), "itens": t.get("tools") if isinstance(t.get("tools"), list) else []})
    return web.json_response({"skills": skills_do_disco(p), "ferramentas": ferramentas})


MEMORIAS = ("MEMORY.md", "USER.md")


async def r_memoria(request):
    p = perfil(request)
    pasta = PERFIS_DIR / p
    arquivos = [{"nome": n, "texto": ler(pasta / "memories" / n), "edita": True} for n in MEMORIAS if (pasta / "memories" / n).exists()]
    arquivos.append({"nome": "SOUL.md", "texto": ler(pasta / "SOUL.md"), "edita": False})
    return web.json_response({"arquivos": arquivos})


async def r_memoria_salvar(request):
    p = perfil(request)
    c = await corpo_json(request)
    nome, texto = c.get("nome"), c.get("texto")
    if nome not in MEMORIAS or not isinstance(texto, str) or len(texto) > 60_000:
        raise Erro(400, "só a memória (MEMORY.md e USER.md) é editada por aqui")
    arq = PERFIS_DIR / p / "memories" / nome
    if arq.exists():       # o que estava fica guardado ao lado
        (arq.parent / (nome + ".antes-do-painel-" + time.strftime("%Y%m%d-%H%M%S"))).write_text(arq.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    arq.write_text(texto, encoding="utf-8")
    return web.json_response({"ok": True})


async def r_logs(request):
    p = perfil(request)
    qual = request.query.get("arquivo", "agent")
    if qual not in ("agent", "gateway", "errors"):
        raise Erro(400, "log desconhecido")
    n = max(20, min(400, inteiro(request.query.get("linhas")) or 150))
    return web.json_response({"linhas": cauda(PERFIS_DIR / p / "logs" / (qual + ".log"), n)})


# ---------------------------------------------------------------- navegador (CDP)
class Cdp:
    """Uma ligação com uma aba do Chrome: manda comando e espera a resposta de mesmo id."""

    def __init__(self, ws):
        self.ws, self.n, self.espera, self.usado = ws, 0, {}, time.time()
        self.leitor = asyncio.create_task(self._ler())

    async def _ler(self):
        try:
            async for bruto in self.ws:
                m = json.loads(bruto)
                f = self.espera.pop(m.get("id"), None)
                if f is not None and not f.done():
                    f.set_result(m)
        except Exception:  # noqa: BLE001
            pass
        finally:
            for f in self.espera.values():
                if not f.done():
                    f.set_exception(ConnectionError("o Chrome fechou a ligação"))
            self.espera.clear()

    @property
    def aberta(self):
        return not self.leitor.done()

    async def cmd(self, metodo, params=None, timeout=12):
        self.n += 1
        self.usado = time.time()
        f = asyncio.get_running_loop().create_future()
        self.espera[self.n] = f
        await self.ws.send(json.dumps({"id": self.n, "method": metodo, "params": params or {}}))
        try:
            m = await asyncio.wait_for(f, timeout)
        except asyncio.TimeoutError:
            self.espera.pop(self.n, None)
            raise
        if "error" in m:
            raise Erro(502, "o navegador recusou: " + str(m["error"].get("message"))[:200])
        return m.get("result") or {}

    async def fechar(self):
        try:
            await self.ws.close()
        except Exception:  # noqa: BLE001
            pass


async def chrome_http(app, p, caminho, metodo="GET", timeout=6):
    async with app["http"].request(metodo, "http://127.0.0.1:%s%s" % (PERFIS[p]["cdp_porta"], caminho),
                                   timeout=aiohttp.ClientTimeout(total=timeout)) as r:
        txt = await r.text()
        try:
            return json.loads(txt)
        except ValueError:
            return txt


async def abas_do_chrome(app, p):
    lista = await chrome_http(app, p, "/json/list")
    return [a for a in lista if isinstance(a, dict) and a.get("type") == "page"] if isinstance(lista, list) else []


async def ligar_cdp(app, p, pedida=None):
    """(ligação, aba em uso, todas as abas). Sem aba escolhida, vale a que o Chrome usou por último: a do agente."""
    nav = NAV.setdefault(p, {"cdp": {}, "aba": None})
    lista = await abas_do_chrome(app, p)
    if not lista:
        await chrome_http(app, p, "/json/new?about:blank", "PUT")
        lista = await abas_do_chrome(app, p)
        if not lista:
            raise Erro(502, "o navegador não abriu nenhuma aba")
    ids = [a["id"] for a in lista]
    if nav["aba"] not in ids:
        nav["aba"] = None
    alvo = pedida if pedida in ids else (nav["aba"] or ids[0])
    c = nav["cdp"].get(alvo)
    if c is None or not c.aberta:
        url = next(a["webSocketDebuggerUrl"] for a in lista if a["id"] == alvo)
        c = nav["cdp"][alvo] = Cdp(await websockets.connect(url, max_size=None, open_timeout=8, ping_interval=None))
    for morta in [i for i in nav["cdp"] if i not in ids]:
        await nav["cdp"].pop(morta).fechar()
    return c, alvo, lista


async def retrato(app, p, pedida, hash_cliente):
    ligado, mem = await chrome_ligado(p)
    if not ligado:
        return {"ligado": False}
    c, alvo, lista = await ligar_cdp(app, p, pedida)
    foto = {"format": "jpeg", "quality": 62, "optimizeForSpeed": True}
    try:
        r = await c.cmd("Page.captureScreenshot", foto, timeout=4)
    except asyncio.TimeoutError:        # aba de fundo não desenha: traz para a frente e tenta de novo
        await c.cmd("Page.bringToFront", timeout=4)
        r = await c.cmd("Page.captureScreenshot", foto, timeout=8)
    dados = r.get("data") or ""
    marca = hashlib.md5(dados.encode()).hexdigest()[:12]
    atual = next(a for a in lista if a["id"] == alvo)
    saida = {"ligado": True, "mem": mem, "aba": alvo, "url": atual.get("url"), "titulo": atual.get("title"), "hash": marca,
             "seguindo": NAV[p]["aba"] is None and not pedida,
             "abas": [{"id": a["id"], "titulo": (a.get("title") or a.get("url") or "")[:80], "url": a.get("url")} for a in lista]}
    if marca != hash_cliente:
        saida["img"] = dados
    return saida


TECLAS = {"Enter": (13, "\r"), "Backspace": (8, None), "Tab": (9, None), "Escape": (27, None), "Delete": (46, None),
          "ArrowLeft": (37, None), "ArrowUp": (38, None), "ArrowRight": (39, None), "ArrowDown": (40, None),
          "Home": (36, None), "End": (35, None), "PageUp": (33, None), "PageDown": (34, None)}
ATALHOS = {"a": "selectAll", "c": "copy", "v": "paste", "x": "cut", "z": "undo"}


def endereco(texto):
    u = str(texto or "").strip()
    if not u:
        raise Erro(400, "diga o endereço")
    if u == "about:blank":
        return u
    if re.match(r"^https?://", u, re.I):
        return u
    if re.match(r"^[a-z][a-z0-9+.\-]*:", u, re.I) and not re.match(r"^[\w.\-]+:\d+", u):
        raise Erro(400, "só abro endereço http ou https")
    if " " in u or "." not in u:
        return "https://www.google.com/search?q=" + urllib.parse.quote(u)
    return "https://" + u


def numero(v, minimo=-100000.0, maximo=100000.0):
    try:
        return max(minimo, min(maximo, float(v)))
    except (TypeError, ValueError):
        raise Erro(400, "número inválido")


async def r_nav_ligar(request):
    """Bater na porta acorda o Chrome (socket do systemd); espera ele responder."""
    app, p = request.app, perfil(request)
    if not PERFIS[p].get("cdp_porta"):
        raise Erro(409, "este agente não tem navegador pelo painel")
    for _ in range(40):
        try:
            v = await chrome_http(app, p, "/json/version", timeout=3)
            if isinstance(v, dict) and v.get("Browser"):
                _cache.pop(("chrome", p), None)
                return web.json_response({"ok": True})
        except Exception:  # noqa: BLE001
            pass
        await asyncio.sleep(0.5)
    raise Erro(504, "o navegador não subiu em 20 s")


async def r_nav_desligar(request):
    p = perfil(request)
    if not PERFIS[p].get("cdp_porta"):
        raise Erro(409, "este agente não tem navegador pelo painel")
    for c in list(NAV.get(p, {}).get("cdp", {}).values()):
        await c.fechar()
    NAV.pop(p, None)
    await sh("systemctl", "stop", "hermes-chrome-%s-porta.service" % p, "hermes-chrome-%s.service" % p)
    _cache.pop(("chrome", p), None)
    return web.json_response({"ok": True})


async def r_nav_acao(request):
    app, p = request.app, perfil(request)
    a = await corpo_json(request)
    tipo = a.get("tipo")
    if not (await chrome_ligado(p))[0]:
        raise Erro(409, "o navegador deste agente está desligado")
    nav = NAV.setdefault(p, {"cdp": {}, "aba": None})
    if tipo == "nova_aba":
        nova = await chrome_http(app, p, "/json/new?" + urllib.parse.quote(endereco(a.get("url") or "about:blank"), safe=":/?&=%#"), "PUT")
        nav["aba"] = nova.get("id") if isinstance(nova, dict) else None
        return web.json_response({"ok": True, "aba": nav["aba"]})
    if tipo == "fechar_aba":
        if len(await abas_do_chrome(app, p)) <= 1:
            raise Erro(409, "é a última aba; para fechar tudo, desligue o navegador")
        await chrome_http(app, p, "/json/close/" + urllib.parse.quote(str(a.get("aba") or ""), safe=""))
        nav["aba"] = None
        return web.json_response({"ok": True})
    if tipo == "seguir":             # volta a acompanhar a aba que o agente estiver usando
        nav["aba"] = None
        return web.json_response({"ok": True})
    c, alvo, _ = await ligar_cdp(app, p, a.get("aba"))
    if tipo == "focar_aba":
        nav["aba"] = alvo
        await c.cmd("Page.bringToFront")
    elif tipo == "navegar":
        await c.cmd("Page.navigate", {"url": endereco(a.get("url"))})
    elif tipo == "recarregar":
        await c.cmd("Page.reload")
    elif tipo in ("voltar", "avancar"):
        h = await c.cmd("Page.getNavigationHistory")
        i = h.get("currentIndex", 0) + (-1 if tipo == "voltar" else 1)
        if 0 <= i < len(h.get("entries", [])):
            await c.cmd("Page.navigateToHistoryEntry", {"entryId": h["entries"][i]["id"]})
    elif tipo == "clicar":
        x, y = numero(a.get("x"), 0), numero(a.get("y"), 0)
        n = 2 if a.get("duplo") else 1      # no duplo clique o primeiro já chegou sozinho; este é o segundo
        await c.cmd("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
        await c.cmd("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": n})
        await c.cmd("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": n})
    elif tipo == "rolar":
        await c.cmd("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": numero(a.get("x"), 0), "y": numero(a.get("y"), 0),
                                                 "deltaX": 0, "deltaY": numero(a.get("dy"), -3000, 3000)})
    elif tipo == "texto":
        txt = str(a.get("texto") or "")[:5000]
        if txt:
            await c.cmd("Input.insertText", {"text": txt})
    elif tipo == "tecla":
        tecla, mods = str(a.get("tecla") or ""), (2 if a.get("ctrl") else 0) | (8 if a.get("shift") else 0)
        if tecla in TECLAS:
            vk, txt = TECLAS[tecla]
            ev = {"key": tecla, "code": tecla, "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk, "modifiers": mods}
            await c.cmd("Input.dispatchKeyEvent", dict(ev, type="keyDown", **({"text": txt} if txt and not mods else {})))
            await c.cmd("Input.dispatchKeyEvent", dict(ev, type="keyUp"))
        elif a.get("ctrl") and len(tecla) == 1 and tecla.isalpha():
            vk = ord(tecla.upper())
            ev = {"key": tecla.lower(), "code": "Key" + tecla.upper(), "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk, "modifiers": mods}
            extra = {"commands": [ATALHOS[tecla.lower()]]} if tecla.lower() in ATALHOS else {}
            await c.cmd("Input.dispatchKeyEvent", dict(ev, type="keyDown", **extra))
            await c.cmd("Input.dispatchKeyEvent", dict(ev, type="keyUp"))
        else:
            raise Erro(400, "tecla desconhecida")
    else:
        raise Erro(400, "ação desconhecida")
    return web.json_response({"ok": True, "aba": alvo})


# ---------------------------------------------------------------- o pulso: uma chamada por batida da tela
async def r_pulso(request):
    """Tudo o que a tela aberta precisa a cada segundo, numa chamada só: a execução em curso e a foto do navegador."""
    app, p, q = request.app, perfil(request), request.query
    saida = {}
    run = EXEC.get(q.get("run") or ATUAL.get(p) or "")
    if run and run["perfil"] == p:
        saida["run"] = {"id": run["id"], "status": run["status"], "v": run["v"], "sessao": run["sessao"], "erro": run["erro"],
                        "saida": run["saida"], "pedido": run["pedido"], "inicio": run["inicio"], "vivo": run["status"] in VIVOS}
        if str(run["v"]) != q.get("v"):
            saida["run"]["linha"] = run["linha"]
    if q.get("tela") == "1" and PERFIS[p].get("cdp_porta"):
        try:
            saida["nav"] = await retrato(app, p, q.get("aba") or None, q.get("hash") or "")
        except Erro as e:
            saida["nav"] = {"ligado": True, "erro": e.msg}
        except Exception as e:  # noqa: BLE001
            log.warning("retrato de %s falhou: %r", p, e)
            saida["nav"] = {"ligado": True, "erro": "não consegui ler a tela agora"}
    else:
        ligado, mem = await chrome_ligado(p)
        saida["nav"] = {"ligado": ligado, "mem": mem}
    return web.json_response(saida)


async def faxina(app):
    """Fecha ligação parada com o Chrome (para ele poder desligar sozinho) e esquece execução velha."""
    while True:
        await asyncio.sleep(20)
        agora = time.time()
        for nav in NAV.values():
            for aba in [a for a, c in nav["cdp"].items() if agora - c.usado > 45 or not c.aberta]:
                await nav["cdp"].pop(aba).fechar()
        for rid in [r for r, x in EXEC.items() if x.get("fim") and agora - x["fim"] > 7200]:
            EXEC.pop(rid, None)


async def ao_subir(app):
    app["http"] = aiohttp.ClientSession()
    app["faxina"] = asyncio.create_task(faxina(app))


async def ao_descer(app):
    app["faxina"].cancel()
    await app["http"].close()


def montar():
    app = web.Application(middlewares=[porteiro], client_max_size=1_000_000)
    app.on_startup.append(ao_subir)
    app.on_cleanup.append(ao_descer)
    r = app.router
    r.add_get("/agentes", r_agentes)
    r.add_post("/agentes/{p}/servico", r_servico)
    r.add_get("/agentes/{p}/pulso", r_pulso)
    r.add_get("/agentes/{p}/sessoes", r_sessoes)
    r.add_get("/agentes/{p}/sessoes/{sid}/mensagens", r_mensagens)
    r.add_post("/agentes/{p}/enviar", r_enviar)
    r.add_post("/agentes/{p}/execucao/{rid}/parar", r_parar)
    r.add_post("/agentes/{p}/execucao/{rid}/aprovar", r_aprovar)
    r.add_get("/agentes/{p}/tarefas", r_tarefas)
    r.add_post("/agentes/{p}/tarefas", r_tarefa_nova)
    r.add_post("/agentes/{p}/tarefas/{jid}/{acao}", r_tarefa_acao)
    r.add_get("/agentes/{p}/skills", r_skills)
    r.add_get("/agentes/{p}/memoria", r_memoria)
    r.add_post("/agentes/{p}/memoria", r_memoria_salvar)
    r.add_get("/agentes/{p}/logs", r_logs)
    r.add_post("/agentes/{p}/navegador/ligar", r_nav_ligar)
    r.add_post("/agentes/{p}/navegador/desligar", r_nav_desligar)
    r.add_post("/agentes/{p}/navegador/acao", r_nav_acao)
    return app


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(TOKEN) < 32:
        raise SystemExit("PAINEL_TOKEN ausente ou curto: a ponte não sobe sem senha")
    web.run_app(montar(), host=os.environ.get("PAINEL_HOST", "127.0.0.1"), port=int(os.environ.get("PAINEL_PORTA", "8650")),
                access_log=None)
