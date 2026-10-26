#!/root/nay-posts/.venv/bin/python
"""CLASSIFICA AS FOTOS DE UM IMÓVEL COM A GEMINI (Pedro, 26/10/2026): "achar a foto principal e mais 4 cômodos legais
... o Gemini acharia a foto principal e esses 4 cômodos e organizaria para a gente depois rodar um algoritmo que
produza esses posts".

Manda até FOTOS_POR_CHAMADA fotos do imóvel (numeradas), numa chamada só, e pede: qual é a melhor capa (fachada/foto
geral) e, de até 4 categorias (sala, quarto, área de lazer, banheiro), qual foto mostra cada uma melhor — só as que
achar com confiança (não força todas as 4). Grava: a capa em imovel_fotos.e_capa (o campo que o resto do sistema já
usa); as 4 em categoria + etiqueta (a legenda curta que aparece sobre a foto no post, 500).

Uso (na VPS):  /root/nay-posts/.venv/bin/python /root/nay-posts/classificar_fotos.py 5739
               /root/nay-posts/.venv/bin/python /root/nay-posts/classificar_fotos.py --todos [--limite 20] [--pausa 8]
               (--todos pula quem já tem e_capa marcado por esta rotina: é retomável)
Daqui:         ./scripts/nay fotos-classificar 5739   |   ./scripts/nay fotos-classificar --todos
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
MODELOS = ["gemini-flash-latest", "gemini-3.5-flash", "gemini-flash-lite-latest"]
ENV_CHAVE = "/etc/nay-posts/gemini.env"
FOTOS_POR_CHAMADA = 18          # teto por imóvel: não precisa olhar as 60-90 fotos de um cadastro grande (Pedro: "nem
                                 # precisa classificar todos"), e mantém a chamada pequena/barata
LADO_MAX = 480                  # foto reduzida antes de mandar à Gemini: já basta para reconhecer o cômodo
CATEGORIAS = ("sala", "quarto", "area_lazer", "banheiro")

PROMPT = """Você vê até %d fotos de UM imóvel à venda ou para alugar, numeradas de 0 em diante na ordem das imagens.
Escolha:
1. "capa": o ÍNDICE da melhor foto para ser a imagem principal do anúncio (de preferência a fachada/entrada do prédio
   ou condomínio; se não houver fachada clara, a foto mais bonita e geral do imóvel).
2. Até 4 fotos DIFERENTES entre si e da capa, uma para cada categoria que você conseguir identificar com confiança:
   "sala" (sala de estar, sala de jantar, cozinha americana integrada à sala), "quarto" (um quarto ou suíte, de
   preferência o principal/maior), "area_lazer" (o diferencial do imóvel: varanda gourmet, piscina, garden, área
   gourmet, vista, terraço — o que mais vender a foto), "banheiro" (um banheiro).
