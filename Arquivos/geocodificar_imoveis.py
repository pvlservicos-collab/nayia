"""
O MAPA DOS IMÓVEIS (Tel, 28/09/2026).

"um mapa focado na cidade de Manaus, e implemente lá a localização próxima de
todos os nossos imóveis, todos divididinhos por bairro... para termos a relação
de bairros ao redor do imóvel pronta e precisa para usarmos depois".

TRÊS PASSOS, cada um grava a sua parte (migração 149):

  bairros   os contornos oficiais dos bairros de Manaus no OpenStreetMap (uma
            consulta ao Overpass), os que só existem como lugar (Parque das
            Laranjeiras...), o de-para do nosso cadastro e quem faz divisa com
            quem -> geo_bairro, geo_bairro_nome, geo_bairro_vizinho
  imoveis   o ponto de cada imóvel nosso -> imovel_geo, com a precisão:
              'condominio'  o condomínio está no mapa, dentro do bairro certo
              'rua'         a rua, procurada DENTRO do bairro do cadastro
              'bairro'      o centro do bairro (nem a rua foi achada)
            O OpenStreetMap de Manaus quase não tem número de casa: por isso
            'rua' é o comum, e é a rua certa no bairro certo.
  ao-redor  os bairros a até 2 km de cada imóvel, medidos até a BORDA do
            bairro -> imovel_bairro_ao_redor

O GEOCODIFICADOR GRATUITO TEM REGRA (Nominatim): uma consulta por segundo, uma
de cada vez, e guardar o resultado. Toda resposta fica em `geo_consulta`; rodar
de novo não pergunta outra vez. Google Maps daria o número exato, mas exige uma
chave paga -- os pontos 'rua' e 'bairro' são os que um refinamento futuro
melhoraria.

Uso (no servidor, em /root/nay-publicador):
    set -a; . ./.env; set +a
    .venv/bin/python geocodificar_imoveis.py bairros
    .venv/bin/python geocodificar_imoveis.py imoveis [--limite N] [--simular]
    .venv/bin/python geocodificar_imoveis.py ao-redor
"""
import hashlib
import json
import math
import os
import re
import sys
import time
import unicodedata

import psycopg2
import psycopg2.extras
import requests

UA = {"User-Agent": "ImobEasy-mapa/1.0 (+https://imobeasy.online)"}
OVERPASS = "https://overpass-api.de/api/interpreter"
NOMINATIM = "https://nominatim.openstreetmap.org/search"
# Manaus com folga (o Tarumã-Açu vai longe para o norte)
MANAUS = (-60.32, -3.25, -59.70, -2.78)  # lon_min, lat_min, lon_max, lat_max
LAT0, LON0 = -3.08, -60.0
KX = 111320.0 * math.cos(math.radians(LAT0))
KY = 110574.0

# ------------------------------------------------------------------ nomes
NUMEROS = {"10": "dez", "14": "quatorze", "1": "um", "2": "dois"}


def norm(s):
    s = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    s = re.sub(r"\bpq\b", "parque", s)
    s = " ".join(NUMEROS.get(p, p) for p in s.split())
    s = re.sub(r" i$", "", s)          # "Dom Pedro I" = "Dom Pedro"
    return s


# ------------------------------------------------------------------ geometria (metros, plano local)
def xy(lon, lat):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def lonlat(x, y):
    return (x / KX + LON0, y / KY + LAT0)


