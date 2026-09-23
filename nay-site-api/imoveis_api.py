"""O que faltava na tela de imóveis (Tel, 23/09/2026).

Três pedidos dele, três rotas:

  /api/imoveis/valores          "por a lista que desce lá em todos os campos de
                                imóveis para selecionar o que temos e não ter
                                que digitar tudo como está em condomínios"

  /api/imoveis/<cod>/proprietario   "quero a opção de proprietário nos nossos
                                imóveis, e um botão lá na lista de imóveis
                                proprietário abre um popup com os dados do
                                proprietário desse imóvel"

  /api/imoveis/<cod>/ficha      "lá onde abre o imóvel não tem todas as
                                informações no nosso site, preciso disso bem
                                organizado para a nay não errar... o que tem
                                EXATAMENTE"

Só leitura. Quem grava imóvel continua sendo o `app.py`, pelo caminho que já
existe.

COMO LIGAR no `app.py` -- duas linhas, e a linha COPY no Dockerfile:

    from imoveis_api import imoveis_bp
    app.register_blueprint(imoveis_bp)
"""
import base64
import hmac
import os
from datetime import date, datetime
from decimal import Decimal

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, request

try:
    from passlib.apache import HtpasswdFile  # noqa: F401  (só para saber que existe)
    from passlib.context import CryptContext
    _CTX = CryptContext(schemes=["apr_md5_crypt", "bcrypt", "sha256_crypt"])
except Exception:  # noqa: BLE001
    _CTX = None

imoveis_bp = Blueprint("imoveis_extra", __name__)

# QUAL ROLE LE O QUE (medido, nao chutado):
#   nay_site_nai      -> so o que e da Nay; nao le `imoveis`
#   nay_site_listas   -> nem `imoveis` nem a view da lista
#   nay_site_leitura  -> le a view, nao le `imoveis`
#   nay_leitura       -> le os dois
# Por isso estas rotas usam a de leitura ampla. O que e dado pessoal
# (telefone do proprietario) so sai pela rota com senha, aqui do lado.
LISTAS_DATABASE_URL = (os.environ.get("TABELAS_DATABASE_URL")
                       or os.environ.get("LISTAS_DATABASE_URL")
                       or os.environ.get("DATABASE_URL"))
NAI_DATABASE_URL = LISTAS_DATABASE_URL
ADMIN_HTPASSWD = os.environ.get("ADMIN_HTPASSWD", "")

# Os campos que ganham lista. Cada um com a coluna de onde os valores saem.
# Ficam de fora os que são número livre (quartos, valores, área) e os que são
# texto único do imóvel (logradouro, número, complemento, descrição).
CAMPOS_COM_LISTA = {
    "tipo": "tipo",
    "bairro": "bairro",
    "cidade": "cidade",
    "estado": "estado",
    "sol": "sol",
    "andar": "andar",
    "mobilia": "mobilia",
    "motivo_bloqueio": "motivo_bloqueio",
}


