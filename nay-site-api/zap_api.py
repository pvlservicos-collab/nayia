"""CANAL PRO (Grupo OLX: ZAP Imóveis, VivaReal, OLX) -- o feed XML e os leads (542, Pedro, 30/10/2026: "cria uma
integração pra gente no developers.grupozap.com, acessa o site e vê tudo o que precisa para integrar").

AS ROTAS (abertas, como as do Chaves na Mão):
  GET  /api/zap/imoveis.xml   O FEED, no formato VRSync. O robô deles (User-Agent "VivaRealBot/1.0") baixa a cada 12 h.
                              Quem vai: os imóveis que entram no portal pelo nosso cadastro (cnm_imoveis(): nossos,
                              Disponíveis, no site, com valor) e que passam nas regras do Grupo OLX: CEP, pelo menos 5
                              fotos JPG, descrição de 50 a 3.000 caracteres. ?todos=1 lista quem ficou de fora e por quê.
  POST /api/zap/leads         O LEAD, um por POST (JSON). Authorization: Basic base64(usuario:SECRET_KEY); a chave vem
                              do Grupo OLX na homologação e fica em privado.zap_config.lead_segredo. Só o código HTTP
                              conta: 2xx recebido; 401 chave errada; 400 sem o nosso código (clientListingId) -- eles
                              revisam e reenviam; 500 erro nosso (eles tentam de novo, até 3 vezes). Repetido = 200.

O formato (developers.grupozap.com/feeds/vrsync): <ListingDataFeed> com <Header>, <Listings><Listing> (ListingID,
Title, TransactionType, PublicationType, DetailViewUrl, Media/Item, Details, Location) e <ContactInfo>.
"""
import base64
import json
import os
import threading
import time
from datetime import datetime
from decimal import Decimal
from xml.sax.saxutils import escape

import psycopg2
import psycopg2.extras
from flask import Blueprint, Response, jsonify, request

zap_bp = Blueprint("zap", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
CACHE_S = 600
SITE = "https://imobeasy.online"
EMPRESA = {"nome": "Imob Easy", "email": "contato@imobeasy.com", "telefone": "92 99471-7316", "site": SITE,
           "logo": SITE + "/assets/img/logo-imobeasy.svg"}
FOTOS_MINIMAS = 5

# o tipo do nosso cadastro (o nome do Chaves na Mão, cnm_imovel_montar) -> o PropertyType do VRSync
TIPO_VRSYNC = {
    "Apartamento": "Residential / Apartment", "Cobertura": "Residential / Penthouse", "Flat": "Residential / Flat",
    "Kitnet / Stúdio": "Residential / Kitnet", "Loft": "Residential / Loft",
    "Casa / Sobrado em Condomínio": "Residential / Condo", "Casa / Sobrado": "Residential / Home",
    "Terreno em Condomínio": "Residential / Land Lot", "Terreno / Lote": "Residential / Land Lot",
    "Sítio / Chácara": "Residential / Farm Ranch", "Fazenda": "Residential / Farm Ranch",
    "Conj. Comercial / Sala": "Commercial / Office", "Loja / Comércio": "Commercial / Business",
    "Barracão / Galpão": "Commercial / Industrial", "Edifício": "Commercial / Building",
    "Consultório": "Commercial / Consultorio", "Garagem": "Commercial / Garage",
}
# área do terreno (LotArea) nestes; nos outros, a área útil (LivingArea)
DE_TERRENO = {"Terreno em Condomínio", "Terreno / Lote", "Sítio / Chácara", "Fazenda", "Barracão / Galpão"}
# só as características cujo nome em inglês está confirmado na documentação (a lista deles é fechada)
CARACTERISTICA = {"Piscina": "Pool", "Elevador": "Elevator", "Academia": "Gym", "Aceita Pet": "Pets Allowed"}

_cache = {"em": 0.0, "xml": None, "fora": []}
_trava = threading.Lock()


def _linhas(sql, args=()):
    conn = psycopg2.connect(DATABASE_URL, connect_timeout=5)
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, args)
            return cur.fetchall()
    finally:
        conn.close()


def _int(v):
    try:
        return int(Decimal(str(v)))
    except Exception:  # noqa: BLE001
        return None


def _cdata(s):
    return "<![CDATA[" + (s or "").replace("]]>", "]]]]><![CDATA[>") + "]]>"