def dentro_anel(px, py, anel):
    d = False
    n = len(anel)
    j = n - 1
    for i in range(n):
        xi, yi = anel[i]
        xj, yj = anel[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / ((yj - yi) or 1e-12) + xi:
            d = not d
        j = i
    return d


def dentro(px, py, pol):
    """pol = lista de (externo, [internos]) em metros."""
    for ext, ints in pol:
        if dentro_anel(px, py, ext) and not any(dentro_anel(px, py, h) for h in ints):
            return True
    return False


def dist_seg(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def dist_pol(px, py, pol):
    """0 dentro; senão a distância até a borda, em metros."""
    if dentro(px, py, pol):
        return 0.0
    m = float("inf")
    for ext, ints in pol:
        for anel in [ext] + ints:
            for i in range(len(anel) - 1):
                d = dist_seg(px, py, anel[i][0], anel[i][1], anel[i + 1][0], anel[i + 1][1])
                if d < m:
                    m = d
    return m


def area_anel(anel):
    return abs(sum(anel[i][0] * anel[i + 1][1] - anel[i + 1][0] * anel[i][1] for i in range(len(anel) - 1))) / 2


def simplificar(anel, tol=12.0):
    """Douglas-Peucker, em metros."""
    if len(anel) < 4:
        return anel
    manter = [False] * len(anel)
    manter[0] = manter[-1] = True
    pilha = [(0, len(anel) - 1)]
    while pilha:
        a, b = pilha.pop()
        maior, k = 0.0, -1
        for i in range(a + 1, b):
            d = dist_seg(anel[i][0], anel[i][1], anel[a][0], anel[a][1], anel[b][0], anel[b][1])
            if d > maior:
                maior, k = d, i
        if maior > tol and k > 0:
            manter[k] = True
            pilha += [(a, k), (k, b)]
    return [p for p, m in zip(anel, manter) if m]


def caixa(pol, folga=0.0):
    xs = [p[0] for ext, _ in pol for p in ext]
    ys = [p[1] for ext, _ in pol for p in ext]
    return (min(xs) - folga, min(ys) - folga, max(xs) + folga, max(ys) + folga)


def na_caixa(px, py, c):
    return c[0] <= px <= c[2] and c[1] <= py <= c[3]


def montar_aneis(vias):
    """Junta as vias (listas de pontos) em anéis fechados, ponta com ponta."""
    vias = [list(v) for v in vias if len(v) >= 2]
    aneis = []
    igual = lambda p, q: abs(p[0] - q[0]) < 1e-7 and abs(p[1] - q[1]) < 1e-7
    while vias:
        anel = vias.pop(0)
        mudou = True
        while not igual(anel[0], anel[-1]) and mudou:
            mudou = False
            for k, v in enumerate(vias):
                if igual(anel[-1], v[0]):
                    anel += v[1:]
                elif igual(anel[-1], v[-1]):
                    anel += list(reversed(v))[1:]
                elif igual(anel[0], v[-1]):
                    anel = v[:-1] + anel
                elif igual(anel[0], v[0]):
                    anel = list(reversed(v))[:-1] + anel
                else:
                    continue
                vias.pop(k)
                mudou = True
                break
        if len(anel) >= 4:
            if not igual(anel[0], anel[-1]):
                anel.append(anel[0])
            aneis.append(anel)
    return aneis


def ponto_interno(pol):
    """O centro de massa do maior pedaço; se cair fora (bairro em U), o ponto de
    dentro mais perto dele numa grade."""
    ext = max((e for e, _ in pol), key=area_anel)
    a = area_anel(ext) or 1
    cx = sum((ext[i][0] + ext[i + 1][0]) * (ext[i][0] * ext[i + 1][1] - ext[i + 1][0] * ext[i][1])
             for i in range(len(ext) - 1))
    cy = sum((ext[i][1] + ext[i + 1][1]) * (ext[i][0] * ext[i + 1][1] - ext[i + 1][0] * ext[i][1])
             for i in range(len(ext) - 1))
    s = sum(ext[i][0] * ext[i + 1][1] - ext[i + 1][0] * ext[i][1] for i in range(len(ext) - 1)) / 2 or 1
    cx, cy = cx / (6 * s), cy / (6 * s)
    if dentro(cx, cy, pol):
        return cx, cy
    c = caixa(pol)
    melhor = None
    for i in range(1, 30):
        for j in range(1, 30):
            x = c[0] + (c[2] - c[0]) * i / 30
            y = c[1] + (c[3] - c[1]) * j / 30
            if dentro(x, y, pol):
                d = math.hypot(x - cx, y - cy)
                if melhor is None or d < melhor[0]:
                    melhor = (d, x, y)
    return (melhor[1], melhor[2]) if melhor else (cx, cy)


# ------------------------------------------------------------------ banco
def conectar():
    return psycopg2.connect(os.environ["DATABASE_URL"], cursor_factory=psycopg2.extras.RealDictCursor)


def carregar_bairros(conn):
    """{bairro: {'pol': [...] ou None, 'caixa', 'x', 'y', 'fonte'}}"""
    with conn.cursor() as cur:
        cur.execute("SELECT bairro, lat, lon, poligono, fonte FROM geo_bairro")
        linhas = cur.fetchall()
    b = {}
    for l in linhas:
        pol = None
        if l["poligono"]:
            g = l["poligono"]
            partes = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
            pol = [([xy(*p) for p in parte[0]], [[xy(*p) for p in h] for h in parte[1:]]) for parte in partes]
        x, y = xy(l["lon"], l["lat"])
        b[l["bairro"]] = {"pol": pol, "caixa": caixa(pol) if pol else None, "x": x, "y": y, "fonte": l["fonte"]}
    return b


# ------------------------------------------------------------------ 1. bairros
def overpass(q):
    for tentativa in range(4):
        r = requests.post(OVERPASS, data={"data": q}, headers=UA, timeout=180)
        if r.status_code == 200:
            return r.json()["elements"]
        time.sleep(20 * (tentativa + 1))
    raise RuntimeError("Overpass não respondeu: %s" % r.status_code)


def passo_bairros(conn):
    area = '[out:json][timeout:180];area["name"="Manaus"]["boundary"="administrative"]["admin_level"="8"]->.m;'
    rels = overpass(area + 'relation["boundary"="administrative"]["admin_level"="10"](area.m);out geom;')
    lugares = overpass(area + 'nwr["place"~"suburb|neighbourhood|quarter"](area.m);out center;')
    print(len(rels), "contornos,", len(lugares), "lugares")

    bairros = {}   # nome oficial -> dict
    for r in rels:
        nome = r["tags"].get("name")
        externos = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in r.get("members", [])
                    if m["type"] == "way" and m.get("role") in ("outer", "") and m.get("geometry")]
        internos = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in r.get("members", [])
                    if m["type"] == "way" and m.get("role") == "inner" and m.get("geometry")]
        ext_aneis = [[xy(*p) for p in a] for a in montar_aneis(externos)]
        int_aneis = [[xy(*p) for p in a] for a in montar_aneis(internos)]
        if not nome or not ext_aneis:
            print("  sem contorno fechado:", nome)
            continue
        pol = [(e, [h for h in int_aneis if dentro_anel(h[0][0], h[0][1], e)]) for e in ext_aneis]
        vias = {m["ref"] for m in r.get("members", []) if m["type"] == "way"}
        bairros[nome] = {"osm_id": r["id"], "pol": pol, "vias": vias}

    for nome, b in bairros.items():
        b["simp"] = [(simplificar(e), [simplificar(h) for h in ints]) for e, ints in b["pol"]]
        b["x"], b["y"] = ponto_interno(b["pol"])
        b["area"] = sum(area_anel(e) - sum(area_anel(h) for h in ints) for e, ints in b["pol"]) / 1e6
        b["caixa"] = caixa(b["simp"])

    # os nomes que o NOSSO cadastro usa
    with conn.cursor() as cur:
        cur.execute("""SELECT DISTINCT btrim(bairro) AS b FROM vw_imoveis_todos
                        WHERE coalesce(btrim(bairro), '') <> ''
                       UNION SELECT DISTINCT btrim(bairro) FROM imoveis WHERE coalesce(btrim(bairro), '') <> ''""")
        cadastro = [l["b"] for l in cur.fetchall()]
    usados = {norm(c) for c in cadastro}

    # os que só existem como lugar (Parque das Laranjeiras, Praça 14...) -- SÓ
    # os que o cadastro usa: o OpenStreetMap tem ~100 conjuntos e loteamentos
    # que poluiriam a relação de bairros ao redor
    so_lugar = {}
    oficiais = {norm(n) for n in bairros}
    for l in lugares:
        nome = l.get("tags", {}).get("name")
        pos = l if "lat" in l else l.get("center")
        if nome and pos and norm(nome) in usados and norm(nome) not in oficiais                 and norm(nome) not in {norm(n) for n in so_lugar}:
            so_lugar[nome] = xy(pos["lon"], pos["lat"])
    # o que ainda falta, pelo nome no geocodificador (um por um, com cache)
    for c in cadastro:
        if norm(c) in oficiais or norm(c) in {norm(n) for n in so_lugar}:
            continue
        for q in (c + ", Manaus, Amazonas", re.sub(r"(?i)^col[oô]nia ", "Col. ", c) + ", Manaus"):
            resp = nominatim(conn, "b|" + norm(q), {"q": q, "viewbox": "%s,%s,%s,%s" % (MANAUS[0], MANAUS[3], MANAUS[2], MANAUS[1]),
                                                    "bounded": 1})
            if resp:
                so_lugar[c] = xy(resp[0]["lon"], resp[0]["lat"])
                break

    def geojson(simp):
        partes = [[[list(lonlat(*p)) for p in e]] + [[list(lonlat(*p)) for p in h] for h in ints] for e, ints in simp]
        partes = [[[[round(c, 6) for c in p] for p in anel] for anel in parte] for parte in partes]
        return {"type": "Polygon", "coordinates": partes[0]} if len(partes) == 1 else \
               {"type": "MultiPolygon", "coordinates": partes}

    # quem faz divisa: a mesma via no contorno dos dois, ou bordas a menos de 30 m
    nomes = sorted(bairros)
    vizinhos = []
    for i, a in enumerate(nomes):
        for b_ in nomes[i + 1:]:
            A, B = bairros[a], bairros[b_]
            ca, cb = caixa(A["simp"], 1500), B["caixa"]
            if not (ca[0] <= cb[2] and cb[0] <= ca[2] and ca[1] <= cb[3] and cb[1] <= ca[3]):
                continue
            divisa = bool(A["vias"] & B["vias"])
            borda = 0.0 if divisa else min(
                min(dist_pol(p[0], p[1], B["simp"]) for e, _ in A["simp"] for p in e[::2]),
                min(dist_pol(p[0], p[1], A["simp"]) for e, _ in B["simp"] for p in e[::2]))
            if borda < 30:
                divisa = True
            if divisa or borda <= 1500:
                km = math.hypot(A["x"] - B["x"], A["y"] - B["y"]) / 1000
                vizinhos.append((a, b_, divisa, round(km, 2)))

    with conn.cursor() as cur:
        cur.execute("DELETE FROM geo_bairro_vizinho")
        cur.execute("DELETE FROM geo_bairro_nome")
        cur.execute("DELETE FROM geo_bairro")
        for nome, b in bairros.items():
            lon, lat = lonlat(b["x"], b["y"])
            cur.execute("INSERT INTO geo_bairro (bairro, osm_id, lat, lon, poligono, area_km2, fonte) "
                        "VALUES (%s, %s, %s, %s, %s, %s, 'osm_limite')",
                        (nome, b["osm_id"], lat, lon, json.dumps(geojson(b["simp"])), round(b["area"], 2)))
        for nome, (x, y) in so_lugar.items():
            lon, lat = lonlat(x, y)
            cur.execute("INSERT INTO geo_bairro (bairro, lat, lon, fonte) VALUES (%s, %s, %s, 'osm_lugar')",
                        (nome, lat, lon))
        for a, b_, divisa, km in vizinhos:
            cur.execute("INSERT INTO geo_bairro_vizinho VALUES (%s, %s, %s, %s), (%s, %s, %s, %s)",
                        (a, b_, divisa, km, b_, a, divisa, km))

        # o de-para: como o nosso cadastro escreve -> o nome oficial
        todos = {norm(n): n for n in list(bairros) + list(so_lugar)}
        sem = []
        for c in cadastro:
            alvo = todos.get(norm(c))
            if alvo:
                cur.execute("INSERT INTO geo_bairro_nome VALUES (%s, %s) ON CONFLICT DO NOTHING", (c, alvo))
            else:
                sem.append(c)
    conn.commit()
    print(len(bairros), "bairros com contorno,", len(so_lugar), "só como lugar,",
          sum(1 for v in vizinhos if v[2]), "divisas,", len(vizinhos), "pares perto")
    print("nomes do cadastro sem bairro no mapa:", sem)


