"""CHAVES NA MÃO: o XML dos nossos imóveis e os leads que o portal manda (458, Pedro, 21/10/2026).

Pedro: "veja como fazemos para integrar nossos imóveis no chaves na mão também igual olx" e "veja tudo aí e deixe
preparado" (com a documentação do portal: chavesnamao.github.io/xml-documentation e /lead-documentation).

AS ROTAS (abertas: quem confere o lead é o banco; o XML só leva o que já está no nosso site):
  GET  /api/chavesnamao/imoveis.xml   o arquivo que o portal lê (uma vez por dia). Quem vai e como vai é
                                      cnm_imoveis() no banco; aqui só se escreve o XML na ordem das tags do portal.
                                      ?todos=1 lista também quem ficou de fora, em JSON, com o motivo.
  POST /api/chavesnamao/leads         o lead do portal (JSON). Authorization: Basic base64(email:token) e o
                                      User-Agent chavesnamao-leads-api; cnm_lead_receber() confere e guarda
                                      (privado.cnm_lead). O mesmo id duas vezes responde 200 e não duplica.

Respostas do lead, como a documentação pede: 2xx = recebido (o portal não reenvia); 400 = dado inválido (não
reenvia); 401 = senha errada; 500 = erro nosso (o portal tenta de novo até 3 vezes).
"""
import base64
import json
import os
import threading
import time
from decimal import Decimal
from xml.sax.saxutils import escape

import psycopg2
import psycopg2.extras
from flask import Blueprint, Response, jsonify, request

chavesnamao_bp = Blueprint("chavesnamao", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
CACHE_S = 600   # o portal lê uma vez por dia; 10 min poupa o banco de quem abrir o link várias vezes

# A ORDEM DAS TAGS é a do exemplo oficial (arquivo/imovel.html). Todas vão, mesmo vazias: o portal exige.
TAGS = ["referencia", "codigo_cliente", "link_cliente", "titulo", "transacao", "transacao2", "finalidade",
        "finalidade2", "destaque", "tipo", "tipo2", "valor", "valor_locacao", "valor_iptu", "valor_condominio",
        "area_total", "area_util", "conservacao", "quartos", "suites", "garagem", "banheiro", "closet", "salas",
        "despensa", "bar", "cozinha", "quarto_empregada", "escritorio", "area_servico", "lareira", "varanda",
        "lavanderia", "aceita_pet", "estado", "cidade", "bairro", "cep", "endereco", "numero", "complemento",
        "esconder_endereco_imovel", "descritivo", "fotos_imovel", "data_atualizacao", "latitude", "longitude",
        "video", "tour_360", "area_comum", "area_privativa", "aceita_troca", "periodo_locacao"]

_cache = {"em": 0.0, "xml": None}
_trava = threading.Lock()


def _numero(v):
    """Sem separador de milhar, ponto decimal; inteiro sai sem ".0"."""
    d = Decimal(str(v))
    return str(int(d)) if d == d.to_integral_value() else format(d.normalize(), "f")


def _texto(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float, Decimal)):
        return _numero(v)
    return escape(str(v))


def _cdata(s):
    return "<![CDATA[" + (s or "").replace("]]>", "]]]]><![CDATA[>") + "]]>"


def _imovel(m):
    linhas = ["    <imovel>"]
    for tag in TAGS:
        if tag == "descritivo":
            linhas.append(f"      <descritivo>{_cdata(m.get('descritivo'))}</descritivo>")
        elif tag == "fotos_imovel":
            fotos = m.get("fotos") or []
            linhas.append("      <fotos_imovel>")
            for url in fotos:
                linhas.append(f"        <foto>\n          <url>{escape(url)}</url>\n          <data_atualizacao></data_atualizacao>\n        </foto>")
            linhas.append("      </fotos_imovel>")
        elif tag in ("area_comum", "area_privativa"):
            itens = m.get(tag) or []
            if itens:
                linhas.append(f"      <{tag}>")
                linhas.extend(f"        <item>{escape(i)}</item>" for i in itens)
                linhas.append(f"      </{tag}>")
            else:
                linhas.append(f"      <{tag}></{tag}>")   # vazia: a tag existe sem <item> (especificação das áreas)
        else:
            linhas.append(f"      <{tag}>{_texto(m.get(tag))}</{tag}>")
    linhas.append("    </imovel>")
    return "\n".join(linhas)


def _linhas(sql):
    conn = psycopg2.connect(DATABASE_URL, connect_timeout=5)
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql)
            return cur.fetchall()
    finally:
        conn.close()


def _xml():
    with _trava:
        if _cache["xml"] and time.monotonic() - _cache["em"] < CACHE_S:
            return _cache["xml"]
        imoveis = [r["imovel"] for r in _linhas("SELECT imovel FROM cnm_imoveis() WHERE ok")]
        corpo = ('<?xml version="1.0" encoding="UTF-8"?>\n<Document>\n  <imoveis>\n'
                 + "\n".join(_imovel(m) for m in imoveis)
                 + "\n  </imoveis>\n</Document>\n")
        _cache.update(em=time.monotonic(), xml=corpo.encode("utf-8"))
        return _cache["xml"]


@chavesnamao_bp.route("/api/chavesnamao/imoveis.xml")
def imoveis_xml():
    if request.args.get("todos"):
        linhas = _linhas("SELECT codigo, ok, falta FROM cnm_imoveis()")
        return jsonify({"vao": sum(1 for l in linhas if l["ok"]),
                        "ficam": [{"codigo": l["codigo"], "falta": l["falta"]} for l in linhas if not l["ok"]]})
    return Response(_xml(), mimetype="application/xml", headers={"Cache-Control": "public, max-age=600"})


def _basic():
    h = request.headers.get("Authorization", "")
    if not h.lower().startswith("basic "):
        return "", ""
    try:
        email, _, token = base64.b64decode(h[6:].strip()).decode("utf-8").partition(":")
        return email, token
    except (ValueError, UnicodeDecodeError):
        return "", ""


@chavesnamao_bp.route("/api/chavesnamao/leads", methods=["POST"])
def receber_lead():
    lead = request.get_json(force=True, silent=True)
    if not isinstance(lead, dict):
        return jsonify({"error": "Dados inválidos", "details": "o corpo tem de ser um JSON (objeto)"}), 400
    email, token = _basic()
    try:
        conn = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT cnm_lead_receber(%s::jsonb, %s, %s, %s)",
                            (json.dumps(lead, ensure_ascii=False), email, token, request.headers.get("User-Agent", "")))
                r = cur.fetchone()[0]
            conn.commit()
        finally:
            conn.close()
    except Exception:  # noqa: BLE001 - erro nosso: 500 e o portal manda de novo
        return jsonify({"error": "Erro interno ao processar lead"}), 500
    status = r.get("status")
    if status == "negado":
        return jsonify({"error": "Não autorizado"}), 401
    if status == "invalido":
        return jsonify({"error": "Dados inválidos", "details": r.get("erro")}), 400
    return jsonify({"success": True, "leadId": r.get("id"),
                    "message": "Lead já processado" if status == "repetido" else "Lead recebido com sucesso"}), 200
