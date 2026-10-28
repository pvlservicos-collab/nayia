"""A ferramenta do Agente de Aprendizado (perfil `aprendizado` do Hermes): salvar a transcrição do tactiq no PC.

Pedro, 28/10/2026: "ele vai abrir esse site aqui https://tactiq.io/tools/youtube-transcript colar o link de um vídeo
ali no navegador e aguardar gerar a transcrição embaixo e depois clicar em copiar e salvar essa transcrição ... já
salvasse em um documento de texto na raiz desse projeto, pode ser até uma pasta só com essas transcrições".

O agente abre o tactiq, cola o link e clica em "Get Video Transcript" pelo navegador. Esta ferramenta faz o resto:
espera a transcrição aparecer, clica em Copy (o texto que o Copy entrega é segurado na página, sem passar pela área de
transferência do PC) e salva um .txt na pasta transcricoes/ do nayia. Quem grava o arquivo é o próprio Chrome do
agente, que roda no computador do Pedro (o mesmo do Agente OLX, pelo túnel 127.0.0.1:9303): por isso o arquivo cai
lá, e não na VPS. O texto inteiro nunca volta ao modelo: a resposta é só o nome do arquivo e o tamanho.

Medido em 28/10: o tactiq barra Chrome sem janela (reCAPTCHA do Firebase devolve 403 e a lista fica vazia); o Chrome
normal do PC passa. Um vídeo de 1h29 deu 858 trechos e 104 mil caracteres.

Roda com o Python do Hermes (tem mcp e websockets), lançado pelo Hermes (mcp_servers.transcricao do config.yaml).
Teste à mão: python mcp_transcricao.py <link do vídeo>
"""
import asyncio
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request

import websockets

CDP = os.environ.get("CDP_URL", "http://127.0.0.1:9303")
PASTA = os.environ.get("TRANSCRICOES_PASTA", r"C:\Users\pedro\Desktop\TEL SOBREIRA\Nay IA\transcricoes")
ESPERA_TRANSCRICAO = 180   # s: vídeo longo demora a aparecer
ESPERA_ARQUIVO = 60


def id_do_video(link):
    m = re.search(r"(?:[?&]v=|youtu\.be/|/shorts/|/embed/|/live/|/watch/)([A-Za-z0-9_-]{11})", link or "")
    return m.group(1) if m else None


def titulo_do_video(vid):
    """O tactiq mostra "No title found"; o título vem do oEmbed do YouTube. Sem ele, o arquivo leva só o id."""
    url = "https://www.youtube.com/oembed?format=json&url=" + urllib.parse.quote("https://www.youtube.com/watch?v=" + vid)
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            return json.load(r).get("title") or ""
    except Exception:  # noqa: BLE001
        return ""


def nome_do_arquivo(vid, titulo):
    limpo = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", titulo)
    limpo = re.sub(r"\s+", " ", limpo).strip(" .")[:120]
    dia = datetime.date.today().isoformat()
    return f"{dia} {limpo} [{vid}].txt" if limpo else f"{dia} [{vid}].txt"


def chrome(caminho):
    with urllib.request.urlopen(CDP + caminho, timeout=8) as r:
        return json.load(r)


class Cdp:
    def __init__(self, ws):
        self.ws, self.n, self.eventos = ws, 0, []

    async def __call__(self, metodo, **params):
        self.n += 1
        meu = self.n
        await self.ws.send(json.dumps({"id": meu, "method": metodo, "params": params}))
        while True:
            m = json.loads(await self.ws.recv())
            if m.get("id") == meu:
                if "error" in m:
                    raise RuntimeError(f"{metodo}: {m['error'].get('message')}")
                return m.get("result", {})
            if "method" in m:
                self.eventos.append(m)

    async def js(self, expressao):
        r = await self("Runtime.evaluate", expression=expressao, awaitPromise=True, returnByValue=True)
        if r.get("exceptionDetails"):
            raise RuntimeError(r["exceptionDetails"].get("text", "erro na página"))
        return r.get("result", {}).get("value")


# Espera a lista da transcrição, clica em Copy e segura o texto que o Copy manda à área de transferência
# (navigator.clipboard.writeText) em window.__tqTexto. A área de transferência do PC fica como estava.
COPIAR = """(async () => {
  const fim = Date.now() + %d * 1000
  while (Date.now() < fim && !(document.querySelectorAll('ul li code').length && document.getElementById('copy')))
    await new Promise(r => setTimeout(r, 1000))
  const botao = document.getElementById('copy')
  if (!botao || !document.querySelectorAll('ul li code').length) return {erro: 'a transcrição não apareceu'}
  // a lista fica embaixo da página: rola até ela, para o Pedro ver na tela do agente
  document.querySelector('ul li code').closest('ul').scrollIntoView({block: 'start'})
  const original = navigator.clipboard && navigator.clipboard.writeText
  let texto = null
  navigator.clipboard.writeText = t => { texto = String(t); return Promise.resolve() }
  try {
    botao.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}))
    for (let i = 0; i < 50 && texto === null; i++) await new Promise(r => setTimeout(r, 100))
  } finally { navigator.clipboard.writeText = original }
  if (!texto) return {erro: 'o botão Copy não entregou o texto'}
  window.__tqTexto = texto
  const tempos = texto.match(/^\\d\\d:\\d\\d:\\d\\d/gm) || []
  return {tamanho: texto.length, trechos: tempos.length, ultimo: tempos[tempos.length - 1] || ''}
})()"""

