"""O BLOG DA IMOB EASY -- blog.imobeasy.online (406, Pedro 17/10/2026).

Pedro: "crie o blog em um modelo de blog com a identidade visual da home ... 2 tipos de artigos, posts de blog e posts
de imóveis ... no final uma lista de imóveis próximos ... um buscador de imóveis igual o card na home numa sidebar ...
filtros por categoria ... uma newsletter de imóveis para corretores ... otimizado tanto para o Google quanto para o
SEO de IA ... uma ferramenta que checa os posts, um criador e editor de post ... e metrifica as visitas".

POR QUE AS PÁGINAS SAEM PRONTAS DAQUI (e não montadas pelo navegador como o resto do site): o Google até executa o
JavaScript, mas os robôs das IAs (GPTBot, ClaudeBot, PerplexityBot...) leem só o HTML que chega. Então o artigo vem
inteiro no HTML: título, texto, FAQ, dados estruturados (JSON-LD). O JavaScript só acrescenta o que é de gente
(a busca da barra lateral, o contador de visitas, a newsletter).

COMO CHEGA AQUI: o Traefik manda Host(blog.imobeasy.online) para esta API com o prefixo /blog (addPrefix); por isso
as rotas das páginas começam com /blog. Os arquivos estáticos do blog (css, js, imagens) moram no site
(imobeasy.online/blog/...), servidos pelo nginx de sempre.

ROTAS
  páginas    GET /blog/  /blog/categoria/<c>  /blog/busca?q=  /blog/artigo/<slug>  /blog/newsletter
             /blog/sitemap.xml  /blog/feed.xml  /blog/robots.txt  /blog/llms.txt
  público    GET /api/blog/recentes  /api/blog/lista  /api/blog/artigo/<slug>
             POST /api/blog/visita  /api/blog/newsletter  /api/blog/newsletter/sair
  admin      /admin/api/blog/artigos (GET lista, POST salvar), /admin/api/blog/artigos/<id> (GET, DELETE),
             /admin/api/blog/previa (POST markdown -> html), /admin/api/blog/imagem (POST arquivo),
             /admin/api/blog/imovel/<codigo>, /admin/api/blog/metricas, /admin/api/blog/newsletter (GET, POST sair)
O banco: as funções site_blog_* (migração 406), pelos papéis do site.
"""
import datetime as dt
import html
import io
import json
import os
import re
import time
import unicodedata
import uuid
from urllib.parse import urlparse

import psycopg2
import psycopg2.extras
from flask import Blueprint, Response, jsonify, request
from jinja2 import Environment, FileSystemLoader, select_autoescape

try:
    import markdown as _markdown
except Exception:  # noqa: BLE001 -- sem a biblioteca o texto sai em parágrafos simples
    _markdown = None

from imoveis_api import _admin_autenticado
from disparo_api import _usuario_admin   # o nome de quem salvou

blog_bp = Blueprint("blog", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
SITE_URL = "https://imobeasy.online"
BLOG_URL = os.environ.get("BLOG_URL", "https://blog.imobeasy.online")
API_URL = "https://api.imobeasy.online"
VERSAO = "20261018a"            # o ?v= do css/js do blog: mudou o arquivo, muda aqui
PASTA_FOTOS = os.environ.get("FOTOS_CAPTACAO_DIR", "/fotos")
URL_FOTOS = os.environ.get("FOTOS_CAPTACAO_URL", SITE_URL + "/fotos-captacao")
CATEGORIAS = [("sobre-nos", "Sobre nós"), ("clientes", "Clientes"), ("corretores", "Corretores"),
              ("locacao", "Imóveis de locação"), ("venda", "Imóveis de venda")]
NOME_CATEGORIA = dict(CATEGORIAS)
POR_PAGINA = 12
IMAGEM_MAXIMA = 15 * 1024 * 1024
LADO_MAXIMO = 1600

# ---------------------------------------------------------------- banco
def _conn(escrita):
    url = WRITE_DATABASE_URL if escrita else DATABASE_URL
    if not url:
        raise RuntimeError("banco do site não configurado")
    c = psycopg2.connect(url, connect_timeout=5)
    c.cursor_factory = psycopg2.extras.RealDictCursor
    return c


def _um(sql, params=(), escrita=False):
    """Uma chamada de função: devolve a coluna `r` (jsonb já vem como dict/list)."""
    c = _conn(escrita)
    try:
        with c.cursor() as cur:
            cur.execute(sql, params)
            linha = cur.fetchone()
        if escrita:
            c.commit()
        return linha["r"] if linha else None
    except Exception:
        c.rollback()
        raise
    finally:
        c.close()


# ---------------------------------------------------------------- texto
def _md(texto):
    """Markdown -> HTML. Imagens com loading lazy; link de fora abre em outra aba."""
    texto = texto or ""
    if _markdown:
        h = _markdown.markdown(texto, extensions=["extra", "sane_lists", "toc"], extension_configs={"toc": {"permalink": False}})
    else:
        h = "".join("<p>%s</p>" % html.escape(p.strip()).replace("\n", "<br>") for p in re.split(r"\n\s*\n", texto) if p.strip())
    h = re.sub(r"<img (?![^>]*loading=)", '<img loading="lazy" decoding="async" ', h)
    h = re.sub(r'<a href="(https?://(?!(?:www\.)?imobeasy\.online|blog\.imobeasy\.online)[^"]*)"',
               r'<a href="\1" target="_blank" rel="noopener"', h)
    return h


def _texto_puro(md):
    t = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", md or "")
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"[#>*_`~\-]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def _palavras(md):
    return len([p for p in _texto_puro(md).split(" ") if p])


MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]


def _data(iso):
    if not iso:
        return ""
    try:
        d = dt.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        d = d.astimezone(dt.timezone(dt.timedelta(hours=-4)))
        return "%d de %s de %d" % (d.day, MESES[d.month - 1], d.year)
    except Exception:  # noqa: BLE001
        return str(iso)[:10]


def _iso(iso):
    if not iso:
        return ""
    try:
        return dt.datetime.fromisoformat(str(iso).replace("Z", "+00:00")).isoformat()
    except Exception:  # noqa: BLE001
        return str(iso)


