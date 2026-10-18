"""SCRAP, O GERENCIADOR DE LISTAS (407, Pedro 18/10/2026) -- menu Scrap do admin do site.

Pedro: "crie um menu lá no menu que desce do site escrito Scrap e salve essa lista lá das 4 url por coluna, minha ideia
é focar nos dados, nome e telefone principalmente, faz uma limpa em duplicados e tire os sem número e monte essas 4
listas lá, essa aba scrap vai ser um grande gerenciador de listas".

Listas de contatos (nome + telefone) que nascem de uma raspagem (a OLX, por enquanto), de um CSV ou da mão. A raspagem
NÃO roda aqui: a OLX barra o servidor (Cloudflare); ela roda no PC do Pedro pelo Chrome escondido do Agente OLX e manda
o resultado para /admin/api/scrap/importar. O banco: funções site_scrap_* (migração 407), pelos papéis do site.

ROTAS (todas atrás da senha do /admin)
  GET    /admin/api/scrap/listas                  as listas com as contagens
  POST   /admin/api/scrap/listas                  cria/edita {id?, nome, descricao, cor, url_busca}
  DELETE /admin/api/scrap/listas/<id>
  GET    /admin/api/scrap/contatos?lista=&q=&status=&etiqueta=&bairro=&ordem=&limite=&desloc=
  POST   /admin/api/scrap/contatos                cria/edita um contato {id?, lista_id, nome, telefone, empresa, status, etiquetas, observacao}
  POST   /admin/api/scrap/contatos/acao           {ids: [...], acao: status|etiqueta_por|etiqueta_tirar|mover|copiar|apagar, valor}
  GET    /admin/api/scrap/anuncios?telefone=&lista=   os anúncios de um contato
  POST   /admin/api/scrap/importar                {lista: {nome|id, url_busca}, anuncios: [...]} (a raspagem)
  POST   /admin/api/scrap/importar-contatos       {lista_id, contatos: [{nome, telefone, ...}]} ou {lista_id, csv: "nome;telefone..."}
  GET    /admin/api/scrap/exportar.csv?lista=&q=&status=&etiqueta=&bairro=
"""
import csv
import io
import json
import os
import re

import psycopg2
import psycopg2.extras
from flask import Blueprint, Response, jsonify, request

from imoveis_api import _admin_autenticado
from disparo_api import _usuario_admin

scrap_bp = Blueprint("scrap", __name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
STATUS = ("novo", "contatado", "respondeu", "interessado", "descartado")


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


def _negado():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


def _quem():
    try:
        return _usuario_admin() or "admin"
    except Exception:  # noqa: BLE001
        return "admin"


def _erro(exc, o_que):
    return jsonify({"ok": False, "erro": "%s: %s" % (o_que, str(exc).splitlines()[0][:200])}), 500


def _int(v, padrao):
    try:
        return int(str(v).strip())
    except Exception:  # noqa: BLE001
        return padrao


def _opt(nome):
    v = (request.args.get(nome) or "").strip()
    return v or None


# ---------------------------------------------------------------- listas
@scrap_bp.route("/admin/api/scrap/listas")
def listas():
    if not _admin_autenticado():
        return _negado()
    try:
        return jsonify(_um("SELECT site_scrap_listas() AS r") or {"listas": []})
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não li as listas")


@scrap_bp.route("/admin/api/scrap/listas", methods=["POST"])
def lista_salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_scrap_lista_salvar(%s::jsonb, %s) AS r", (json.dumps(b, ensure_ascii=False), _quem()), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não salvou a lista")
    return jsonify(r), (200 if r.get("ok") else 422)