Se não achar uma foto clara para alguma categoria, DEIXE DE FORA (não force, não repita índice de outra categoria).
Para cada foto escolhida (menos a capa), escreva uma "etiqueta": um texto CURTO (até 28 letras), natural, no estilo de
legenda de post de imobiliária — ex.: "Sala / cozinha americana", "Quarto com sacada", "Garden privativo",
"Banheiro social", "Varanda gourmet". Não repita o nome do condomínio nem invente detalhe que não dá para ver.
Responda SÓ o JSON pedido."""

ESQUEMA = {
    "type": "OBJECT",
    "properties": {
        "capa": {"type": "INTEGER"},
        "comodos": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
            "indice": {"type": "INTEGER"},
            "categoria": {"type": "STRING", "enum": list(CATEGORIAS)},
            "etiqueta": {"type": "STRING"}}, "required": ["indice", "categoria", "etiqueta"]}},
    },
    "required": ["capa", "comodos"],
}


def sql_texto(v) -> str:
    """Um valor como literal SQL seguro: inteiro sem aspas, o resto como string com aspas escapadas."""
    if isinstance(v, int):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def banco(sql: str) -> str:
    """`sql` já pronta (sem placeholder): quem chama monta com sql_texto()."""
    r = subprocess.run(["docker", "exec", "nay-postgres", "psql", "-U", "nay", "-d", "naydb", "-tA", "-F", "\t", "-c", sql],
                       capture_output=True, text=True, timeout=60)
    if r.returncode:
        raise RuntimeError("banco: " + r.stderr.strip())
    return r.stdout


def linhas(sql: str) -> list[list[str]]:
    out = banco(sql).strip("\n")
    return [l.split("\t") for l in out.split("\n")] if out else []


def chave_gemini() -> str:
    with open(ENV_CHAVE, encoding="utf-8") as f:
        for linha in f:
            if linha.startswith("GEMINI_API_KEY="):
                return linha.split("=", 1)[1].strip()
    raise SystemExit("sem GEMINI_API_KEY em " + ENV_CHAVE)


def baixar_e_reduzir(url: str) -> bytes | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 ImobEasy/fotos-classificar"})
        with urllib.request.urlopen(req, timeout=20) as r:
            dados = r.read()
        from PIL import Image, ImageOps
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(dados)))
        if img.mode != "RGB":
            img = img.convert("RGB")
        img.thumbnail((LADO_MAX, LADO_MAX))
        saida = io.BytesIO()
        img.save(saida, "JPEG", quality=78)
        return saida.getvalue()
    except Exception as e:  # noqa: BLE001 -- uma foto ruim não para o imóvel
        print("  foto pulada (%s): %s" % (url[:60], e), file=sys.stderr)
        return None


def chamar_gemini(chave: str, imagens: list[bytes]) -> tuple[dict, dict]:
    partes = [{"inline_data": {"mime_type": "image/jpeg", "data": base64.b64encode(b).decode()}} for b in imagens]
    partes.append({"text": PROMPT % len(imagens)})
    corpo = {"contents": [{"role": "user", "parts": partes}],
             "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json", "responseSchema": ESQUEMA}}
    ultimo = ""
    for tentativa in range(4):
        modelo = MODELOS[tentativa % len(MODELOS)]
        req = urllib.request.Request(API % modelo, data=json.dumps(corpo).encode(),
                                     headers={"Content-Type": "application/json", "x-goog-api-key": chave}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                j = json.loads(r.read())
            texto = "".join(p.get("text", "") for p in (((j.get("candidates") or [{}])[0]).get("content") or {}).get("parts", []))
            uso = j.get("usageMetadata") or {}
            return json.loads(texto), uso
        except urllib.error.HTTPError as e:
            corpo_erro = e.read().decode("utf-8", "replace")[:300]
            ultimo = "%s (%s): %s" % (modelo, e.code, corpo_erro)
            if e.code == 429:
                print("  cota/limite (%s); tentando outro modelo" % modelo, file=sys.stderr)
            if e.code not in (404, 429, 500, 502, 503):
                break
        except Exception as e:  # noqa: BLE001
            ultimo = "%s: %s" % (modelo, e)
        time.sleep(3 * (tentativa + 1))
    raise RuntimeError("Gemini falhou: " + ultimo)


def classificar(codigo: int, chave: str) -> dict:
    fotos = linhas("SELECT id, url FROM imovel_fotos WHERE codigo = %s ORDER BY ordem NULLS LAST, id LIMIT %s" %
                   (sql_texto(codigo), sql_texto(FOTOS_POR_CHAMADA)))
    if not fotos:
        return {"codigo": codigo, "ok": False, "motivo": "sem fotos"}
    ids, urls = [f[0] for f in fotos], [f[1] for f in fotos]
    imagens, ids_validos = [], []
    for fid, url in zip(ids, urls):
        dados = baixar_e_reduzir(url)
        if dados:
            imagens.append(dados)
            ids_validos.append(fid)
    if len(imagens) < 2:
        return {"codigo": codigo, "ok": False, "motivo": "poucas fotos baixaram (%d)" % len(imagens)}

    resposta, uso = chamar_gemini(chave, imagens)
    capa_i = resposta.get("capa")
    comodos = [c for c in (resposta.get("comodos") or [])
              if isinstance(c.get("indice"), int) and 0 <= c["indice"] < len(ids_validos) and c.get("categoria") in CATEGORIAS]
    # nunca a mesma foto em duas categorias, nem a mesma da capa
    vistos, comodos_ok = {capa_i}, []
    for c in comodos:
        if c["indice"] in vistos:
            continue
        vistos.add(c["indice"])
        comodos_ok.append(c)

    banco("UPDATE imovel_fotos SET e_capa = false WHERE codigo = %s" % sql_texto(codigo))
    if isinstance(capa_i, int) and 0 <= capa_i < len(ids_validos):
        banco("UPDATE imovel_fotos SET e_capa = true WHERE id = %s" % sql_texto(int(ids_validos[capa_i])))
    banco("UPDATE imovel_fotos SET categoria = NULL, etiqueta = NULL, categoria_em = NULL WHERE codigo = %s" % sql_texto(codigo))
    for c in comodos_ok:
        banco("UPDATE imovel_fotos SET categoria = %s, etiqueta = %s, categoria_em = now() WHERE id = %s" %
              (sql_texto(c["categoria"]), sql_texto(c["etiqueta"][:60]), sql_texto(int(ids_validos[c["indice"]]))))

    return {"codigo": codigo, "ok": True, "fotos_vistas": len(imagens), "capa": capa_i is not None,
           "comodos": [c["categoria"] for c in comodos_ok], "tokens": uso}


def imoveis_pendentes(limite: int) -> list[int]:
    return [int(l[0]) for l in linhas("""
        SELECT i.codigo FROM imoveis i
         WHERE i.disponivel AND NOT i.bloqueado AND NOT i.e_parceiro
           AND EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo)
           AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo AND (f.categoria_em IS NOT NULL OR f.e_capa))
         ORDER BY i.codigo LIMIT %s""" % sql_texto(limite))]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("codigo", type=int, nargs="?")
    p.add_argument("--todos", action="store_true")
    p.add_argument("--limite", type=int, default=9999)
    p.add_argument("--pausa", type=float, default=8.0, help="segundos entre imóveis, no --todos")
    a = p.parse_args()
    if not a.codigo and not a.todos:
        raise SystemExit("diga o código do imóvel, ou --todos")
    chave = chave_gemini()

    codigos = imoveis_pendentes(a.limite) if a.todos else [a.codigo]
    print("%d imóvel(is) para classificar" % len(codigos), file=sys.stderr)
    feitos, falhas = 0, 0
    for n, codigo in enumerate(codigos, 1):
        try:
            r = classificar(codigo, chave)
            print(json.dumps(r, ensure_ascii=False))
            feitos += r.get("ok", False)
            falhas += not r.get("ok", False)
        except Exception as e:  # noqa: BLE001 -- um imóvel com erro não para os outros
            falhas += 1
            print(json.dumps({"codigo": codigo, "ok": False, "erro": str(e)[:300]}, ensure_ascii=False))
        if a.todos and n < len(codigos):
            time.sleep(a.pausa)
    print("feitos=%d falhas=%d" % (feitos, falhas), file=sys.stderr)


if __name__ == "__main__":
    main()