def _reais(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return ""
    if not v:
        return ""
    return "R$ " + ("{:,.0f}".format(v)).replace(",", ".")


def _url_artigo(slug):
    return BLOG_URL + "/artigo/" + slug


def _url_categoria(chave):
    return BLOG_URL + "/categoria/" + chave


def _ld(obj):
    """JSON-LD dentro de <script>: o </ não pode fechar a tag."""
    return json.dumps(obj, ensure_ascii=False).replace("</", "<\\/")


# ---------------------------------------------------------------- templates
_env = Environment(loader=FileSystemLoader(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blog_templates")),
                   autoescape=select_autoescape(["html"]), trim_blocks=True, lstrip_blocks=True)
_env.globals.update(SITE_URL=SITE_URL, BLOG_URL=BLOG_URL, API_URL=API_URL, VERSAO=VERSAO, CATEGORIAS=CATEGORIAS,
                    url_artigo=_url_artigo, url_categoria=_url_categoria, data=_data, iso=_iso, reais=_reais, ld=_ld,
                    nome_categoria=lambda c: NOME_CATEGORIA.get(c, c or ""))


def _pagina(nome, status=200, cache=300, **ctx):
    corpo = _env.get_template(nome).render(**ctx)
    r = Response(corpo, status=status, mimetype="text/html; charset=utf-8")
    r.headers["Cache-Control"] = "public, max-age=%d" % cache if cache else "no-store"
    r.headers["X-Robots-Tag"] = "index, follow" if status == 200 else "noindex"
    return r


# ---------------------------------------------------------------- de onde veio a visita
RASTREADORES = [
    ("gptbot", "gptbot"), ("chatgpt-user", "chatgpt"), ("oai-searchbot", "openai-search"), ("claudebot", "claudebot"),
    ("anthropic-ai", "anthropic"), ("claude-web", "claude"), ("perplexitybot", "perplexity"), ("perplexity-user", "perplexity"),
    ("google-extended", "google-extended"), ("googleother", "googleother"), ("googlebot", "googlebot"), ("bingbot", "bingbot"),
    ("applebot", "applebot"), ("ccbot", "ccbot"), ("bytespider", "bytespider"), ("amazonbot", "amazonbot"),
    ("meta-externalagent", "meta"), ("facebookexternalhit", "facebook"), ("youbot", "you.com"), ("duckassistbot", "duckduckgo"),
    ("duckduckbot", "duckduckgo"), ("cohere-ai", "cohere"), ("mistralai", "mistral"), ("yandex", "yandex"), ("ahrefsbot", "ahrefs"),
    ("semrushbot", "semrush"), ("linkedinbot", "linkedin"), ("whatsapp", "whatsapp"), ("telegrambot", "telegram"),
]


def _rastreador(ua):
    ua = (ua or "").lower()
    for marca, nome in RASTREADORES:
        if marca in ua:
            return nome
    return "bot" if re.search(r"bot|crawl|spider|slurp|fetch|preview", ua) else None


def _origem(referer, ua):
    r = _rastreador(ua)
    if r:
        return "rastreador:" + r
    host = ""
    try:
        host = (urlparse(referer or "").hostname or "").lower()
    except Exception:  # noqa: BLE001
        host = ""
    if not host:
        return "direto"
    if "google." in host:
        return "google"
    if any(x in host for x in ("chatgpt.com", "openai.com", "perplexity.ai", "claude.ai", "copilot.microsoft", "gemini.google", "you.com")):
        return "ia"
    if any(x in host for x in ("facebook.", "instagram.", "whatsapp.", "wa.me", "t.co", "twitter.", "x.com", "linkedin.", "l.facebook", "lm.facebook")):
        return "social"
    if "imobeasy.online" in host:
        return "direto"
    return "outro"


# ================================================================ as páginas
@blog_bp.route("/blog/")
@blog_bp.route("/blog")
@blog_bp.route("/blog/categoria/<categoria>")
@blog_bp.route("/blog/busca")
def pagina_lista(categoria=None):
    if categoria and categoria not in NOME_CATEGORIA:
        return _pagina("erro.html", status=404, cache=60, titulo="Categoria não encontrada", canonical=BLOG_URL + "/")
    q = (request.args.get("q") or "").strip()[:80] if request.path.endswith("/busca") else ""
    pagina = max(1, min(int(request.args.get("pagina") or 1) if str(request.args.get("pagina") or "1").isdigit() else 1, 200))
    try:
        d = _um("SELECT site_blog_lista(%s, %s, %s, %s) AS r", (categoria, q or None, POR_PAGINA, (pagina - 1) * POR_PAGINA)) or {}
    except Exception:  # noqa: BLE001
        d = {"total": 0, "artigos": [], "categorias": []}
    total = int(d.get("total") or 0)
    paginas = max(1, -(-total // POR_PAGINA))
    if categoria:
        canonical = _url_categoria(categoria) + ("?pagina=%d" % pagina if pagina > 1 else "")
        titulo = NOME_CATEGORIA[categoria] + " · Blog Imob Easy"
        descricao = {"sobre-nos": "Quem é a Imob Easy, como trabalhamos e o que mudou no mercado imobiliário de Manaus.",
                     "clientes": "Guias para quem vai alugar, comprar ou anunciar um imóvel em Manaus.",
                     "corretores": "Para corretores: a parceria de 50%, os grupos, a Nay e como fechar mais negócios.",
                     "locacao": "Imóveis para alugar em Manaus: os destaques do catálogo, bairro a bairro.",
                     "venda": "Imóveis à venda em Manaus: os destaques do catálogo, com valor e localização."}[categoria]
    elif q:
        canonical = BLOG_URL + "/busca?q=" + q
        titulo = 'Busca por "%s" · Blog Imob Easy' % q
        descricao = "Artigos do blog da Imob Easy sobre " + q
    else:
        canonical = BLOG_URL + "/" + ("?pagina=%d" % pagina if pagina > 1 else "")
        titulo = "Blog Imob Easy · Imóveis em Manaus, parceria 50% e dicas para alugar e comprar"
        descricao = ("O blog da Imob Easy: imóveis para alugar e comprar em Manaus, guias para clientes, a parceria de 50% para "
                     "corretores e os bastidores da imobiliária.")
    ld = [{"@context": "https://schema.org", "@type": "Blog", "name": "Blog Imob Easy", "url": BLOG_URL + "/",
           "description": descricao, "inLanguage": "pt-BR",
           "publisher": {"@type": "Organization", "name": "Imob Easy", "url": SITE_URL,
                         "logo": {"@type": "ImageObject", "url": SITE_URL + "/assets/img/logo.svg"}},
           "blogPost": [{"@type": "BlogPosting", "headline": a["titulo"], "url": _url_artigo(a["slug"]),
                         "datePublished": _iso(a.get("publicado_em")), "image": a.get("capa_url") or None}
                        for a in d.get("artigos", [])]}]
    return _pagina("index.html", titulo=titulo, descricao=descricao, canonical=canonical, categoria=categoria, busca=q,
                   artigos=d.get("artigos", []), categorias=d.get("categorias", []), total=total, pagina=pagina, paginas=paginas,
                   ld_json=[_ld(x) for x in ld])


@blog_bp.route("/blog/artigo/<slug>")
def pagina_artigo(slug):
    slug = re.sub(r"[^a-z0-9-]", "", (slug or "").lower())[:80]
    try:
        a = _um("SELECT site_blog_artigo(%s) AS r", (slug,))
    except Exception:  # noqa: BLE001
        a = None
    if not a:
        return _pagina("erro.html", status=404, cache=60, titulo="Artigo não encontrado", canonical=BLOG_URL + "/")
    # o robô (Google, GPTBot, ClaudeBot...) não roda JavaScript: a visita dele é contada aqui, no HTML que ele pediu
    r = _rastreador(request.headers.get("User-Agent"))
    if r:
        try:
            _um("SELECT site_blog_visita(%s, %s) AS r", (slug, "rastreador:" + r), escrita=True)
        except Exception:  # noqa: BLE001
            pass
    a["html"] = _md(a.get("corpo"))
    a["palavras"] = _palavras(a.get("corpo"))
    descricao = (a.get("resumo") or _texto_puro(a.get("corpo"))[:157].rsplit(" ", 1)[0] + "…")[:160]
    canonical = _url_artigo(a["slug"])
    capa = a.get("capa_url") or (a.get("imovel") or {}).get("capa") or SITE_URL + "/assets/img/hero-casal.jpg"
    org = {"@type": "Organization", "name": "Imob Easy", "url": SITE_URL,
           "logo": {"@type": "ImageObject", "url": SITE_URL + "/assets/img/logo.svg"}}
    post = {"@context": "https://schema.org", "@type": "BlogPosting", "mainEntityOfPage": canonical, "headline": a["titulo"][:110],
            "description": descricao, "image": [capa], "datePublished": _iso(a.get("publicado_em")),
            "dateModified": _iso(a.get("atualizado_em") or a.get("publicado_em")),
            "author": {"@type": "Organization", "name": a.get("autor") or "Equipe Imob Easy", "url": SITE_URL},
            "publisher": org, "articleSection": a.get("categoria_nome"), "inLanguage": "pt-BR", "wordCount": a["palavras"],
            "keywords": a.get("palavra_chave") or None, "isAccessibleForFree": True}
    im = a.get("imovel")
    if im:
        ofertas = []
        if im.get("valor_aluguel"):
            ofertas.append({"@type": "Offer", "price": im["valor_aluguel"], "priceCurrency": "BRL", "businessFunction": "http://purl.org/goodrelations/v1#LeaseOut", "url": im["url"]})
        if im.get("valor_venda"):
            ofertas.append({"@type": "Offer", "price": im["valor_venda"], "priceCurrency": "BRL", "businessFunction": "http://purl.org/goodrelations/v1#Sell", "url": im["url"]})
        post["about"] = {"@type": "RealEstateListing", "name": " · ".join(x for x in [im.get("tipo"), im.get("condominio"), im.get("bairro")] if x),
                         "url": im["url"], "image": im.get("capa"), "offers": ofertas or None,
                         "address": {"@type": "PostalAddress", "addressLocality": "Manaus", "addressRegion": "AM",
                                     "addressCountry": "BR", "streetAddress": im.get("bairro")}}
    lds = [post, {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "Blog", "item": BLOG_URL + "/"},
        {"@type": "ListItem", "position": 2, "name": a.get("categoria_nome"), "item": _url_categoria(a["categoria"])},
        {"@type": "ListItem", "position": 3, "name": a["titulo"], "item": canonical}]}]
    faq = [f for f in (a.get("faq") or []) if isinstance(f, dict) and (f.get("pergunta") or "").strip() and (f.get("resposta") or "").strip()]
    if faq:
        lds.append({"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
            {"@type": "Question", "name": f["pergunta"].strip(),
             "acceptedAnswer": {"@type": "Answer", "text": f["resposta"].strip()}} for f in faq]})
    a["faq"] = faq
    return _pagina("artigo.html", titulo=a["titulo"] + " · Blog Imob Easy", descricao=descricao, canonical=canonical, a=a, capa=capa,
                   ld_json=[_ld(x) for x in lds])


@blog_bp.route("/blog/newsletter")
def pagina_newsletter():
    return _pagina("newsletter.html", cache=600, titulo="Receba imóveis novos no WhatsApp · Blog Imob Easy",
                   descricao="Corretor: cadastre seu WhatsApp e receba o card de cada imóvel novo da Imob Easy, com parceria de 50%.",
                   canonical=BLOG_URL + "/newsletter", sair=request.args.get("sair") == "1")


def _todos_publicados():
    saida, offset = [], 0
    while True:
        d = _um("SELECT site_blog_lista(NULL, NULL, 50, %s) AS r", (offset,)) or {}
        lote = d.get("artigos") or []
        saida.extend(lote)
        offset += 50
        if len(lote) < 50 or offset > 5000:
            return saida


@blog_bp.route("/blog/sitemap.xml")
def sitemap():
    try:
        arts = _todos_publicados()
    except Exception:  # noqa: BLE001
        arts = []
    linhas = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">',
              "<url><loc>%s/</loc><changefreq>daily</changefreq><priority>0.8</priority></url>" % BLOG_URL]
    for c, _ in CATEGORIAS:
        linhas.append("<url><loc>%s</loc><changefreq>weekly</changefreq><priority>0.5</priority></url>" % _url_categoria(c))
    linhas.append("<url><loc>%s/newsletter</loc><changefreq>monthly</changefreq><priority>0.4</priority></url>" % BLOG_URL)
    for a in arts:
        img = ("<image:image><image:loc>%s</image:loc></image:image>" % html.escape(a["capa_url"])) if a.get("capa_url") else ""
        linhas.append("<url><loc>%s</loc><lastmod>%s</lastmod><changefreq>monthly</changefreq><priority>0.7</priority>%s</url>"
                      % (_url_artigo(a["slug"]), _iso(a.get("atualizado_em") or a.get("publicado_em"))[:10], img))
    linhas.append("</urlset>")
    r = Response("\n".join(linhas), mimetype="application/xml")
    r.headers["Cache-Control"] = "public, max-age=1800"
    return r


