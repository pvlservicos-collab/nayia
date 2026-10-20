"""Procurar na OLX o imóvel que o cliente pediu e dar a nota (416, Pedro 19/10/2026).

"usando nosso mesmo mecanismo de nota da aba Grupos; se o anúncio tiver uma correspondência maior do que 88 ... abrir o
anúncio e verificar o contato". A nota é a da Captação ativa por grupos, sem cópia: o código de /root/nay-grupos
(`grupos.pontuar`, `grupos.lugares`, `grupos.regras`, com o config.json de lá). O anúncio vira o "imóvel" que essa conta
entende; o pedido vem dos filtros que a Nay do WhatsApp já juntou (`privado.olx_lead_whatsapp.filtros`).

A lista da OLX vem pronta no HTML (Next.js: os pedaços `self.__next_f`, "ads":[...], 50 por página); o anúncio aberto
traz o bloco `initial-data` (descrição, anunciante, fotos). Os dois formatos foram medidos em 18/10 (scrap das 4 buscas).
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse

from olx import cdp

sys.path.insert(0, os.environ.get("NAY_GRUPOS_DIR", "/root/nay-grupos"))
from grupos import catalogo as gcatalogo  # noqa: E402
from grupos import lugares as glugares  # noqa: E402
from grupos import pontuar as gpontuar  # noqa: E402
from grupos import regras as gregras  # noqa: E402
from grupos.texto import normal  # noqa: E402

REGRAS_DOS_GRUPOS = os.environ.get("GRUPOS_REGRAS", os.path.join(os.environ.get("NAY_GRUPOS_DIR", "/root/nay-grupos"),
                                                                  "config.json"))
BASE = "https://www.olx.com.br/imoveis/{negocio}/estado-am/regiao-de-manaus/manaus"
NOSSOS = ("imob easy", "imobeasy", "f v sobreira", "telmario")      # os nossos anúncios não são de parceiro

# a lista: junta os pedaços do Next.js que estão no HTML (a página não precisa terminar de carregar)
JS_LISTA = r"""(() => { try {
  const pedacos = [];
  for (const sc of document.scripts) {
    const t = sc.textContent || '';
    if (!t.startsWith('self.__next_f.push([1,')) continue;
    const m = t.match(/^self\.__next_f\.push\(\[1,("[\s\S]*")\]\)\s*;?\s*$/);
    if (m) { try { pedacos.push(JSON.parse(m[1])) } catch (e) {} }
  }
  const f = pedacos.join('');
  return f.includes('"ads":[') && f.includes('"totalOfAds"') ? f : null;
} catch (e) { return null } })()"""
JS_DETALHE = r"""(() => { const e = document.getElementById('initial-data'); return e ? e.getAttribute('data-json') : null })()"""


def _numero(v) -> float | None:
    m = re.search(r"\d[\d.]*(?:,\d+)?", str(v or ""))
    if not m:
        return None
    return float(m.group(0).replace(".", "").replace(",", "."))


def _int(v) -> int | None:
    n = _numero(v)
    return int(n) if n is not None else None


def operacao(filtros: dict) -> str:
    return "venda" if str(filtros.get("finalidade") or "").lower().startswith("vend") else "aluguel"


def tipo_texto(tipo: str | None) -> str:
    t = normal(tipo)
    return "casa" if t.startswith("casa") else "apartamento" if t.startswith(("apart", "kitnet", "flat", "studio")) else ""


# OS FILTROS DA OLX (Pedro, 20/10/2026: "a busca precisa ser mais detalhada, de preferência igual ao filtro da OLX").
# Os nomes e códigos foram lidos da própria página de busca da OLX (definição dos filtros no Next.js) e conferidos em
# 20/10: múltipla escolha = o parâmetro repetido; anunciante f=p/f=c; ordem sf=1 (recentes) e sp=1 (menor preço).
SUBTIPOS_OLX = {"casa_condominio": "300", "casa_vila": "301", "cobertura": "302", "duplex": "303", "kitnet": "304",
                "loft": "305", "padrao": "306"}
DETALHES_DO_IMOVEL_OLX = {"academia": "100", "aquecimento": "101", "ar_condicionado": "102", "area_servico": "103",
                          "armarios_cozinha": "104", "armarios_quarto": "105", "banheiro_quarto": "106", "churrasqueira": "107",
                          "internet": "108", "mobiliado": "109", "piscina": "110", "porteiro_24h": "111",
                          "quarto_servico": "112", "salao_festas": "113", "tv_cabo": "114", "varanda": "115"}
DETALHES_DO_CONDOMINIO_OLX = {"academia": "200", "area_murada": "201", "condominio_fechado": "202", "elevador": "203",
                              "aceita_pet": "204", "piscina": "205", "portao_eletronico": "206", "portaria": "207",
                              "salao_festas": "208", "seguranca_24h": "209"}
TIPOS_OLX = {"apartamento": ("apartamentos", "1020"), "casa": ("casas", "1040")}


def _lista(v) -> list:
    return [x for x in (v if isinstance(v, list) else [v] if v not in (None, "") else []) if x not in (None, "")]


def _ate_5(v) -> list[str]:
    """Quartos, banheiros, vagas: 0..4 e 5 (= 5 ou mais), como os chips da OLX."""
    saida = []
    for x in _lista(v):
        n = _int(x)
        if n is not None and 0 <= n:
            saida.append(str(min(n, 5)))
    return sorted(set(saida))


def parametros_da_olx(filtros: dict) -> tuple[list[tuple[str, str]], str]:
    """(os pares do endereço, o pedaço do caminho do tipo) a partir dos filtros (os da Nay e o bloco "olx" do CRM)."""
    o = filtros.get("olx") if isinstance(filtros.get("olx"), dict) else {}
    pares: list[tuple[str, str]] = []
    ordem = str(o.get("ordem") or "recentes")
    if ordem == "recentes":
        pares.append(("sf", "1"))
    elif ordem == "menor_preco":
        pares.append(("sp", "1"))
    teto = _numero(filtros.get("teto"))
    minimo = _numero(o.get("preco_min"))
    if minimo or teto:
        pares.append(("ps", str(int(minimo if minimo else teto * 0.6))))
    if teto:
        pares.append(("pe", str(int(teto * 1.1))))      # até 10% acima do teto: a nota sabe pesar (aba Grupos)
    for qs, k in (("ips", "iptu_min"), ("ipe", "iptu_max"), ("ss", "area_min"), ("se", "area_max")):
        n = _numero(o.get(k))
        if n:
            pares.append((qs, str(int(n))))
    quartos = _ate_5(o.get("quartos")) or ([str(min(_int(filtros.get("quartos")), 5))] if _int(filtros.get("quartos")) else [])
    if quartos and filtros.get("aceita_menos_quartos") in (True, "true"):
        quartos = sorted(set(quartos) | {str(max(0, int(min(quartos)) - 1))})
    for qs, valores in (("ros", quartos), ("bas", _ate_5(o.get("banheiros"))), ("gsp", _ate_5(o.get("vagas")))):
        pares += [(qs, v) for v in valores]
    pares += [("rts", SUBTIPOS_OLX[x]) for x in _lista(o.get("subtipos")) if x in SUBTIPOS_OLX]
    detalhes = [x for x in _lista(o.get("detalhes")) if x in DETALHES_DO_IMOVEL_OLX]
    if normal(filtros.get("mobilia")).startswith("mobil") and "mobiliado" not in detalhes:
        detalhes.append("mobiliado")
    pares += [("rfs", DETALHES_DO_IMOVEL_OLX[x]) for x in detalhes]
    cond = [x for x in _lista(o.get("condominio")) if x in DETALHES_DO_CONDOMINIO_OLX]
    if filtros.get("aceita_escada") in (False, "false") and "elevador" not in cond:
        cond.append("elevador")
    pares += [("rcf", DETALHES_DO_CONDOMINIO_OLX[x]) for x in cond]
    if o.get("anunciante") in ("p", "c"):
        pares.append(("f", o["anunciante"]))
    tipos = [t for t in _lista(o.get("tipos")) if t in TIPOS_OLX] or ([tipo_texto(filtros.get("tipo"))] if tipo_texto(filtros.get("tipo")) else [])
    caminho = ""
    if len(tipos) == 1:
        caminho = TIPOS_OLX[tipos[0]][0]
    elif len(tipos) > 1:
        pares += [("ret", TIPOS_OLX[t][1]) for t in tipos]
    return pares, caminho


def urls_da_busca(filtros: dict, max_bairros: int = 3) -> list[str]:
    """Uma busca por bairro pedido (até 3), ou uma só sem bairro; os filtros da OLX no endereço (a nota é quem separa)."""
    pares, caminho = parametros_da_olx(filtros)
    bairros = [] if filtros.get("qualquer_bairro") else [b for b in (filtros.get("bairros") or []) if str(b).strip()][:max_bairros]
    base = BASE.format(negocio=operacao(filtros))
    if caminho:
        base = base.replace("/imoveis/" + operacao(filtros) + "/", "/imoveis/" + operacao(filtros) + "/" + caminho + "/")
    return [base + "?" + urllib.parse.urlencode(pares + ([("q", b)] if b else [])) for b in (bairros or [""])]


def anuncios_da_lista(flight: str) -> list[dict]:
    i = flight.find('"ads":[')
    if i < 0:
        return []
    ads, _ = json.JSONDecoder().raw_decode(flight, i + len('"ads":'))
    return [a for a in ads if isinstance(a, dict) and a.get("listId")]


def e_nosso(a: dict) -> bool:
    quem = normal(((a.get("olxPay") or {}).get("transactionalSellerName")) or a.get("anunciante") or "")
    return any(n in quem for n in NOSSOS)


def para_imovel(a: dict, oper: str) -> dict:
    """O anúncio da OLX no formato que `grupos.pontuar.avaliar` entende."""
    props = {p.get("name"): p.get("value") for p in a.get("properties") or []}
    cat = normal(props.get("category") or a.get("categoryName"))
    tipo = "apartamento" if cat.startswith("apart") else "casa" if cat.startswith("casa") else "outro"
    det, cond = normal(props.get("re_features")), normal(props.get("re_complex_features"))
    if "elevador" in det + " " + cond:
        elevador, como = True, "o anúncio lista elevador"
    elif tipo == "apartamento" and cond:
        elevador, como = False, "o anúncio lista o condomínio sem elevador"
    else:
        elevador, como = None, "elevador não informado no anúncio"
    bairro = (a.get("locationDetails") or {}).get("neighbourhood")
    preco = _numero(a.get("price") or a.get("priceValue"))
    return {
        "codigo": a["listId"], "tipo": tipo, "bairro": bairro, "bairro_chave": normal(bairro),
        "condominio": None, "condominio_chave": "", "quartos": _int(props.get("rooms")), "suites": None,
        "vagas": _int(props.get("garage_spaces")), "andar": None,
        "mobilia": "mobiliado" if "mobiliado" in det else None, "pet": None, "financiamento": None,
        "elevador": elevador, "elevador_como": como,
        "valor_aluguel": preco if oper == "aluguel" else None, "valor_venda": preco if oper == "venda" else None,
        "area": _numero(props.get("size")), "confirmado_em": None, "confirmado_como": "anúncio no ar na OLX",
    }


def pedido_dos_filtros(filtros: dict, lugares) -> dict:
    """Os filtros da Nay do WhatsApp no formato do pedido da aba Grupos (o lugar passa pelo mesmo resolvedor)."""
    q = _int(filtros.get("quartos"))
    if not q and _ate_5((filtros.get("olx") or {}).get("quartos") if isinstance(filtros.get("olx"), dict) else None):
        q = int(min(_ate_5(filtros["olx"]["quartos"])))     # o menor dos marcados é o que a nota pede
    if q and filtros.get("aceita_menos_quartos") in (True, "true"):
        q = max(1, q - 1)
    mob = normal(filtros.get("mobilia"))
    o = filtros.get("olx") if isinstance(filtros.get("olx"), dict) else {}
    if not mob and "mobiliado" in _lista(o.get("detalhes")):
        mob = "mobiliado"                                   # 20/10: marcado no filtro da OLX do CRM
    escada = filtros.get("aceita_escada")
    if escada is None and "elevador" in _lista(o.get("condominio")):
        escada = False
    ficha = {
        "bairros": [] if filtros.get("qualquer_bairro") else list(filtros.get("bairros") or []),
        "condominio": None, "operacao": operacao(filtros), "tipo": tipo_texto(filtros.get("tipo")) or None,
        "quartos": q, "preco_max": _numero(filtros.get("teto")),
        "mobiliado": True if mob.startswith(("mobil", "semi")) else False if mob.startswith(("nao", "sem", "vazio")) else None,
        "andar": None, "suite": None, "vagas": None, "pet": None,
        "financiamento": True if normal(filtros.get("financiamento")).startswith(("simul", "aprov", "financ", "sim")) else None,
        # "serve escada?" -> "não": é o pedido de elevador (394)
        "elevador": True if escada in (False, "false") else None,
        "trecho": "",
    }
    pedido, _local, _duv = glugares.resolver(ficha, None, lugares)
    return pedido


def buscar(conn, base_cdp: str, filtros: dict, paginas: int = 1) -> list[dict]:
    """Os anúncios da OLX com a nota, os melhores primeiro: [{nota, detalhe, anuncio, imovel}]. Levanta cdp.SemNavegador."""
    regras, _ = gregras.carregar(REGRAS_DOS_GRUPOS)
    _imoveis, vizinhos = gcatalogo.carregar(conn)
    pedido = pedido_dos_filtros(filtros, glugares.Lugares(conn))
    oper = operacao(filtros)
    vistos: dict[int, dict] = {}
    for url in urls_da_busca(filtros):
        for pagina in range(1, paginas + 1):
            with cdp.Aba(base_cdp, url + ("&o=%d" % pagina if pagina > 1 else "")) as aba:
                flight = aba.esperar(JS_LISTA, ate_s=30)
                if not flight:
                    titulo = aba.avaliar("document.title") or ""
                    if re.search(r"blocked|attention required", titulo, re.I):
                        raise cdp.SemNavegador("a OLX bloqueou o navegador")
                    break
            for a in anuncios_da_lista(flight):
                if a["listId"] in vistos or e_nosso(a):
                    continue
                im = para_imovel(a, oper)
                etapa, r = gpontuar.avaliar(pedido, im, regras, vizinhos, None)
                if etapa or not r or r.get("nota") is None:
                    continue
                vistos[a["listId"]] = {"nota": float(r["nota"]), "detalhe": r["detalhe"], "anuncio": resumo(a), "imovel": im}
    return sorted(vistos.values(), key=lambda c: -c["nota"])


def resumo(a: dict) -> dict:
    props = {p.get("name"): p.get("value") for p in a.get("properties") or []}
    return {"olx_id": a["listId"], "titulo": a.get("subject"), "preco_texto": a.get("price") or a.get("priceValue"),
            "bairro": (a.get("locationDetails") or {}).get("neighbourhood"), "url": a.get("url"),
            "quartos": props.get("rooms"), "area": props.get("size"), "condominio": props.get("condominio"),
            "anunciante": (a.get("olxPay") or {}).get("transactionalSellerName"),
            "profissional": a.get("professionalAd"), "fotos": [i.get("original") for i in (a.get("images") or [])][:10]}


def _achar_anuncio(o):
    if isinstance(o, dict):
        if o.get("listId") and o.get("subject"):
            return o
        for v in o.values():
            r = _achar_anuncio(v)
            if r:
                return r
    elif isinstance(o, list):
        for v in o:
            r = _achar_anuncio(v)
            if r:
                return r
    return None


def detalhe(base_cdp: str, url: str) -> dict | None:
    """O anúncio aberto: descrição, anunciante, o telefone que a OLX mostra (mascarado), fotos, CEP."""
    with cdp.Aba(base_cdp, url) as aba:
        dj = aba.esperar(JS_DETALHE, ate_s=30)
    if not dj:
        return None
    a = _achar_anuncio(json.loads(dj))
    if not a:
        return None
    u, loc = a.get("user") or {}, a.get("location") or {}
    corpo = re.sub(r"<br\s*/?>", "\n", a.get("body") or "", flags=re.I)
    return {"descricao": re.sub(r"<[^>]+>", "", corpo).strip(), "anunciante": u.get("name"),
            "anunciante_id": u.get("publicAccountId"), "telefone_mascarado": (a.get("phone") or {}).get("maskedPhone"),
            "fotos": [i.get("original") for i in (a.get("images") or []) if i.get("original")][:10],
            "cep": loc.get("zipcode"), "bairro": loc.get("neighbourhood"), "preco_texto": a.get("priceValue"),
            "titulo": a.get("subject"), "url": a.get("friendlyUrl") or url}
