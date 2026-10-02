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
VERSAO = "20261002e"

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
/* O MAPA É O DO NOSSO PAINEL (gerado por scripts/montar_pagina_de_enviar.py): OpenStreetMap com filtro
   escuro, divisas e nomes dos bairros. As regras do fundo e do nome do bairro são as de imoveis-ux.css. */
.world{position:absolute;inset:0;width:100%;height:100%;z-index:1;background:#1d1b22}
.mapa--escuro .leaflet-tile-pane{filter:invert(1) hue-rotate(180deg) grayscale(1) brightness(.92) contrast(.88)}
.mapa--cinza .leaflet-tile-pane{filter:grayscale(1) brightness(.9) contrast(.92)}
.world.mapa--cinza{background:#d9d9d9}
.leaflet-tooltip.ux-rotulo-bairro{background:transparent;border:0;box-shadow:none;font-weight:700;font-size:11px;white-space:nowrap;padding:0;color:#3b2a63;text-shadow:0 0 3px #fff,0 0 3px #fff}
.mapa--escuro .leaflet-tooltip.ux-rotulo-bairro{color:#ede9fe;text-shadow:0 0 3px #000,0 0 3px #000}
.leaflet-tooltip.ux-rotulo-bairro::before{display:none}
.leaflet-container{font-family:inherit}
.leaflet-control-attribution{font-size:10.5px;background:rgba(255,255,255,.8)!important;border-radius:0 8px 0 0}
.maptag{bottom:30px!important}
.map{cursor:default;background:#1d1b22}

/* O PINO COM O PREÇO DENTRO: roxo da casa, pequeno e de tamanho FIXO (não cresce com a tela nem com o zoom) */
.pinw{width:0!important;height:0!important;border:0;background:transparent}
.ux-preco-pin{position:absolute;left:0;top:0;transform:translate(-50%,calc(-100% - 5px));border:0;cursor:pointer;white-space:nowrap;
  font:700 10.5px/1 "Barlow",Arial,sans-serif;letter-spacing:.01em;color:#fff;padding:4px 7px;border-radius:9px;font-variant-numeric:tabular-nums;
  background:linear-gradient(160deg,#a78bfa 0%,#7c3aed 45%,#4c1d95 100%);box-shadow:0 2px 5px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.35)}
.ux-preco-pin::after{content:"";position:absolute;left:50%;bottom:-5px;transform:translateX(-50%);border:5px solid transparent;border-top-color:#5b21b6;border-bottom:0}
.ux-preco-pin i{font-style:normal;font-weight:600;font-size:9.5px;opacity:.85;margin-left:4px}
.ux-preco-pin.sel{background:linear-gradient(160deg,#34d399 0%,#059669 55%,#065f46 100%)}
.ux-preco-pin.sel::after{border-top-color:#047857}
.ux-preco-pin.focus{box-shadow:0 0 0 2px #fff,0 0 0 4px #7c3aed,0 2px 6px rgba(0,0,0,.5)}
.pinw:hover{z-index:9999!important}

/* o balão: o desenho estica todo svg de .world (era o mapa ilustrativo); os ícones dos botões voltam ao normal */
.pinw .popup{left:0;top:0;cursor:default;transform:translate(-50%,calc(-100% - 34px))}
.world .pinw svg{position:static;inset:auto;width:15px;height:15px;display:inline-block}
/* ...e o tracado das divisas dos bairros (o svg do Leaflet) tambem: o tamanho e a posicao sao dele */
.world .leaflet-pane>svg{left:0;top:0;right:auto;bottom:auto;width:auto;height:auto}
.world .pinw .popup .x svg{width:14px;height:14px}
.pinw .popup img{width:100%!important;height:96px!important;max-width:100%!important}
/* vários imóveis no mesmo ponto: a lista dentro do balão */
.popup--lugar{width:286px}
.popup--lugar .pb{padding:10px 10px 8px}
.popup--lugar .pb>b{padding-right:28px}
.pl-lista{margin-top:8px;max-height:232px;overflow-y:auto;overscroll-behavior:contain;display:grid;gap:5px}
.pl{display:grid;grid-template-columns:48px minmax(0,1fr) auto auto;gap:7px;align-items:center;background:var(--soft);border-radius:10px;padding:4px}
.pl.focus{box-shadow:0 0 0 2px #C9B2F5}
.pinw .popup .pl img{width:48px!important;height:38px!important;border-radius:7px;object-fit:cover}
.pl span b{display:block;font-size:13px;font-weight:600;color:var(--brand-dark);line-height:1.2}
.pl span b span{font-size:11px;color:var(--muted);font-weight:400}
.pl span small{display:block;font-size:11.5px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pl .vbtn,.pl .pick{padding:6px 8px}

/* A LISTA FICA EMBAIXO DO MAPA e a página rola até ela (Pedro, 02/10): o mapa não ocupa mais a tela toda */
@media (min-width:1024px){.map{height:min(64dvh,660px)!important}}
@media (max-width:1023px){.map{height:max(260px,calc(100dvh - var(--head-h,58px) - var(--sheet-h,200px) - 64px))!important}}
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