@blog_bp.route("/blog/feed.xml")
def feed():
    try:
        d = _um("SELECT site_blog_lista(NULL, NULL, 20, 0) AS r") or {}
    except Exception:  # noqa: BLE001
        d = {}
    itens = []
    for a in d.get("artigos") or []:
        itens.append("<item><title>%s</title><link>%s</link><guid isPermaLink=\"true\">%s</guid><pubDate>%s</pubDate><category>%s</category><description>%s</description></item>"
                     % (html.escape(a["titulo"]), _url_artigo(a["slug"]), _url_artigo(a["slug"]),
                        _rfc822(a.get("publicado_em")), html.escape(a.get("categoria_nome") or ""), html.escape(a.get("resumo") or "")))
    xml = ('<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Blog Imob Easy</title><link>' + BLOG_URL + "/</link>"
           "<description>Imóveis em Manaus, parceria 50% para corretores e dicas para alugar e comprar.</description><language>pt-BR</language>"
           + "".join(itens) + "</channel></rss>")
    r = Response(xml, mimetype="application/rss+xml")
    r.headers["Cache-Control"] = "public, max-age=1800"
    return r


def _rfc822(iso):
    try:
        d = dt.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        return d.strftime("%a, %d %b %Y %H:%M:%S %z")
    except Exception:  # noqa: BLE001
        return ""


