"""
Prova a tela de captação (captacao.py) com o cliente de teste do Flask.

NADA DE REDE E NADA DE BANCO: o extrator do OLX, os três módulos irmãos
(`captacao_campos`, `captacao_fotos`, `captacao_site`) e o repositório do
Postgres são todos dublados aqui dentro. Teste que precisa de rede não prova
nada num dia em que a OLX está bloqueando o nosso IP -- que é exatamente o dia
de hoje (medido em 02/09/2026: 403 do servidor, 200 do Mac).

O que cada bloco guarda, e por que ele existe:
  * sem senha ninguém entra, e senha errada em série leva castigo -- é uma
    senha única numa porta aberta, e sem freio uma noite de tentativas acha
    qualquer senha curta;
  * link que não é do OLX é RECUSADO antes de qualquer requisição: sem essa
    parede o campo de texto vira um buscador para qualquer endereço a partir
    da nossa máquina;
  * OLX bloqueada vira mensagem que explica o bloqueio e o que fazer, não
    "erro inesperado";
  * o formulário mostra o que falta com o obrigatório em cima;
  * publicar sem a credencial do admin LISTA o que falta e não chama o site --
    hoje essa credencial não existe, e fingir seria pior que não ter o botão;
  * erro interno nunca leva detalhe (traceback, DATABASE_URL) para a tela.

São 109 casos em 23 blocos (contados na saída, não de cabeça). Os
tracebacks que aparecem em stderr ao rodar são de propósito: são os caminhos
de erro sendo exercitados, e ver o traceback SÓ no log -- nunca na tela -- é
justamente o que os casos de "não vaza detalhe" provam.

    .venv/bin/python teste_captacao_web.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

os.environ["CAPTACAO_SENHA"] = "senha-de-teste-fake"   # antes do import: captacao.py lê na subida
os.environ.pop("IMOBEASY_EMAIL", None)     # os nomes REAIS, lidos de
os.environ.pop("IMOBEASY_SENHA", None)     # captacao_site.credenciais()

import captacao  # noqa: E402
import extrair_olx  # noqa: E402

# Os dois módulos irmãos, se já existirem no disco. Alguns casos rodam contra
# eles DE VERDADE (sem rede) -- é o que pega assinatura trocada, que é
# justamente o erro que um dublê inventado esconderia.
try:
    import captacao_fotos as fotos_real
except Exception:                                    # pragma: no cover
    fotos_real = None
try:
    import captacao_site as site_real
except Exception:                                    # pragma: no cover
    site_real = None
try:
    import captacao_campos as campos_real
except Exception:                                    # pragma: no cover
    campos_real = None

falhas = 0
SENHA = "senha-de-teste-fake"


def checar(rotulo, condicao, detalhe=""):
    global falhas
    if condicao:
        print(f"  OK   {rotulo}")
    else:
        falhas += 1
        print(f"  FALHOU {rotulo} {detalhe}")


# ------------------------------------------------------------- os dublês

def _chave_do_link(link):
    """O mesmo criterio da `nay_chave_do_link` do esquema: o numero final do
    link identifica o anuncio. `www` e `am` sao o mesmo anuncio, e o slug muda
    quando o proprietario edita o titulo."""
    import re as _re
    m = _re.search(r"(\d{6,})", str(link or ""))
    return m.group(1) if m else (str(link or "").split("?")[0] or None)


class BancoFalso:
    """Guarda as captações num dicionário. Substitui as funções `repo_*` de
    captacao.py inteiras -- assim o teste não depende do DDL de `captacoes`,
    que está sendo escrito noutro arquivo ao mesmo tempo que este."""

    def __init__(self):
        self.linhas = {}
        self.fotos = {}
        self.proximo = 1

    def instalar(self):
        captacao.db.conectar = lambda: self
        captacao.repo_listar = lambda conn: sorted(
            self.linhas.values(), key=lambda l: -l["id"])
        captacao.repo_buscar = lambda conn, i: self.linhas.get(i)
        captacao.repo_por_link = self._por_link
        captacao.repo_gravar_relatorio = self._gravar_relatorio
        captacao.repo_criar = self._criar
        captacao.repo_salvar_campos = self._salvar
        captacao.repo_marcar = self._marcar
        captacao.repo_listar_fotos = lambda conn, i: self.fotos.get(i, [])
        return self

    def close(self):
        pass

    def _por_link(self, conn, link):
        """Dedupe pelo LINK, como a funcao `nay_captacao_do_link` do esquema:
        link que ainda nao foi lido nao tem `olx_id`, e procurar por id abriria
        um segundo rascunho do mesmo anuncio."""
        chave = _chave_do_link(link)
        for linha in self.linhas.values():
            if chave and _chave_do_link(linha.get("link_olx")) == chave:
                return linha
        return None

    def _criar(self, conn, link, dados, campos, pasta=None):
        i = self.proximo
        self.proximo += 1
        # Os nomes sao os do `captacao_schema.sql`: `link_olx`,
        # `codigo_no_site`, e NEM `titulo` NEM `fotos_pasta` -- o titulo sai de
        # `dados_olx` e a pasta sai do `olx_id`. Dube que inventa coluna e
        # teste verde que nao prova nada.
        self.linhas[i] = {"id": i, "link_olx": link, "status": "rascunho",
                          "olx_id": dados.get("olx_id"),
                          "titulo": (dados.get("titulo")),
                          "dados_olx": dados, "campos": campos,
                          "codigo_no_site": None, "erro": None,
                          "criado_em": None, "atualizado_em": None}
        self.fotos[i] = [{"ordem": o + 1, "url": u, "caminho": None,
                          "bytes": None, "e_capa": o == 0, "baixada_em": None,
                          "erro": None}
                         for o, u in enumerate(dados.get("fotos") or [])]
        return i

    def _gravar_relatorio(self, conn, i, relatorio):
        for f in (relatorio or {}).get("fotos") or []:
            for linha in self.fotos.get(i, []):
                if linha["ordem"] == f["ordem"]:
                    linha.update(caminho=f.get("arquivo"), bytes=f.get("bytes"),
                                 e_capa=bool(f.get("e_capa")), baixada_em="agora")

    def _salvar(self, conn, i, campos, status):
        self.linhas[i]["campos"] = campos
        self.linhas[i]["status"] = status

    def _marcar(self, conn, i, status, erro=None, codigo_site=None):
        self.linhas[i].update(status=status, erro=erro,
                              codigo_no_site=codigo_site)


class CamposFalso:
    """Dublê de `captacao_campos`. Traduz o mínimo e declara o que falta --
    inclusive um obrigatório e um opcional, para provar a ordem na tela."""

    @staticmethod
    def traduzir(dados_olx):
        return {"bairro": dados_olx.get("bairro"),
                "quartos": (dados_olx.get("campos") or {}).get("rooms"),
                "descricao": dados_olx.get("descricao")}

    @staticmethod
    def o_que_falta(campos):
        faltam = []
        if not campos.get("area_util"):
            faltam.append({"nome": "area_util", "rotulo": "Área útil (m²)",
                           "obrigatorio": True})
        if not campos.get("valor_venda"):
            faltam.append({"nome": "valor_venda", "rotulo": "Valor de venda",
                           "obrigatorio": True})
        if not campos.get("sol"):
            faltam.append({"nome": "sol", "rotulo": "Sol", "obrigatorio": False})
        return faltam

    @staticmethod
    def duvidas(dados_olx, campos):
        return ["O condomínio tem taxa? De quanto?"]


class SiteFalso:
    """Dublê de `captacao_site` com a assinatura REAL, conferida no arquivo
    dele em 02/09/2026: `entrar()` devolve a sessão e `cadastrar` RECEBE essa
    sessão -- ele não faz login sozinho. Um dublê com assinatura inventada
    passaria aqui e quebraria em produção, que é o pior teste possível."""

    chamadas = []
    conferidas = []
    MAPA_PROVISORIO = type("Mapa", (), {"confirmado": True, "campos": None})()
    FalhaNaCaptacao = RuntimeError

    @staticmethod
    def entrar():
        return "sessao-logada"

    @staticmethod
    def cadastrar(sessao, campos, fotos=()):
        SiteFalso.chamadas.append((sessao, campos, list(fotos)))
        return {"codigo": "5999", "url": "https://imobeasy.com/anuncios/5999"}

    @staticmethod
    def conferir(sessao, codigo, enviado=None):
        SiteFalso.conferidas.append(codigo)


ANUNCIO = {
    "olx_id": 1526572128,
    "titulo": "Casa bem localizada no parque das laranjeiras.",
    "descricao": "Casa com 3 quartos sendo 1 suíte",
    "preco_texto": "R$ 390.000",
    "preco_rotulo": "Preço",
    "bairro": "Flores", "municipio": "Manaus",
    "logradouro": "Rua Barão de Indaiá", "cep": "69058448",
    "campos": {"rooms": "3", "bathrooms": "3", "garage_spaces": "2"},
    "fotos": ["https://img.olx.com.br/images/48/481626791965796.jpg",
              "https://img.olx.com.br/images/50/505613799054848.jpg"],
}

banco = BancoFalso().instalar()
captacao.captacao_campos = CamposFalso
captacao.captacao_fotos = None
captacao.captacao_site = None
extrair_olx.do_link = lambda url, buscar=None: dict(ANUNCIO)


def cliente_logado():
    c = captacao.app.test_client()
    resp = c.post("/entrar", data={"senha": SENHA})
    assert resp.status_code in (302, 303), resp.status_code
    with c.session_transaction() as s:
        c._csrf = s["csrf"]
    return c


def texto(resp):
    return resp.get_data(as_text=True)


# ------------------------------------------------------------- os casos

print("--- o app não sobe sem CAPTACAO_SENHA ---")
# Não é detalhe: sem essa parede o app subiria com senha vazia e QUALQUER
# senha entraria. Mesmo padrão de servidor.py, db.py e enviar_zapi.py.
ambiente = dict(os.environ)
ambiente.pop("CAPTACAO_SENHA", None)
proc = subprocess.run([sys.executable, "-c", "import captacao"],
                      cwd=os.path.dirname(os.path.abspath(__file__)),
                      env=ambiente, capture_output=True, text=True)
checar("processo morre sem a variável", proc.returncode != 0)
checar("e diz qual variável falta", "CAPTACAO_SENHA" in proc.stderr,
       proc.stderr[-200:])

print("\n--- sem senha ninguém entra ---")
anonimo = captacao.app.test_client()
r = anonimo.get("/")
checar("a lista redireciona para /entrar", r.status_code == 302
       and "/entrar" in r.headers.get("Location", ""), r.status_code)
r = anonimo.post("/captar", data={"link": "https://www.olx.com.br/x-1"})
checar("captar sem sessão também é barrado", r.status_code == 302,
       r.status_code)
r = anonimo.get("/captacao/1")
checar("a captação de alguém não abre sem sessão", r.status_code == 302,
       r.status_code)

print("\n--- senha errada ---")
r = anonimo.post("/entrar", data={"senha": "chutando"})
checar("senha errada devolve 401", r.status_code == 401, r.status_code)
checar("e diz que a senha está errada", "Senha errada" in texto(r))
r = anonimo.get("/")
checar("e continua sem entrar", r.status_code == 302, r.status_code)

print("\n--- freio de tentativa (senha única em porta aberta) ---")
for _ in range(5):
    anonimo.post("/entrar", data={"senha": "chutando"})
r = anonimo.post("/entrar", data={"senha": "chutando"})
checar("depois de 5 erros o IP leva castigo (429)", r.status_code == 429,
       r.status_code)
r = anonimo.post("/entrar", data={"senha": SENHA})
checar("e nem a senha CERTA passa durante o castigo", r.status_code == 429,
       r.status_code)
checar("a tela diz quanto tempo falta", "min" in texto(r))
captacao._limpar_tentativas("127.0.0.1")   # os casos seguintes precisam entrar

print("\n--- senha certa ---")
c = cliente_logado()
r = c.get("/")
checar("a lista abre", r.status_code == 200, r.status_code)
checar("e mostra o campo de colar o link", 'name="link"' in texto(r))
checar("e avisa que os módulos irmãos faltam",
       "captacao_site.py" in texto(r))

print("\n--- todo POST exige o token da sessão (falha FECHADO) ---")
r = c.post("/captar", data={"link": "https://www.olx.com.br/x-1"})
checar("POST sem token é recusado com 400", r.status_code == 400, r.status_code)
r = c.post("/captar", data={"link": "https://www.olx.com.br/x-1", "csrf": "inventado"})
checar("token inventado também é recusado", r.status_code == 400, r.status_code)

print("\n--- link inválido não quebra ---")
ruins = ["", "   ", "não é link", "javascript:alert(1)",
         "https://olx.com.br.invasor.com/anuncio",
         "http://169.254.169.254/latest/meta-data/",
         "file:///etc/passwd", "https://www.olx.com/anuncio"]
for ruim in ruins:
    r = c.post("/captar", data={"link": ruim, "csrf": c._csrf})
    ok = r.status_code == 400 and "Esse link não serve" in texto(r)
    checar(f"recusado: {ruim!r}", ok, f"{r.status_code}")
checar("host que só PARECE olx é recusado",
       captacao.link_valido("https://olx.com.br.invasor.com/x") is None)
checar("subdomínio de verdade passa",
       captacao.link_valido("https://am.olx.com.br/x") == "https://am.olx.com.br/x")
checar("http vira https em vez de sair em claro",
       captacao.link_valido("http://www.olx.com.br/x") == "https://www.olx.com.br/x")

print("\n--- a OLX recusando o nosso IP vira mensagem honesta ---")


def bloqueado(url, buscar=None):
    raise extrair_olx.OlxBloqueado("403 Cloudflare")


extrair_olx.do_link = bloqueado
r = c.post("/captar", data={"link": "https://www.olx.com.br/casa-1", "csrf": c._csrf})
corpo = texto(r)
checar("responde 502, não 500", r.status_code == 502, r.status_code)
checar("diz que quem recusou foi a OLX", "OLX recusou" in corpo)
checar("diz o que fazer (rodar do Mac)", "do Mac" in corpo)
checar("diz que as fotos NÃO estão bloqueadas", "FOTOS não estão bloqueadas" in corpo)
checar("não chama isso de erro inesperado", "inesperado" not in corpo)

print("\n--- anúncio que não abre não vaza detalhe interno ---")


def explode(url, buscar=None):
    raise RuntimeError(
        "DATABASE_URL=postgresql://nay:SENHA_SECRETA@127.0.0.1:5432/naydb")


extrair_olx.do_link = explode
r = c.post("/captar", data={"link": "https://www.olx.com.br/casa-1", "csrf": c._csrf})
corpo = texto(r)
checar("responde 502", r.status_code == 502, r.status_code)
checar("sem senha na tela", "SENHA_SECRETA" not in corpo)
checar("sem DATABASE_URL na tela", "DATABASE_URL" not in corpo)
checar("sem traceback na tela", "Traceback" not in corpo)
checar("mas explica o que aconteceu", "não achei os dados do anúncio" in corpo)

print("\n--- captar de verdade ---")
extrair_olx.do_link = lambda url, buscar=None: dict(ANUNCIO)
r = c.post("/captar", data={"link": "https://www.olx.com.br/casa-1526572128",
                            "csrf": c._csrf})
checar("redireciona para a captação", r.status_code == 302, r.status_code)
destino = r.headers.get("Location", "")
checar("para a captação criada", destino.endswith("/captacao/1"), destino)
checar("gravou uma captação", len(banco.linhas) == 1, str(banco.linhas))
checar("com o olx_id", banco.linhas[1]["olx_id"] == 1526572128)
checar("e as duas fotos", len(banco.fotos[1]) == 2)
checar("e o que captacao_campos traduziu",
       banco.linhas[1]["campos"].get("bairro") == "Flores")

print("\n--- colar o mesmo link duas vezes não abre dois rascunhos ---")
r = c.post("/captar", data={"link": "https://www.olx.com.br/casa-1526572128",
                            "csrf": c._csrf})
checar("continua com uma captação só", len(banco.linhas) == 1, str(len(banco.linhas)))
checar("e manda para a que já existia", "/captacao/1" in r.headers.get("Location", ""))

print("\n--- o formulário mostra o que falta, obrigatório em cima ---")
r = c.get("/captacao/1")
corpo = texto(r)
checar("a tela abre", r.status_code == 200, r.status_code)
checar("tem o campo da área útil", 'name="campo_area_util"' in corpo)
checar("tem o campo do valor de venda", 'name="campo_valor_venda"' in corpo)
checar("tem o campo opcional do sol", 'name="campo_sol"' in corpo)
checar("o obrigatório está marcado", "obrigatório" in corpo)
checar("obrigatório vem ANTES do opcional",
       corpo.index('name="campo_area_util"') < corpo.index('name="campo_sol"'))
checar("mostra as dúvidas para perguntar ao proprietário",
       "O condomínio tem taxa?" in corpo)
checar("mostra as fotos do anúncio", "481626791965796.jpg" in corpo)
checar("mostra o preço CRU, sem converter", "R$ 390.000" in corpo)
checar("mostra a descrição do proprietário", "3 quartos sendo 1 suíte" in corpo)
checar("deixa CORRIGIR o que veio do OLX",
       'name="campo_bairro"' in corpo and "Flores" in corpo)

print("\n--- salvar o que ele preencheu ---")
r = c.post("/captacao/1", data={"csrf": c._csrf, "campo_area_util": " 120 ",
                                "campo_valor_venda": "R$ 390.000",
                                "campo_sol": ""})
checar("redireciona de volta", r.status_code == 302, r.status_code)
salvos = banco.linhas[1]["campos"]
checar("guardou a área sem os espaços", salvos.get("area_util") == "120", str(salvos))
checar("campo deixado em branco NÃO vira vazio", "sol" not in salvos, str(salvos))
checar("status virou pronto quando não falta obrigatório",
       banco.linhas[1]["status"] == "pronto", banco.linhas[1]["status"])

print("\n--- publicar sem credencial diz o que falta, e NÃO chama o site ---")
captacao.captacao_site = None
r = c.post("/captacao/1/publicar", data={"csrf": c._csrf})
corpo = texto(r)
checar("responde 409, não finge que publicou", r.status_code == 409, r.status_code)
checar("diz que falta o módulo do site", "captacao_site.py" in corpo)
checar("diz qual variável de ambiente falta", "IMOBEASY_EMAIL" in corpo)
checar("diz que nada foi enviado", "nada foi enviado ao site" in corpo)
checar("a captação continua pronta, não virou erro",
       banco.linhas[1]["status"] == "pronto", banco.linhas[1]["status"])

print("\n--- e a tela da captação lista a mesma pendência ---")
corpo = texto(c.get("/captacao/1"))
checar("avisa que ainda não dá para publicar", "Ainda não dá para publicar" in corpo)
checar("e não mostra botão de cadastrar", "Cadastrar no site" not in corpo)

print("\n--- contra o captacao_site DE VERDADE, sem rede ---")
if site_real is None:
    print("  (pulado: captacao_site.py ainda não existe)")
else:
    # Este é o estado REAL de hoje: sem credencial e com o mapa do formulário
    # nunca conferido contra o admin logado. As duas coisas têm que aparecer
    # na tela, porque as duas fazem `captacao_site.cadastrar` recusar.
    captacao.captacao_site = site_real
    corpo = texto(c.post("/captacao/1/publicar", data={"csrf": c._csrf}))
    checar("cobra IMOBEASY_EMAIL pelo nome exato do captacao_site",
           "IMOBEASY_EMAIL" in corpo)
    checar("cobra IMOBEASY_SENHA", "IMOBEASY_SENHA" in corpo)
    checar("avisa que o mapa do formulário nunca foi conferido",
           "nunca foi conferido" in corpo)
    checar("explica que o Rails gravaria vazio sem erro",
           "SEM ERRO NENHUM" in corpo)
    checar("o mapa de verdade continua NÃO confirmado",
           site_real.MAPA_PROVISORIO.confirmado is False)

print("\n--- com credencial e módulos, publica e marca o código do site ---")
pasta_base = tempfile.mkdtemp(prefix="captacao-fotos-")
captacao.PASTA_FOTOS = pasta_base
pasta = os.path.join(pasta_base, captacao._nome_de_pasta(banco.linhas[1].get("olx_id")))
os.makedirs(pasta, exist_ok=True)
os.environ["IMOBEASY_EMAIL"] = "usuario@teste"
os.environ["IMOBEASY_SENHA"] = "senha-de-teste"
captacao.captacao_site = SiteFalso

if fotos_real is None:
    print("  (fotos: captacao_fotos.py ainda não existe, usando dublê)")
    captacao.captacao_fotos = type("FotosFalso", (), {
        "baixar": staticmethod(lambda u, p: {"pasta": p, "fotos": [], "falhas": []})})
    esperados = []
else:
    # As fotos são gravadas com o nome que o PRÓPRIO captacao_fotos daria, e
    # com tamanho acima do piso dele -- assim o `baixar` de verdade reconhece
    # que já estão em disco e NÃO vai à rede. É a retomada dele sendo usada
    # como dublê, em vez de um dublê inventado por mim.
    captacao.captacao_fotos = fotos_real
    esperados = []
    for ordem, url in enumerate(ANUNCIO["fotos"], start=1):
        caminho = os.path.join(pasta, fotos_real.nome_base(ordem, url) + ".jpg")
        with open(caminho, "wb") as f:
            f.write(b"\xff\xd8\xff" + b"x" * 4096)
        esperados.append(caminho)
    checar("os nomes saem do próprio captacao_fotos",
           os.path.basename(esperados[0]) == "01-481626791965796.jpg",
           os.path.basename(esperados[0]))

print("\n--- foto faltando é AVISO, não bloqueio ---")
banco.fotos[1].append({"ordem": 2, "url": "https://img.olx.com.br/images/9/999.jpg"})
corpo = texto(c.get("/captacao/1"))
if fotos_real is not None:
    checar("avisa quantas fotos estão no disco", "das 3 fotos estão no disco" in corpo)
checar("mas o botão de publicar continua lá", "Cadastrar no site" in corpo)
banco.fotos[1].pop()      # a 3a URL é inventada: baixar de verdade iria à rede

corpo = texto(c.get("/captacao/1"))
checar("sem pendência, o botão aparece", "Cadastrar no site" in corpo)
r = c.post("/captacao/1/publicar", data={"csrf": c._csrf})
checar("redireciona depois de publicar", r.status_code == 302, r.status_code)
checar("chamou o site uma vez", len(SiteFalso.chamadas) == 1, str(SiteFalso.chamadas))
sessao, enviados, arquivos = SiteFalso.chamadas[0]
checar("passou a SESSÃO logada como 1o argumento", sessao == "sessao-logada")
checar("passou os campos preenchidos", enviados.get("area_util") == "120")
if fotos_real is not None:
    checar("passou os CAMINHOS das fotos, na ordem do anúncio",
           arquivos == esperados, str(arquivos))
checar("conferiu o que o site gravou", SiteFalso.conferidas == ["5999"],
       str(SiteFalso.conferidas))
checar("status virou publicado", banco.linhas[1]["status"] == "publicado")
checar("guardou o código devolvido pelo site",
       banco.linhas[1]["codigo_no_site"] == "5999")
corpo = texto(c.get("/captacao/1"))
checar("a tela diz que a varredura traz para o banco sozinha",
       "varredura" in corpo)

print("\n--- o site recusando vira status erro, com a mensagem do módulo ---")
banco.linhas[1]["status"] = "pronto"
banco.linhas[1]["codigo_no_site"] = None
if site_real is None:
    print("  (pulado: captacao_site.py ainda não existe)")
else:
    def recusar(sessao, campos, fotos=()):
        raise site_real.FalhaDeFormulario(
            "o admin respondeu 200 em vez de redirecionar: o imóvel NÃO foi "
            "criado. Provável campo obrigatório faltando.")

    captacao.captacao_site = type("SiteQueRecusa", (), {
        "entrar": staticmethod(lambda: "sessao"),
        "cadastrar": staticmethod(recusar),
        "MAPA_PROVISORIO": SiteFalso.MAPA_PROVISORIO,
        "FalhaNaCaptacao": site_real.FalhaNaCaptacao})
    r = c.post("/captacao/1/publicar", data={"csrf": c._csrf})
    corpo = texto(r)
    checar("responde 502", r.status_code == 502, r.status_code)
    checar("marcou a captação como erro", banco.linhas[1]["status"] == "erro",
           banco.linhas[1]["status"])
    checar("mostra a mensagem que o módulo escreveu para o Tel",
           "o imóvel NÃO foi criado" in corpo)
    checar("e diz em que passo parou", "[formulario]" in corpo, corpo[:0])
    checar("sem traceback na tela", "Traceback" not in corpo)
    checar("e diz que os dados continuam salvos", "continuam salvos" in corpo)

print("\n--- exceção QUE NÃO É do módulo não vira texto na tela ---")
banco.linhas[1]["status"] = "pronto"


def explodir_cru(sessao, campos, fotos=()):
    raise RuntimeError("psycopg2: password authentication failed for user \"nay\"")


captacao.captacao_site = type("SiteQueExplode", (), {
    "entrar": staticmethod(lambda: "sessao"),
    "cadastrar": staticmethod(explodir_cru),
    "MAPA_PROVISORIO": SiteFalso.MAPA_PROVISORIO,
    "FalhaNaCaptacao": getattr(site_real, "FalhaNaCaptacao", ValueError)})
r = c.post("/captacao/1/publicar", data={"csrf": c._csrf})
corpo = texto(r)
checar("responde 502", r.status_code == 502, r.status_code)
checar("sem o detalhe do psycopg2 na tela", "psycopg2" not in corpo)
checar("sem o usuário do banco", "authentication" not in corpo)
checar("mas manda conferir no admin antes de repetir",
       "confira no admin" in corpo)

print("\n--- erro interno inesperado não vaza nada ---")


def repo_que_explode(conn, i):
    raise RuntimeError("psycopg2 OperationalError: password authentication "
                       "failed for user \"nay\"")


guardado = captacao.repo_buscar
captacao.repo_buscar = repo_que_explode
r = c.get("/captacao/1")
corpo = texto(r)
captacao.repo_buscar = guardado
checar("responde 500", r.status_code == 500, r.status_code)
checar("sem detalhe do psycopg2", "psycopg2" not in corpo)
checar("sem o usuário do banco", "authentication" not in corpo)
checar("mas avisa que quebrou", "Deu erro aqui dentro" in corpo)

print("\n--- a tela inteira contra o captacao_campos DE VERDADE ---")
if campos_real is None:
    print("  (pulado: captacao_campos.py ainda não existe)")
else:
    # Dois erros que este bloco existe para pegar, e nenhum dos dois estoura
    # sozinho -- os dois APAGAM em silêncio:
    #   1. `o_que_falta` usa a chave "campo" e `duvidas` usa "aviso". Procurar
    #      "nome"/"pergunta" faz a lista voltar vazia e a tela não mostrar
    #      nada, sem erro nenhum;
    #   2. `traduzir` devolve a forma inteira com None no que o anúncio não
    #      trouxe, e None num `value=` vira a palavra "None" dentro da caixa.
    captacao.captacao_campos = campos_real
    captacao.captacao_site = None
    outro = dict(ANUNCIO, olx_id=999888, titulo="Outro anúncio")
    extrair_olx.do_link = lambda url, buscar=None: dict(outro)
    r = c.post("/captar", data={"link": "https://www.olx.com.br/casa-999888",
                                "csrf": c._csrf})
    novo = int(r.headers["Location"].rsplit("/", 1)[-1])
    corpo = texto(c.get(f"/captacao/{novo}"))

    checar("a tela abre com o módulo de verdade", "Outro anúncio" in corpo)
    checar("pede o tipo do imóvel (obrigatório que a OLX não dá)",
           'name="campo_tipo"' in corpo)
    checar("pede a área útil", 'name="campo_area_util"' in corpo)
    checar("mostra a dúvida da suíte, que vem na chave `aviso`",
           "confirme com o proprietário" in corpo, corpo.count("aviso"))
    checar("a palavra None não aparece em campo nenhum",
           'value="None"' not in corpo)
    checar("o que a OLX deu vem preenchido para conferir",
           'value="Flores"' in corpo)
    checar("e o valor convertido também", 'value="390000.0"' in corpo)
    banco.linhas[novo]["campos"]["tipo"] = "Casa"
    banco.linhas[novo]["campos"]["area_util"] = "180"
    corpo = texto(c.get(f"/captacao/{novo}"))
    checar("preenchidos os obrigatórios, some o aviso de faltar",
           "Falta preencher: " not in corpo)

print("\n--- o caminho feliz de ponta a ponta, com os módulos DE VERDADE ---")
# ESTE BLOCO EXISTE PORQUE O CAMINHO FELIZ NÃO FUNCIONAVA. Todos os casos
# abaixo falhavam em 02/09/2026, e nenhum deles estourava exceção -- por isso a
# suíte inteira passava verde enquanto o Tel não conseguia cadastrar um imóvel.
# O bloco anterior mexia no dicionário do banco à mão
# (`banco.linhas[novo]["campos"]["tipo"] = "Casa"`), então nunca exercitava o
# POST do formulário, que é onde estavam os defeitos.
if campos_real is None or site_real is None:
    print("  (pulado: os módulos irmãos ainda não existem)")
else:
    class SiteQueAceita:
        """Dublê com o MAPA CONFIRMADO -- é o único jeito de chegar ao fim do
        caminho hoje, porque `captacao_site.MAPA_PROVISORIO.confirmado` é False
        até alguém abrir o admin logado. Os nomes de campo são os do mapa de
        verdade, para o portão de campo desconhecido valer alguma coisa."""
        VARIAVEIS_NECESSARIAS = ("IMOBEASY_EMAIL", "IMOBEASY_SENHA")
        MAPA_PROVISORIO = type("M", (), {
            "confirmado": True,
            "campos": {k: k for k in site_real.MAPA_PROVISORIO.campos}})()
        FalhaNaCaptacao = site_real.FalhaNaCaptacao
        recebidos = []
        @staticmethod
        def entrar():
            return "SESSAO"
        @staticmethod
        def cadastrar(sessao, campos, fotos=()):
            SiteQueAceita.recebidos.append(dict(campos))
            return {"codigo": "6001"}

    class FotosQueNaoVaoARede:
        @staticmethod
        def baixar(urls, pasta, **kw):
            return {"pasta": pasta, "fotos": [], "falhas": []}

    os.environ["IMOBEASY_EMAIL"] = "conta@exemplo"   # dublê: nada sai daqui
    os.environ["IMOBEASY_SENHA"] = "nao-e-a-de-verdade"
    captacao.captacao_campos = campos_real
    captacao.captacao_site = SiteQueAceita
    captacao.captacao_fotos = FotosQueNaoVaoARede

    # Um anúncio SEM preço reconhecível: é assim que o obrigatório `valor`
    # aparece de verdade. Com preço, ele já vinha respondido e o defeito ficava
    # escondido -- foi exatamente o que aconteceu com o fixture ANUNCIO.
    sem_preco = {"olx_id": 555111, "titulo": "Casa no Tarumã",
                 "descricao": "casa boa", "bairro": "Tarumã", "fotos": [],
                 "campos": {"rooms": "3", "bathrooms": "2", "size": "120",
                            "garage_spaces": "1"}}
    extrair_olx.do_link = lambda url, buscar=None: dict(sem_preco)
    r = c.post("/captar", data={"link": "https://www.olx.com.br/casa-555111",
                                "csrf": c._csrf})
    cap = int(r.headers["Location"].rsplit("/", 1)[-1])
    corpo = texto(c.get(f"/captacao/{cap}"))

    # `o_que_falta` cobra um obrigatório chamado `valor`, que NÃO é coluna
    # nenhuma -- ele só se dá por respondido quando `valor_venda` ou
    # `valor_aluguel` estiver preenchido. A tela gravava em `campos["valor"]` e
    # perguntava de novo, para sempre.
    checar("a caixa do valor tem o nome de uma coluna de verdade",
           'name="campo_valor_venda"' in corpo and 'name="campo_valor_aluguel"' in corpo,
           'name="campo_valor"' in corpo and "gravaria em campos['valor']")
    checar("e não existe mais uma caixa chamada campo_valor",
           'name="campo_valor"' not in corpo)

    # O navegador manda TODAS as caixas, inclusive as vazias.
    formulario = {"csrf": c._csrf, "campo_tipo": "casa",
                  "campo_valor_venda": "390000", "campo_valor_aluguel": "",
                  "campo_suites": "", "campo_logradouro": "",
                  "campo_taxa_condominio": "", "campo_iptu": "",
                  "campo_mobilia": "", "campo_caracteristicas": "",
                  "campo_vagas_cobertas": "",
                  "campo_anotacoes": "o dono só atende depois das 18h"}
    c.post(f"/captacao/{cap}", data=formulario)
    linha = banco.linhas[cap]
    checar("responder o valor faz a captação virar 'pronto'",
           linha["status"] == "pronto", linha["status"])
    checar("e a resposta ficou na coluna certa",
           linha["campos"].get("valor_venda") == "390000", linha["campos"])

    # `captacao_campos.duvidas` compara `valor_venda < VENDA_MINIMA`, e o que o
    # formulário devolve é TEXTO: a comparação estoura TypeError. Antes disso
    # ser contido, a captação passava a devolver 500 toda vez que fosse aberta,
    # para sempre, logo depois de o Tel responder o valor.
    r = c.get(f"/captacao/{cap}")
    corpo = texto(r)
    checar("a tela ABRE depois de salvar o valor (não vira 500 para sempre)",
           r.status_code == 200, r.status_code)
    checar("a anotação continua guardada aqui", "18h" in corpo)

    campos_salvos = captacao._campos_de(linha)
    pend = captacao.pendencias_para_publicar(
        linha, campos_salvos, captacao._o_que_falta(campos_salvos), [])
    # `traduzir` devolve a forma INTEIRA, então TODA captação nasce com a chave
    # `caracteristicas`, que o mapa do formulário não tem. A pendência
    # "não tem onde pôr: Características" aparecia sem ninguém ter escrito nada.
    checar("nada impede de publicar depois de responder o obrigatório",
           pend == [], pend)
    checar("o botão de publicar aparece", "Cadastrar no site" in corpo)

    r = c.post(f"/captacao/{cap}/publicar", data={"csrf": c._csrf})
    checar("publicar dá certo", r.status_code == 302, r.status_code)
    checar("e guarda o código do site", linha["codigo_no_site"] == "6001", linha)
    enviado = SiteQueAceita.recebidos[0]
    # `captacao_site.cadastrar` recusa o cadastro INTEIRO quando recebe um campo
    # que não está no mapa -- então mandar a anotação junto derrubaria tudo.
    checar("a anotação NÃO vai para o site", "anotacoes" not in enviado, enviado)
    checar("mas o que é do imóvel vai", enviado.get("valor_venda") == "390000",
           enviado)
    checar("e nenhum campo vazio vai junto",
           all(v not in (None, "") for v in enviado.values()), enviado)

    # O botão some da tela quando vira `publicado`, mas isso não é proteção: o
    # cadastro demora, a página ainda está com o botão na frente do Tel, e o
    # segundo clique manda o mesmo POST. Dois imóveis iguais no site, sem
    # desfazer -- e a varredura horária traz os dois para `imoveis`.
    r = c.post(f"/captacao/{cap}/publicar", data={"csrf": c._csrf})
    checar("o segundo clique NÃO cadastra o imóvel de novo",
           len(SiteQueAceita.recebidos) == 1,
           f"{len(SiteQueAceita.recebidos)} cadastros")
    checar("e explica por que recusou", r.status_code == 409, r.status_code)
    checar("dizendo que já está no site", "já está no site" in texto(r))

print("\n--- nada que o Tel lê está em inglês ---")
# O Flask devolve a página PADRÃO DO WERKZEUG quando ninguém trata o erro, e
# ela é em inglês: "Not Found -- The requested URL was not found on the server".
# Medido em 02/09/2026 abrindo `/captacao/4242`.
for caminho in ("/captacao/424242", "/nao-existe-essa-tela"):
    corpo = texto(c.get(caminho))
    checar(f"{caminho} responde em português",
           "Not Found" not in corpo and "requested URL" not in corpo,
           corpo[:80])
    checar(f"{caminho} diz o que fazer", "lista" in corpo, corpo[:80])

print("\n--- só entra em `campos` o nome que a tela desenhou ---")
# O nome vinha cru do formulário e virava chave do dicionário. Não é só
# sujeira: chave que o mapa do site não conhece bloqueia a publicação para
# sempre, com um rótulo que não quer dizer nada.
banco.linhas[9001] = {"id": 9001, "link": "https://am.olx.com.br/x",
                      "status": "rascunho", "olx_id": "9001", "titulo": "T",
                      "dados_olx": {}, "campos": {"tipo": "casa"},
                      "fotos_pasta": None, "codigo_site": None, "erro": None,
                      "criado_em": None, "atualizado_em": None}
banco.fotos[9001] = []
c.post("/captacao/9001", data={"csrf": c._csrf, "campo_": "vazio",
                               "campo_../../etc/passwd": "x",
                               "campo_tipo": "apartamento"})
salvos = banco.linhas[9001]["campos"]
checar("nome de campo vazio não entra", "" not in salvos, salvos)
checar("nome de campo com caminho não entra", "../../etc/passwd" not in salvos,
       salvos)
checar("mas o campo de verdade entra", salvos.get("tipo") == "apartamento",
       salvos)

print("\n--- a caixa vazia não apaga o valor que já estava lá ---")
# O mesmo nome pode chegar duas vezes (o campo aparece em "Falta preencher" e
# em "Já preenchido"), e `request.form.items()` entrega só a PRIMEIRA
# ocorrência -- que é a caixa vazia. Salvar assim APAGAVA o valor.
from werkzeug.datastructures import MultiDict   # noqa: E402
banco.linhas[9002] = dict(banco.linhas[9001], id=9002,
                          campos={"area_util": "80"})
banco.fotos[9002] = []
c.post("/captacao/9002", data=MultiDict([("csrf", c._csrf),
                                         ("campo_area_util", ""),
                                         ("campo_area_util", "80")]))
checar("vale a resposta com conteúdo, não a caixa vazia",
       banco.linhas[9002]["campos"].get("area_util") == "80",
       banco.linhas[9002]["campos"])

print("\n--- o olx_id vira nome de pasta, e nome de pasta vindo de fora tem coleira ---")
base = os.path.normpath(captacao.PASTA_FOTOS) + os.sep
for hostil in ("../../../../tmp/invadido", "/etc/passwd", "..", "", None):
    destino = os.path.normpath(
        os.path.join(captacao.PASTA_FOTOS, captacao._nome_de_pasta(hostil)))
    checar(f"olx_id {hostil!r} não sai da pasta de fotos",
           destino.startswith(base), destino)
checar("e o id normal continua sendo o nome da pasta",
       captacao._nome_de_pasta("1526572128") == "1526572128")

print("\n--- castigo cumprido zera a conta ---")
# Sem isto o contador ficava em 5 para sempre, e meses depois um único erro de
# digitação do Tel valia outros 5 minutos de porta fechada.
captacao._TENTATIVAS.clear()
for _ in range(captacao.LIMITE_TENTATIVAS):
    captacao._registrar_falha("10.0.0.9")
checar("5 erros seguidos castigam", captacao._bloqueado_ate("10.0.0.9") > 0)
captacao._TENTATIVAS["10.0.0.9"] = (captacao.LIMITE_TENTATIVAS, time.time() - 1)
captacao._registrar_falha("10.0.0.9")
checar("um erro depois do castigo vencido NÃO castiga de novo",
       captacao._bloqueado_ate("10.0.0.9") == 0)
captacao._TENTATIVAS.clear()

print("\n--- o host do link vai em minúscula ---")
# `extrair_olx._regionalizar` troca `www.olx.com.br` por `am.olx.com.br` com uma
# regex sensível a maiúscula. Um `WWW.OLX.COM.BR` colado do celular ia buscar no
# host `www`, que devolve 200 com a página ERRADA -- erro silencioso.
checar("WWW.OLX.COM.BR vira www.olx.com.br",
       captacao.link_valido("https://WWW.OLX.COM.BR/casa-1")
       == "https://www.olx.com.br/casa-1",
       captacao.link_valido("https://WWW.OLX.COM.BR/casa-1"))
checar("e o caminho não é mexido",
       captacao.link_valido("https://AM.Olx.Com.Br/Casa-Grande-1")
       == "https://am.olx.com.br/Casa-Grande-1",
       captacao.link_valido("https://AM.Olx.Com.Br/Casa-Grande-1"))

print("\n--- sair encerra a sessão ---")
r = c.post("/sair", data={"csrf": c._csrf})
checar("redireciona", r.status_code == 302, r.status_code)
r = c.get("/")
checar("e a lista volta a pedir senha", r.status_code == 302, r.status_code)

shutil.rmtree(pasta, ignore_errors=True)   # teste não deixa lixo em /tmp

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    sys.exit(1)
print("TODOS OS CASOS DA TELA DE CAPTACAO PASSARAM")