# ------------------------------------------------------------------ 2. imóveis
ULTIMA = [0.0]


def nominatim(conn, chave, params):
    """Uma pergunta, com cache. Respeita 1 por segundo."""
    with conn.cursor() as cur:
        cur.execute("SELECT resposta FROM geo_consulta WHERE consulta = %s", (chave,))
        l = cur.fetchone()
    if l:
        return l["resposta"]
    espera = 1.1 - (time.time() - ULTIMA[0])
    if espera > 0:
        time.sleep(espera)
    p = dict(params, format="jsonv2", limit=5, countrycodes="br")
    for tentativa in range(4):
        try:
            r = requests.get(NOMINATIM, params=p, headers=UA, timeout=30)
            ULTIMA[0] = time.time()
            if r.status_code == 200:
                resposta = [{"lat": float(x["lat"]), "lon": float(x["lon"]), "tipo": x.get("addresstype") or x.get("type"),
                             "classe": x.get("category") or x.get("class"), "nome": x.get("display_name", "")[:160]}
                            for x in r.json()]
                break
            if r.status_code in (429, 503):
                time.sleep(60 * (tentativa + 1))
                continue
            resposta = []
            break
        except requests.RequestException:
            time.sleep(15 * (tentativa + 1))
    else:
        return None   # nao guarda: tenta de novo na proxima rodada
    with conn.cursor() as cur:
        cur.execute("INSERT INTO geo_consulta (consulta, resposta) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    (chave, json.dumps(resposta)))
    conn.commit()
    return resposta


ABREV = [(r"^r\.?\s+", "Rua "), (r"^rua\s*-\s*", "Rua "), (r"^av\.?\s+", "Avenida "), (r"^al\.?\s+", "Alameda "),
         (r"^tv\.?\s+", "Travessa "), (r"^trav\.?\s+", "Travessa "), (r"^est\.?\s+", "Estrada "),
         (r"^p[cç]a?\.?\s+", "Praça "), (r"^rod\.?\s+", "Rodovia ")]
NAO_E_CONDOMINIO = {"condominio nao identificado", "loja ponto", "casa", "sala", "apartamento", "terreno",
                    "galpao", "predio", "flat", "cobertura", "sala andar", "lote", "ponto comercial", ""}


def limpar_rua(rua):
    r = re.sub(r"\s+", " ", str(rua or "")).strip(" ,.-")
    # o cadastro traz anotacao junto: "(ant. Av. Perimetral)", "no 4981", e ate o
    # texto do anuncio depois do numero ("... 527 centro Galpao 600 metros")
    r = re.sub(r"\(.*?\)", " ", r)
    r = re.split(r"\s+n[ºo°]\.?\s*\d|\s+\d+\b(?!\s+de\b)", r, maxsplit=1, flags=re.I)[0]
    r = re.sub(r"\s+", " ", r).strip(" ,.-")
    for a, b in ABREV:
        r = re.sub(a, b, r, flags=re.I)
    return r


def partes_endereco(endereco):
    """'Rua X, 123, Bairro, Manaus - Amazonas' -> ('Rua X', 'Bairro')"""
    p = [x.strip() for x in str(endereco or "").split(",") if x.strip()]
    if not p:
        return None, None
    rua = limpar_rua(p[0])
    bairro = None
    for k, x in enumerate(p):
        if norm(x).startswith("manaus") and k >= 1:
            cand = p[k - 1]
            if not re.fullmatch(r"\d+\s*\w?", cand) and k - 1 >= 1:
                bairro = cand
            break
    if rua and norm(rua) in ("", "manaus"):
        rua = None
    return rua, bairro


def espalhar(codigo, x, y, raio_min=60, raio_max=260):
    """O centro do bairro, espalhado um pouco -- senão 200 imóveis viram um ponto só."""
    h = int(hashlib.md5(str(codigo).encode()).hexdigest(), 16)
    ang = (h % 3600) / 3600 * 2 * math.pi
    r = raio_min + (h // 3600 % 1000) / 1000 * (raio_max - raio_min)
    return x + r * math.cos(ang), y + r * math.sin(ang)


def bairro_do_ponto(x, y, bairros):
    for nome, b in bairros.items():
        if b["pol"] and na_caixa(x, y, b["caixa"]) and dentro(x, y, b["pol"]):
            return nome
    return None


def passo_imoveis(conn, limite=None, simular=False):
    bairros = carregar_bairros(conn)
    with conn.cursor() as cur:
        cur.execute("SELECT nome_cadastro, bairro FROM geo_bairro_nome")
        de_para = {norm(l["nome_cadastro"]): l["bairro"] for l in cur.fetchall()}
        cur.execute("""
            SELECT v.codigo, v.condominio, v.endereco, v.bairro,
                   i.logradouro, i.condominio_nome
              FROM vw_imoveis_todos v
              LEFT JOIN imoveis i ON i.codigo = v.codigo
             WHERE NOT v.e_parceiro
               AND NOT EXISTS (SELECT 1 FROM imovel_geo g WHERE g.codigo = v.codigo)
             ORDER BY v.codigo DESC""" + (" LIMIT %d" % int(limite) if limite else ""))
        imoveis = cur.fetchall()
    print(len(imoveis), "imóveis para localizar")
    conta = {"condominio": 0, "rua": 0, "bairro": 0, "sem": 0}

    for n, im in enumerate(imoveis, 1):
        rua_end, bairro_end = partes_endereco(im["endereco"])
        rua = limpar_rua(im["logradouro"]) if im["logradouro"] else rua_end
        nome_bairro = (im["bairro"] or "").strip() or bairro_end
        oficial = de_para.get(norm(nome_bairro)) if nome_bairro else None
        alvo = bairros.get(oficial) if oficial else None
        condo = (im["condominio_nome"] or im["condominio"] or "").strip()

        ponto, precisao, consulta = None, None, None

        def perto(r, folga):
            x, y = xy(r["lon"], r["lat"])
            if not na_caixa(x, y, xy(MANAUS[0], MANAUS[1]) + xy(MANAUS[2], MANAUS[3])):
                return None
            if alvo and alvo["pol"]:
                return (x, y) if dist_pol(x, y, alvo["pol"]) <= folga else None
            if alvo:   # bairro que so existe como lugar: ate 1,5 km do centro dele
                return (x, y) if math.hypot(x - alvo["x"], y - alvo["y"]) <= 1500 else None
            return (x, y)

        # 1) o condomínio -- só quando se sabe o bairro (nome de condomínio se repete na cidade)
        if alvo and norm(condo) not in NAO_E_CONDOMINIO and len(norm(condo)) >= 4:
            consulta = "c|" + norm(condo) + "|" + oficial
            resp = nominatim(conn, consulta, {"q": condo + ", Manaus, Amazonas",
                                              "viewbox": "%s,%s,%s,%s" % (MANAUS[0], MANAUS[3], MANAUS[2], MANAUS[1]),
                                              "bounded": 1})
            for r in resp or []:
                if r["classe"] == "highway":
                    continue       # uma rua com o nome do condomínio não é o condomínio
                ponto = perto(r, 400)
                if ponto:
                    precisao = "condominio"
                    break

        # 2) a rua, procurada dentro do bairro
        if not ponto and rua and len(norm(rua)) >= 4:
            if alvo and alvo["pol"]:
                c = caixa(alvo["pol"], 300)
                (lo1, la1), (lo2, la2) = lonlat(c[0], c[1]), lonlat(c[2], c[3])
                vb = "%s,%s,%s,%s" % (lo1, la2, lo2, la1)
            else:
                vb = "%s,%s,%s,%s" % (MANAUS[0], MANAUS[3], MANAUS[2], MANAUS[1])
            consulta = "r|" + norm(rua) + "|" + (oficial or "")
            resp = nominatim(conn, consulta, {"street": rua, "city": "Manaus", "state": "Amazonas",
                                              "viewbox": vb, "bounded": 1})
            for r in resp or []:
                ponto = perto(r, 300)
                if ponto:
                    precisao = "rua"
                    break

        # 2b) o endereço por extenso ("rua, bairro, Manaus"): pega grafia que a
        #     busca estruturada não reconhece
        if not ponto and rua and len(norm(rua)) >= 4 and nome_bairro:
            consulta = "e|" + norm(rua) + "|" + norm(nome_bairro)
            resp = nominatim(conn, consulta, {"q": "%s, %s, Manaus, Amazonas" % (rua, nome_bairro),
                                              "viewbox": "%s,%s,%s,%s" % (MANAUS[0], MANAUS[3], MANAUS[2], MANAUS[1]),
                                              "bounded": 1})
            for r in resp or []:
                ponto = perto(r, 300)
                if ponto:
                    precisao = "rua"
                    break

        # 2c) sem o tipo da via: o cadastro chama de "Rua" o que e Avenida
        sem_tipo = re.sub(r"(?i)^(rua|avenida|alameda|travessa|estrada|rodovia|pra[cç]a|beco)\s+", "", rua or "")
        if not ponto and sem_tipo and sem_tipo != rua and len(norm(sem_tipo)) >= 6 and (oficial or nome_bairro):
            consulta = "s|" + norm(sem_tipo) + "|" + norm(oficial or nome_bairro)
            resp = nominatim(conn, consulta, {"q": "%s, %s, Manaus, Amazonas" % (sem_tipo, oficial or nome_bairro),
                                              "viewbox": "%s,%s,%s,%s" % (MANAUS[0], MANAUS[3], MANAUS[2], MANAUS[1]),
                                              "bounded": 1})
            for r in resp or []:
                ponto = perto(r, 300)
                if ponto:
                    precisao = "rua"
                    break

        # 3) o centro do bairro, espalhado
        if not ponto and alvo:
            ponto = espalhar(im["codigo"], alvo["x"], alvo["y"])
            precisao, consulta = "bairro", "centro do bairro " + oficial

        if not ponto:
            conta["sem"] += 1
            continue
        conta[precisao] += 1
        x, y = ponto
        lon, lat = lonlat(x, y)
        onde = bairro_do_ponto(x, y, bairros) or oficial
        if simular:
            print(im["codigo"], precisao, round(lat, 5), round(lon, 5), "|", nome_bairro, "->", onde, "|", consulta)
            continue
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO imovel_geo (codigo, lat, lon, precisao, bairro, consulta, fonte)
                           VALUES (%s, %s, %s, %s, %s, %s, %s)
                           ON CONFLICT (codigo) DO UPDATE SET lat = EXCLUDED.lat, lon = EXCLUDED.lon,
                             precisao = EXCLUDED.precisao, bairro = EXCLUDED.bairro, consulta = EXCLUDED.consulta,
                             fonte = EXCLUDED.fonte, geocodificado_em = now()""",
                        (im["codigo"], lat, lon, precisao, onde, consulta,
                         "centro_do_bairro" if precisao == "bairro" else "nominatim"))
        conn.commit()
        if n % 50 == 0:
            print(time.strftime("%H:%M:%S"), n, "de", len(imoveis), conta, flush=True)
    print("fim:", conta)


# ------------------------------------------------------------------ 3. bairros ao redor
def passo_ao_redor(conn, raio=2000):
    bairros = carregar_bairros(conn)
    with conn.cursor() as cur:
        cur.execute("SELECT codigo, lat, lon FROM imovel_geo")
        pontos = cur.fetchall()
    linhas = []
    for p in pontos:
        x, y = xy(p["lon"], p["lat"])
        for nome, b in bairros.items():
            if b["pol"]:
                if not na_caixa(x, y, caixa(b["pol"], raio)):
                    continue
                d = dist_pol(x, y, b["pol"])
            else:
                d = math.hypot(x - b["x"], y - b["y"])   # só o lugar: até o centro dele
                if d > 1500:
                    continue
            if d <= raio:
                linhas.append((p["codigo"], nome, round(d / 1000, 2), d == 0.0 and b["pol"] is not None))
    with conn.cursor() as cur:
        cur.execute("DELETE FROM imovel_bairro_ao_redor")
        psycopg2.extras.execute_values(cur, "INSERT INTO imovel_bairro_ao_redor (codigo, bairro, km, dentro) VALUES %s",
                                       linhas, page_size=2000)
    conn.commit()
    print(len(pontos), "imóveis,", len(linhas), "relações imóvel-bairro a até", raio / 1000, "km")


if __name__ == "__main__":
    args = sys.argv[1:]
    conn = conectar()
    try:
        if not args or args[0] == "bairros":
            passo_bairros(conn)
        elif args[0] == "imoveis":
            limite = int(args[args.index("--limite") + 1]) if "--limite" in args else None
            passo_imoveis(conn, limite, simular="--simular" in args)
        elif args[0] == "ao-redor":
            passo_ao_redor(conn)
        else:
            print(__doc__)
    finally:
        conn.close()