@blog_bp.route("/blog/robots.txt")
def robots():
    # os robôs das IAs são bem-vindos de propósito (Pedro: "otimizado para o SEO de IA")
    txt = "\n".join(["User-agent: *", "Allow: /", "", "User-agent: GPTBot", "Allow: /", "User-agent: OAI-SearchBot", "Allow: /",
                     "User-agent: ChatGPT-User", "Allow: /", "User-agent: ClaudeBot", "Allow: /", "User-agent: anthropic-ai", "Allow: /",
                     "User-agent: PerplexityBot", "Allow: /", "User-agent: Google-Extended", "Allow: /", "User-agent: Applebot-Extended", "Allow: /",
                     "", "Sitemap: %s/sitemap.xml" % BLOG_URL, ""])
    r = Response(txt, mimetype="text/plain; charset=utf-8")
    r.headers["Cache-Control"] = "public, max-age=86400"
    return r


@blog_bp.route("/blog/llms.txt")
def llms():
    """O resumo do blog para as IAs (a convenção llms.txt): o que é, e a lista dos artigos com uma linha cada."""
    try:
        arts = _todos_publicados()
    except Exception:  # noqa: BLE001
        arts = []
    linhas = ["# Blog Imob Easy", "",
              "> A Imob Easy é uma imobiliária de Manaus (AM, Brasil) que aluga, vende e administra imóveis, com atendimento "
              "pela Nay (assistente no WhatsApp) e parceria de 50% da comissão com corretores. Site: " + SITE_URL + ". Blog: " + BLOG_URL + ".",
              "", "Categorias: " + ", ".join(n for _, n in CATEGORIAS) + ".", "",
              "## Artigos"]
    for a in arts:
        linhas.append("- [%s](%s): %s" % (a["titulo"], _url_artigo(a["slug"]), (a.get("resumo") or a.get("categoria_nome") or "").strip()))
    linhas += ["", "## Imóveis", "- [Comprar em Manaus](%s/comprar.html)" % SITE_URL, "- [Alugar em Manaus](%s/alugar.html)" % SITE_URL,
               "- [Mapa dos imóveis](%s/imoveis.html)" % SITE_URL, "- Página de cada imóvel: %s/imovel/<código>" % SITE_URL,
               "", "## Para corretores", "- [Receber imóveis novos no WhatsApp](%s/newsletter)" % BLOG_URL, ""]
    r = Response("\n".join(linhas), mimetype="text/plain; charset=utf-8")
    r.headers["Cache-Control"] = "public, max-age=3600"
    return r


# ================================================================ a API pública
@blog_bp.route("/api/blog/recentes")
def api_recentes():
    n = max(1, min(int(request.args.get("n") or 3) if str(request.args.get("n") or "3").isdigit() else 3, 12))
    d = _um("SELECT site_blog_lista(NULL, NULL, %s, 0) AS r", (n,)) or {}
    r = jsonify({"artigos": [dict(a, url=_url_artigo(a["slug"])) for a in d.get("artigos") or []], "blog": BLOG_URL})
    r.headers["Cache-Control"] = "public, max-age=300"
    return r


@blog_bp.route("/api/blog/lista")
def api_lista():
    cat = request.args.get("categoria") or None
    if cat and cat not in NOME_CATEGORIA:
        return jsonify({"erro": "categoria desconhecida"}), 400
    pagina = max(1, int(request.args.get("pagina") or 1) if str(request.args.get("pagina") or "1").isdigit() else 1)
    d = _um("SELECT site_blog_lista(%s, %s, %s, %s) AS r", (cat, (request.args.get("q") or "").strip()[:80] or None, POR_PAGINA, (pagina - 1) * POR_PAGINA)) or {}
    for a in d.get("artigos") or []:
        a["url"] = _url_artigo(a["slug"])
    r = jsonify(d)
    r.headers["Cache-Control"] = "public, max-age=120"
    return r


@blog_bp.route("/api/blog/artigo/<slug>")
def api_artigo(slug):
    a = _um("SELECT site_blog_artigo(%s) AS r", (re.sub(r"[^a-z0-9-]", "", slug.lower())[:80],))
    if not a:
        return jsonify({"erro": "não encontrado"}), 404
    a["html"] = _md(a.get("corpo"))
    a["url"] = _url_artigo(a["slug"])
    r = jsonify(a)
    r.headers["Cache-Control"] = "public, max-age=300"
    return r


@blog_bp.route("/api/blog/visita", methods=["POST"])
def api_visita():
    """O contador de gente (o navegador manda ao abrir o artigo). O robô é contado no HTML, lá em cima."""
    b = request.get_json(silent=True) or {}
    slug = re.sub(r"[^a-z0-9-]", "", str(b.get("slug") or "").lower())[:80]
    if not slug:
        return jsonify({"ok": False}), 400
    origem = _origem(str(b.get("referer") or request.headers.get("Referer") or ""), request.headers.get("User-Agent"))
    if origem.startswith("rastreador:"):
        return jsonify({"ok": True, "origem": origem})          # robô rodando JS: já foi contado no HTML
    try:
        ok = _um("SELECT site_blog_visita(%s, %s) AS r", (slug, origem), escrita=True)
    except Exception:  # noqa: BLE001
        ok = False
    return jsonify({"ok": bool(ok), "origem": origem})


_ULTIMOS_CADASTROS = {}     # ip -> [instantes]: 5 cadastros por hora por IP, para a página não virar porta de spam


def _ip():
    return (request.headers.get("X-Forwarded-For") or request.remote_addr or "?").split(",")[0].strip()


def _pode_cadastrar(ip):
    agora = time.time()
    lista = [t for t in _ULTIMOS_CADASTROS.get(ip, []) if agora - t < 3600]
    _ULTIMOS_CADASTROS[ip] = lista
    if len(lista) >= 5:
        return False
    lista.append(agora)
    return True


@blog_bp.route("/api/blog/newsletter", methods=["POST"])
def api_newsletter():
    b = request.get_json(silent=True) or {}
    if not _pode_cadastrar(_ip()):
        return jsonify({"ok": False, "erro": "Muitos cadastros seguidos daqui. Tente de novo mais tarde."}), 429
    if str(b.get("site") or "").strip():          # o campo escondido que só robô preenche
        return jsonify({"ok": True, "novo": False})
    try:
        r = _um("SELECT site_blog_newsletter_cadastrar(%s, %s, %s) AS r",
                (str(b.get("nome") or "")[:80], str(b.get("telefone") or "")[:30], str(b.get("creci") or "")[:30]), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não consegui cadastrar agora (%s)." % exc.__class__.__name__}), 500
    return jsonify(r), (200 if r.get("ok") else 400)


@blog_bp.route("/api/blog/newsletter/sair", methods=["POST"])
def api_newsletter_sair():
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_blog_newsletter_sair(%s) AS r", (str(b.get("telefone") or "")[:30],), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não consegui agora (%s)." % exc.__class__.__name__}), 500
    return jsonify(r)


