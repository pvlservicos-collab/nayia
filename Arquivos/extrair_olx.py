"""Lê um anúncio do OLX e devolve os dados e TODAS as fotos.

ESTADO: funciona, medido em 02/09/2026 -- mas **não está ligado em nada**.
Falta a decisão do Tel sobre de onde rodar (ver o bloqueio abaixo) e sobre
publicar no site. Ver `33-OLX-Para-o-Site.md`.

O QUE FOI MEDIDO, e cada coisa custou tempo para descobrir:

1. `curl` comum leva 403 do Cloudflare, do servidor E do Mac. Não é o IP:
   é a impressão digital TLS. Com `curl_cffi` imitando Chrome, passa.
       pip install curl_cffi
       cr.get(url, impersonate="chrome124")

2. O host TEM que ser o regional (`am.olx.com.br`). O `www.olx.com.br/<anúncio>`
   devolve **308 para a home** e depois um 200 com a página errada -- uma
   página que parece boa e não tem o anúncio. Erro silencioso, do tipo pior.

3. Os dados vêm no PRÓPRIO HTML, num `<script id="initial-data" data-json="...">`
   com o JSON escapado em HTML. Não existe API secreta a descobrir; essa
   procura foi feita e não leva a nada.

4. O SERVIDOR ESTÁ BLOQUEADO pela OLX: 403 "Sorry, you have been blocked" em
   `www`, `am` e `apigw`, a partir de 179.198.121.171. Do Mac, 200 no mesmo
   minuto. Provavelmente disparado pelas nossas próprias requisições de teste.

5. MAS O CDN DE FOTO NÃO ESTÁ BLOQUEADO: `img.olx.com.br` devolve 200 e
   192 KB para o servidor, com md5 idêntico ao baixado no Mac. Ou seja: ler o
   anúncio precisa de um IP liberado; **baixar as fotos roda no servidor**.

6. `--fail` / `raise_for_status` é OBRIGATÓRIO ao baixar foto: URL que não
   existe devolve **404 com um JPEG de verdade dentro** (um quadrado cinza de
   ~49 KB). Sem conferir o status, grava-se placeholder achando que deu certo.

7. O dado da OLX é pior que o nosso e não tem dono a quem cobrar: o primeiro
   anúncio que peguei, sem escolher, era uma fazenda de 12.000 hectares com
   `priceValue: R$ 1.500` e `priceLabel: Aluguel` -- é R$ 1.500 por hectare, à
   venda. É a mesma classe do "1601 quartos" do nosso catálogo. Por isso esta
   função **não converte nada**: devolve o que veio, cru, e quem decide o que
   fazer com isso é quem chama.

    .venv/bin/python extrair_olx.py https://am.olx.com.br/.../casa-...-1526572128
"""
import html
import json
import re
import sys

try:
    from curl_cffi import requests as cr
except ImportError:                       # pragma: no cover
    cr = None

NAVEGADOR = "chrome124"


class OlxBloqueado(RuntimeError):
    """A OLX recusou a requisição deste IP -- não é erro de código."""


def _regionalizar(url):
    """`www.olx.com.br/<anúncio>` redireciona para a home e devolve página
    vazia com status 200. O host regional entrega o anúncio."""
    return re.sub(r"^https://www\.olx\.com\.br/", "https://am.olx.com.br/", url.strip())


def baixar_html(url, buscar=None):
    if cr is None:
        raise RuntimeError("curl_cffi não instalado: pip install curl_cffi")
    buscar = buscar or (lambda u: cr.get(u, impersonate=NAVEGADOR, timeout=30))
    r = buscar(_regionalizar(url))
    texto = r.text
    if r.status_code == 403 or "been blocked" in texto or "Attention Required" in texto:
        raise OlxBloqueado(
            "a OLX recusou esta requisição (403 Cloudflare). O IP do servidor "
            "está bloqueado; do Mac passa. Ver 33-OLX-Para-o-Site.md.")
    if r.status_code != 200:
        raise RuntimeError(f"OLX devolveu {r.status_code}")
    return texto


def _achar_anuncio(no, profundidade=0):
    """O JSON aninha o anúncio em lugares que já mudaram de nome. Procura o
    dicionário que tem as chaves que interessam, em vez de fixar o caminho."""
    if profundidade > 8 or not isinstance(no, dict):
        return None
    if "subject" in no and ("images" in no or "properties" in no):
        return no
    for v in no.values():
        if isinstance(v, dict):
            achado = _achar_anuncio(v, profundidade + 1)
            if achado:
                return achado
        elif isinstance(v, list):
            for item in v[:20]:
                achado = _achar_anuncio(item, profundidade + 1)
                if achado:
                    return achado
    return None


def extrair(texto_html):
    """Devolve o anúncio CRU, sem converter nada. Campo que a OLX não mandou
    fica ausente -- e ausente não é zero."""
    m = re.search(r'id="initial-data"[^>]*data-json="([^"]+)"', texto_html)
    if not m:
        raise RuntimeError(
            "não achei o bloco `initial-data` no HTML. Ou a OLX mudou o "
            "formato, ou veio a página errada (host `www` em vez do regional).")
    dados = json.loads(html.unescape(m.group(1)))
    anuncio = _achar_anuncio(dados)
    if not anuncio:
        raise RuntimeError("o `initial-data` veio sem anúncio dentro.")

    props = {p.get("name"): p.get("value")
             for p in (anuncio.get("properties") or []) if p.get("name")}
    local = anuncio.get("location") or {}
    fotos = []
    for img in (anuncio.get("images") or []):
        url = img.get("original") or img.get("originalAlternative")
        if url:
            fotos.append(url)

    return {
        "olx_id": anuncio.get("listId"),
        "titulo": anuncio.get("subject"),
        "descricao": anuncio.get("body"),
        "preco_texto": anuncio.get("priceValue"),
        "preco_rotulo": anuncio.get("priceLabel"),
        "bairro": local.get("neighbourhood"),
        "municipio": local.get("municipality"),
        "logradouro": local.get("address"),
        "cep": local.get("zipcode"),
        "campos": props,
        "fotos": fotos,
    }


def do_link(url, buscar=None):
    return extrair(baixar_html(url, buscar=buscar))


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-1])
        return 2
    try:
        a = do_link(sys.argv[1])
    except OlxBloqueado as erro:
        print(f"BLOQUEADO: {erro}")
        return 3
    print(json.dumps(a, ensure_ascii=False, indent=1))
    print(f"\n{len(a['fotos'])} foto(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
