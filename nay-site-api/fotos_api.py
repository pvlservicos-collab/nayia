"""A BIBLIOTECA DE FOTOS DO CADASTRO (Pedro, 03/10/2026).

"cria no cadastro de imóveis uma biblioteca de subir imagens manualmente, abre um
popup e eu posso subir do meu computador direto em um imóvel que já existe no
menu editar, ou lá em criar imóvel tenha esse campo que monta a galeria, e eu
posso mudar a ordem das fotos" / "excluir fotos também".

Com a senha do painel (a mesma do /admin; o proxy do CRM também passa, porque o
caminho começa por /admin/api/imoveis):

  GET    /admin/api/imoveis/<cod>/fotos            as fotos, na ordem (com o id)
  POST   /admin/api/imoveis/<cod>/fotos            sobe UMA foto (o corpo é o arquivo)
  PUT    /admin/api/imoveis/<cod>/fotos/ordem      {"ids": [...]}: a ordem nova; a 1ª é a capa
  DELETE /admin/api/imoveis/<cod>/fotos/<id>       exclui a foto

O ARQUIVO vai para a pasta que o nginx do site já serve
(/docker/nay-site-web/public/fotos-captacao/manual/<código>/), como as fotos da
OLX e do CRM: a Nay manda foto por URL. A LINHA e a ORDEM ficam por conta das
funções do banco (migração 283), que também marcam o imóvel como "fotos editadas
à mão" -- sem a marca, a conferência diária do site antigo desfaria tudo.

A foto de celular chega deitada e com 4 a 12 MB: aqui ela é posta de pé (EXIF),
reduzida a 2048 px no lado maior e gravada em JPEG. Sem o Pillow, vai como veio.
"""
import io
import os
import secrets
from datetime import datetime

import psycopg2
import psycopg2.extras
from flask import Blueprint, jsonify, request

from imoveis_api import _admin_autenticado

try:
    from PIL import Image, ImageOps
except Exception:  # noqa: BLE001
    Image = None
    ImageOps = None

fotos_bp = Blueprint("fotos", __name__)

WRITE_DATABASE_URL = os.environ.get("WRITE_DATABASE_URL")
PASTA_FOTOS = os.environ.get("FOTOS_CAPTACAO_DIR", "/fotos")
URL_FOTOS = os.environ.get("FOTOS_CAPTACAO_URL", "https://imobeasy.online/fotos-captacao")
FOTO_MAXIMA = 25 * 1024 * 1024
FOTO_MINIMA = 2_000
LADO_MAXIMO = 2048
MAXIMO_POR_IMOVEL = 80
# as pastas em que o arquivo é NOSSO e de um imóvel só: excluir a foto apaga o arquivo
PASTAS_POR_IMOVEL = ("manual", "crm", "olx")


def _sem_senha():
    return jsonify({"erro": "não autenticado"}), 401, {"WWW-Authenticate": 'Basic realm="admin"'}


def _conectar():
    if not WRITE_DATABASE_URL:
        raise RuntimeError("WRITE_DATABASE_URL não configurada")
    conn = psycopg2.connect(WRITE_DATABASE_URL, connect_timeout=5)
    conn.cursor_factory = psycopg2.extras.RealDictCursor
    return conn


def _extensao(conteudo):
    if conteudo[:3] == b"\xff\xd8\xff":
        return "jpg"
    if conteudo[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if conteudo[:4] == b"RIFF" and conteudo[8:12] == b"WEBP":
        return "webp"
    return None


def _preparar(conteudo):
    """(bytes, extensão) prontos para gravar. Levanta ValueError com a frase para a tela."""
    extensao = _extensao(conteudo)
    if not extensao:
        if conteudo[4:8] == b"ftyp" and conteudo[8:12] in (b"heic", b"heix", b"hevc", b"heif", b"mif1", b"msf1"):
            raise ValueError("foto em HEIC (formato do iPhone): salve como JPG e suba de novo")
        raise ValueError("o arquivo não é uma foto JPG, PNG ou WEBP")
    if Image is None:
        return conteudo, extensao
    try:
        img = Image.open(io.BytesIO(conteudo))
        img.load()
        img = ImageOps.exif_transpose(img)        # a foto do celular vem deitada
        if img.mode in ("RGBA", "LA", "P"):
            rgba = img.convert("RGBA")
            fundo = Image.new("RGB", rgba.size, (255, 255, 255))
            fundo.paste(rgba, mask=rgba.split()[-1])
            img = fundo
        else:
            img = img.convert("RGB")
        img.thumbnail((LADO_MAXIMO, LADO_MAXIMO), Image.LANCZOS)
        saida = io.BytesIO()
        img.save(saida, "JPEG", quality=86, optimize=True, progressive=True)
        return saida.getvalue(), "jpg"
    except Exception:  # noqa: BLE001  (foto que o Pillow não abre vai como veio: já é jpg/png/webp)
        return conteudo, extensao


def _apagar_arquivo(codigo, url):
    """Só o arquivo que está dentro de uma pasta NOSSA deste imóvel. A url vem do banco, mas
    caminho nenhum escolhe o que apagar sem passar por este portão."""
    for pasta in PASTAS_POR_IMOVEL:
        prefixo = f"{URL_FOTOS}/{pasta}/{codigo}/"
        if not url.startswith(prefixo):
            continue
        nome = os.path.basename(url[len(prefixo):])
        raiz = os.path.realpath(os.path.join(PASTA_FOTOS, pasta, str(codigo)))
        caminho = os.path.realpath(os.path.join(raiz, nome))
        if nome and caminho.startswith(raiz + os.sep):
            try:
                os.remove(caminho)
            except OSError:
                pass    # sem arquivo é o mesmo resultado
        return


def _chamar(sql, parametros):
    conn = _conectar()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, parametros)
            r = cur.fetchone()["r"]
        conn.commit()
        return r
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@fotos_bp.route("/admin/api/imoveis/<int:codigo>/fotos", methods=["GET"])
def fotos_lista(codigo):
    if not _admin_autenticado():
        return _sem_senha()
    try:
        r = _chamar("SELECT site_fotos_lista(%s) AS r", (codigo,))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"erro": exc.__class__.__name__}), 500
    if not r.get("existe"):
        return jsonify({"erro": "imóvel não encontrado"}), 404
    return jsonify(r)


