#!/usr/bin/env python3
"""Painel do Agente Claude em agentes.imobeasy.online (Pedro, 20/10/2026: "só dá pra entrar nessa tela quem vier do
site principal").

    navegador ─ senha do /admin (nay-site-admin-auth) ─► Traefik da VPS1 ─ Tailscale + X-Agentes-Token ─► aqui (VPS2)

Escuta só no endereço do Tailscale e recusa quem chega sem o segredo que o Traefik põe no pedido. Gravar ou disparar
exige também o cabeçalho X-Agente: 1, que só a própria tela manda (formulário de outro site não consegue).

Roda como root (Pedro, 20/10: as regras "alterar" põem o Claude a mexer no servidor como root). O disparo pela tela vai
para segundo plano, porque uma alteração pode levar até 30 minutos; a tela acompanha pela lista "rodando" do /api/estado.
"""
import hmac, json, os, re, sys, threading, time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import agente  # noqa: E402
import conta  # noqa: E402
import projetos  # noqa: E402
import fila_nay  # noqa: E402
import rotinas  # noqa: E402

TOKEN = os.environ.get("AGENTES_TOKEN", "")
ENDERECO = os.environ.get("PAINEL_ENDERECO", "100.113.222.11")
PORTA = int(os.environ.get("PAINEL_PORTA", "8660"))
with open(os.path.join(BASE, "painel.html"), "rb") as f:
    HTML = f.read()
TRAVA_REGRAS = threading.Lock()
RODANDO = {}  # chave -> {"regras", "desde"}
CAMPOS = {"mensagem": str, "modelo": str, "sistema": str, "esforco": str, "timeout_s": int, "ativa": bool,
          "servidor": str, "modo": str, "horario": str, "dias": str}
BRASILIA = timezone(timedelta(hours=-3))
AGENDA_FEITA = os.path.join(BASE, "agenda_feita.json")


def agendador():
    """O horário marcado (Pedro, 20/10: "só o Claude", sem o Hermes no meio). A cada 20 s olha a hora de Brasília e
    dispara as regras e os projetos marcados para este minuto. O que já saiu fica em agenda_feita.json, para um
    reinício do painel no mesmo minuto não mandar de novo."""
    while True:
        try:
            agora = datetime.now(BRASILIA)
            minuto, dia = agora.strftime("%H:%M"), agora.weekday()
            chave_min = agora.strftime("%Y-%m-%d %H:%M")
            try:
                with open(AGENDA_FEITA, encoding="utf-8") as f:
                    feita = json.load(f)
            except (FileNotFoundError, ValueError):
                feita = {}
            novas = {}
            for nome, r in agente.regras().items():
                if (r.get("ativa", True) and r.get("horario") == minuto
                        and dia in projetos.DIAS_AGENDA.get(r.get("dias") or "todos", ())
                        and feita.get("regra:" + nome) != chave_min):
                    novas["regra:" + nome] = chave_min
                    threading.Thread(target=agente.executar, args=([nome], "agenda"), daemon=True).start()
            madrugada = projetos.madrugada(agora)
            for p in projetos.listar():
                ag = p.get("agenda") or {}
                # 21/10: o horário marcado que caiu de madrugada (0h-6h de Brasília) ficou adiado: sai às 6h
                if not madrugada and feita.get("adiada:" + p["id"]) and ag.get("mensagem"):
                    try:
                        projetos.enviar(projetos.conversa_atual(p["id"]), ag["mensagem"], origem="agenda")
                        novas["adiada:" + p["id"]] = ""
                    except ValueError:  # ainda respondendo: tenta na próxima olhada
                        pass
                if (ag.get("horario") == minuto and dia in projetos.DIAS_AGENDA.get(ag.get("dias"), ())
                        and feita.get("projeto:" + p["id"]) != chave_min):
                    novas["projeto:" + p["id"]] = chave_min
                    if madrugada:
                        novas["adiada:" + p["id"]] = chave_min
                        continue
                    try:
                        projetos.enviar(projetos.conversa_atual(p["id"]), ag["mensagem"], origem="agenda")
                    except ValueError:  # a conversa ainda está respondendo: a agenda deste minuto fica para amanhã
                        pass
            if novas:
                feita.update(novas)
                tmp = AGENDA_FEITA + ".tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(feita, f)
                os.replace(tmp, AGENDA_FEITA)
        except Exception as e:  # noqa: BLE001 - o agendador não pode morrer por um erro de uma regra
            print("agenda:", type(e).__name__, e, flush=True)
        time.sleep(20)


