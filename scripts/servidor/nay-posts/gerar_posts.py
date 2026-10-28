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
    piscinas = [t.lower() for t in tags if "piscina" in t.lower()]
    if piscinas:
        # 28/10 (9058): o Weekend Club só tem "Piscina infantil" e a arte dizia "Piscina no condomínio"
        so_infantil = all("infantil" in t and "adulto" not in t for t in piscinas)
        caracts.append({"icone": "piscina", "destaque": "Piscina infantil" if so_infantil else "Piscina",
                        "complemento": "no condomínio"})
    # 28/10 (Pedro: "extremo cuidado com as informações ... tudo que tem nos ícones"): antes qualquer etiqueta com
    # "segurança" ou "24" virava "Portaria 24h". Agora só portaria/guarita 24 h diz portaria; segurança 24 h diz segurança.
    portaria = next(("Portaria 24h" for t in tags if re.search(r"portaria|guarita", t.lower()) and "24" in t), None) or         next(("Segurança 24h" for t in tags if "segurança" in t.lower() and "24" in t), None)
    if portaria:
        caracts.append({"icone": "escudo", "destaque": portaria, "complemento": ""})
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


ORDEM_DOS_COMODOS = ("sala", "quarto", "area_lazer", "banheiro")   # 500 (26/10): a ordem em que os cômodos aparecem


def categorias_do_imovel(codigo):
    """{url: (categoria|None, etiqueta)} do que a classificar_fotos.py (Gemini) já marcou para este imóvel."""
    bruto = banco("SELECT coalesce(jsonb_object_agg(url, jsonb_build_array(categoria, etiqueta)), '{}')::text "
                 "FROM imovel_fotos WHERE codigo = %d AND (categoria IS NOT NULL OR e_capa)" % codigo)
    return {u: (v[0], v[1] or "") for u, v in json.loads(bruto).items()}


def ordenar_fotos(urls, mapa):
    """Põe primeiro a capa (já é a 1ª: site_imovel_publico ordena e_capa antes) e, logo depois, os cômodos marcados
    pela Gemini (sala, quarto, área de lazer, banheiro, nessa ordem) — mesmo que a ordem original os deixasse para
    trás e o --fotos cortasse fora. O resto segue na ordem de sempre."""
    por_categoria = {}   # 1 foto por categoria (a 1ª que achar na ordem de urls)
    for u in urls:
        c, _e = mapa.get(u, (None, ""))
        if c and c not in por_categoria:
            por_categoria[c] = u
    primeiros = ([urls[0]] if urls else []) + [por_categoria[c] for c in ORDEM_DOS_COMODOS if c in por_categoria]
    vistos = set(primeiros)
    return primeiros + [u for u in urls if u not in vistos]


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
    todas = [f for f in (i.get("fotos") or []) if isinstance(f, str)]
    mapa_comodos = categorias_do_imovel(a.codigo)        # 500: o que a Gemini já marcou (capa + até 4 cômodos)
    urls = ordenar_fotos(todas, mapa_comodos)[: max(1, min(a.fotos, 12))]
    if a.json:
        print(json.dumps({"imovel": imovel, "fotos": urls, "negocio": negocio,
                          "comodos": {u: c for u, (c, _e) in mapa_comodos.items() if c}}, ensure_ascii=False, indent=1))
        return
    if not urls:
        raise SystemExit("o imóvel %d não tem foto: sem post" % a.codigo)
    fotos = []
    for n, u in enumerate(urls):
        try:
            etiqueta = mapa_comodos.get(u, (None, ""))[1] if n > 0 else ""   # a capa (1ª) nunca mostra etiqueta
            fotos.append({"src": baixar_foto(u), "etiqueta": etiqueta})
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
