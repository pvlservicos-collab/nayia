"""ENVIO PARA CHAVES NA MÃO (Pedro, 30/10/2026): a tela do admin onde ele escolhe os imóveis do plano (400 no ar, 20 em
destaque), vê as métricas dos últimos 2 meses para decidir e gera o arquivo.

AS ROTAS (atrás da senha do /admin, como as outras de /admin/api):
  GET  /api/chavesnamao/envio.xml               A URL DE INTEGRAÇÃO (aberta, o portal lê): o XML só dos imóveis escolhidos e
                                                publicados (privado.cnm_envio_selecao, migração 538), com os links das fotos.
                                                Sai na hora do banco (preço, situação, fotos); quem deixou de entrar no portal
                                                sai sozinho. Sem escolha publicada: 404 (o portal não apaga os anúncios).
  GET  /admin/api/chavesnamao/selecao           a escolha que está publicada na URL
  POST /admin/api/chavesnamao/publicar          {ids, destaques}: confere e grava a escolha na URL
  GET  /admin/api/chavesnamao/painel?dias=60    todos os imóveis com as métricas + o perfil da demanda (cache de 5 min)
  POST /admin/api/chavesnamao/exportar          {ids, destaques, formato: "xml" | "planilha", fotos: "pagina" | "reais"}
                                                devolve o arquivo para baixar

O banco faz as contas (cnm_envio_lista e cnm_envio_demanda, migração 537); o XML é o do portal, o mesmo de
chavesnamao_api (cnm_imovel_montar), com duas diferenças:
  - destaque = 1 só nos escolhidos como destaque (no feed automático é sempre 0);
  - as fotos vão como a PÁGINA do imóvel no nosso site (pedido do Pedro: "por enquanto vai a página dele"), a não ser
    que se peça as fotos de verdade.
A "planilha" é o mesmo conteúdo em XML do Excel (SpreadsheetML) com duas abas: Imóveis e Destaques.
"""
import os
import re
import threading
import time
import unicodedata
from datetime import datetime
from decimal import Decimal
from xml.sax.saxutils import escape

import psycopg2
import psycopg2.extras
from flask import Blueprint, Response, jsonify, request

from chavesnamao_api import TAGS, _imovel

