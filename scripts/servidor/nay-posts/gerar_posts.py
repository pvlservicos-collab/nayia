#!/root/nay-posts/.venv/bin/python
"""GERA OS POSTS DE UM IMÓVEL NA VPS, no automático (Pedro, 18/10/2026: "deixei um gerador de post lá ... sobe na VPS
para quando eu pedir você gerar lá no automático").

O gerador é o HTML do Pedro (gerador-posts-imob-easy.html, cópia em /root/nay-posts/gerador.html e no admin do site em
/admin/gerador-posts.html). Ele desenha tudo no navegador (canvas) e expõe a API window.GeradorImob. Aqui um Chromium sem
tela (Playwright) abre o HTML, monta o imóvel a partir do cadastro (site_imovel_publico), põe as fotos e exporta:
  post único nos formatos (feed 1080x1350, quadrado, story, paisagem), o carrossel (capa, fotos, diferenciais, final),
  a legenda pronta e, se pedido, o prompt do vídeo.
Sai em /docker/nay-site-web/public/fotos-captacao/posts/<codigo>/<AAAAMMDD-HHMM>/ (público: imobeasy.online/fotos-captacao/posts/...),
com um ZIP de tudo. Imóvel de parceiro não sai (parceria nunca sai).

Uso (na VPS):  /root/nay-posts/.venv/bin/python /root/nay-posts/gerar_posts.py 5739 [opções]
Daqui:         ./scripts/nay posts 5739 [opções]
Opções: --modelo galeria|classico|vitrine|mosaico   --carrossel faixaBaixo|faixaLado|etiqueta|grade4|nenhum (a capa é o post Galeria e a última lâmina é a CTA, 23/10)
        --formatos feed,quadrado,story,paisagem    --fotos 8   --video   --contato "92 9471-7316"
        --chamada "à venda!"  --destaque "Mobiliado"  --slogan "..."  --fita "Pode ser financiado!"  --json (só imprime o estado)
"""
import argparse
import base64
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
GERADOR = os.path.join(AQUI, "gerador.html")
SAIDA_RAIZ = "/docker/nay-site-web/public/fotos-captacao/posts"
URL_RAIZ = "https://imobeasy.online/fotos-captacao/posts"
CONTATO_PADRAO = "92 9471-7316"
MAX_LADO = 1800


def banco(sql):
    r = subprocess.run(["docker", "exec", "nay-postgres", "psql", "-U", "nay", "-d", "naydb", "-tA", "-c", sql],
                       capture_output=True, text=True, timeout=60)
    if r.returncode:
        raise SystemExit("banco: " + r.stderr.strip())
    return r.stdout.strip()


def ler_imovel(codigo):
    bruto = banco("SELECT coalesce(site_imovel_publico(%d)::text, '')" % codigo)
    if not bruto:
        raise SystemExit("o imóvel %d não está no ar (não é Disponível, está fora do site ou é de parceiro)" % codigo)
    i = json.loads(bruto)
    if i.get("parceiro"):
        raise SystemExit("o imóvel %d é de parceiro: não sai em post (parceria nunca sai)" % codigo)
    extra = banco("SELECT coalesce(extras->>'aceita financiamento', '') || '|' || coalesce(observacao, '') FROM imoveis WHERE codigo = %d" % codigo)
    fin, obs = (extra.split("|", 1) + [""])[:2]
    i["_financia"] = fin.strip().lower().startswith("s")
    i["_obs"] = obs.strip()
    return i


def plural(n, um, varios):
    return "%d %s" % (n, um if n == 1 else varios)