# ================================================================ o admin
def _negado():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


@blog_bp.route("/admin/api/blog/artigos")
def admin_artigos():
    if not _admin_autenticado():
        return _negado()
    return jsonify({"artigos": _um("SELECT site_blog_admin_lista() AS r", escrita=True) or [], "blog": BLOG_URL, "categorias": CATEGORIAS})


@blog_bp.route("/admin/api/blog/artigos/<int:aid>")
def admin_artigo(aid):
    if not _admin_autenticado():
        return _negado()
    a = _um("SELECT site_blog_admin_artigo(%s) AS r", (aid,), escrita=True)
    if not a:
        return jsonify({"erro": "não encontrado"}), 404
    a["html"] = _md(a.get("corpo"))
    a["url"] = _url_artigo(a["slug"])
    return jsonify(a)


@blog_bp.route("/admin/api/blog/artigos", methods=["POST"])
def admin_salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    quem = _quem()
    try:
        r = _um("SELECT site_blog_salvar(%s::jsonb, %s) AS r", (json.dumps(b, ensure_ascii=False), quem), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "Não salvou: %s" % str(exc).splitlines()[0][:200]}), 500
    if r.get("ok"):
        r["url"] = _url_artigo(r["slug"])
    return jsonify(r), (200 if r.get("ok") else 422)


@blog_bp.route("/admin/api/blog/artigos/<int:aid>", methods=["DELETE"])
def admin_apagar(aid):
    if not _admin_autenticado():
        return _negado()
    return jsonify(_um("SELECT site_blog_apagar(%s) AS r", (aid,), escrita=True) or {"ok": False})


@blog_bp.route("/admin/api/blog/previa", methods=["POST"])
def admin_previa():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    corpo = str(b.get("corpo") or "")[:200000]
    return jsonify({"html": _md(corpo), "palavras": _palavras(corpo)})


@blog_bp.route("/admin/api/blog/imovel/<int:codigo>")
def admin_imovel(codigo):
    """O imóvel do post: o card (se está no ar) e, senão, o básico do cadastro com o aviso."""
    if not _admin_autenticado():
        return _negado()
    card = _um("SELECT site_blog_card_imovel(%s) AS r", (codigo,), escrita=True)
    if card:
        return jsonify(dict(card, no_ar=True))
    c = _conn(True)
    try:
        with c.cursor() as cur:
            cur.execute("SELECT codigo, tipo, condominio_nome, bairro, status, valor_venda, valor_aluguel, e_parceiro FROM imoveis WHERE codigo = %s", (codigo,))
            l = cur.fetchone()
    finally:
        c.close()
    if not l:
        return jsonify({"erro": "o imóvel %d não existe no cadastro" % codigo}), 404
    motivo = "é de parceiro (não vai ao blog)" if l["e_parceiro"] else ("está %s" % (l["status"] or "sem situação")) if l["status"] != "Disponível" else "está fora do site"
    return jsonify({"codigo": l["codigo"], "tipo": l["tipo"], "condominio": l["condominio_nome"], "bairro": l["bairro"],
                    "valor_venda": l["valor_venda"], "valor_aluguel": l["valor_aluguel"], "no_ar": False, "motivo": motivo})


@blog_bp.route("/admin/api/blog/metricas")
def admin_metricas():
    if not _admin_autenticado():
        return _negado()
    de, ate = request.args.get("de") or None, request.args.get("ate") or None
    for v in (de, ate):
        if v and not re.match(r"^\d{4}-\d{2}-\d{2}$", v):
            return jsonify({"erro": "data inválida"}), 400
    return jsonify(_um("SELECT site_blog_metricas(%s::date, %s::date) AS r", (de, ate), escrita=True) or {})


@blog_bp.route("/admin/api/blog/newsletter")
def admin_newsletter():
    if not _admin_autenticado():
        return _negado()
    return jsonify(_um("SELECT site_blog_newsletter_lista() AS r", escrita=True) or {})


@blog_bp.route("/admin/api/blog/newsletter/sair", methods=["POST"])
def admin_newsletter_sair():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    return jsonify(_um("SELECT site_blog_newsletter_sair(%s) AS r", (str(b.get("telefone") or "")[:30],), escrita=True) or {"ok": False})


@blog_bp.route("/admin/api/blog/imagem", methods=["POST"])
def admin_imagem():
    """A capa (ou uma imagem do texto): vai para a pasta pública das fotos (fotos-captacao/blog/AAAAMM/), reduzida."""
    if not _admin_autenticado():
        return _negado()
    f = request.files.get("arquivo")
    if not f:
        return jsonify({"erro": "mande o arquivo no campo 'arquivo'"}), 400
    conteudo = f.read(IMAGEM_MAXIMA + 1)
    if len(conteudo) > IMAGEM_MAXIMA:
        return jsonify({"erro": "imagem acima de 15 MB"}), 413
    try:
        from PIL import Image, ImageOps
        img = Image.open(io.BytesIO(conteudo))
        img = ImageOps.exif_transpose(img)
        if img.mode in ("RGBA", "P", "LA"):
            fundo = Image.new("RGB", img.size, (255, 255, 255))
            fundo.paste(img.convert("RGBA"), mask=img.convert("RGBA").split()[-1])
            img = fundo
        elif img.mode != "RGB":
            img = img.convert("RGB")
        img.thumbnail((LADO_MAXIMO, LADO_MAXIMO), Image.LANCZOS)
        largura, altura = img.size
        saida = io.BytesIO()
        img.save(saida, "JPEG", quality=84, optimize=True, progressive=True)
        dados, ext = saida.getvalue(), "jpg"
    except Exception:  # noqa: BLE001  -- não é imagem que o Pillow abra: recusa
        return jsonify({"erro": "não consegui ler a imagem (use JPG, PNG ou WebP)"}), 415
    pasta = os.path.join(PASTA_FOTOS, "blog", dt.datetime.now().strftime("%Y%m"))
    os.makedirs(pasta, exist_ok=True)
    nome = uuid.uuid4().hex[:16] + "." + ext
    with open(os.path.join(pasta, nome), "wb") as arq:
        arq.write(dados)
    return jsonify({"ok": True, "url": "%s/blog/%s/%s" % (URL_FOTOS, dt.datetime.now().strftime("%Y%m"), nome),
                    "largura": largura, "altura": altura, "bytes": len(dados)})


def _quem():
    try:
        return _usuario_admin() or "admin"
    except Exception:  # noqa: BLE001
        return "admin"