BAIXAR = """(() => {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([window.__tqTexto], {type: 'text/plain;charset=utf-8'}))
  a.download = %s
  document.body.appendChild(a); a.click(); a.remove()
  return 'ok'
})()"""


async def salvar(link):
    vid = id_do_video(link)
    if not vid:
        return "Não reconheci o link do YouTube: mande um link como https://www.youtube.com/watch?v=XXXXXXXXXXX."
    try:
        abas = chrome("/json/list")
        versao = chrome("/json/version")
    except Exception:  # noqa: BLE001
        return "O navegador do agente está desligado: ligue o navegador-olx.bat no computador do Pedro."
    paginas = [a for a in abas if a.get("type") == "page"]
    aba = next((a for a in paginas if "tactiq.io/tools/run/youtube_transcript" in a.get("url", "")
                and vid in urllib.parse.unquote(a.get("url", ""))), None)
    # 28/10, primeiro pedido de verdade: o link ficou certo no campo, mas o clique do agente em "Get Video Transcript"
    # não saiu da página. Sem a página da transcrição aberta, a ferramenta mesma abre a aba do tactiq no endereço que o
    # botão abre (o formulário é um GET para /tools/run/youtube_transcript?yt=<link>).
    abrir = None
    if not aba:
        aba = next((a for a in paginas if "tactiq.io" in a.get("url", "")), None)
        if not aba:
            return ("Não achei a aba do tactiq. Abra https://tactiq.io/tools/youtube-transcript e chame esta "
                    "ferramenta de novo.")
        abrir = "https://tactiq.io/tools/run/youtube_transcript?yt=" + urllib.parse.quote(link, safe="")

    async with websockets.connect(aba["webSocketDebuggerUrl"], max_size=None, open_timeout=8, ping_interval=None) as wp:
        pagina = Cdp(wp)
        if abrir:
            await pagina("Page.navigate", url=abrir)
            await asyncio.sleep(4)
        r = await pagina.js(COPIAR % ESPERA_TRANSCRICAO)
        if r.get("erro"):
            return f"Não salvei: {r['erro']} (esperei {ESPERA_TRANSCRICAO} s). Vídeo sem legenda no YouTube não tem transcrição."
        nome = nome_do_arquivo(vid, titulo_do_video(vid))

        # o Chrome do agente grava o arquivo direto na pasta do PC; depois volta ao jeito de sempre
        async with websockets.connect(versao["webSocketDebuggerUrl"], max_size=None, open_timeout=8, ping_interval=None) as wb:
            navegador = Cdp(wb)
            alvos = (await navegador("Target.getTargets"))["targetInfos"]
            contexto = next((t.get("browserContextId") for t in alvos if t["targetId"] == aba["id"]), None)
            extra = {"browserContextId": contexto} if contexto else {}
            await navegador("Browser.setDownloadBehavior", behavior="allow", downloadPath=PASTA, eventsEnabled=True, **extra)
            try:
                await pagina.js(BAIXAR % json.dumps(nome))
                estado, gravado = "", nome
                fim = asyncio.get_running_loop().time() + ESPERA_ARQUIVO
                while estado not in ("completed", "canceled") and asyncio.get_running_loop().time() < fim:
                    try:
                        m = json.loads(await asyncio.wait_for(wb.recv(), timeout=2))
                    except asyncio.TimeoutError:
                        continue
                    if m.get("method") == "Browser.downloadWillBegin":
                        gravado = m["params"].get("suggestedFilename") or nome
                    if m.get("method") == "Browser.downloadProgress":
                        estado = m["params"].get("state", "")
            finally:
                await navegador("Browser.setDownloadBehavior", behavior="default", **extra)
    if estado != "completed":
        return f"O Chrome não terminou de gravar o arquivo ({estado or 'sem resposta'}). Nada foi salvo."
    tamanho = f"{r['tamanho']:,}".replace(",", ".")
    return f"Salvo no computador do Pedro: transcricoes\\{gravado} — {tamanho} caracteres, {r['trechos']} trechos, até {r['ultimo']}."


if __name__ == "__main__" and len(sys.argv) > 1:
    print(asyncio.run(salvar(sys.argv[1])))
elif __name__ == "__main__":
    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP("transcricao")

    @mcp.tool()
    async def salvar_transcricao(link_do_video: str) -> str:
        """Salva a transcrição que o tactiq gerou para este vídeo do YouTube num .txt na pasta transcricoes do
        computador do Pedro. Use DEPOIS de abrir o tactiq, colar o link e clicar em Get Video Transcript: a ferramenta
        espera a transcrição aparecer (até 3 minutos), clica em Copy e grava o arquivo. Devolve o nome do arquivo."""
        return await salvar(link_do_video)

    mcp.run()