def montar_estado(i, a):
    c, l, v = i.get("carac") or {}, i.get("local") or {}, i.get("valores") or {}
    aluguel, venda = v.get("aluguel"), v.get("venda")
    negocio = "venda" if (venda and not aluguel) else "aluguel" if aluguel else "venda"
    valor = venda if negocio == "venda" else aluguel
    mob = (c.get("mobilia_nivel") or c.get("mobilia") or "").lower()
    tipo = c.get("tipo") or "Imóvel"
    destaque = a.destaque if a.destaque is not None else ("Mobiliado" if mob == "mobiliado" else "Semimobiliado" if mob.startswith("semi") else
                                                           (plural(c["quartos"], "quarto", "quartos") if c.get("quartos") else ""))
    chamada = a.chamada or ("para alugar!" if negocio == "aluguel" else "à venda!")
    caracts = []
    if c.get("areautil"):
        caracts.append({"icone": "metragem", "destaque": "%d m²" % round(float(c["areautil"])), "complemento": "de área útil"})
    if c.get("quartos"):
        caracts.append({"icone": "cama", "destaque": plural(c["quartos"], "quarto", "quartos"),
                        "complemento": ("sendo " + plural(c["suites"], "suíte", "suítes")) if c.get("suites") else ""})
    if c.get("banheiros"):
        caracts.append({"icone": "banheiro", "destaque": plural(c["banheiros"], "banheiro", "banheiros"), "complemento": ""})
    if c.get("vagas"):
        caracts.append({"icone": "carro", "destaque": plural(c["vagas"], "vaga", "vagas"), "complemento": "de garagem"})
    if mob == "mobiliado":
        caracts.append({"icone": "sofa", "destaque": "Mobiliado", "complemento": "entra e já mora"})
    elif mob.startswith("semi"):
        caracts.append({"icone": "sofa", "destaque": "Semimobiliado", "complemento": ""})
    if c.get("andares") or c.get("elevadores"):
        caracts.append({"icone": "predio", "destaque": "Com elevador" if c.get("elevadores") else "%s andares" % c.get("andares"), "complemento": ""})
    tags = [t for t in (i.get("tagscondo") or []) if isinstance(t, str)]
    if any("piscina" in t.lower() for t in tags):
        caracts.append({"icone": "piscina", "destaque": "Piscina", "complemento": "no condomínio"})
    if any(re.search(r"portaria|segurança|24", t.lower()) for t in tags):
        caracts.append({"icone": "escudo", "destaque": "Portaria 24h", "complemento": ""})
    if negocio == "aluguel" and i.get("incluso"):
        caracts.append({"icone": "contrato", "destaque": "Incluso no aluguel", "complemento": i["incluso"]})
    caracts = caracts[:6]
    if a.fita is not None:
        fita = a.fita
    elif negocio == "venda":
        fita = "Pode ser financiado!" if i.get("_financia") else "Agende sua visita!"
    else:
        fita = "Condomínio incluso!" if "condom" in (i.get("incluso") or "").lower() else "Agende sua visita!"
    slogan = a.slogan if a.slogan is not None else (i.get("_obs")[:90] if 0 < len(i.get("_obs") or "") <= 90 else
                                                     ("Pronto para você morar, no bairro que você quer!" if negocio == "aluguel"
                                                      else "Conforto, praticidade e o espaço que sua família merece!"))
    return {
        "tipo": tipo, "destaque": destaque, "chamada": chamada,
        "localRotulo": "Condomínio" if l.get("condominio") else "Bairro", "localNome": l.get("condominio") or l.get("bairro") or "",
        "bairro": l.get("bairro") or "", "cidade": l.get("cidade") or "Manaus",
        "slogan": slogan, "caracteristicas": caracts,
        "valorRotulo": "Aluguel" if negocio == "aluguel" else "Valor", "valor": str(int(round(float(valor)))) if valor else "",
        "mostrarCentavos": False, "sufixoValor": "/mês" if negocio == "aluguel" else "",
        "mostrarSelo": True, "seloTitulo": "Ótima oportunidade", "seloTexto": "para morar ou investir!" if negocio == "venda" else "para morar bem!",
        "seloFita": fita, "contatoRotulo": "Chame no WhatsApp", "contato": a.contato or CONTATO_PADRAO,
    }, negocio