# ====================================================================== IMPORTAR POSTS + IMAGENS + AGENDA (412, 19/10/2026)
# Pedro: "peguei uma lista de post para nosso blog ... programa lá 2 por dia ... pesquise a imagem que ele sugere aí no
# formato certinho ... faz uma ferramenta interna só para isso ... e lá no blog põe uma agenda de planejamento".
#
# O arquivo é o .md que a IA devolve com o prompt do blog (Arquivos/prompt-posts-do-blog.md): blocos "## POST n de N",
# os campos num ```...``` (TÍTULO, SLUG, CATEGORIA, TIPO, PALAVRA-CHAVE, RESUMO, CAPA (buscar...), CAPA (alt)), o corpo
# num ````markdown````, o FAQ em P:/R: e um SCHEMA que ignoramos (a página já gera o JSON-LD). Dentro do corpo, o marcador
# [IMAGEM | buscar: "..." | alt: "..." | legenda: "..."] vira uma imagem do texto.
#
# As imagens: Pexels (oficial, se PEXELS_API_KEY estiver no ambiente da API), senão Openverse (CC comercial) e
# Wikimedia Commons, os dois sem chave. A capa é cortada em 16:9 (1600x900), a do texto fica em até 1200 de largura.
import urllib.request
import urllib.parse

CAPA_LARGURA, CAPA_ALTURA = 1600, 900
TEXTO_LARGURA = 1200
_UA = "Mozilla/5.0 (compatible; ImobEasyBlog/1.0; +https://blog.imobeasy.online)"


def _normalizar_chave(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\(.*?\)", "", s)            # "TÍTULO (H1)" -> "titulo"
    return re.sub(r"[^a-z]", "", s)


_CAMPOS = {"titulo": "titulo", "slug": "slug", "urlfinal": None, "categoria": "categoria", "tipo": "tipo", "codigo": "codigo",
           "codigodoimovel": "codigo", "bairro": "bairro", "palavrachave": "palavra_chave", "palavrassecundarias": "palavras_secundarias",
           "resumo": "resumo", "capa": "capa_busca", "capaalt": "capa_alt", "ctadomeio": None, "ctafinal": None}


def _parse_posts(texto):
    """Divide o .md em posts e lê os campos. Devolve [{campos..., imagens_pedidas: [{marcador, busca, alt, legenda}], avisos: []}]."""
    texto = (texto or "").replace("\r\n", "\n").lstrip("\ufeff")
    partes = re.split(r"^##\s+POST\s+\d+.*$", texto, flags=re.M | re.I)
    if len(partes) <= 1:
        partes = re.split(r"^---\s*$", texto, flags=re.M)
    posts = []
    for bloco in partes[1:] if len(partes) > 1 else partes:
        if "CORPO" not in bloco.upper() or "TÍTULO" not in bloco.upper() and "TITULO" not in bloco.upper():
            continue
        p = {"faq": [], "imagens_pedidas": [], "avisos": []}
        # 1. os campos: o primeiro bloco ``` ... ``` com "CHAVE: valor" por linha
        m = re.search(r"```[^\n]*\n(.*?)```", bloco, flags=re.S)
        if m:
            for linha in m.group(1).split("\n"):
                mm = re.match(r"^\s*([^:]{2,60}?)\s*:\s*(.*)$", linha)
                if not mm:
                    continue
                bruta = mm.group(1).strip().lower()
                k = _normalizar_chave(mm.group(1))
                if bruta.startswith("capa"):
                    campo = "capa_alt" if re.search(r"\balt\b", bruta) else "capa_busca"
                else:
                    campo = _CAMPOS.get(k)
                if campo:
                    p[campo] = mm.group(2).strip()
        # 2. o corpo: ````markdown ... ```` (4 crases) ou, sem ele, ```markdown ... ```
        m = re.search(r"````(?:markdown)?\s*\n(.*?)\n````", bloco, flags=re.S)
        if not m:
            m = re.search(r"\*\*CORPO[^\n]*\n+```(?:markdown)?\s*\n(.*?)\n```", bloco, flags=re.S)
        p["corpo"] = (m.group(1).strip() if m else "")
        if not p["corpo"]:
            p["avisos"].append("não achei o corpo em markdown")
        # 3. o FAQ: linhas P:/R:
        m = re.search(r"\*\*FAQ[^\n]*\n+```\s*\n(.*?)\n```", bloco, flags=re.S)
        if m:
            perg = None
            for linha in m.group(1).split("\n"):
                mm = re.match(r"^\s*(P|R)\s*:\s*(.*)$", linha)
                if not mm:
                    continue
                if mm.group(1) == "P":
                    perg = mm.group(2).strip()
                elif perg:
                    p["faq"].append({"pergunta": perg, "resposta": mm.group(2).strip()})
                    perg = None
        # 4. as imagens do texto
        for mm in re.finditer(r"\[IMAGEM\s*\|([^\]]*)\]", p["corpo"]):
            partes_i = [x.strip() for x in mm.group(1).split("|")]
            item = {"marcador": mm.group(0), "busca": "", "alt": "", "legenda": ""}
            for x in partes_i:
                mk = re.match(r"^(buscar|busca|alt|legenda)\s*:\s*\"?(.*?)\"?$", x, flags=re.I)
                if mk:
                    item["busca" if mk.group(1).lower().startswith("busca") else mk.group(1).lower()] = mk.group(2).strip()
            p["imagens_pedidas"].append(item)
        p["titulo"] = (p.get("titulo") or "").strip()
        p["categoria"] = (p.get("categoria") or "").strip().lower()
        p["tipo"] = (p.get("tipo") or "post").strip().lower()
        if not p["titulo"]:
            p["avisos"].append("sem título")
        if p["categoria"] not in dict(CATEGORIAS):
            p["avisos"].append("categoria desconhecida: %s" % (p["categoria"] or "(vazia)"))
        if len(p["faq"]) < 2:
            p["avisos"].append("FAQ com menos de 2 perguntas")
        posts.append(p)
    return posts


def _http_json(url, cab=None, tempo=20):
    req = urllib.request.Request(url, headers=dict({"User-Agent": _UA, "Accept": "application/json"}, **(cab or {})))
    with urllib.request.urlopen(req, timeout=tempo) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def _buscar_imagens(q, n=8, orientacao="landscape"):
    """Candidatas para uma busca: [{url, thumb, largura, altura, fonte, credito, licenca, pagina}]. Pexels > Openverse > Wikimedia."""
    q = (q or "").strip()
    if not q:
        return [], "sem busca"
    saida, fontes = [], []
    chave = os.environ.get("PEXELS_API_KEY", "").strip()
    if chave:
        try:
            d = _http_json("https://api.pexels.com/v1/search?" + urllib.parse.urlencode({"query": q, "per_page": n, "orientation": orientacao}), {"Authorization": chave})
            for f in d.get("photos") or []:
                saida.append({"url": f["src"].get("large2x") or f["src"].get("original"), "thumb": f["src"].get("medium"), "largura": f.get("width"), "altura": f.get("height"),
                              "fonte": "pexels", "credito": "Foto de %s (Pexels)" % f.get("photographer", ""), "licenca": "Pexels", "pagina": f.get("url")})
            fontes.append("pexels")
        except Exception as exc:  # noqa: BLE001
            fontes.append("pexels: %s" % str(exc)[:80])
    if len(saida) < 3:
        try:
            d = _http_json("https://api.openverse.org/v1/images/?" + urllib.parse.urlencode({"q": q, "license_type": "commercial", "page_size": max(n, 12)}))
            for f in d.get("results") or []:
                w, h = int(f.get("width") or 0), int(f.get("height") or 0)
                if w < 1000 or (orientacao == "landscape" and h and w < h):
                    continue
                saida.append({"url": f.get("url"), "thumb": f.get("thumbnail") or f.get("url"), "largura": w, "altura": h, "fonte": "openverse/" + str(f.get("source") or ""),
                              "credito": "%s (%s, %s)" % (f.get("creator") or "autor não informado", f.get("source") or "Openverse", (f.get("license") or "").upper()),
                              "licenca": (f.get("license") or "").upper(), "pagina": f.get("foreign_landing_url")})
            fontes.append("openverse")
        except Exception as exc:  # noqa: BLE001
            fontes.append("openverse: %s" % str(exc)[:80])
    if len(saida) < 3:
        try:
            d = _http_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
                "action": "query", "format": "json", "generator": "search", "gsrsearch": "filetype:bitmap " + q, "gsrnamespace": 6, "gsrlimit": max(n, 10),
                "prop": "imageinfo", "iiprop": "url|size|extmetadata", "iiurlwidth": 1600}))
            for pg in (d.get("query") or {}).get("pages", {}).values():
                ii = (pg.get("imageinfo") or [{}])[0]
                w, h = int(ii.get("width") or 0), int(ii.get("height") or 0)
                if w < 1000 or (orientacao == "landscape" and h and w < h):
                    continue
                meta = ii.get("extmetadata") or {}
                autor = re.sub(r"<[^>]+>", "", (meta.get("Artist") or {}).get("value", "") or "")[:60]
                lic = (meta.get("LicenseShortName") or {}).get("value", "")
                saida.append({"url": ii.get("thumburl") or ii.get("url"), "thumb": ii.get("thumburl") or ii.get("url"), "largura": w, "altura": h, "fonte": "wikimedia",
                              "credito": "%s (Wikimedia Commons, %s)" % (autor or "autor não informado", lic), "licenca": lic, "pagina": ii.get("descriptionurl")})
            fontes.append("wikimedia")
        except Exception as exc:  # noqa: BLE001
            fontes.append("wikimedia: %s" % str(exc)[:80])
    return saida[:n], ", ".join(fontes)