def estado(dias):
    con = agente.banco()
    con.row_factory = lambda c, r: {d[0]: v for d, v in zip(c.description, r)}
    metricas = con.execute("""
        SELECT regra, COUNT(*) vezes, SUM(ok) ok, ROUND(AVG(ms_total)) ms_medio, MAX(ms_total) ms_max,
               ROUND(AVG(ms_api)) ms_api_medio, SUM(tokens_entrada) tokens_entrada, SUM(tokens_saida) tokens_saida,
               SUM(cache_lido) cache_lido, ROUND(SUM(custo_usd), 4) custo_usd, datetime(MAX(inicio), '-3 hours') ultima
        FROM execucoes WHERE inicio >= datetime('now', ?) GROUP BY regra ORDER BY regra""", (f"-{dias} days",)).fetchall()
    ultimas = con.execute("""
        SELECT id, datetime(inicio, '-3 hours') inicio, regra, modelo, servidor, modo, origem, ok, ms_total, ms_api,
               tokens_entrada, tokens_saida, custo_usd, resposta, erro
        FROM execucoes ORDER BY id DESC LIMIT 40""").fetchall()
    con.close()
    return {"regras": agente.regras(), "padrao": agente.PADRAO, "limite_s": agente.LIMITE_S,
            "metricas": metricas, "ultimas": ultimas, "rodando": list(RODANDO.values())}


def validar(regras):
    if not isinstance(regras, dict):
        raise ValueError("regras tem de ser um objeto nome → regra")
    limpas = {}
    for nome, r in regras.items():
        nome = str(nome).strip()
        if not nome or len(nome) > 60 or not isinstance(r, dict):
            raise ValueError(f"regra inválida: {nome!r}")
        if not str(r.get("mensagem") or "").strip():
            raise ValueError(f"a regra {nome!r} está sem mensagem")
        limpa = {}
        for k, tipo in CAMPOS.items():
            v = r.get(k)
            if v in (None, ""):
                continue
            if not isinstance(v, tipo) or (tipo is int and isinstance(v, bool)):
                raise ValueError(f"{nome}: o campo {k} tem de ser {tipo.__name__}")
            limpa[k] = v
        if limpa.get("servidor", "vps2") not in agente.SERVIDORES:
            raise ValueError(f"{nome}: servidor tem de ser {' ou '.join(agente.SERVIDORES)}")
        if limpa.get("modo", "responder") not in agente.MODOS:
            raise ValueError(f"{nome}: modo tem de ser {' ou '.join(agente.MODOS)}")
        if limpa.get("horario") and not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", limpa["horario"]):
            raise ValueError(f"{nome}: horário no formato HH:MM")
        if limpa.get("dias", "todos") not in projetos.DIAS_AGENDA:
            raise ValueError(f"{nome}: dias tem de ser todos, seg-sex ou seg-sab")
        limpas[nome] = limpa
    return limpas


class Pedido(BaseHTTPRequestHandler):
    server_version = "agente-claude"

    def log_message(self, *a):
        pass

    def responder(self, codigo, corpo, tipo="application/json; charset=utf-8"):
        if not isinstance(corpo, bytes):
            corpo = json.dumps(corpo, ensure_ascii=False).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(corpo)

    def liberado(self, escrita=False):
        veio = self.headers.get("X-Agentes-Token", "")
        if not (TOKEN and hmac.compare_digest(veio, TOKEN)):
            self.responder(403, {"erro": "entre pelo site principal"})
            return False
        if escrita and self.headers.get("X-Agente") != "1":
            self.responder(403, {"erro": "só a tela do painel grava"})
            return False
        return True

    def corpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n <= 1_000_000 else {}

    def tratar(self, metodo):
        """Chama a rota; KeyError vira 404 e ValueError vira 400, com o texto do erro para a tela."""
        if not self.liberado(escrita=metodo != "GET"):
            return
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        for m, padrao, funcao in ROTAS:
            achou = m == metodo and re.fullmatch(padrao, url.path)
            if achou:
                try:
                    codigo, corpo = funcao(self, q, *achou.groups())
                except KeyError as e:
                    codigo, corpo = 404, {"erro": e.args[0] if e.args else "não existe"}
                except ValueError as e:
                    codigo, corpo = 400, {"erro": str(e)}
                if isinstance(corpo, bytes):
                    return self.responder(codigo, corpo, "text/html; charset=utf-8")
                return self.responder(codigo, corpo)
        self.responder(404, {"erro": "não existe"})

    def do_GET(self):
        self.tratar("GET")

    def do_PUT(self):
        self.tratar("PUT")

    def do_POST(self):
        self.tratar("POST")

    def do_DELETE(self):
        self.tratar("DELETE")