@scrap_bp.route("/admin/api/scrap/listas/<int:lid>", methods=["DELETE"])
def lista_apagar(lid):
    if not _admin_autenticado():
        return _negado()
    try:
        r = _um("SELECT site_scrap_lista_apagar(%s) AS r", (lid,), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não apagou a lista")
    return jsonify(r), (200 if r.get("ok") else 422)


# ---------------------------------------------------------------- contatos
def _filtros():
    lista = _int(request.args.get("lista"), 0) or None
    return (lista, _opt("q"), _opt("status"), _opt("etiqueta"), _opt("bairro"), _opt("ordem") or "anuncios")


@scrap_bp.route("/admin/api/scrap/contatos")
def contatos():
    if not _admin_autenticado():
        return _negado()
    lista, q, status, etiqueta, bairro, ordem = _filtros()
    limite = min(max(_int(request.args.get("limite"), 200), 1), 2000)
    desloc = max(_int(request.args.get("desloc"), 0), 0)
    try:
        r = _um("SELECT site_scrap_contatos(%s, %s, %s, %s, %s, %s, %s, %s) AS r", (lista, q, status, etiqueta, bairro, ordem, limite, desloc))
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não li os contatos")
    return jsonify(r or {"total": 0, "contatos": [], "bairros": []})


@scrap_bp.route("/admin/api/scrap/contatos", methods=["POST"])
def contato_salvar():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    try:
        r = _um("SELECT site_scrap_contato_salvar(%s::jsonb, %s) AS r", (json.dumps(b, ensure_ascii=False), _quem()), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não salvou o contato")
    return jsonify(r), (200 if r.get("ok") else 422)


@scrap_bp.route("/admin/api/scrap/contatos/acao", methods=["POST"])
def contatos_acao():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    ids = [int(x) for x in (b.get("ids") or []) if str(x).strip().isdigit()]
    acao = str(b.get("acao") or "").strip()
    valor = b.get("valor")
    valor = None if valor is None else str(valor).strip()
    if not ids:
        return jsonify({"ok": False, "erro": "nenhum contato escolhido"}), 422
    try:
        r = _um("SELECT site_scrap_contatos_acao(%s::bigint[], %s, %s) AS r", (ids, acao, valor), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não fez a ação")
    return jsonify(r), (200 if r.get("ok") else 422)


@scrap_bp.route("/admin/api/scrap/anuncios")
def anuncios():
    if not _admin_autenticado():
        return _negado()
    tel = _opt("telefone")
    if not tel:
        return jsonify({"anuncios": []})
    lista = _int(request.args.get("lista"), 0) or None
    try:
        return jsonify({"anuncios": _um("SELECT site_scrap_anuncios(%s, %s) AS r", (tel, lista)) or []})
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não li os anúncios")


# ---------------------------------------------------------------- carga
@scrap_bp.route("/admin/api/scrap/importar", methods=["POST"])
def importar():
    """A raspagem manda {lista: {nome|id, url_busca, descricao}, anuncios: [...]}. Grandes: até uns 20 MB."""
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True, cache=False) or {}
    if not isinstance(b.get("anuncios"), list):
        return jsonify({"ok": False, "erro": "mande {lista, anuncios: [...]}"}), 422
    try:
        r = _um("SELECT site_scrap_importar(%s::jsonb, %s) AS r", (json.dumps(b, ensure_ascii=False), _quem()), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não importou")
    return jsonify(r), (200 if r.get("ok") else 422)


_CAB = {"nome": ("nome", "name", "contato", "anunciante", "cliente"), "telefone": ("telefone", "fone", "celular", "whatsapp", "numero", "número", "tel", "phone"),
        "empresa": ("empresa", "imobiliaria", "imobiliária", "loja"), "observacao": ("observacao", "observação", "obs", "nota"), "etiquetas": ("etiquetas", "tags", "etiqueta")}


def _csv_para_contatos(texto):
    """CSV/TSV/colado do Excel: cabeçalho opcional; sem cabeçalho, a coluna com cara de telefone é o telefone e a outra o nome."""
    texto = (texto or "").lstrip("﻿")
    if not texto.strip():
        return []
    amostra = "\n".join(texto.splitlines()[:5])
    try:
        dialeto = csv.Sniffer().sniff(amostra, delimiters=";,\t|")
    except Exception:  # noqa: BLE001
        class dialeto(csv.excel):  # noqa: N801
            delimiter = ";" if amostra.count(";") >= amostra.count(",") else ","
    linhas = [l for l in csv.reader(io.StringIO(texto), dialect=dialeto) if any((c or "").strip() for c in l)]
    if not linhas:
        return []
    cab = [c.strip().lower() for c in linhas[0]]
    mapa = {}
    for i, c in enumerate(cab):
        for campo, nomes in _CAB.items():
            if c in nomes and campo not in mapa:
                mapa[campo] = i
    if "telefone" in mapa:
        linhas = linhas[1:]
    else:
        # sem cabeçalho: a coluna com mais telefones é o telefone, a primeira outra é o nome
        pontos = {}
        for l in linhas[:50]:
            for i, c in enumerate(l):
                if re.search(r"\d{4}[\s.-]?\d{4}", c or ""):
                    pontos[i] = pontos.get(i, 0) + 1
        if not pontos:
            return []
        itel = max(pontos, key=pontos.get)
        mapa = {"telefone": itel}
        outras = [i for i in range(len(linhas[0])) if i != itel]
        if outras:
            mapa["nome"] = outras[0]
        if len(outras) > 1:
            mapa["empresa"] = outras[1]
    saida = []
    for l in linhas:
        def pega(campo):
            i = mapa.get(campo)
            return (l[i].strip() if i is not None and i < len(l) and l[i] is not None else "")
        item = {"nome": pega("nome"), "telefone": pega("telefone"), "empresa": pega("empresa"), "observacao": pega("observacao")}
        et = pega("etiquetas")
        if et:
            item["etiquetas"] = [e.strip() for e in re.split(r"[,|/]", et) if e.strip()]
        if item["telefone"]:
            saida.append(item)
    return saida


@scrap_bp.route("/admin/api/scrap/importar-contatos", methods=["POST"])
def importar_contatos():
    if not _admin_autenticado():
        return _negado()
    b = request.get_json(silent=True) or {}
    lid = _int(b.get("lista_id"), 0)
    if not lid:
        return jsonify({"ok": False, "erro": "escolha a lista"}), 422
    contatos = b.get("contatos")
    if not isinstance(contatos, list):
        contatos = _csv_para_contatos(str(b.get("csv") or ""))
    if not contatos:
        return jsonify({"ok": False, "erro": "não achei nenhuma linha com telefone"}), 422
    try:
        r = _um("SELECT site_scrap_importar_contatos(%s, %s::jsonb, %s) AS r", (lid, json.dumps(contatos, ensure_ascii=False), _quem()), escrita=True) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não importou os contatos")
    r["lidos"] = len(contatos)
    return jsonify(r), (200 if r.get("ok") else 422)


@scrap_bp.route("/admin/api/scrap/exportar.csv")
def exportar():
    if not _admin_autenticado():
        return _negado()
    lista, q, status, etiqueta, bairro, ordem = _filtros()
    try:
        r = _um("SELECT site_scrap_contatos(%s, %s, %s, %s, %s, %s, %s, %s) AS r", (lista, q, status, etiqueta, bairro, ordem, 100000, 0)) or {}
    except Exception as exc:  # noqa: BLE001
        return _erro(exc, "Não exportou")
    saida = io.StringIO()
    w = csv.writer(saida, delimiter=";", lineterminator="\r\n")
    w.writerow(["nome", "telefone", "telefone_whatsapp", "empresa", "lista", "status", "etiquetas", "anuncios", "bairros", "preco_min", "preco_max",
                "confirmado_olx", "exemplo_titulo", "exemplo_url", "observacao", "tambem_em"])
    for c in r.get("contatos") or []:
        w.writerow([c.get("nome") or "", c.get("telefone_fmt") or "", "55" + (c.get("telefone") or ""), c.get("empresa") or "", c.get("lista_nome") or "",
                    c.get("status") or "", ", ".join(c.get("etiquetas") or []), c.get("n_anuncios") or 0, ", ".join(c.get("bairros") or []),
                    c.get("preco_min") or "", c.get("preco_max") or "", "sim" if c.get("confirmado") else "", c.get("exemplo_titulo") or "",
                    c.get("exemplo_url") or "", c.get("observacao") or "", ", ".join(c.get("tambem_em") or [])])
    nome = "scrap-%s.csv" % (lista or "todos")
    return Response("﻿" + saida.getvalue(), mimetype="text/csv; charset=utf-8", headers={"Content-Disposition": 'attachment; filename="%s"' % nome})