chaves_envio_bp = Blueprint("chaves_envio", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
URL_DO_XML = "https://api.imobeasy.online/api/chavesnamao/envio.xml"
SITE = "https://imobeasy.online"
LIMITE_NO_AR = 400        # o plano: anúncios
LIMITE_DESTAQUES = 20     # o plano: destaques
CACHE_S = 300

_cache: dict = {}
_trava = threading.Lock()


def _sem_acento(t: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", t or "") if not unicodedata.combining(c))


def _slug(texto: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", _sem_acento(texto).lower()).strip("-")


def _pagina(r: dict) -> str:
    """https://imobeasy.online/imovel/9090-apartamento-4-quartos-no-piazza-del-acqua (o site aceita só o código também)."""
    partes = [r.get("tipo") or ""]
    if r.get("quartos"):
        partes.append(f"{r['quartos']} quartos")
    onde = r.get("condominio") or r.get("bairro") or ""
    if onde:
        partes.append("no " + onde)
    slug = _slug(" ".join(partes))
    return f"{SITE}/imovel/{r['codigo']}" + (f"-{slug}" if slug else "")


def _num(v):
    return float(v) if isinstance(v, Decimal) else v


def _ler(sql, args=()):
    conn = psycopg2.connect(DATABASE_URL, connect_timeout=5)
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, args)
            return cur.fetchall()
    finally:
        conn.close()


def _painel(dias: int) -> dict:
    with _trava:
        c = _cache.get(dias)
        if c and time.monotonic() - c["em"] < CACHE_S:
            return c["dados"]
    linhas = _ler("SELECT * FROM cnm_envio_lista(%s)", (dias,))
    demanda = _ler("SELECT cnm_envio_demanda(%s) AS d", (dias,))[0]["d"]
    imoveis = []
    for r in linhas:
        r = {k: _num(v) for k, v in r.items()}
        r["pagina"] = _pagina(r)
        r["preco"] = r.get("valor_venda") or r.get("valor_aluguel")
        r["finalidade"] = ("ambos" if r.get("valor_venda") and r.get("valor_aluguel")
                           else "venda" if r.get("valor_venda") else "aluguel")
        r["_imovel"] = r.pop("imovel", None)
        imoveis.append(r)
    dados = {"dias": dias, "imoveis": imoveis, "demanda": demanda, "gerado_em": datetime.now().isoformat(timespec="seconds")}
    with _trava:
        _cache[dias] = {"em": time.monotonic(), "dados": dados}
    return dados


def _media(xs):
    xs = [x for x in xs if x]
    return round(sum(xs) / len(xs)) if xs else None


def _resumo(imoveis: list[dict]) -> dict:
    """As contas das métricas sobre o que foi BUSCADO: média de preço, aluguel x venda, condomínio recente x antigo."""
    buscados = [r for r in imoveis if r["buscados"] > 0]
    peso = lambda r: r["buscados"]  # noqa: E731
    return {
        "imoveis_buscados": len(buscados),
        "buscas": sum(peso(r) for r in buscados),
        "enviados": sum(r["enviados"] for r in imoveis),
        "em_grupos": sum(r["em_grupos"] for r in imoveis),
        "visitas": sum(r["visitas"] for r in imoveis),
        "buscas_em_recentes": sum(peso(r) for r in buscados if r["condo_recente"]),
        "buscas_em_antigos": sum(peso(r) for r in buscados if not r["condo_recente"]),
        "buscas_aluguel": sum(peso(r) for r in buscados if r["valor_aluguel"] and not r["valor_venda"]),
        "buscas_venda": sum(peso(r) for r in buscados if r["valor_venda"] and not r["valor_aluguel"]),
        "buscas_ambos": sum(peso(r) for r in buscados if r["valor_venda"] and r["valor_aluguel"]),
        "preco_medio_venda": _media([r["valor_venda"] for r in buscados]),
        "preco_medio_aluguel": _media([r["valor_aluguel"] for r in buscados]),
    }


# ── a URL de integração e a escolha publicada ──
_xml_cache = {"em": 0.0, "xml": None}


def _selecao() -> dict:
    return _ler("SELECT cnm_envio_selecao() AS s")[0]["s"]


def _xml_publicado():
    sel = _selecao()        # leitura barata de uma linha: o cache só vale enquanto a escolha publicada for a mesma
    ids, dest = sel.get("ids") or [], set(sel.get("destaques") or [])
    if not ids:
        return None
    marca = str(sel.get("atualizado_em"))
    with _trava:
        if _xml_cache["xml"] and _xml_cache.get("marca") == marca and time.monotonic() - _xml_cache["em"] < CACHE_S:
            return _xml_cache["xml"]
    por = {r["codigo"]: r["imovel"] for r in _ler("SELECT codigo, imovel FROM cnm_imoveis() WHERE ok AND codigo = ANY(%s)", (ids,))}
    # os destaques primeiro, depois o resto, cada grupo na ordem em que foi escolhido
    ordem = [c for c in ids if c in dest] + [c for c in ids if c not in dest]
    itens = []
    for c in ordem:
        if c not in por:
            continue                      # deixou de entrar no portal (saiu do site, perdeu foto...): sai sozinho
        m = dict(por[c])
        m["destaque"] = 1 if c in dest else 0
        itens.append(_imovel(m))
    cabeca = '<?xml version="1.0" encoding="UTF-8"?>\n<Document>\n  <imoveis>\n'
    pe = "\n  </imoveis>\n</Document>\n"
    corpo = (cabeca + "\n".join(itens) + pe).encode("utf-8")
    with _trava:
        _xml_cache.update(em=time.monotonic(), xml=corpo, marca=marca)
    return corpo


@chaves_envio_bp.route("/api/chavesnamao/envio.xml")
def envio_xml():
    corpo = _xml_publicado()
    if corpo is None:
        return Response("Nenhuma escolha de imóveis foi publicada ainda.", status=404, mimetype="text/plain")
    return Response(corpo, mimetype="application/xml", headers={"Cache-Control": "public, max-age=300"})


@chaves_envio_bp.route("/admin/api/chavesnamao/selecao")
def selecao():
    sel = _selecao()
    return jsonify({**sel, "url": URL_DO_XML})


@chaves_envio_bp.route("/admin/api/chavesnamao/publicar", methods=["POST"])
def publicar():
    corpo = request.get_json(force=True, silent=True) or {}
    try:
        ids = [int(x) for x in corpo.get("ids") or []]
        destaques = [int(x) for x in corpo.get("destaques") or []]
    except (TypeError, ValueError):
        return jsonify({"erro": "Os códigos têm de ser números."}), 400
    ids = list(dict.fromkeys(ids))
    erro = _conferir(ids, set(destaques))
    if erro:
        return jsonify(erro[0]), erro[1]
    conn = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT cnm_envio_publicar(%s, %s, %s)", (ids, destaques, "admin do site"))
            sel = cur.fetchone()[0]
        conn.commit()
    finally:
        conn.close()
    with _trava:
        _xml_cache.update(em=0.0, xml=None)
    return jsonify({**sel, "url": URL_DO_XML})


@chaves_envio_bp.route("/admin/api/chavesnamao/painel")
def painel():
    try:
        dias = max(7, min(int(request.args.get("dias") or 60), 180))
    except ValueError:
        dias = 60
    d = _painel(dias)
    imoveis = [{k: v for k, v in r.items() if k != "_imovel"} for r in d["imoveis"]]
    return jsonify({"dias": dias, "gerado_em": d["gerado_em"], "limites": {"no_ar": LIMITE_NO_AR, "destaques": LIMITE_DESTAQUES},
                    "resumo": _resumo(d["imoveis"]), "demanda": d["demanda"], "imoveis": imoveis})


# ── a exportação ──
def _xml_do_portal(escolhidos: list[dict], destaques: set[int], fotos: str) -> bytes:
    itens = []
    for r in escolhidos:
        m = dict(r["_imovel"])
        m["destaque"] = 1 if int(r["codigo"]) in destaques else 0
        m["link_cliente"] = r["pagina"]
        if fotos != "reais":
            m["fotos"] = [r["pagina"]]
        itens.append(_imovel(m))
    corpo = ('<?xml version="1.0" encoding="UTF-8"?>\n<Document>\n  <imoveis>\n' + "\n".join(itens) + "\n  </imoveis>\n</Document>\n")
    return corpo.encode("utf-8")


def _valor_da_celula(v):
    """(tipo, texto) de uma célula do Excel XML."""
    if v is None or v == "":
        return "String", ""
    if isinstance(v, bool):
        return "Number", "1" if v else "0"
    if isinstance(v, (int, float, Decimal)):
        d = Decimal(str(v))
        return "Number", str(int(d)) if d == d.to_integral_value() else format(d.normalize(), "f")
    if isinstance(v, list):
        return "String", ", ".join(str(x) for x in v)
    return "String", str(v)


def _aba(nome: str, colunas: list[str], linhas: list[list]) -> str:
    def celula(v):
        tipo, texto = _valor_da_celula(v)
        return f'<Cell><Data ss:Type="{tipo}">{escape(texto)}</Data></Cell>'
    cab = "<Row>" + "".join(f'<Cell ss:StyleID="cab"><Data ss:Type="String">{escape(c)}</Data></Cell>' for c in colunas) + "</Row>"
    corpo = "".join("<Row>" + "".join(celula(v) for v in l) + "</Row>" for l in linhas)
    return f'<Worksheet ss:Name="{escape(nome)}"><Table>{cab}{corpo}</Table></Worksheet>'


COLUNAS = TAGS + ["pagina_do_imovel", "links_das_imagens"]


def _planilha(escolhidos: list[dict], destaques: set[int], fotos: str) -> bytes:
    """O mesmo conteúdo do XML do portal em duas abas (Imóveis e Destaques), uma coluna por tag."""
    def linha(r):
        m = dict(r["_imovel"])
        m["destaque"] = 1 if int(r["codigo"]) in destaques else 0
        m["link_cliente"] = r["pagina"]
        m["fotos_imovel"] = [r["pagina"]] if fotos != "reais" else (m.get("fotos") or [])
        # 30/10 (Pedro: "uma colunha de links de imagem separados por vírgula, o link de cada imagem do imóvel"): as colunas
        # extras vão SEMPRE, qualquer que seja a escolha das fotos do XML do portal
        return [m.get(t) if t != "fotos_imovel" else m["fotos_imovel"] for t in TAGS] + [r["pagina"], ", ".join(m.get("fotos") or [])]
    todas = [linha(r) for r in escolhidos]
    dest = [linha(r) for r in escolhidos if int(r["codigo"]) in destaques]
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<?mso-application progid="Excel.Sheet"?>\n'
           '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
           '<Styles><Style ss:ID="cab"><Font ss:Bold="1"/></Style></Styles>'
           + _aba("Imóveis", COLUNAS, todas) + _aba("Destaques", COLUNAS, dest) + "</Workbook>")
    return xml.encode("utf-8")


def _conferir(ids: list[int], destaques: set[int]):
    """Os limites do plano e se cada imóvel entra no portal. Devolve (corpo do erro, status) ou None."""
    if not ids:
        return {"erro": "Escolha ao menos um imóvel."}, 400
    if len(ids) > LIMITE_NO_AR:
        return {"erro": f"O plano leva {LIMITE_NO_AR} imóveis; foram escolhidos {len(ids)}."}, 400
    if not destaques <= set(ids):
        return {"erro": "Todo destaque tem de estar entre os imóveis escolhidos."}, 400
    if len(destaques) > LIMITE_DESTAQUES:
        return {"erro": f"O plano leva {LIMITE_DESTAQUES} destaques; foram marcados {len(destaques)}."}, 400
    por_codigo = {int(r["codigo"]): r for r in _painel(60)["imoveis"]}
    fora = [c for c in ids if c not in por_codigo or not por_codigo[c]["ok"]]
    if fora:
        return {"erro": "Estes imóveis não entram no portal (incompletos ou fora do site): " + ", ".join(map(str, fora[:20])), "codigos": fora}, 400
    return None


@chaves_envio_bp.route("/admin/api/chavesnamao/exportar", methods=["POST"])
def exportar():
    corpo = request.get_json(force=True, silent=True) or {}
    try:
        ids = [int(x) for x in corpo.get("ids") or []]
        destaques = {int(x) for x in corpo.get("destaques") or []}
    except (TypeError, ValueError):
        return jsonify({"erro": "Os códigos têm de ser números."}), 400
    formato = "planilha" if corpo.get("formato") == "planilha" else "xml"
    fotos = "pagina" if corpo.get("fotos") == "pagina" else "reais"
    ids = list(dict.fromkeys(ids))
    erro = _conferir(ids, destaques)
    if erro:
        return jsonify(erro[0]), erro[1]
    por_codigo = {int(r["codigo"]): r for r in _painel(60)["imoveis"]}
    escolhidos = [por_codigo[c] for c in ids]
    quando = datetime.now().strftime("%Y%m%d-%H%M")
    if formato == "planilha":
        dados, tipo, nome = _planilha(escolhidos, destaques, fotos), "application/vnd.ms-excel", f"chaves-na-mao-planilha-{quando}.xml"
    else:
        dados, tipo, nome = _xml_do_portal(escolhidos, destaques, fotos), "application/xml", f"chaves-na-mao-{quando}.xml"
    return Response(dados, mimetype=tipo, headers={"Content-Disposition": f'attachment; filename="{nome}"',
                                                   "X-Imoveis": str(len(escolhidos)), "X-Destaques": str(len(destaques)),
                                                   "Cache-Control": "no-store"})