def _fotos_jpg(m) -> list[str]:
    return [u for u in (m.get("fotos") or []) if u.split("?", 1)[0].lower().endswith((".jpg", ".jpeg"))]


def _falta(m) -> list[str]:
    """As regras do Grupo OLX que o nosso cadastro pode não cumprir."""
    falta = []
    if not str(m.get("cep") or "").isdigit() or len(str(m.get("cep") or "")) != 8:
        falta.append("sem CEP")
    if len(_fotos_jpg(m)) < FOTOS_MINIMAS:
        falta.append(f"menos de {FOTOS_MINIMAS} fotos JPG ({len(_fotos_jpg(m))})")
    d = (m.get("descritivo") or "").strip()
    if not 50 <= len(d) <= 3000:
        falta.append(f"descrição com {len(d)} caracteres (precisa de 50 a 3.000)")
    if m.get("tipo") not in TIPO_VRSYNC:
        falta.append(f"tipo sem par no ZAP ({m.get('tipo')})")
    return falta


def _listing(m) -> str:
    venda = m.get("transacao") == "V"
    aluga = m.get("transacao") == "L" or m.get("transacao2") == "L"
    transacao = "Sale/Rent" if venda and aluga else "For Sale" if venda else "For Rent"
    preco_venda = _int(m.get("valor")) if venda else None
    preco_aluguel = _int(m.get("valor_locacao") if venda else m.get("valor")) if aluga else None
    fotos = _fotos_jpg(m)
    tipo = m.get("tipo")
    area = _int(m.get("area_util") or m.get("area_total"))
    area_tag = "LotArea" if tipo in DE_TERRENO else "LivingArea"
    feats = sorted({CARACTERISTICA[c] for c in (m.get("area_privativa") or []) + (m.get("area_comum") or []) if c in CARACTERISTICA})
    if str(m.get("aceita_pet")) == "1":
        feats = sorted(set(feats) | {"Pets Allowed"})
    d = []
    d.append(f"<UsageType>{'Commercial' if m.get('finalidade') == 'CO' else 'Residential'}</UsageType>")
    d.append(f"<PropertyType>{escape(TIPO_VRSYNC[tipo])}</PropertyType>")
    d.append(f"<Description>{_cdata((m.get('descritivo') or '').strip())}</Description>")
    if preco_venda:
        d.append(f'<ListPrice currency="BRL">{preco_venda}</ListPrice>')
    if preco_aluguel:
        d.append(f'<RentalPrice currency="BRL" period="Monthly">{preco_aluguel}</RentalPrice>')
    if _int(m.get("valor_condominio")):
        d.append(f'<PropertyAdministrationFee currency="BRL">{_int(m.get("valor_condominio"))}</PropertyAdministrationFee>')
    if _int(m.get("valor_iptu")):
        d.append(f'<Iptu currency="BRL" period="Yearly">{_int(m.get("valor_iptu"))}</Iptu>')
    if area:
        d.append(f'<{area_tag} unit="square metres">{area}</{area_tag}>')
    for tag, campo in (("Bedrooms", "quartos"), ("Bathrooms", "banheiro"), ("Suites", "suites"), ("Garage", "garagem")):
        if m.get(campo) is not None:
            d.append(f"<{tag}>{_int(m.get(campo))}</{tag}>")
    if feats:
        d.append("<Features>" + "".join(f"<Feature>{escape(f)}</Feature>" for f in feats) + "</Features>")
    primaria = ' primary="true"'
    midia = "".join(f'<Item medium="image" caption="img{n}"{primaria if n == 1 else ""}>{escape(u)}</Item>'
                    for n, u in enumerate(fotos[:50], start=1))
    loc = [f'<Country abbreviation="BR">Brasil</Country>',
           f'<State abbreviation="{escape(m.get("estado") or "AM")}">{escape("Amazonas" if (m.get("estado") or "AM") == "AM" else m.get("estado"))}</State>',
           f"<City>{_cdata(m.get('cidade') or 'Manaus')}</City>",
           f"<Neighborhood>{_cdata(m.get('bairro') or '')}</Neighborhood>"]
    if m.get("endereco"):
        loc.append(f"<Address>{_cdata(m.get('endereco'))}</Address>")
    loc.append(f"<PostalCode>{escape(str(m.get('cep')))}</PostalCode>")
    if m.get("latitude") and m.get("longitude"):
        loc += [f"<Latitude>{m.get('latitude')}</Latitude>", f"<Longitude>{m.get('longitude')}</Longitude>"]
    return ("    <Listing>\n"
            f"      <ListingID>{escape(str(m.get('referencia')))}</ListingID>\n"
            f"      <Title>{_cdata((m.get('titulo') or '')[:100])}</Title>\n"
            f"      <TransactionType>{transacao}</TransactionType>\n"
            "      <PublicationType>STANDARD</PublicationType>\n"
            f"      <DetailViewUrl>{escape(m.get('link_cliente') or SITE + '/imovel/' + str(m.get('referencia')))}</DetailViewUrl>\n"
            f"      <Media>{midia}</Media>\n"
            f"      <Details>{''.join(d)}</Details>\n"
            # o endereço vai (o portal acha no mapa), mas só o bairro aparece -- como no Chaves na Mão
            f'      <Location displayAddress="Neighborhood">{"".join(loc)}</Location>\n'
            "    </Listing>")


