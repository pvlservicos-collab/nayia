#!/root/nay-posts/.venv/bin/python
"""A GALERIA "NOSSOS IMÓVEIS" DO GERADOR DE POSTS (Pedro, 28/10/2026): "quero adicionar uma aba lá no gerador de post
ao lado de Vídeo, Nossos imóveis, e quero que seja gerada uma arte estilo Clássico, o modelo original, para cada imóvel
... primeiro testar 10 imóveis ... extremo cuidado com as informações de preço e metragem e tudo mais que tem nos ícones
... embaixo diz uma informação sobre financiamento, se nosso imóvel não tiver isso não põe ... usar a API do Gemini
para analisar as fotos e traçar qual ambiente da casa é cada foto e com isso organizar as fotos também do jeito certo".

Para cada imóvel:
  1. os dados saem do cadastro como no `nay posts` (gerar_posts.ler_imovel / montar_estado: site_imovel_publico, a
     mesma função da página pública; a fita "Pode ser financiado!" só sai em venda com "aceita financiamento" = Sim);
  2. a Gemini olha TODAS as fotos (até MAX_FOTOS, em resolução baixa: basta para reconhecer o cômodo) e diz o
     ambiente e uma legenda curta de cada uma, e qual é a melhor capa;
  3. as fotos ficam na ordem de um anúncio (capa, fachada, sala, cozinha, varanda, quartos, banheiros, ...), e a arte
     Clássica (feed 1080x1350: a foto grande + 4 com legenda) usa a capa e os 4 cômodos mais variados;
  4. sai em /fotos-captacao/posts/nossos-imoveis/<codigo>/ (classico-feed.png, estado.json, ambientes.json) e o
     index.json da galeria. NADA é gravado no banco: a ordem das fotos do site e a capa do site não mudam.

Uso (na VPS):  /root/nay-posts/.venv/bin/python /root/nay-posts/nossos_imoveis.py --recentes 10
               /root/nay-posts/.venv/bin/python /root/nay-posts/nossos_imoveis.py 9073 9064
Daqui:         ./scripts/nay nossos-imoveis --recentes 10
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import classificar_fotos as cf  # noqa: E402
import gerar_posts as gp  # noqa: E402

SAIDA = "/docker/nay-site-web/public/fotos-captacao/posts/nossos-imoveis"
URL = "/fotos-captacao/posts/nossos-imoveis"
MAX_FOTOS = 40
AMBIENTES = ("fachada", "sala", "cozinha", "varanda", "quarto", "banheiro", "area_servico", "garagem", "area_lazer",
             "vista", "planta", "outro")
ROTULO = {"fachada": "Fachada", "sala": "Sala", "cozinha": "Cozinha", "varanda": "Varanda", "quarto": "Quarto",
          "banheiro": "Banheiro", "area_servico": "Área de serviço", "garagem": "Garagem",
          "area_lazer": "Área de lazer", "vista": "Vista", "planta": "Planta", "outro": "Outro"}
# as 4 fotos pequenas da arte: uma de cada grupo, nesta ordem; o que faltar vem do próximo grupo que tiver foto
PARA_A_ARTE = (("sala",), ("quarto",), ("area_lazer", "varanda", "vista"), ("cozinha", "banheiro"))

PROMPT = """Você vê %d fotos de UM imóvel (anúncio de imobiliária), numeradas de 0 em diante na ordem das imagens.
Para CADA foto diga:
- "ambiente": o que ela mostra, um destes: fachada (frente do prédio, da casa ou do condomínio, entrada, portaria),
  sala (estar ou jantar, inclusive sala com cozinha americana), cozinha, varanda (sacada, varanda gourmet do
  apartamento ou da casa), quarto (quarto ou suíte), banheiro, area_servico (lavanderia, área de serviço),
  garagem, area_lazer (piscina, churrasqueira, salão de festas, academia, playground, quadra, área gourmet do
  condomínio), vista (vista da janela ou da varanda), planta (planta baixa, desenho), outro (corredor, escada,
  detalhe, o que não der para dizer).
- "etiqueta": legenda CURTA (até 26 letras), natural, de post de imobiliária: "Sala de estar", "Suíte com closet",
  "Cozinha planejada", "Piscina do condomínio", "Varanda gourmet". Só o que DÁ PARA VER na foto; não invente
  acabamento, medida nem nome de condomínio.