def _baixar_imagem(url):
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read(IMAGEM_MAXIMA + 1)


def _guardar_imagem(conteudo, capa=False):
    """Reduz e grava na pasta pública (fotos-captacao/blog/AAAAMM/). Capa: corte 16:9 em 1600x900; texto: até 1200 de largura."""
    from PIL import Image, ImageOps
    img = Image.open(io.BytesIO(conteudo))
    img = ImageOps.exif_transpose(img)
    if img.mode in ("RGBA", "P", "LA"):
        fundo = Image.new("RGB", img.size, (255, 255, 255))
        fundo.paste(img.convert("RGBA"), mask=img.convert("RGBA").split()[-1])
        img = fundo
    elif img.mode != "RGB":
        img = img.convert("RGB")
    if capa:
        img = ImageOps.fit(img, (CAPA_LARGURA, CAPA_ALTURA), Image.LANCZOS, centering=(0.5, 0.45))
    else:
        img.thumbnail((TEXTO_LARGURA, TEXTO_LARGURA * 3), Image.LANCZOS)
    saida = io.BytesIO()
    img.save(saida, "JPEG", quality=84, optimize=True, progressive=True)
    mes = dt.datetime.now().strftime("%Y%m")
    pasta = os.path.join(PASTA_FOTOS, "blog", mes)
    os.makedirs(pasta, exist_ok=True)
    nome = uuid.uuid4().hex[:16] + ".jpg"
    with open(os.path.join(pasta, nome), "wb") as arq:
        arq.write(saida.getvalue())
    return "%s/blog/%s/%s" % (URL_FOTOS, mes, nome), img.size


@blog_bp.route("/admin/api/blog/importar/previa", methods=["POST"])
def admin_importar_previa():
    """Lê o .md e devolve os posts com os campos e, para cada busca de imagem, as candidatas."""
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    texto = str(b.get("texto") or "")
    if not texto.strip() and request.files.get("arquivo"):
        texto = request.files["arquivo"].read(5_000_000).decode("utf-8", "replace")
    posts = _parse_posts(texto)
    if not posts:
        return jsonify({"ok": False, "erro": "não achei nenhum post no arquivo (esperava blocos '## POST n de N' com CORPO em markdown)"}), 422
    com_imagens = b.get("imagens", True)
    for p in posts:
        p["capa_candidatas"], p["capa_fontes"] = (_buscar_imagens(p.get("capa_busca"), 8) if com_imagens else ([], ""))
        for im in p["imagens_pedidas"]:
            im["candidatas"], im["fontes"] = (_buscar_imagens(im.get("busca"), 6) if com_imagens else ([], ""))
    return jsonify({"ok": True, "posts": posts, "pexels": bool(os.environ.get("PEXELS_API_KEY", "").strip())})


@blog_bp.route("/admin/api/blog/imagens")
def admin_imagens_buscar():
    if not _admin_autenticado():
        return _negado()
    q = (request.args.get("q") or "").strip()[:120]
    cands, fontes = _buscar_imagens(q, min(max(int(request.args.get("n") or 8), 1), 20), request.args.get("orientacao") or "landscape")
    return jsonify({"ok": True, "candidatas": cands, "fontes": fontes, "pexels": bool(os.environ.get("PEXELS_API_KEY", "").strip())})


@blog_bp.route("/admin/api/blog/imagens/guardar", methods=["POST"])
def admin_imagem_guardar():
    """Baixa uma imagem escolhida (capa ou do texto) e grava no formato do blog; devolve a URL nossa."""
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    url = str(b.get("url") or "").strip()
    if not url.startswith("http"):
        return jsonify({"ok": False, "erro": "sem a URL da imagem"}), 422
    try:
        nossa, tam = _guardar_imagem(_baixar_imagem(url), capa=bool(b.get("capa", True)))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "não consegui baixar ou converter: %s" % str(exc)[:160]}), 502
    return jsonify({"ok": True, "url": nossa, "largura": tam[0], "altura": tam[1]})