def baixar_foto(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) ImobEasy/posts"})
    with urllib.request.urlopen(req, timeout=30) as r:
        dados = r.read()
    try:
        from PIL import Image, ImageOps
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(dados)))
        if img.mode != "RGB":
            img = img.convert("RGB")
        img.thumbnail((MAX_LADO, MAX_LADO))
        saida = io.BytesIO()
        img.save(saida, "JPEG", quality=88)
        dados, tipo = saida.getvalue(), "image/jpeg"
    except Exception:  # noqa: BLE001 -- sem Pillow ou formato estranho: vai como veio
        tipo = "image/png" if dados[:4] == b"\x89PNG" else "image/webp" if dados[8:12] == b"WEBP" else "image/jpeg"
    return "data:%s;base64,%s" % (tipo, base64.b64encode(dados).decode())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("codigo", type=int)
    p.add_argument("--modelo", default="galeria")
    p.add_argument("--carrossel", default="faixaBaixo")
    p.add_argument("--formatos", default="feed,quadrado,story,paisagem")
    p.add_argument("--fotos", type=int, default=8)
    p.add_argument("--video", action="store_true")
    p.add_argument("--contato")
    p.add_argument("--chamada")
    p.add_argument("--destaque")
    p.add_argument("--slogan")
    p.add_argument("--fita")
    p.add_argument("--json", action="store_true", help="só imprime o estado montado, sem desenhar")
    a = p.parse_args()

    i = ler_imovel(a.codigo)
    imovel, negocio = montar_estado(i, a)
    urls = [f for f in (i.get("fotos") or []) if isinstance(f, str)][: max(1, min(a.fotos, 12))]
    if a.json:
        print(json.dumps({"imovel": imovel, "fotos": urls, "negocio": negocio}, ensure_ascii=False, indent=1))
        return
    if not urls:
        raise SystemExit("o imóvel %d não tem foto: sem post" % a.codigo)
    fotos = []
    for u in urls:
        try:
            fotos.append({"src": baixar_foto(u), "etiqueta": ""})
        except Exception as e:  # noqa: BLE001
            print("foto pulada: %s (%s)" % (u[:70], e), file=sys.stderr)
    if not fotos:
        raise SystemExit("nenhuma foto baixou")

    from playwright.sync_api import sync_playwright
    carimbo = time.strftime("%Y%m%d-%H%M")
    pasta = os.path.join(SAIDA_RAIZ, str(a.codigo), carimbo)
    os.makedirs(pasta, exist_ok=True)
    arquivos = []

    def salvar(nome, data_url):
        cab, b64 = data_url.split(",", 1)
        with open(os.path.join(pasta, nome), "wb") as arq:
            arq.write(base64.b64decode(b64))
        arquivos.append(nome)

    with sync_playwright() as pw:
        nav = pw.chromium.launch()
        ctx = nav.new_context(viewport={"width": 1400, "height": 1000})
        ctx.add_init_script("try { localStorage.clear(); } catch (e) {}")      # sem o rascunho de antes
        pg = ctx.new_page()
        erros = []
        pg.on("pageerror", lambda e: erros.append(str(e)))
        pg.goto("file://" + GERADOR, wait_until="load")
        pg.wait_for_function("window.GeradorImob && window.GeradorImob.versao", timeout=30000)
        pg.evaluate("() => GeradorImob.novoImovel()")
        pg.evaluate("(im) => GeradorImob.definirImovel(im)", imovel)
        pg.evaluate("(fs) => GeradorImob.adicionarFotos(fs)", fotos)
        pg.evaluate("(m) => GeradorImob.definirModelo('post', m)", a.modelo)
        formatos = [f.strip() for f in a.formatos.split(",") if f.strip()]
        for f in formatos:
            salvar("post-%s-%s.png" % (a.modelo, f), pg.evaluate("([f, m]) => GeradorImob.exportarPost(f, m)", [f, a.modelo]))
        if a.carrossel and a.carrossel != "nenhum":
            laminas = pg.evaluate("(m) => GeradorImob.exportarCarrossel(m)", a.carrossel)
            for n, d in enumerate(laminas, 1):
                salvar("carrossel-%s-%02d.png" % (a.carrossel, n), d)
        legenda = pg.evaluate("() => GeradorImob.legenda()")
        with open(os.path.join(pasta, "legenda.txt"), "w", encoding="utf-8") as arq:
            arq.write(legenda)
        arquivos.append("legenda.txt")
        if a.video:
            pg.evaluate("() => GeradorImob.preencherVideo()")
            with open(os.path.join(pasta, "prompt-video.txt"), "w", encoding="utf-8") as arq:
                arq.write(pg.evaluate("() => GeradorImob.promptVideo()"))
            arquivos.append("prompt-video.txt")
        estado = pg.evaluate("() => { const e = GeradorImob.obterEstado(); e.fotos = e.fotos.map(f => ({...f, src: '(foto omitida)'})); return e; }")
        nav.close()

    with open(os.path.join(pasta, "estado.json"), "w", encoding="utf-8") as arq:
        json.dump(estado, arq, ensure_ascii=False, indent=1)
    zip_nome = "posts-%d-%s.zip" % (a.codigo, carimbo)
    with zipfile.ZipFile(os.path.join(pasta, zip_nome), "w", zipfile.ZIP_DEFLATED) as z:
        for n in arquivos:
            z.write(os.path.join(pasta, n), n)
    base = "%s/%d/%s" % (URL_RAIZ, a.codigo, carimbo)
    print(json.dumps({"ok": True, "codigo": a.codigo, "negocio": negocio, "modelo": a.modelo, "carrossel": a.carrossel, "fotos": len(fotos),
                      "pasta": pasta, "zip": base + "/" + zip_nome, "arquivos": [base + "/" + n for n in arquivos],
                      "legenda": legenda, "erros_da_pagina": erros}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