def _montar():
    with _trava:
        if _cache["xml"] and time.monotonic() - _cache["em"] < CACHE_S:
            return _cache
    vao, fora = [], []
    for r in _linhas("SELECT codigo, imovel FROM cnm_imoveis() WHERE ok"):
        m = r["imovel"]
        falta = _falta(m)
        if falta:
            fora.append({"codigo": r["codigo"], "falta": falta})
        else:
            vao.append(_listing(m))
    cab = (f"<Provider>{EMPRESA['nome']}</Provider><Email>{EMPRESA['email']}</Email><ContactName>{EMPRESA['nome']}</ContactName>"
           f"<PublishDate>{datetime.now().strftime('%Y-%m-%dT%H:%M:%S')}</PublishDate><Telephone>{EMPRESA['telefone']}</Telephone>")
    contato = (f"<Name>{EMPRESA['nome']}</Name><Email>{EMPRESA['email']}</Email><Website>{EMPRESA['site']}</Website>"
               f"<OfficeName>{EMPRESA['nome']}</OfficeName><Telephone>{EMPRESA['telefone']}</Telephone>")
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<ListingDataFeed xmlns="http://www.vivareal.com/schemas/1.0/VRSync" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:schemaLocation="http://www.vivareal.com/schemas/1.0/VRSync http://xml.vivareal.com/vrsync.xsd">\n'
           f"  <Header>{cab}</Header>\n  <Listings>\n" + "\n".join(vao) + "\n  </Listings>\n"
           f"  <ContactInfo>{contato}</ContactInfo>\n</ListingDataFeed>\n")
    with _trava:
        _cache.update(em=time.monotonic(), xml=xml.encode("utf-8"), fora=fora, vao=len(vao))
    return _cache


@zap_bp.route("/api/zap/imoveis.xml")
def imoveis_xml():
    c = _montar()
    if request.args.get("todos"):
        return jsonify({"vao": c.get("vao"), "ficam": c["fora"]})
    return Response(c["xml"], mimetype="application/xml", headers={"Cache-Control": "public, max-age=600"})


def _segredo():
    h = request.headers.get("Authorization", "")
    if not h.lower().startswith("basic "):
        return ""
    try:
        return base64.b64decode(h[6:].strip()).decode("utf-8").partition(":")[2]
    except (ValueError, UnicodeDecodeError):
        return ""


@zap_bp.route("/api/zap/leads", methods=["POST"])
def receber_lead():
    lead = request.get_json(force=True, silent=True)
    if not isinstance(lead, dict):
        return jsonify({"erro": "o corpo tem de ser um JSON (objeto)"}), 400
    try:
        conn = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT zap_lead_receber(%s::jsonb, %s)", (json.dumps(lead, ensure_ascii=False), _segredo()))
                r = cur.fetchone()[0]
            conn.commit()
        finally:
            conn.close()
    except Exception:  # noqa: BLE001 - erro nosso: 500 e o Grupo OLX reenvia
        return jsonify({"erro": "erro interno"}), 500
    if r.get("status") == "negado":
        return jsonify({"erro": "não autorizado"}), 401
    if r.get("status") == "invalido":
        return jsonify({"erro": r.get("erro")}), 400
    return jsonify({"ok": True, "id": r.get("id"), "repetido": r.get("status") == "repetido"}), 200
