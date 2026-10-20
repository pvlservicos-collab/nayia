#!/usr/bin/env python3
"""Painel do Agente Claude em agentes.imobeasy.online (Pedro, 20/10/2026: "só dá pra entrar nessa tela quem vier do
site principal").

    navegador ─ senha do /admin (nay-site-admin-auth) ─► Traefik da VPS1 ─ Tailscale + X-Agentes-Token ─► aqui (VPS2)

Escuta só no endereço do Tailscale e recusa quem chega sem o segredo que o Traefik põe no pedido. Gravar ou disparar
exige também o cabeçalho X-Agente: 1, que só a própria tela manda (formulário de outro site não consegue).

Roda como root (Pedro, 20/10: as regras "alterar" põem o Claude a mexer no servidor como root). O disparo pela tela vai
para segundo plano, porque uma alteração pode levar até 30 minutos; a tela acompanha pela lista "rodando" do /api/estado.
"""
import hmac, json, os, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import agente  # noqa: E402

TOKEN = os.environ.get("AGENTES_TOKEN", "")
ENDERECO = os.environ.get("PAINEL_ENDERECO", "100.113.222.11")
PORTA = int(os.environ.get("PAINEL_PORTA", "8660"))
with open(os.path.join(BASE, "painel.html"), "rb") as f:
    HTML = f.read()
TRAVA_REGRAS = threading.Lock()
RODANDO = {}  # chave -> {"regras", "desde"}
CAMPOS = {"mensagem": str, "modelo": str, "sistema": str, "esforco": str, "timeout_s": int, "ativa": bool,
          "servidor": str, "modo": str}


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

    def do_GET(self):
        if not self.liberado():
            return
        url = urlparse(self.path)
        if url.path == "/":
            self.responder(200, HTML, "text/html; charset=utf-8")
        elif url.path == "/api/estado":
            dias = parse_qs(url.query).get("dias", ["7"])[0]
            self.responder(200, estado(int(dias) if dias.isdigit() else 7))
        else:
            self.responder(404, {"erro": "não existe"})

    def do_PUT(self):
        if not self.liberado(escrita=True):
            return
        if self.path != "/api/regras":
            return self.responder(404, {"erro": "não existe"})
        try:
            regras = validar(self.corpo())
        except ValueError as e:
            return self.responder(400, {"erro": str(e)})
        with TRAVA_REGRAS:
            tmp = agente.REGRAS + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(regras, f, ensure_ascii=False, indent=2)
            os.replace(tmp, agente.REGRAS)
        self.responder(200, {"regras": regras})

    def do_POST(self):
        if not self.liberado(escrita=True):
            return
        if self.path != "/api/disparar":
            return self.responder(404, {"erro": "não existe"})
        nomes = [str(n) for n in self.corpo().get("regras") or []]
        faltam = [n for n in nomes if n not in agente.regras()]
        if not nomes or faltam:
            return self.responder(400, {"erro": "regra não existe: " + ", ".join(faltam)})
        chave = object()
        RODANDO[id(chave)] = {"regras": nomes, "desde": time.time()}

        def rodar():
            try:
                agente.executar(nomes, origem="painel")
            finally:
                RODANDO.pop(id(chave), None)
        threading.Thread(target=rodar, daemon=True).start()
        self.responder(202, {"iniciado": nomes})


if __name__ == "__main__":
    if not TOKEN:
        sys.exit("falta AGENTES_TOKEN")
    ThreadingHTTPServer((ENDERECO, PORTA), Pedido).serve_forever()
