"""API da página de VAGAS (/vagas-manaus) e da tela Vagas do painel.

Tel (21/09/2026): "uma página com um video do que precisamos e uma
descrição do que é a vaga com um formulário, a vaga é de SDR ... e cria no
painel uma nova página no menu Vagas com uma tabela com os dados dessa
pessoa, acrescente um campo de subir currículo".

DUAS PORTAS, COM REGRAS OPOSTAS:

  POST /api/vagas/candidatura          -- PÚBLICA. Qualquer um manda.
       Grava pela role nay_site_escrita, que no banco só pode INSERIR em
       vagas.candidaturas. Não devolve nada do que está gravado.

  GET  /admin/api/vagas/candidaturas           -- SÓ O ADMIN.
  GET  /admin/api/vagas/candidaturas/<id>/curriculo
       Nome, WhatsApp, e-mail e currículo de gente de verdade. Conferem a
       MESMA senha do /admin (o hash do basicauth do Traefik), aqui dentro.

POR QUE A SENHA É CONFERIDA AQUI E NÃO SÓ NO TRAEFIK:
o painel chama imobeasy.online/admin/api/..., e o Traefik já pede senha
nesse caminho. Mas este mesmo processo também atende api.imobeasy.online,
que NÃO tem senha nenhuma -- as outras rotas da API são todas abertas. Sem a
conferência aqui, api.imobeasy.online/admin/api/vagas/candidaturas entregaria
a lista inteira a qualquer um. Com ela, o caminho não importa: sem a senha
certa, 401.

COMO LIGAR no `app.py` -- o mesmo try/except dos outros blueprints:

    from vagas_api import vagas_bp
    app.register_blueprint(vagas_bp)

E no Dockerfile, uma linha `COPY vagas_api.py .` -- sem ela o import falha e
o try/except deixa a rota fora do ar calado.
"""
import base64
import hmac
import os
import re
from datetime import date, datetime, timezone

import psycopg2
import psycopg2.extras
from flask import Blueprint, Response, jsonify, request
from passlib.hash import apr_md5_crypt

vagas_bp = Blueprint("vagas", __name__)

ESCRITA_URL = os.environ.get("WRITE_DATABASE_URL")
LEITURA_URL = os.environ.get("DATABASE_URL")
# "usuario:hash", o mesmo formato do basicauth do Traefik ($apr1$...).
ADMIN_HTPASSWD = os.environ.get("ADMIN_HTPASSWD", "")

VAGAS_ABERTAS = {"sdr-manaus"}
TETO_CURRICULO = 5 * 1024 * 1024
# Freio de rajada: mais que isto do mesmo IP numa hora e a gente recusa.
TETO_POR_HORA = 4

# O tipo declarado pelo navegador não vale nada -- qualquer um escreve o que
# quiser ali. O que vale é o começo do arquivo.
TIPOS = {
    "application/pdf": (b"%PDF",),
    "application/msword": (b"\xd0\xcf\x11\xe0",),
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": (b"PK\x03\x04",),
}
EXTENSAO_PARA_TIPO = {
    ".pdf": "application/pdf",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}

OPCOES = {
    "experiencia_vendas": {"nenhuma", "menos_de_1_ano", "1_a_3_anos", "mais_de_3_anos"},
    "experiencia_imobiliaria": {"sim", "nao"},
    "disponibilidade": {"imediata", "15_dias", "30_dias"},
}

RE_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


# ------------------------------------------------------------------ banco ---
def _conectar(url):
    if not url:
        raise RuntimeError("conexao do banco nao configurada")
    return psycopg2.connect(url, connect_timeout=5)


def _limpar(v):
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


# ------------------------------------------------------------------ senha ---
def _admin_autenticado():
    """Confere o cabeçalho Authorization: Basic contra o hash do /admin."""
    if ":" not in ADMIN_HTPASSWD:
        return False  # sem hash configurado, ninguém entra -- falha fechado
    usuario_ok, hash_ok = ADMIN_HTPASSWD.split(":", 1)
    cab = request.headers.get("Authorization", "")
    if not cab.startswith("Basic "):
        return False
    try:
        usuario, senha = base64.b64decode(cab[6:]).decode("utf-8").split(":", 1)
    except Exception:  # noqa: BLE001 -- cabeçalho torto é só "não autenticado"
        return False
    if not hmac.compare_digest(usuario, usuario_ok):
        return False
    try:
        return apr_md5_crypt.verify(senha, hash_ok)
    except Exception:  # noqa: BLE001
        return False


def _negar():
    return Response("senha necessaria", 401,
                    {"WWW-Authenticate": 'Basic realm="traefik"', "Cache-Control": "no-store"})


# --------------------------------------------------------- porta pública ---
def _texto(nome, teto, obrigatorio=False):
    v = (request.form.get(nome) or "").strip()
    v = re.sub(r"\s+", " ", v) if nome != "por_que" else v
    if obrigatorio and not v:
        raise ValueError(nome)
    if len(v) > teto:
        raise ValueError(nome)
    return v or None


def _ip():
    # O Traefik sobrescreve X-Real-Ip com o endereço de quem conectou; o
    # X-Forwarded-For o próprio visitante pode preencher, então não serve.
    return (request.headers.get("X-Real-Ip") or request.remote_addr or "")[:64]