# ---- Unsplash (Pedro, 22/10/2026: "API Unsplash ... prepara uma tela rápida lá no blog para eu passar nessa autorização").
# As regras de produção deles: a foto é mostrada direto da URL do Unsplash (hotlink, nunca baixada para cá), usar a foto
# dispara o download_location deles, e o crédito leva o nome do fotógrafo com link para o perfil e link para o Unsplash,
# com utm_source = o nome do aplicativo lá ("Pvlwordpress"). A chave mora no .env do servidor (UNSPLASH_ACCESS_KEY).
UNSPLASH_APP = "pvlwordpress"
UNSPLASH_UTM = "utm_source=%s&utm_medium=referral" % UNSPLASH_APP


def _unsplash_cab():
    return {"Authorization": "Client-ID " + os.environ.get("UNSPLASH_ACCESS_KEY", "").strip(), "Accept-Version": "v1"}


def _com_utm(url):
    return (url or "") + ("&" if "?" in (url or "") else "?") + UNSPLASH_UTM if url else ""


@blog_bp.route("/admin/api/blog/unsplash")
def admin_unsplash_buscar():
    if not _admin_autenticado():
        return _negado()
    if not os.environ.get("UNSPLASH_ACCESS_KEY", "").strip():
        return jsonify({"ok": False, "erro": "falta a chave UNSPLASH_ACCESS_KEY no servidor"}), 503
    q = (request.args.get("q") or "").strip()[:120]
    if not q:
        return jsonify({"ok": True, "fotos": [], "total": 0})
    pagina = min(max(int(request.args.get("pagina") or 1), 1), 50)
    params = {"query": q, "page": pagina, "per_page": 24, "content_filter": "high"}
    if request.args.get("orientacao") in ("landscape", "portrait", "squarish"):
        params["orientation"] = request.args["orientacao"]
    try:
        d = _http_json("https://api.unsplash.com/search/photos?" + urllib.parse.urlencode(params), _unsplash_cab())
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "o Unsplash não respondeu: %s" % str(exc)[:160]}), 502
    fotos = []
    for f in d.get("results") or []:
        u, urls, links = f.get("user") or {}, f.get("urls") or {}, f.get("links") or {}
        fotos.append({"id": f.get("id"), "alt": f.get("alt_description") or f.get("description") or "",
                      "url": urls.get("regular"), "thumb": urls.get("small"), "largura": f.get("width"), "altura": f.get("height"),
                      "cor": f.get("color"), "autor": u.get("name") or u.get("username") or "",
                      "perfil": _com_utm((u.get("links") or {}).get("html")), "pagina": _com_utm(links.get("html")),
                      "unsplash": "https://unsplash.com/?" + UNSPLASH_UTM, "download": links.get("download_location")})
    return jsonify({"ok": True, "fotos": fotos, "total": d.get("total", 0), "paginas": d.get("total_pages", 0)})


@blog_bp.route("/admin/api/blog/unsplash/usar", methods=["POST"])
def admin_unsplash_usar():
    """A foto foi usada: avisa o Unsplash pelo download_location dela (regra deles; não baixa a imagem)."""
    if not _admin_autenticado():
        return _negado()
    dl = str((request.get_json(silent=True) or {}).get("download") or "")
    if not dl.startswith("https://api.unsplash.com/photos/"):
        return jsonify({"ok": False, "erro": "download_location inválido"}), 422
    try:
        _http_json(dl, _unsplash_cab())
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": "o Unsplash não respondeu: %s" % str(exc)[:160]}), 502
    return jsonify({"ok": True})


def _montar_corpo(p, escolhas):
    """Troca cada [IMAGEM | ...] pela imagem escolhida (markdown + legenda em itálico) ou tira o marcador."""
    corpo = p.get("corpo") or ""
    for im in p.get("imagens_pedidas") or []:
        esc = escolhas.get(im["marcador"]) or {}
        if esc.get("url"):
            trecho = "![%s](%s)" % ((im.get("alt") or "").replace("]", ""), esc["url"])
            legenda = (im.get("legenda") or "").strip()
            credito = (esc.get("credito") or "").strip()
            if legenda or credito:
                trecho += "\n\n*%s*" % " · ".join(x for x in [legenda, credito] if x)
            corpo = corpo.replace(im["marcador"], trecho)
        else:
            corpo = corpo.replace(im["marcador"], "")
    return re.sub(r"\n{3,}", "\n\n", corpo).strip()


@blog_bp.route("/admin/api/blog/importar/criar", methods=["POST"])
def admin_importar_criar():
    """Cria os artigos: {posts: [{...campos do post, agendado_para, capa: {url, credito} | null, imagens: {marcador: {url, credito}}, seo_nota}]}.
    Baixa e converte as imagens escolhidas; agenda (publicado=false + agendado_para) ou publica se a hora já passou."""
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    posts = b.get("posts") or []
    if not isinstance(posts, list) or not posts:
        return jsonify({"ok": False, "erro": "mande os posts"}), 422
    quem = _quem()
    saida = []
    for p in posts:
        item = {"titulo": p.get("titulo"), "ok": False}
        try:
            capa_url, capa_credito = None, ""
            capa = p.get("capa") or {}
            if capa.get("url"):
                if str(capa["url"]).startswith(URL_FOTOS):
                    capa_url = capa["url"]
                else:
                    capa_url, _ = _guardar_imagem(_baixar_imagem(capa["url"]), capa=True)
                capa_credito = capa.get("credito") or ""
            escolhas = {}
            for marcador, esc in (p.get("imagens") or {}).items():
                if not esc or not esc.get("url"):
                    continue
                url = esc["url"] if str(esc["url"]).startswith(URL_FOTOS) else _guardar_imagem(_baixar_imagem(esc["url"]), capa=False)[0]
                escolhas[marcador] = {"url": url, "credito": esc.get("credito") or ""}
            corpo = _montar_corpo(p, escolhas)
            if capa_credito and capa_credito not in corpo:
                corpo = corpo.rstrip() + "\n\n*Foto da capa: %s*" % capa_credito
            dados = {"titulo": p.get("titulo"), "slug": p.get("slug"), "resumo": p.get("resumo"), "categoria": p.get("categoria"), "tipo": p.get("tipo") or "post",
                     "codigo": p.get("codigo"), "bairro": p.get("bairro"), "corpo": corpo, "capa_url": capa_url, "capa_alt": p.get("capa_alt"),
                     "palavra_chave": p.get("palavra_chave"), "faq": p.get("faq") or [], "publicado": bool(p.get("publicado")),
                     "agendado_para": p.get("agendado_para"), "seo_nota": p.get("seo_nota")}
            r = _um("SELECT site_blog_salvar(%s::jsonb, %s) AS r", (json.dumps(dados, ensure_ascii=False), quem), escrita=True) or {}
            item.update(r)
            if r.get("ok"):
                item["url"] = _url_artigo(r["slug"])
                item["capa_url"] = capa_url
        except Exception as exc:  # noqa: BLE001
            item["erro"] = str(exc).splitlines()[0][:200]
        saida.append(item)
    return jsonify({"ok": all(x.get("ok") for x in saida), "resultados": saida})
