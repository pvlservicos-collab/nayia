"""Monta imob-easy/imovel.html a partir do desenho do Pedro (Novateladeverimovel.html).

O desenho é um arquivo só, com dados de exemplo dentro do <script>. A página de verdade usa a
MESMA marcação e o MESMO CSS, e troca o script de exemplo por assets/js/imovel-publico.js, que
busca o imóvel na API. Mudou o desenho? Rode de novo:

    python scripts/montar_pagina_do_imovel.py

e publique: ./scripts/nay site imovel.html assets/js/imovel-publico.js
"""
import io
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DESENHO = RAIZ / "Novateladeverimovel.html"
SAIDA = RAIZ / "imob-easy" / "imovel.html"

html = io.open(DESENHO, encoding="utf-8").read()

# 1. o script de exemplo (o último <script> sem src) sai; entram a config e o script de verdade
inicio = html.rindex("<script>")
fim = html.index("</script>", inicio) + len("</script>")
html = html[:inicio] + ('<script src="/assets/js/config.js"></script>\n'
                        '<script src="/assets/js/imovel-publico.js?v=20261006-mapa"></script>') + html[fim:]

# 2. o título de exemplo vira neutro (o script põe o nome do imóvel quando carrega)
html = re.sub(r"<title>.*?</title>", "<title>Imóvel · Imob Easy</title>", html, count=1, flags=re.S)

# 3. o logo aponta para a raiz do site, e a página diz de onde veio
html = html.replace('href="https://imobeasy.online"', 'href="/"')
html = html.replace("<head>", "<head>\n<!-- Gerado por scripts/montar_pagina_do_imovel.py a partir de Novateladeverimovel.html. "
                    "Não edite aqui: edite o desenho e gere de novo. -->", 1)

assert "IMOVEL={" not in html and "fakePhoto" not in html, "sobrou dado de exemplo do desenho"
for obrigatorio in ('id="fic"', 'id="stage"', 'id="thumbs"', 'id="priceCard"', 'id="priceMobile"', 'id="caracB"', 'id="oqtB"',
                    'id="valB"', 'id="locB"', 'id="nav"', 'id="sendCard"', 'id="phone1"', 'id="phone2"', 'id="err1"', 'id="err2"',
                    'id="dock"', 'id="dockBtn"', 'id="badge"', 'id="dockSub"', 'id="items"', 'id="sendListBtn"', 'id="toast"',
                    'id="prev"', 'id="next"', 'id="mainImg"', 'id="count"', 'class="mbar"'):
    assert obrigatorio in html, f"o desenho não tem mais {obrigatorio}: o script da página precisa dele"

io.open(SAIDA, "w", encoding="utf-8", newline="\n").write(html)
print(f"{SAIDA.relative_to(RAIZ)}: {len(html.splitlines())} linhas")