@vagas_bp.route("/api/vagas/candidatura", methods=["POST", "OPTIONS"])
def receber_candidatura():
    if request.method == "OPTIONS":
        return ("", 204)

    if (request.content_length or 0) > TETO_CURRICULO + 256 * 1024:
        return jsonify({"ok": False, "erro": "O currículo passa de 5 MB."}), 413

    # Isca para robô: campo escondido que gente não vê nem preenche.
    if (request.form.get("site") or "").strip():
        return jsonify({"ok": True})

    try:
        vaga = _texto("vaga", 40, True)
        if vaga not in VAGAS_ABERTAS:
            raise ValueError("vaga")
        nome = _texto("nome", 120, True)
        if len(nome) < 3:
            raise ValueError("nome")
        whatsapp = re.sub(r"\D", "", request.form.get("whatsapp") or "")
        if len(whatsapp) in (10, 11):
            whatsapp = "55" + whatsapp
        if not 12 <= len(whatsapp) <= 13:
            raise ValueError("whatsapp")
        email = _texto("email", 160, True).lower()
        if not RE_EMAIL.match(email):
            raise ValueError("email")
        bairro = _texto("bairro", 80)
        escolhas = {}
        for campo, validas in OPCOES.items():
            v = _texto(campo, 40, True)
            if v not in validas:
                raise ValueError(campo)
            escolhas[campo] = v
        pretensao = _texto("pretensao_salarial", 40)
        linkedin = _texto("linkedin", 200)
        por_que = _texto("por_que", 2000)
        if request.form.get("consentimento") != "sim":
            raise ValueError("consentimento")
    except ValueError as e:
        return jsonify({"ok": False, "campo": str(e),
                        "erro": "Confira o campo destacado e tente de novo."}), 400

    arquivo = request.files.get("curriculo")
    if not arquivo or not arquivo.filename:
        return jsonify({"ok": False, "campo": "curriculo", "erro": "Anexe o seu currículo."}), 400
    nome_arquivo = os.path.basename(arquivo.filename.replace("\\", "/"))[:160]
    extensao = os.path.splitext(nome_arquivo.lower())[1]
    tipo = EXTENSAO_PARA_TIPO.get(extensao)
    conteudo = arquivo.read(TETO_CURRICULO + 1)
    if not tipo:
        return jsonify({"ok": False, "campo": "curriculo",
                        "erro": "O currículo precisa ser PDF ou Word (.doc, .docx)."}), 400
    if len(conteudo) > TETO_CURRICULO:
        return jsonify({"ok": False, "campo": "curriculo", "erro": "O currículo passa de 5 MB."}), 413
    if not conteudo or not any(conteudo.startswith(m) for m in TIPOS[tipo]):
        return jsonify({"ok": False, "campo": "curriculo",
                        "erro": "Não consegui abrir esse arquivo. Envie em PDF ou Word."}), 400

    ip = _ip()
    conn = _conectar(ESCRITA_URL)
    try:
        with conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM vagas.candidaturas "
                        "WHERE ip = %s AND criada_em > now() - interval '1 hour'", (ip,))
            if cur.fetchone()[0] >= TETO_POR_HORA:
                return jsonify({"ok": False,
                                "erro": "Recebemos várias candidaturas daqui agora há pouco. "
                                        "Tente de novo em uma hora."}), 429
            cur.execute("""
                INSERT INTO vagas.candidaturas
                  (vaga, nome, whatsapp, email, bairro, experiencia_vendas,
                   experiencia_imobiliaria, disponibilidade, pretensao_salarial,
                   linkedin, por_que, curriculo_nome, curriculo_tipo, curriculo,
                   consentimento_em, ip)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (vaga, nome, whatsapp, email, bairro, escolhas["experiencia_vendas"],
                  escolhas["experiencia_imobiliaria"], escolhas["disponibilidade"],
                  pretensao, linkedin, por_que, nome_arquivo, tipo,
                  psycopg2.Binary(conteudo), datetime.now(timezone.utc), ip))
    finally:
        conn.close()
    return jsonify({"ok": True})


# ------------------------------------------------------------ porta admin ---
@vagas_bp.route("/admin/api/vagas/candidaturas")
def listar_candidaturas():
    if not _admin_autenticado():
        return _negar()
    conn = _conectar(LEITURA_URL)
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            # O currículo NÃO vem aqui -- só o tamanho. O arquivo sai pela rota
            # dele, um de cada vez, quando alguém clica.
            cur.execute("""
                SELECT id, vaga, nome, whatsapp, email, bairro, experiencia_vendas,
                       experiencia_imobiliaria, disponibilidade, pretensao_salarial,
                       linkedin, por_que, curriculo_nome, octet_length(curriculo) AS curriculo_bytes,
                       criada_em
                  FROM vagas.candidaturas
                 ORDER BY criada_em DESC
                 LIMIT 1000
            """)
            linhas = [{k: _limpar(v) for k, v in l.items()} for l in cur.fetchall()]
    finally:
        conn.close()
    resp = jsonify({"candidaturas": linhas})
    resp.headers["Cache-Control"] = "no-store"
    return resp


@vagas_bp.route("/admin/api/vagas/candidaturas/<int:cid>/curriculo")
def baixar_curriculo(cid):
    if not _admin_autenticado():
        return _negar()
    conn = _conectar(LEITURA_URL)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT curriculo_nome, curriculo_tipo, curriculo "
                        "FROM vagas.candidaturas WHERE id = %s", (cid,))
            linha = cur.fetchone()
    finally:
        conn.close()
    if not linha:
        return jsonify({"erro": "não encontrado"}), 404
    nome, tipo, dados = linha
    seguro = re.sub(r'[^A-Za-z0-9._ -]', "_", nome) or "curriculo"
    return Response(bytes(dados), 200, {
        "Content-Type": tipo,
        # attachment, nunca inline: arquivo de terceiro não abre dentro do painel.
        "Content-Disposition": 'attachment; filename="%s"' % seguro,
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "no-store",
    })