def gravar_regras(pedido, q):
    regras = validar(pedido.corpo())
    with TRAVA_REGRAS:
        tmp = agente.REGRAS + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(regras, f, ensure_ascii=False, indent=2)
        os.replace(tmp, agente.REGRAS)
    return 200, {"regras": regras}


def disparar(pedido, q):
    nomes = [str(n) for n in pedido.corpo().get("regras") or []]
    faltam = [n for n in nomes if n not in agente.regras()]
    if not nomes or faltam:
        raise ValueError("regra não existe: " + ", ".join(faltam))
    chave = object()
    RODANDO[id(chave)] = {"regras": nomes, "desde": time.time()}

    def rodar():
        try:
            agente.executar(nomes, origem="painel")
        finally:
            RODANDO.pop(id(chave), None)
    threading.Thread(target=rodar, daemon=True).start()
    return 202, {"iniciado": nomes}


def anexar(pedido, q, pid):
    n = int(pedido.headers.get("Content-Length") or 0)
    if n > projetos.MAX_ANEXO:
        raise ValueError("arquivo maior que 50 MB")
    return 200, projetos.anexar(pid, q.get("nome"), pedido.rfile.read(n))


def novo_projeto(pedido, q):
    d = pedido.corpo()
    return 200, projetos.salvar(str(d.get("id") or "").strip(), d, novo=True)


def nova_conversa(pedido, q, pid):
    return 200, {"id": projetos.nova_conversa(pid)}


def enviar(pedido, q, cid):
    projetos.enviar(int(cid), pedido.corpo().get("texto"))
    return 202, {"ok": True}


def fila_agora(pedido, q):
    """Uma volta da fila da revisão da Nay já (enfileira e manda, se tiver), em segundo plano."""
    threading.Thread(target=lambda: print("fila_nay:", fila_nay.volta(), flush=True), daemon=True).start()
    return 202, {"ok": True}


def importar(pedido, q, pid):
    dias = int(pedido.corpo().get("dias") or 7)
    projetos.importar(pid, max(1, min(dias, 400)))
    return 202, {"ok": True}


ROTAS = [
    ("GET", r"/", lambda p, q: (200, HTML)),
    ("GET", r"/api/estado", lambda p, q: (200, estado(int(q["dias"]) if q.get("dias", "").isdigit() else 7))),
    ("PUT", r"/api/regras", gravar_regras),
    # 23/10: assinatura ou API, com o contador de gasto da API e o limite (conta.py)
    ("GET", r"/api/conta", lambda p, q: (200, conta.estado())),
    ("PUT", r"/api/conta", lambda p, q: (200, conta.salvar(p.corpo()))),
    ("POST", r"/api/disparar", disparar),
    ("GET", r"/api/projetos", lambda p, q: (200, {"projetos": projetos.listar()})),
    ("POST", r"/api/projetos", novo_projeto),
    ("GET", r"/api/projetos/([\w-]+)", lambda p, q, pid: (200, projetos.detalhe(pid))),
    ("PUT", r"/api/projetos/([\w-]+)", lambda p, q, pid: (200, projetos.salvar(pid, p.corpo()))),
    ("POST", r"/api/projetos/([\w-]+)/conversas", nova_conversa),
    ("POST", r"/api/projetos/([\w-]+)/anexos", anexar),
    ("DELETE", r"/api/projetos/([\w-]+)/anexos", lambda p, q, pid: (200, {"anexos": projetos.apagar_anexo(pid, q.get("nome"))})),
    ("POST", r"/api/projetos/([\w-]+)/importar", importar),
    ("GET", r"/api/conversas/(\d+)", lambda p, q, cid: (200, projetos.mensagens(int(cid)))),
    ("POST", r"/api/conversas/(\d+)/mensagens", enviar),
    # a fila da revisão da Nay (fila_nay.py): toda conversa com imóvel enviado, de 20 em 20 min; às 22h o relatório
    ("GET", r"/api/fila_nay", lambda p, q: (200, fila_nay.estado())),
    ("POST", r"/api/fila_nay/agora", fila_agora),
    # as rotinas dos outros agentes (rotinas.py): visitas novas do CRM, métricas às 23h, estratégia às 7h
    ("GET", r"/api/rotinas", lambda p, q: (200, rotinas.estado())),
]


if __name__ == "__main__":
    if not TOKEN:
        sys.exit("falta AGENTES_TOKEN")
    projetos.sem_resposta()
    threading.Thread(target=agendador, daemon=True).start()
    threading.Thread(target=fila_nay.laco, daemon=True).start()
    threading.Thread(target=rotinas.laco, daemon=True).start()
    ThreadingHTTPServer((ENDERECO, PORTA), Pedido).serve_forever()
