"""Monta imob-easy/imoveis.html a partir do desenho do Pedro (Telaenviarmovel.html).

É a tela /imoveis: o corretor acha os imóveis no mapa ou na lista e se envia pelo WhatsApp.
O desenho é um arquivo só, com dados de exemplo e um mapa ilustrativo dentro do <script>. A
página de verdade usa a MESMA marcação e o MESMO CSS, e troca o script de exemplo por
assets/js/imoveis-enviar.js (imóveis da API, mapa de verdade, envio pela Nay). Mudou o
desenho? Rode de novo:

    python scripts/montar_pagina_de_enviar.py

e publique: ./scripts/nay site imoveis.html assets/js/imoveis-enviar.js
"""
import io
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DESENHO = RAIZ / "Telaenviarmovel.html"
SAIDA = RAIZ / "imob-easy" / "imoveis.html"
VERSAO = "20261002c"

html = io.open(DESENHO, encoding="utf-8").read()

# 1. o script de exemplo (o último <script> sem src) sai; entram o mapa, a config e o script de verdade
inicio = html.rindex("<script>")
fim = html.index("</script>", inicio) + len("</script>")
html = html[:inicio] + (
    '<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>\n'
    '<script src="/assets/js/config.js"></script>\n'
    f'<script src="/assets/js/imoveis-enviar.js?v={VERSAO}"></script>') + html[fim:]

# 2. o estilo do mapa de verdade: a camada do mapa ocupa a área do desenho, o pino de preço é o do desenho
ESTILO = """<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
/* mapa de verdade no lugar do ilustrativo (gerado por scripts/montar_pagina_de_enviar.py) */
.world{position:absolute;inset:0;width:100%;height:100%;z-index:1;background:#EEF2EC}
.pinw{width:0!important;height:0!important;border:0;background:transparent}
.pinw .pin{left:0;top:0}
.pinw .popup{left:0;top:0;cursor:default}
/* o desenho estica todo svg de .world (era o mapa ilustrativo); os icones dos botoes voltam ao normal */
.world .pinw svg{position:static;inset:auto;width:15px;height:15px;display:inline-block}
.world .pinw .popup .x svg{width:14px;height:14px}
/* o Leaflet poe width:auto em toda imagem de marcador */
.pinw .popup img{width:100%!important;height:96px!important;max-width:100%!important}
.leaflet-container{font-family:inherit}
.leaflet-control-attribution{font-size:10.5px;background:rgba(255,255,255,.8)!important;border-radius:0 8px 0 0}
.maptag{bottom:30px!important}
.map{cursor:default}
</style>
</head>"""
assert html.count("</head>") == 1
html = html.replace("</head>", ESTILO, 1)

# 3. textos que eram do exemplo
html = re.sub(r"<title>.*?</title>", "<title>Imóveis para enviar · Imob Easy</title>", html, count=1, flags=re.S)
html = html.replace('href="https://imobeasy.online"', 'href="/"')
antes = html.count("Endereço, condomínio, código ou bairro")
assert antes >= 1, "o desenho mudou o texto da busca"
html = html.replace("Endereço, condomínio, código ou bairro", "Condomínio, bairro ou código")   # a rua não é pública
assert "Mapa ilustrativo" in html, "o desenho não tem mais a etiqueta do mapa"
html = html.replace("Mapa ilustrativo", "Região aproximada do imóvel")
html = html.replace("<head>", "<head>\n<!-- Gerado por scripts/montar_pagina_de_enviar.py a partir de Telaenviarmovel.html. "
                    "Não edite aqui: edite o desenho e gere de novo. -->", 1)

assert "RAW=[" not in html and "fakePhoto" not in html, "sobrou dado de exemplo do desenho"
for obrigatorio in ('id="site"', 'id="map"', 'id="world"', 'id="mtop"', 'id="q"', 'id="sugs"', 'id="mapF"', 'id="mapCount"',
                    'id="zin"', 'id="zout"', 'id="zfit"', 'id="mhint"', 'id="results"', 'id="resCount"', 'id="listF"',
                    'id="list"', 'id="sheet"', 'id="grab"', 'id="ftog"', 'id="ftogBd"', 'id="sheetF"', 'id="listbtn"',
                    'id="listbtnTxt"', 'id="nSel"', 'id="clearAll"', 'id="selList"', 'id="phone"', 'id="send"',
                    'id="sendTxt"', 'id="err"', 'id="toast"', 'data-neg="venda"', 'data-neg="aluguel"'):
    assert obrigatorio in html, f"o desenho não tem mais {obrigatorio}: o script da página precisa dele"

io.open(SAIDA, "w", encoding="utf-8", newline="\n").write(html)
print(f"{SAIDA.relative_to(RAIZ)}: {len(html.splitlines())} linhas")
