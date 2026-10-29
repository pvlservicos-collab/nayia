"""29/10/2026 (Pedro: "tem alguns imóveis que ficou com foto, por exemplo, que diz sala de estar mas pega só um pedaço da sala e
mais o corretor; se desse para substituir essas imagens por outro cômodo"). Revisa as 5 fotos da arte de cada imóvel da galeria
Nossos imóveis (pasta nossos-imoveis/<código>/ambientes.json) e troca a que tem problema por outra do MESMO cômodo; sem outra
boa, por foto de outro cômodo que a arte ainda não mostre.

  Etapa 1 (1 chamada por imóvel, só as 5 fotos da arte): problema = nenhum | pessoa | pedaco | escura | marca
    pessoa = rosto ou corpo de gente (corretor, morador, fotógrafo) bem visível; pedaco = a foto mostra só um canto/parede/teto
    e não dá para ver o cômodo; escura = muito escura ou borrada; marca = logotipo de outra imobiliária. Grande-angular
    distorcida NÃO é problema.
  Etapa 2 (só nas marcadas): as candidatas (mesmo cômodo, depois outros) e a Gemini escolhe a melhor sem problema, ou nenhuma.

Uso: python revisar_fotos_arte.py [códigos...] [--aplicar] [--pausa 3]
  sem --aplicar: só escreve o relatório (/root/nay-posts/revisao_artes.json); com --aplicar: guarda ambientes.json.bk-pre-troca,
  troca o `arte` e imprime os códigos mudados (a arte nova sai com `nossos_imoveis.py <códigos>`, que reaproveita o arquivo).
Sem códigos: todos da galeria; quem já está no relatório não é revisado de novo (o relatório é a memória da rodada).
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import classificar_fotos as cf  # noqa: E402

SAIDA = "/docker/nay-site-web/public/fotos-captacao/posts/nossos-imoveis"
RELATORIO = "/root/nay-posts/revisao_artes.json"
ROTULO = {"fachada": "Fachada", "sala": "Sala de estar", "cozinha": "Cozinha", "varanda": "Varanda", "quarto": "Quarto",
          "banheiro": "Banheiro", "area_servico": "Área de serviço", "garagem": "Garagem", "area_lazer": "Área de lazer",
          "vista": "Vista", "planta": "Planta", "outro": "Outro"}
PROBLEMAS = ("nenhum", "pessoa", "pedaco", "escura", "marca")
MAX_CANDIDATAS = 6

# o chamar_gemini faz `prompt % len(imagens)`: cada prompt tem UM %d e nenhum outro sinal de porcento
PROMPT1 = """Você revisa as %d fotos de uma arte de imobiliária, numeradas de 0 em diante na ordem das imagens.
Para CADA foto diga o "problema":
- "pessoa": rosto ou corpo de gente (corretor, morador, fotógrafo) bem visível na foto;
- "pedaco": a foto mostra só um canto, parede, teto ou um pedaço do cômodo e não dá para ver o cômodo;
- "escura": muito escura, borrada ou desfocada;
- "marca": logotipo ou nome de OUTRA imobiliária bem visível;
- "nenhum": está boa. Foto grande-angular (olho de peixe) e móveis do morador NÃO são problema.
Na dúvida, "nenhum". Responda SÓ o JSON pedido."""
ESQ1 = {"type": "OBJECT", "properties": {"fotos": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
    "indice": {"type": "INTEGER"}, "problema": {"type": "STRING", "enum": list(PROBLEMAS)}},
    "required": ["indice", "problema"]}}}, "required": ["fotos"]}

PROMPT2 = """A foto 0 da arte de um imóvel tem problema (PROBLEMA). As outras fotos, de 1 em diante, são candidatas para trocar
(total de imagens enviadas: %d). Escolha a MELHOR candidata: mostra bem o cômodo inteiro, bem iluminada, sem gente, sem
logotipo de outra imobiliária. Se nenhuma serve, escolha -1. Responda SÓ o JSON: o número da candidata (1 em diante) ou -1."""
ESQ2 = {"type": "OBJECT", "properties": {"escolha": {"type": "INTEGER"}}, "required": ["escolha"]}


def reduzir(url, cache):
    if url not in cache:
        cache[url] = cf.baixar_e_reduzir(url)
    return cache[url]


def revisar(chave, pasta, pausa):
    with open(os.path.join(pasta, "ambientes.json"), encoding="utf-8") as f:
        g = json.load(f)
    por_url = {x["url"]: x for x in g["fotos"]}
    arte = list(g["arte"])
    cache = {}
    imgs = [reduzir(u, cache) for u in arte]
    if any(i is None for i in imgs):
        return {"erro": "foto da arte não baixou", "trocas": []}
    r1, _ = cf.chamar_gemini(chave, imgs, PROMPT1, ESQ1)
    time.sleep(pausa)
    prob = {x["indice"]: x["problema"] for x in r1.get("fotos") or [] if isinstance(x.get("indice"), int)}
    trocas, usadas = [], set(arte)
    for pos, url in enumerate(arte):
        p = prob.get(pos, "nenhum")
        if p == "nenhum":
            continue
        amb = (por_url.get(url) or {}).get("ambiente")
        livres = [x for x in g["fotos"] if x["url"] not in usadas and x.get("ambiente") != "planta"]
        mesmas = [x for x in livres if x.get("ambiente") == amb][:MAX_CANDIDATAS]
        outras, vistos = [], {por_url[u].get("ambiente") for u in arte if u in por_url}
        for x in livres:                                   # outro cômodo que a arte ainda não mostra, uma foto por cômodo
            a = x.get("ambiente")
            if a and a not in vistos and a not in ("outro", "garagem", "area_servico") and a not in {o["ambiente"] for o in outras}:
                outras.append(x)
        escolhida = None
        for grupo in (mesmas, outras[:MAX_CANDIDATAS]):
            cands = [(x, reduzir(x["url"], cache)) for x in grupo]
            cands = [(x, b) for x, b in cands if b]
            if not cands:
                continue
            r2, _ = cf.chamar_gemini(chave, [imgs[pos]] + [b for _, b in cands], PROMPT2.replace("PROBLEMA", p), ESQ2)
            time.sleep(pausa)
            e = r2.get("escolha")
            if isinstance(e, int) and 1 <= e <= len(cands):
                escolhida = cands[e - 1][0]
                break
        if escolhida:
            usadas.add(escolhida["url"])
            trocas.append({"posicao": pos, "problema": p, "de": url, "de_ambiente": amb, "para": escolhida["url"],
                           "para_ambiente": escolhida.get("ambiente"),
                           "etiqueta": escolhida.get("etiqueta") or ROTULO.get(escolhida.get("ambiente") or "", "")})
        else:
            trocas.append({"posicao": pos, "problema": p, "de": url, "de_ambiente": amb, "para": None})
    return {"trocas": trocas}


def aplicar(pasta, trocas):
    caminho = os.path.join(pasta, "ambientes.json")
    with open(caminho, encoding="utf-8") as f:
        g = json.load(f)
    novas = [t for t in trocas if t.get("para")]
    if not novas:
        return False
    with open(caminho + ".bk-pre-troca", "w", encoding="utf-8") as f:
        json.dump(g, f, ensure_ascii=False, indent=1)
    arte = list(g["arte"])
    for t in novas:
        arte[t["posicao"]] = t["para"]
        for x in g["fotos"]:                               # a foto nova leva o rótulo do cômodo dela se não tinha etiqueta
            if x["url"] == t["para"] and not (x.get("etiqueta") or "").strip():
                x["etiqueta"] = ROTULO.get(x.get("ambiente") or "", "")
    g["arte"] = arte
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(g, f, ensure_ascii=False, indent=1)
    return True


def main():
    p = argparse.ArgumentParser()
    p.add_argument("codigos", type=int, nargs="*")
    p.add_argument("--aplicar", action="store_true")
    p.add_argument("--pausa", type=float, default=3.0)
    a = p.parse_args()
    codigos = a.codigos or sorted(int(d) for d in os.listdir(SAIDA)
                                  if d.isdigit() and os.path.exists(os.path.join(SAIDA, d, "ambientes.json")))
    chave = cf.chave_gemini()
    try:
        with open(RELATORIO, encoding="utf-8") as f:
            rel = json.load(f)
    except (OSError, ValueError):
        rel = {}
    mudados = []
    for n, c in enumerate(codigos, 1):
        pasta = os.path.join(SAIDA, str(c))
        try:
            r = rel[str(c)] if (str(c) in rel and not a.codigos) else revisar(chave, pasta, a.pausa)
        except (Exception, SystemExit) as e:  # noqa: BLE001 -- um imóvel com erro não para os outros
            r = {"erro": str(e)[:200], "trocas": []}
        if not r.get("erro"):
            rel[str(c)] = r
        if a.aplicar and aplicar(pasta, r.get("trocas") or []):
            mudados.append(c)
        if n % 10 == 0 or n == len(codigos):
            with open(RELATORIO, "w", encoding="utf-8") as f:
                json.dump(rel, f, ensure_ascii=False, indent=1)
        resumo = [(t["posicao"], t["problema"], bool(t.get("para"))) for t in r.get("trocas") or []]
        print("%d/%d %s %s%s" % (n, len(codigos), c, json.dumps(resumo), " ERRO " + r["erro"] if r.get("erro") else ""), flush=True)
    print("mudados:", " ".join(str(c) for c in mudados), flush=True)


if __name__ == "__main__":
    main()