def _conectar(url=None):
    alvo = url or NAI_DATABASE_URL
    if not alvo:
        raise RuntimeError("banco não configurado")
    conn = psycopg2.connect(alvo, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def _admin_autenticado():
    """TELEFONE DE PROPRIETARIO E DADO PESSOAL. Por isso esta rota passa pela
    mesma senha do /admin, como a de Vagas -- e nao pelo /api aberto."""
    if ":" not in ADMIN_HTPASSWD or _CTX is None:
        return False
    usuario_ok, hash_ok = ADMIN_HTPASSWD.split(":", 1)
    cab = request.headers.get("Authorization", "")
    if not cab.startswith("Basic "):
        return False
    try:
        usuario, senha = base64.b64decode(cab[6:]).decode("utf-8").split(":", 1)
    except Exception:  # noqa: BLE001
        return False
    if not hmac.compare_digest(usuario, usuario_ok):
        return False
    try:
        return _CTX.verify(senha, hash_ok)
    except Exception:  # noqa: BLE001
        return False


def _simples(v):
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    return v


def _linhas(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return [{k: _simples(v) for k, v in l.items()} for l in cur.fetchall()]


@imoveis_bp.route("/api/imoveis/valores")
def api_imoveis_valores():
    """O que JÁ existe em cada campo, para a tela oferecer em vez de pedir
    para digitar. Sai do próprio catálogo: o que não está em uso não aparece,
    e o que alguém cadastrar novo entra sozinho."""
    conn = _conectar()
    try:
        saida = {}
        for campo, coluna in CAMPOS_COM_LISTA.items():
            saida[campo] = [l["v"] for l in _linhas(conn, """
                SELECT btrim(%s) AS v, count(*) AS n
                  FROM imoveis
                 WHERE btrim(coalesce(%s, '')) <> ''
                 GROUP BY 1 ORDER BY 2 DESC, 1
                 LIMIT 200
            """ % ('"%s"' % coluna, '"%s"' % coluna))]

        # as características são uma lista dentro de cada imóvel: o valor útil
        # é cada item, não a linha inteira
        saida["caracteristicas"] = [l["v"] for l in _linhas(conn, """
            SELECT btrim(x) AS v, count(*) AS n
              FROM imoveis i, unnest(coalesce(i.caracteristicas, '{}')) x
             WHERE btrim(x) <> ''
             GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 200
        """)]
        return jsonify(saida)
    finally:
        conn.close()


@imoveis_bp.route("/admin/api/imoveis/<int:codigo>/proprietario")
def api_imovel_proprietario(codigo):
    """Quem é o dono desse imóvel, com o que se sabe dele.

    O nome vem da lista geral (que junta o catálogo e as tabelas do site
    antigo). O telefone e o e-mail são procurados PELO NOME em
    `proprietarios_admin` e em `proprietarios` -- não existe chave ligando
    imóvel e proprietário no banco novo, e é por isso que o retorno diz de
    onde tirou cada coisa: o Tel precisa saber o que é certo e o que é
    parecido.
    """
    if not _admin_autenticado():
        return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}
    conn = _conectar(LISTAS_DATABASE_URL)
    try:
        base = _linhas(conn, """
            SELECT codigo, coalesce(proprietario_nome, '') AS nome,
                   coalesce(condominio, '') AS condominio, coalesce(endereco, '') AS endereco,
                   status, e_parceiro, no_catalogo
              FROM vw_imoveis_todos WHERE codigo = %s
        """, (codigo,))
        if not base:
            return jsonify({"erro": "imóvel não encontrado"}), 404
        i = base[0]
        if not i["nome"]:
            return jsonify({"imovel": i, "proprietario": None,
                            "aviso": "este imóvel não tem proprietário cadastrado"})

        contatos = _linhas(conn, """
            SELECT 'proprietarios_admin' AS fonte, pa.nome, pa.telefone, pa.email, NULL::text AS tratamento
              FROM proprietarios_admin pa
             WHERE lower(nay_sem_acento(pa.nome)) = lower(nay_sem_acento(%s))
            UNION ALL
            SELECT 'proprietarios', p.nome, p.telefone, p.email, p.tratamento
              FROM proprietarios p
             WHERE lower(nay_sem_acento(p.nome)) = lower(nay_sem_acento(%s))
             LIMIT 6
        """, (i["nome"], i["nome"]))

        return jsonify({
            "imovel": i,
            "proprietario": {
                "nome": i["nome"],
                "e_parceiro": bool(i["e_parceiro"]),
                "contatos": contatos,
            },
            "aviso": None if contatos else
                     "achei o nome, mas nenhum telefone: o vínculo é por nome, não por cadastro",
        })
    finally:
        conn.close()


@imoveis_bp.route("/api/imoveis/<int:codigo>/ficha")
def api_imovel_ficha(codigo):
    """Tudo o que se sabe do imóvel, organizado -- e dizendo o que FALTA.

    A lista de buracos é o ponto: é ela que explica por que a Nay às vezes
    não acha o imóvel numa busca (sem mobília não entra em "mobiliado", sem
    bairro não entra em busca por bairro).
    """
    conn = _conectar(LISTAS_DATABASE_URL)
    try:
        linhas = _linhas(conn, """
            SELECT i.*,
                   (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
                   nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AS no_mercado,
                   (SELECT proprietario_nome FROM vw_imoveis_todos v WHERE v.codigo = i.codigo) AS proprietario_nome
              FROM imoveis i WHERE i.codigo = %s
        """, (codigo,))
        if not linhas:
            return jsonify({"erro": "imóvel não encontrado no catálogo"}), 404
        i = linhas[0]

        falta = []
        for campo, rotulo in (("tipo", "tipo do imóvel"), ("bairro", "bairro"),
                              ("condominio_nome", "condomínio"), ("mobilia", "mobília"),
                              ("descricao", "descrição")):
            if not str(i.get(campo) or "").strip():
                falta.append(rotulo)
        for campo, rotulo in (("quartos", "quartos"), ("banheiros", "banheiros"),
                              ("suites", "suítes"), ("vagas", "vagas")):
            if i.get(campo) is None:
                falta.append(rotulo)
        if not (i.get("valor_venda") or i.get("valor_aluguel")):
            falta.append("valor de venda ou aluguel")
        if not (i.get("area_util") or i.get("area_total")):
            falta.append("área")
        if not i.get("caracteristicas"):
            falta.append("o que tem no imóvel (características)")
        if not i.get("fotos"):
            falta.append("fotos")
        if not str(i.get("proprietario_nome") or "").strip():
            falta.append("proprietário")

        return jsonify({
            "imovel": i,
            "falta": falta,
            "a_nay_pode_oferecer": bool(i["no_mercado"]) and not bool(i.get("e_parceiro")),
        })
    finally:
        conn.close()