@fotos_bp.route("/admin/api/imoveis/<int:codigo>/fotos", methods=["POST"])
def fotos_subir(codigo):
    if not _admin_autenticado():
        return _sem_senha()
    if (request.content_length or 0) > FOTO_MAXIMA + 1_000_000:
        return jsonify({"ok": False, "erro": "foto grande demais (o limite é 25 MB)"}), 413
    arquivo = request.files.get("foto")
    conteudo = arquivo.read(FOTO_MAXIMA + 1) if arquivo else request.get_data(cache=False)
    if len(conteudo) > FOTO_MAXIMA:
        return jsonify({"ok": False, "erro": "foto grande demais (o limite é 25 MB)"}), 413
    if len(conteudo) < FOTO_MINIMA:
        return jsonify({"ok": False, "erro": "arquivo vazio ou pequeno demais para ser foto"}), 400
    try:
        conteudo, extensao = _preparar(conteudo)
    except ValueError as exc:
        return jsonify({"ok": False, "erro": str(exc)}), 400

    try:
        atual = _chamar("SELECT site_fotos_lista(%s) AS r", (codigo,))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": exc.__class__.__name__}), 500
    if not atual.get("existe"):
        return jsonify({"ok": False, "erro": "imóvel não encontrado"}), 404
    if len(atual.get("fotos") or []) >= MAXIMO_POR_IMOVEL:
        return jsonify({"ok": False, "erro": f"este imóvel já tem {MAXIMO_POR_IMOVEL} fotos: exclua alguma antes"}), 400

    nome = f"{datetime.now():%Y%m%d%H%M%S}_{secrets.token_hex(4)}.{extensao}"
    pasta = os.path.join(PASTA_FOTOS, "manual", str(codigo))
    destino = os.path.join(pasta, nome)
    publica = f"{URL_FOTOS}/manual/{codigo}/{nome}"
    try:
        os.makedirs(pasta, exist_ok=True)
        with open(destino + ".parcial", "wb") as f:
            f.write(conteudo)
        os.replace(destino + ".parcial", destino)      # ou existe inteiro, ou não existe
        r = _chamar("SELECT site_foto_adicionar(%s, %s) AS r", (codigo, publica))
    except Exception as exc:  # noqa: BLE001
        for sobra in (destino + ".parcial", destino):
            try:
                os.remove(sobra)
            except OSError:
                pass
        return jsonify({"ok": False, "erro": exc.__class__.__name__, "detalhe": str(exc)[:200]}), 500
    if not r.get("ok"):
        try:
            os.remove(destino)
        except OSError:
            pass
        return jsonify(r), 400
    return jsonify({"ok": True, "id": r.get("id"), "ordem": r.get("ordem"), "url": publica, "bytes": len(conteudo)})


@fotos_bp.route("/admin/api/imoveis/<int:codigo>/fotos/ordem", methods=["PUT"])
def fotos_ordenar(codigo):
    if not _admin_autenticado():
        return _sem_senha()
    ids = (request.get_json(silent=True) or {}).get("ids")
    if not isinstance(ids, list) or not ids or not all(isinstance(x, int) and not isinstance(x, bool) for x in ids):
        return jsonify({"ok": False, "erro": "ids inválidos"}), 400
    try:
        r = _chamar("SELECT site_fotos_ordenar(%s, %s::int[]) AS r", (codigo, ids))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": exc.__class__.__name__}), 500
    return jsonify(r), (200 if r.get("ok") else 409)


@fotos_bp.route("/admin/api/imoveis/<int:codigo>/fotos/<int:foto_id>", methods=["DELETE"])
def fotos_apagar(codigo, foto_id):
    if not _admin_autenticado():
        return _sem_senha()
    try:
        r = _chamar("SELECT site_foto_apagar(%s, %s) AS r", (codigo, foto_id))
    except Exception as exc:  # noqa: BLE001
        return jsonify({"ok": False, "erro": exc.__class__.__name__}), 500
    if not r.get("ok"):
        return jsonify(r), 404
    _apagar_arquivo(codigo, r.get("url") or "")     # depois do commit: a linha já se foi
    return jsonify({"ok": True, "restam": r.get("restam")})