E diga "capa": o índice da melhor foto para ser a principal do anúncio (a mais bonita e geral do imóvel; fachada só se
for bonita). Responda SÓ o JSON pedido."""

ESQUEMA = {
    "type": "OBJECT",
    "properties": {
        "capa": {"type": "INTEGER"},
        "fotos": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
            "indice": {"type": "INTEGER"},
            "ambiente": {"type": "STRING", "enum": list(AMBIENTES)},
            "etiqueta": {"type": "STRING"}}, "required": ["indice", "ambiente", "etiqueta"]}},
    },
    "required": ["capa", "fotos"],
}
BAIXA = {"mediaResolution": "MEDIA_RESOLUTION_LOW"}


def recentes(n: int) -> list[int]:
    """Os N imóveis nossos mais novos no cadastro que estão no site e têm foto (a capa + 4 da arte pedem 5)."""
    return [int(x) for x in gp.banco("""
        SELECT i.codigo FROM imoveis i
         WHERE i.disponivel AND NOT i.bloqueado AND NOT coalesce(i.e_parceiro, false)
           AND site_imovel_publico(i.codigo) IS NOT NULL
           AND (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) > 0
         ORDER BY i.criado_em DESC, i.codigo DESC LIMIT %d""" % n).split()]


def ambientes(chave: str, urls: list[str]) -> tuple[list[dict], int, dict]:
    """[{url, ambiente, etiqueta}] na ordem de urls, o índice da capa e o uso de tokens."""
    vistas, imagens = [], []
    for u in urls[:MAX_FOTOS]:
        b = cf.baixar_e_reduzir(u)
        if b:
            vistas.append(u)
            imagens.append(b)
    if not imagens:
        return [{"url": u, "ambiente": None, "etiqueta": ""} for u in urls], 0, {}
    try:
        r, uso = cf.chamar_gemini(chave, imagens, PROMPT, ESQUEMA, BAIXA)
    except RuntimeError as e:
        if "mediaResolution" not in str(e) and "media_resolution" not in str(e):
            raise
        r, uso = cf.chamar_gemini(chave, imagens, PROMPT, ESQUEMA)        # o modelo não aceita a resolução baixa
    por_indice = {f["indice"]: f for f in (r.get("fotos") or [])
                  if isinstance(f.get("indice"), int) and f.get("ambiente") in AMBIENTES}
    lista = []
    for n, u in enumerate(vistas):
        f = por_indice.get(n) or {}
        lista.append({"url": u, "ambiente": f.get("ambiente"), "etiqueta": (f.get("etiqueta") or "").strip()[:40]})
    lista += [{"url": u, "ambiente": None, "etiqueta": ""} for u in urls if u not in vistas]
    capa = r.get("capa") if isinstance(r.get("capa"), int) and 0 <= r["capa"] < len(vistas) else 0
    return lista, capa, uso


def organizar(lista: list[dict], capa: int) -> list[dict]:
    """A capa primeiro e o resto por ambiente, na ordem de AMBIENTES (dentro do ambiente, a ordem do site)."""
    resto = [f for n, f in enumerate(lista) if n != capa]
    ordem = {a: n for n, a in enumerate(AMBIENTES)}
    resto.sort(key=lambda f: ordem.get(f["ambiente"], len(AMBIENTES)))
    return [lista[capa]] + resto if lista else []


def da_arte(organizadas: list[dict]) -> list[dict]:
    """A capa + 4: uma foto de cada grupo de PARA_A_ARTE; faltando, a próxima foto ainda não usada (sem planta)."""
    capa, resto = organizadas[0], organizadas[1:]
    usadas, escolha = set(), []
    for grupo in PARA_A_ARTE:
        f = next((f for a in grupo for f in resto if f["ambiente"] == a and f["url"] not in usadas), None)
        if f:
            escolha.append(f)
            usadas.add(f["url"])
    # faltando: primeiro um ambiente que ainda não está na arte (9073: banheiro antes da 2ª cozinha), depois qualquer um
    for so_novo in (True, False):
        for f in resto:
            ja = {capa["ambiente"]} | {e["ambiente"] for e in escolha}
            if len(escolha) >= 4:
                break
            if f["url"] not in usadas and f["ambiente"] != "planta" and not (so_novo and f["ambiente"] in ja):
                escolha.append(f)
                usadas.add(f["url"])
    return [capa] + escolha[:4]


def gerar(codigo: int, chave: str, pg) -> dict:
    i = gp.ler_imovel(codigo)
    sem_ajuste = argparse.Namespace(destaque=None, chamada=None, fita=None, slogan=None, contato=None)
    imovel, negocio = gp.montar_estado(i, sem_ajuste)
    urls = [f for f in (i.get("fotos") or []) if isinstance(f, str)]
    if not urls:
        raise RuntimeError("sem foto")
    lista, capa, uso = ambientes(chave, urls)
    organizadas = organizar(lista, capa)
    arte = da_arte(organizadas)
    fotos = [{"src": gp.baixar_foto(f["url"]), "etiqueta": f["etiqueta"] if n else ""} for n, f in enumerate(arte)]

    pg.evaluate("() => GeradorImob.novoImovel()")
    pg.evaluate("(im) => GeradorImob.definirImovel(im)", imovel)
    pg.evaluate("(fs) => GeradorImob.adicionarFotos(fs)", fotos)
    pg.evaluate("() => GeradorImob.definirModelo('post', 'classico')")
    png = pg.evaluate("() => GeradorImob.exportarPost('feed', 'classico')")

    pasta = os.path.join(SAIDA, str(codigo))
    os.makedirs(pasta, exist_ok=True)
    with open(os.path.join(pasta, "classico-feed.png"), "wb") as arq:
        arq.write(base64.b64decode(png.split(",", 1)[1]))
    with open(os.path.join(pasta, "estado.json"), "w", encoding="utf-8") as arq:
        json.dump({"imovel": imovel, "negocio": negocio}, arq, ensure_ascii=False, indent=1)
    with open(os.path.join(pasta, "ambientes.json"), "w", encoding="utf-8") as arq:
        json.dump({"capa": organizadas[0]["url"], "arte": [f["url"] for f in arte],
                   "fotos": [{**f, "rotulo": ROTULO.get(f["ambiente"] or "", "Sem leitura")} for f in organizadas]},
                  arq, ensure_ascii=False, indent=1)
    return {"codigo": codigo, "titulo": i.get("titulo") or "", "negocio": negocio,
            "imagem": "%s/%d/classico-feed.png" % (URL, codigo), "fotos": len(urls),
            "lidas": sum(1 for f in lista if f["ambiente"]), "tokens": (uso or {}).get("totalTokenCount")}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("codigos", type=int, nargs="*")
    p.add_argument("--recentes", type=int, default=0)
    a = p.parse_args()
    codigos = a.codigos or recentes(a.recentes or 10)
    chave = cf.chave_gemini()
    os.makedirs(SAIDA, exist_ok=True)
    indice_arq = os.path.join(SAIDA, "index.json")
    try:
        with open(indice_arq, encoding="utf-8") as arq:
            antigos = {x["codigo"]: x for x in json.load(arq).get("imoveis", [])}
    except (OSError, ValueError):
        antigos = {}

    from playwright.sync_api import sync_playwright
    feitos, erros = [], []
    with sync_playwright() as pw:
        nav = pw.chromium.launch()
        ctx = nav.new_context(viewport={"width": 1400, "height": 1000})
        ctx.add_init_script("try { localStorage.clear(); } catch (e) {}")
        pg = ctx.new_page()
        pg.on("pageerror", lambda e: erros.append(str(e)))
        pg.goto("file://" + gp.GERADOR, wait_until="load")
        pg.wait_for_function("window.GeradorImob && window.GeradorImob.versao", timeout=30000)
        for codigo in codigos:
            try:
                r = gerar(codigo, chave, pg)
                r["gerado_em"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
                antigos[codigo] = r
                feitos.append(r)
                print(json.dumps(r, ensure_ascii=False), flush=True)
            except (Exception, SystemExit) as e:  # noqa: BLE001 -- um imóvel com erro não para os outros
                print(json.dumps({"codigo": codigo, "ok": False, "erro": str(e)[:300]}, ensure_ascii=False), flush=True)
        nav.close()

    # os desta rodada na ordem pedida (o mais novo no cadastro primeiro), depois os de antes
    lista = feitos + [x for c, x in antigos.items() if c not in {f["codigo"] for f in feitos}]
    with open(indice_arq + ".novo", "w", encoding="utf-8") as arq:
        json.dump({"atualizado_em": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "imoveis": lista}, arq, ensure_ascii=False, indent=1)
    os.replace(indice_arq + ".novo", indice_arq)
    print("feitos=%d de %d; erros da página: %s" % (len(feitos), len(codigos), erros[:3]), file=sys.stderr)


if __name__ == "__main__":
    main()
