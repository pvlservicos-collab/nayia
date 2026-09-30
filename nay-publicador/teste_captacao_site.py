"""Prova o cadastrador do admin da Imob Easy SEM SENHA e SEM REDE.

Não temos credencial do admin (02/09/2026), então nada aqui pode ser provado
"rodando de verdade". O que dá para provar, e é o que estes casos fazem, é o
comportamento do nosso lado diante de cada resposta que o site pode dar --
com uma sessão dublê que devolve HTML fixo.

Os dois HTML de referência foram COPIADOS da forma real, medida no mesmo dia:
  * o formulário de /entrar, com `authenticity_token` no form e um
    <meta csrf-token> de valor DIFERENTE (é assim mesmo que o site manda);
  * a página pública /anuncios/3985, com os pares
    <label class="form-control-label"> + <span class="form-control">, o
    <h5 class="mg-b-0 tx-black"> do tipo e o <meta name="description"> onde os
    valores moram (a seção de valores vem comentada no HTML visível).

O que cada bloco existe para impedir:
  * tratar 200 como login/cadastro bem-sucedido -- o Rails responde 200 e
    redesenha o MESMO formulário quando a senha está errada ou a validação
    reprova. Achar que deu certo é o erro silencioso caro;
  * postar com nome de campo deduzido -- o Rails descarta em silêncio o
    parâmetro que não conhece, e o imóvel nasce com o campo vazio, sem erro;
  * dar por conferido o que não foi conferido -- valor que não dá para provar
    igual conta como DIVERGÊNCIA, nunca como "ok";
  * deixar a senha vazar para dentro de uma mensagem de erro.

    .venv/bin/python teste_captacao_site.py
"""
import os
import re
import sys
import tempfile

import captacao_site as cs

falhas = 0


def checar(rotulo, condicao, detalhe=""):
    global falhas
    if condicao:
        print(f"  OK   {rotulo}")
    else:
        falhas += 1
        print(f"  FALHOU {rotulo} {detalhe}")


def levanta(rotulo, funcao, tipo, trecho=None, detalhe=""):
    """Roda `funcao` esperando a exceção `tipo`; confere um trecho da mensagem."""
    try:
        funcao()
    except tipo as erro:
        texto = str(erro)
        if trecho and trecho.lower() not in texto.lower():
            checar(rotulo, False, f"mensagem sem {trecho!r}: {texto!r}")
            return None
        checar(rotulo, True)
        return erro
    except Exception as outra:
        checar(rotulo, False, f"levantou {type(outra).__name__}: {outra} {detalhe}")
        return None
    checar(rotulo, False, f"não levantou nada {detalhe}")
    return None


# --------------------------------------------------------------- os dublês
class Resposta:
    def __init__(self, status=200, texto="", local=None):
        self.status_code = status
        self.text = texto
        self.headers = {"Location": local} if local else {}


class SessaoFalsa:
    """Devolve HTML fixo por pedaço de URL e guarda tudo que foi chamado --
    é assim que se prova que uma recusa NÃO postou nada."""

    def __init__(self, respostas, padrao=None):
        self.respostas = respostas
        self.padrao = padrao or Resposta(404, "")
        self.gets = []
        self.posts = []

    def _achar(self, url):
        for pedaco, resposta in self.respostas.items():
            if pedaco in url:
                return resposta
        return self.padrao

    def _resposta(self, url):
        """Lista = uma resposta por chamada, na ordem: é assim que se encena o
        `entrar` (GET da página, depois POST) e a foto que falha no meio."""
        alvo = self._achar(url)
        return alvo.pop(0) if isinstance(alvo, list) else alvo

    def get(self, url, **kw):
        self.gets.append((url, kw))
        return self._resposta(url)

    def post(self, url, **kw):
        self.posts.append((url, kw))
        return self._resposta(url)


# ------------------------------------------------------- HTML de referência
LOGIN_HTML = """<html><head>
<meta name="csrf-param" content="authenticity_token" />
<meta name="csrf-token" content="TOKEN-DO-META-QUE-E-OUTRO" />
</head><body>
<form class="form floating-label" id="new_user" action="/entrar" accept-charset="UTF-8" method="post">
<input name="utf8" type="hidden" value="&#x2713;" />
<input type="hidden" name="authenticity_token" value="TOKEN-DO-FORM-123==" />
<div class="form-group">
<input autofocus="autofocus" class="form-control" placeholder="Email" type="email" value="" name="user[email]" id="user_email" />
</div>
<div class="form-group">
<input autocomplete="off" class="form-control" placeholder="Senha" type="password" name="user[password]" id="user_password" />
</div>
<input name="user[remember_me]" type="hidden" value="0" />
<button class="btn btn-primary btn-block btn-signin">Entrar</button>
</form></body></html>"""

FORM_NOVO_HTML = """<html><body>
<form action="/admin/imoveis" method="post">
<input type="hidden" name="authenticity_token" value="TOKEN-DO-CADASTRO" />
<input type="text" name="imovel[bairro]" />
</form></body></html>"""


def pagina_publica(pares, tipo="Apartamento / Apartamento - Vision Residence",
                   descricao="Apartamento localizado no condomínio Vision Residence\n"
                             "- 3 quarto (sendo 3 suite)\n- 5 banheiro\n- 150 m2\n"
                             " - R$ 2.200.000,00 (venda)"):
    """Monta a página no MESMO aninhamento do site (copiado de /anuncios/3985)."""
    blocos = "\n".join(
        '<div class="col-md-12"><div class="form-group ">'
        f'<label class="form-control-label">{rotulo}</label>\n'
        f'<span class="form-control">{valor}</span>'
        "</div></div>" for rotulo, valor in pares)
    return (f'<html><head><meta name="description" content="{descricao}" />'
            f'</head><body><h5 class="mg-b-0 tx-black">{tipo}</h5>'
            f'<div class="card-body pd-t-0-force"><div class="row no-gutters tx-left">'
            f"{blocos}</div></div></body></html>")


# Os valores são os do imóvel 3985 de verdade, lidos em 02/09/2026.
ANUNCIO_3985 = pagina_publica([
    ("Condomínio", "Vision Residence"),
    ("Bairro", "Ponta Negra"),
    ("Área", "150.0 m2"),
    ("Quartos", "3\n          (sendo 3 suítes)"),
    ("Banheiros", "5"),
    ("Sol", "Nascente"),
    ("Vagas", "3"),
    ("Aceita Permuta?", "Não"),
    ("Aceita Financiamento?", "Sim"),
])

MAPA_CONFIRMADO = cs.MapaDoFormulario(
    url_form="https://imobeasy.com/admin/imoveis/new",
    url_criar="https://imobeasy.com/admin/imoveis",
    prefixo="imovel",
    campos={"bairro": "bairro", "quartos": "quartos", "area_util": "area_util",
            "sol": "sol", "descricao": "descricao", "suites": "suites",
            "aceita_permuta": "aceita_permuta"},
    campo_foto="imovel[fotos][]",
    fotos_no_mesmo_post=True,
    # Data de mentira, SÓ NESTE TESTE: é o estado "alguém já leu o formulário
    # de verdade". No módulo continua None, e é isso que segura o cadastro.
    confirmado_em="2026-09-02 (dublê de teste)",
)

JPEG = b"\xff\xd8\xff\xe0" + b"foto de verdade" * 10


print("--- o token do formulário de login (HTML real) ---")
checar("tira o authenticity_token do form",
       cs._token(LOGIN_HTML, "/entrar") == "TOKEN-DO-FORM-123==")
checar("prefere o do FORM ao do <meta csrf-token>",
       cs._token(LOGIN_HTML, "/entrar") != "TOKEN-DO-META-QUE-E-OUTRO",
       "medido: os dois vêm com valores diferentes na mesma página")
checar("sem form, cai no meta",
       cs._token('<meta name="csrf-token" content="SO-O-META" />', None) == "SO-O-META")
erro = levanta("página sem token nenhum vira erro com passo",
               lambda: cs._token("<html><body>oi</body></html>", "/entrar"),
               cs.FalhaNaCaptacao, "authenticity_token")
checar("o erro do token diz o passo", erro is not None and erro.passo == cs.PASSO_LOGIN)


print()
print("--- credencial: só do ambiente, nunca no código ---")
guardado = {n: os.environ.pop(n, None) for n in ("IMOBEASY_EMAIL", "IMOBEASY_SENHA")}
try:
    erro = levanta("sem as duas variáveis, erro que diz o nome delas",
                   cs.credenciais, cs.FalhaDeCredencial, "IMOBEASY_EMAIL")
    checar("o erro cita também a senha", erro is not None and "IMOBEASY_SENHA" in str(erro))
    checar("o passo é 'credencial'", erro is not None and erro.passo == cs.PASSO_CREDENCIAL)

    os.environ["IMOBEASY_EMAIL"] = "quem@exemplo.com"
    erro = levanta("com e-mail e sem senha, reclama só da senha",
                   cs.credenciais, cs.FalhaDeCredencial, "IMOBEASY_SENHA")
    checar("não reclama do que já tem",
           erro is not None and "IMOBEASY_EMAIL" not in erro.mensagem)

    os.environ["IMOBEASY_SENHA"] = "segredo-que-nao-pode-vazar"
    checar("com as duas, devolve as duas",
           cs.credenciais() == ("quem@exemplo.com", "segredo-que-nao-pode-vazar"))
    checar("argumento explícito ganha do ambiente",
           cs.credenciais("outro@x.com", "outra")[0] == "outro@x.com")

    fonte = open("captacao_site.py", encoding="utf-8").read()
    checar("nenhum e-mail literal no código do módulo",
           not re.search(r"[\w.+-]+@[\w-]+\.[a-z]{2,}", fonte),
           "credencial em código é regra quebrada do projeto")
    checar("a senha vem do ambiente",
           'os.environ.get("IMOBEASY_SENHA")' in fonte)
    # O `'...'` do texto de ajuda é o único valor entre aspas aceito ao lado do
    # nome da variável: qualquer outro seria credencial dentro do repositório.
    checar("nenhuma credencial escrita no arquivo",
           not re.search(r"""IMOBEASY_(?:EMAIL|SENHA)\s*=\s*['\"](?!\.\.\.['\"])""",
                         fonte))

    print()
    print("--- entrar: 200 NÃO é sucesso ---")
    sessao = SessaoFalsa({"/entrar": [Resposta(200, LOGIN_HTML),
                                      Resposta(302, "", "https://imobeasy.com/admin")]})
    devolvida = cs.entrar("quem@exemplo.com", "senha", sessao=sessao)
    checar("302 para fora de /entrar é login feito", devolvida is sessao)
    enviado = sessao.posts[0][1]["data"]
    checar("manda user[email] e user[password]",
           enviado["user[email]"] == "quem@exemplo.com"
           and enviado["user[password]"] == "senha")
    checar("manda o token do formulário",
           enviado["authenticity_token"] == "TOKEN-DO-FORM-123==")
    checar("manda o utf8 do Rails", enviado["utf8"] == "✓")
    checar("não segue o redirect sozinho",
           sessao.posts[0][1]["allow_redirects"] is False,
           "seguir o redirect esconde justamente o sinal que prova o sucesso")

    sessao = SessaoFalsa({"/entrar": [Resposta(200, LOGIN_HTML),
                                      Resposta(200, LOGIN_HTML)]})
    erro = levanta("senha errada (200 + o mesmo form) NÃO é sucesso",
                   lambda: cs.entrar("quem@exemplo.com", "errada", sessao=sessao),
                   cs.FalhaDeLogin, "não me deixou entrar")
    checar("o passo é 'login'", erro is not None and erro.passo == cs.PASSO_LOGIN)
    checar("a SENHA não aparece na mensagem de erro",
           erro is not None and "errada" not in str(erro),
           "esta mensagem vai para log e pode ir para o WhatsApp do Tel")

    sessao = SessaoFalsa({"/entrar": [Resposta(200, LOGIN_HTML),
                                      Resposta(302, "", "https://imobeasy.com/entrar")]})
    levanta("302 de volta para /entrar também é recusa",
            lambda: cs.entrar("a@b.com", "x", sessao=sessao),
            cs.FalhaDeLogin, "não me deixou entrar")

    sessao = SessaoFalsa({"/entrar": Resposta(500, "")})
    erro = levanta("site fora do ar: erro que diz que a senha nem foi mandada",
                   lambda: cs.entrar("a@b.com", "x", sessao=sessao),
                   cs.FalhaDeLogin, "nem cheguei a mandar")
    checar("e nesse caso não postou nada", sessao.posts == [])
finally:
    for nome, valor in guardado.items():
        os.environ.pop(nome, None)
        if valor is not None:
            os.environ[nome] = valor


print()
print("--- cadastrar: os portões que fecham ---")
sessao = SessaoFalsa({"/admin": Resposta(200, FORM_NOVO_HTML)})
erro = levanta("mapa nunca conferido NÃO posta",
               lambda: cs.cadastrar(sessao, {"bairro": "Flores"}),
               cs.FalhaDeFormulario, "nunca foi conferido")
checar("o passo é 'formulario'", erro is not None and erro.passo == cs.PASSO_FORMULARIO)
checar("e não chegou a postar nem a abrir o formulário",
       sessao.posts == [] and sessao.gets == [],
       "o Rails descarta campo desconhecido em silêncio: postar às cegas grava vazio")
checar("o mapa de produção continua não confirmado",
       cs.MAPA_PROVISORIO.confirmado_em is None and not cs.MAPA_PROVISORIO.confirmado)

sessao = SessaoFalsa({"/admin": Resposta(200, FORM_NOVO_HTML)})
levanta("campo fora do mapa NÃO posta",
        lambda: cs.cadastrar(sessao, {"bairro": "Flores", "piscina": "sim"},
                             mapa=MAPA_CONFIRMADO),
        cs.FalhaDeFormulario, "piscina")
checar("e também não postou nada", sessao.posts == [])

sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/admin/imoveis": Resposta(302, "",
                                                 "https://imobeasy.com/admin/imoveis/5750")})
resultado = cs.cadastrar(sessao, {"bairro": "Flores", "quartos": 3, "suites": None,
                                  "aceita_permuta": False},
                         mapa=MAPA_CONFIRMADO)
checar("devolve o código lido do redirect", resultado["codigo"] == "5750")
checar("devolve a URL pública do imóvel",
       resultado["url"] == "https://imobeasy.com/anuncios/5750")
postado = sessao.posts[0][1]["data"]
checar("prefixa os campos como o Rails espera", postado["imovel[bairro]"] == "Flores")
checar("número vai como texto", postado["imovel[quartos]"] == "3")
checar("no POST de verdade, o False vai como '0'",
       postado["imovel[aceita_permuta]"] == "0")
checar("campo None NÃO é enviado", "imovel[suites]" not in postado,
       "ausente não é zero: mandar vazio apagaria no site o que já estava lá")
checar("usa o token da PÁGINA DO CADASTRO, não o do login",
       postado["authenticity_token"] == "TOKEN-DO-CADASTRO")

checar("True vira '1' e False vira '0'",
       cs._para_o_form(True) == "1" and cs._para_o_form(False) == "0",
       "o Rails lê a string 'False' como VERDADEIRO: só 0/f/false/off são falso")
checar("número e texto passam inteiros",
       cs._para_o_form(150) == "150" and cs._para_o_form("Flores") == "Flores")

sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/admin/imoveis": Resposta(200, FORM_NOVO_HTML)})
levanta("200 depois do POST é validação reprovada, não sucesso",
        lambda: cs.cadastrar(sessao, {"bairro": "Flores"}, mapa=MAPA_CONFIRMADO),
        cs.FalhaDeFormulario, "NÃO foi criado")

sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/admin/imoveis": Resposta(302, "", "https://imobeasy.com/admin")})
levanta("redirect sem código avisa que PODE ter criado",
        lambda: cs.cadastrar(sessao, {"bairro": "Flores"}, mapa=MAPA_CONFIRMADO),
        cs.FalhaDeFormulario, "PROVAVELMENTE FOI CRIADO")

sessao = SessaoFalsa({"/admin": Resposta(200, LOGIN_HTML)})
erro = levanta("formulário voltando como tela de login é sessão caída",
               lambda: cs.cadastrar(sessao, {"bairro": "Flores"}, mapa=MAPA_CONFIRMADO),
               cs.FalhaDeSessao, "sessão caiu")
checar("o passo é 'sessao', não 'formulario'",
       erro is not None and erro.passo == cs.PASSO_SESSAO,
       "confundir os dois manda consertar a coisa errada")


print()
print("--- foto: recusa o que não é foto ---")
levanta("foto vazia é recusada",
        lambda: cs._arquivo(("vazia.jpg", b"")), cs.FalhaDeFoto, "VAZIA")
levanta("página de erro salva como .jpg é recusada",
        lambda: cs._arquivo(("erro.jpg", b"<html><body>404</body></html>")),
        cs.FalhaDeFoto, "não parece imagem")
levanta("arquivo que não existe diz o caminho",
        lambda: cs._arquivo("/tmp/nao-existe-de-jeito-nenhum.jpg"),
        cs.FalhaDeFoto, "não consegui ler")
nome, conteudo, tipo = cs._arquivo(("boa.jpg", JPEG))
checar("JPEG de verdade passa", nome == "boa.jpg" and tipo == "image/jpeg")
checar("PNG também passa",
       cs._arquivo(("a.png", b"\x89PNG\r\n\x1a\n" + b"x" * 40))[2] == "image/png")

# O caminho de disco é o que a plataforma vai usar de verdade: quem baixa a
# foto da OLX grava em arquivo antes de subir.
caminho = os.path.join(tempfile.mkdtemp(), "capa.jpg")
with open(caminho, "wb") as arquivo:
    arquivo.write(JPEG)
checar("lê foto de um caminho no disco",
       cs._arquivo(caminho) == ("capa.jpg", JPEG, "image/jpeg"))

sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML)})
sem_caminho = cs.MapaDoFormulario(
    url_form="https://imobeasy.com/admin/imoveis/new",
    url_criar="https://imobeasy.com/admin/imoveis",
    campos={"bairro": "bairro"}, confirmado_em="dublê")
levanta("foto sem caminho no mapa NÃO cadastra pela metade",
        lambda: cs.cadastrar(sessao, {"bairro": "Flores"},
                             fotos=[("a.jpg", JPEG)], mapa=sem_caminho),
        cs.FalhaDeFoto, "por onde subir")
checar("e não postou nada", sessao.posts == [])

sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/admin/imoveis": Resposta(302, "",
                                                 "https://imobeasy.com/admin/imoveis/77")})
resultado = cs.cadastrar(sessao, {"bairro": "Flores"},
                         fotos=[("a.jpg", JPEG), ("b.jpg", JPEG)],
                         mapa=MAPA_CONFIRMADO)
checar("com fotos no mesmo POST, sobem as duas", resultado["fotos_enviadas"] == 2)
checar("as fotos vão no campo do mapa",
       list(sessao.posts[0][1]["files"]) == ["imovel[fotos][]"])

# Admin com tela de foto separada: cadastra primeiro, sobe as fotos depois.
em_duas_etapas = cs.MapaDoFormulario(
    url_form="https://imobeasy.com/admin/imoveis/new",
    url_criar="https://imobeasy.com/admin/imoveis",
    campos={"bairro": "bairro"}, campo_foto="foto[arquivo]",
    url_fotos="https://imobeasy.com/admin/imoveis/{codigo}/fotos",
    fotos_no_mesmo_post=False, confirmado_em="dublê")
sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/fotos": Resposta(302, "", "/ok"),
                      "/admin/imoveis": Resposta(302, "",
                                                 "https://imobeasy.com/admin/imoveis/88")})
resultado = cs.cadastrar(sessao, {"bairro": "Flores"},
                         fotos=[("a.jpg", JPEG), ("b.jpg", JPEG)],
                         mapa=em_duas_etapas)
checar("com tela de foto separada, sobe as duas depois de cadastrar",
       resultado["codigo"] == "88" and resultado["fotos_enviadas"] == 2)
checar("cada foto vai num POST próprio, na URL do imóvel",
       [u for u, _ in sessao.posts].count(
           "https://imobeasy.com/admin/imoveis/88/fotos") == 2,
       "uma a uma: falhar em lote não diz quais entraram")

separado = cs.MapaDoFormulario(
    url_form="https://imobeasy.com/admin/imoveis/new",
    url_criar="https://imobeasy.com/admin/imoveis",
    campos={"bairro": "bairro"}, campo_foto="foto[arquivo]",
    url_fotos="https://imobeasy.com/admin/imoveis/{codigo}/fotos",
    confirmado_em="dublê")
sessao = SessaoFalsa({"/fotos": [Resposta(302, "", "/ok"), Resposta(500, "")],
                      "/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML)})
erro = levanta("foto recusada no meio diz QUAL e quantas já subiram",
               lambda: cs.enviar_fotos(sessao, "77",
                                       [("a.jpg", JPEG), ("b.jpg", JPEG)],
                                       mapa=separado),
               cs.FalhaDeFoto, "'b.jpg'")
checar("diz que é a 2ª", erro is not None and "2ª" in str(erro))
checar("diz que 1 já subiu", erro is not None and "1 anteriores já subiram" in str(erro),
       "reenviar tudo duplicaria as que entraram")
checar("o passo é 'foto'", erro is not None and erro.passo == cs.PASSO_FOTO)


# ------------------------------------------------------------------------
# Regressao (02/09/2026, achada rodando contra o modulo): o portao de fotos
# olhava `campo_foto or url_fotos`. Mapa MEIO preenchido passava, o imovel era
# CRIADO e so entao estourava no envio da foto -- imovel no ar sem foto, e
# quem repetisse o comando criava um segundo. Portao tem que fechar ANTES do
# POST, conferindo a rota QUE VAI SER USADA.
meio_preenchido = cs.MapaDoFormulario(   # a forma do MAPA_PROVISORIO de hoje
    url_form="https://imobeasy.com/admin/imoveis/new",
    url_criar="https://imobeasy.com/admin/imoveis",
    campos={"bairro": "bairro"},
    campo_foto="imovel[fotos][]", url_fotos=None,
    fotos_no_mesmo_post=False, confirmado_em="dublê")
sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/admin/imoveis": Resposta(302, "",
                                                 "https://imobeasy.com/admin/imoveis/9001")})
levanta("campo_foto sem url_fotos NAO cria o imovel primeiro",
        lambda: cs.cadastrar(sessao, {"bairro": "Flores"},
                             fotos=[("a.jpg", JPEG)], mapa=meio_preenchido),
        cs.FalhaDeFoto, "por onde subir")
checar("e o imovel NAO chegou a ser criado", sessao.posts == [],
       "criar e so depois descobrir que nao sabe subir foto deixa imovel orfao")

so_url = cs.MapaDoFormulario(
    url_form="https://imobeasy.com/admin/imoveis/new",
    url_criar="https://imobeasy.com/admin/imoveis",
    campos={"bairro": "bairro"},
    campo_foto=None,
    url_fotos="https://imobeasy.com/admin/imoveis/{codigo}/fotos",
    fotos_no_mesmo_post=True, confirmado_em="dublê")
sessao = SessaoFalsa({"/admin/imoveis/new": Resposta(200, FORM_NOVO_HTML),
                      "/admin/imoveis": Resposta(302, "",
                                                 "https://imobeasy.com/admin/imoveis/9002")})
levanta("no mesmo POST sem saber o nome do campo, tambem nao cria",
        lambda: cs.cadastrar(sessao, {"bairro": "Flores"},
                             fotos=[("a.jpg", JPEG)], mapa=so_url),
        cs.FalhaDeFoto, "campo_foto")
checar("e tambem nao criou nada", sessao.posts == [],
       "senao o files= iria com a chave None e ele diria 'foto enviada'")

# A sessao pode cair NO MEIO das fotos: o admin devolve a tela de login com
# status 200, que estava na lista de "deu certo". 1 de 3 virava 3 de 3.
sessao = SessaoFalsa({"/fotos": [Resposta(302, "", "/ok"),
                                 Resposta(200, LOGIN_HTML),
                                 Resposta(200, LOGIN_HTML)]})
erro = levanta("sessao caida no meio das fotos NAO conta como enviada",
               lambda: cs.enviar_fotos(sessao, "9003",
                                       [("a.jpg", JPEG), ("b.jpg", JPEG),
                                        ("c.jpg", JPEG)], mapa=separado),
               cs.FalhaDeSessao, "sessão caiu")
checar("diz qual foto parou e quantas ja subiram",
       erro is not None and "'b.jpg'" in str(erro) and "1 anteriores" in str(erro),
       "tela de login com 200 estava sendo contada como foto enviada")

# `str(None)` e' a palavra "None", e o Rails le "None" num campo de sim/nao
# como VERDADEIRO -- o mesmo estrago que o "False" que esta funcao ja evitava.
levanta("None NUNCA vira a palavra 'None' no formulario",
        lambda: cs._para_o_form(None), cs.FalhaDeFormulario, "None é")

# `_texto()` ja devolve "" para resposta sem corpo; isto garante que uma
# chamada direta nao vaze TypeError cru do BeautifulSoup.
checar("HTML vazio/None nao estoura erro cru",
       cs._valores_publicados(None) == {} and cs._e_pagina_de_login(None) is False)


print()
print("--- conferir: lê de volta a página real e compara ---")
lidos = cs._valores_publicados(ANUNCIO_3985)
checar("lê o bairro", lidos["bairro"] == "Ponta Negra")
checar("lê o condomínio", lidos["condominio_nome"] == "Vision Residence")
checar("'Área' vira area_util", lidos["area_util"] == "150.0 m2")
checar("separa quartos de suítes", lidos["quartos"] == "3" and lidos["suites"] == "3")
checar("lê o tipo do cabeçalho", lidos["tipo"] == "Apartamento")
checar("lê o valor de venda do <meta description>",
       lidos["valor_venda"] == "2.200.000,00",
       "a seção de valores vem comentada no HTML visível")
checar("valor não existente fica AUSENTE", "valor_aluguel" not in lidos)

sem_suite = cs._valores_publicados(pagina_publica([("Quartos", "2")]))
checar("sem a palavra suíte, suítes fica AUSENTE, não zero",
       "suites" not in sem_suite and sem_suite["quartos"] == "2",
       "inventar suites=0 é bug conhecido do extrator do catálogo")

maiusculo = cs._valores_publicados(pagina_publica([("Área total", "750.0 m2")]))
minusculo = cs._valores_publicados(pagina_publica([("Área Total", "30.0 m2")]))
checar("'Área total' e 'Área Total' caem no mesmo campo",
       maiusculo.get("area_total") and minusculo.get("area_total"),
       "o próprio site escreve dos dois jeitos, medido")

sessao = SessaoFalsa({"/anuncios/3985": Resposta(200, ANUNCIO_3985)})
relatorio = cs.conferir(sessao, "3985", {
    "bairro": "Ponta Negra", "condominio_nome": "Vision Residence",
    "area_util": 150, "quartos": 3, "banheiros": 5, "sol": "Nascente",
    "valor_venda": 2200000, "aceita_financiamento": True,
    "aceita_permuta": False,
})
checar("tudo batendo dá ok", relatorio["ok"] is True)
checar("conferiu os 9 campos", len(relatorio["conferidos"]) == 9,
       str(sorted(relatorio["conferidos"])))
checar("'150.0 m2' bate com 150", "area_util" in relatorio["conferidos"])
checar("'2.200.000,00' bate com 2200000", "valor_venda" in relatorio["conferidos"])
checar("'Sim' bate com True", "aceita_financiamento" in relatorio["conferidos"])
checar("'Não' bate com False", "aceita_permuta" in relatorio["conferidos"])

erro = levanta("divergência de bairro estoura",
               lambda: cs.conferir(sessao, "3985", {"bairro": "Flores"}),
               cs.FalhaDeConferencia, "Flores")
checar("o passo é 'conferencia'", erro is not None and erro.passo == cs.PASSO_CONFERENCIA)
checar("o erro diz o que o site tem", erro is not None and "Ponta Negra" in str(erro))
checar("o relatório inteiro vem junto do erro",
       erro is not None and erro.detalhe["divergencias"][0]["campo"] == "bairro")

relatorio = cs.conferir(sessao, "3985", {"bairro": "Flores"}, estourar=False)
checar("com estourar=False devolve o relatório", relatorio["ok"] is False)

relatorio = cs.conferir(sessao, "3985", {"logradouro": "Rua X"}, estourar=False)
checar("campo enviado que sumiu da página é DIVERGÊNCIA",
       relatorio["divergencias"][0]["motivo"] == "não apareceu na página",
       "é exatamente assim que o Rails descarta um nome de campo errado")

relatorio = cs.conferir(sessao, "3985", {"descricao": "casa boa"}, estourar=False)
checar("campo que a página não mostra vira 'não conferido', não 'ok'",
       relatorio["nao_conferidos"] == ["descricao"]
       and relatorio["conferidos"] == [],
       "dar por conferido o que não foi olhado é pior que não conferir")

relatorio = cs.conferir(sessao, "3985")
checar("sem 'enviado', só prova que o imóvel existe",
       relatorio["ok"] is True and relatorio["conferidos"] == []
       and relatorio["gravados"]["bairro"] == "Ponta Negra")

sessao = SessaoFalsa({"/anuncios/": Resposta(302, "", "https://imobeasy.com/nao-encontrado")})
erro = levanta("imóvel não publicado: erro que aponta o anúncio",
               lambda: cs.conferir(sessao, "9999", {"bairro": "X"}),
               cs.FalhaDeConferencia, "não está publicado")
checar("lembra que o ANÚNCIO é outro cadastro",
       erro is not None and "ANÚNCIO" in str(erro),
       "/admin/imoveis/new e /admin/anuncios/new são rotas diferentes, medido")

sessao = SessaoFalsa({"/anuncios/": Resposta(200, "<html><body>oi</body></html>")})
levanta("200 sem campo nenhum não vira 'conferido'",
        lambda: cs.conferir(sessao, "3985", {"bairro": "X"}),
        cs.FalhaDeConferencia, "campo NENHUM")

sessao = SessaoFalsa({"/anuncios/": Resposta(200, LOGIN_HTML)})
levanta("tela de login na conferência é sessão caída",
        lambda: cs.conferir(sessao, "3985", {"bairro": "X"}),
        cs.FalhaDeSessao, "sessão caiu")


print()
print("--- a comparação só diz 'igual' quando PROVA que é igual ---")
checar("acento e caixa não são divergência",
       cs._mesmo_valor("Nascente", "nascente") and cs._mesmo_valor("Taruma", "Tarumã"))
checar("valor diferente é divergência", not cs._mesmo_valor("Nascente", "Poente"))
checar("'R$  1.700,00' é 1700", cs._numero("R$  1.700,00") == 1700.0)
checar("'150.0 m2' é 150, não 1500", cs._numero("150.0 m2") == 150.0)
checar("'12.000' é doze mil (ponto de milhar)", cs._numero("12.000") == 12000.0)
checar("'Rua 3 de Maio' NÃO é o número 3", cs._numero("Rua 3 de Maio") is None,
       "casar um pedaço da string faria endereço virar número")
checar("texto vs número não vira igual",
       not cs._mesmo_valor(3, "Nascente") and not cs._mesmo_valor("Nascente", 3))
checar("número NÃO é sim/não", cs._booleano("1") is None and cs._booleano(1) is None,
       "se 1 virasse True, quartos=1 casaria com um 'Sim' gravado noutro campo")
checar("vazio dos dois lados é igual", cs._mesmo_valor(None, ""))
checar("vazio de um lado só é divergência",
       not cs._mesmo_valor("Flores", "") and not cs._mesmo_valor(None, "Flores"))


print()
print("--- toda falha diz o passo ---")
for classe, passo in ((cs.FalhaDeCredencial, "credencial"), (cs.FalhaDeLogin, "login"),
                      (cs.FalhaDeSessao, "sessao"), (cs.FalhaDeFormulario, "formulario"),
                      (cs.FalhaDeFoto, "foto"), (cs.FalhaDeConferencia, "conferencia")):
    erro = classe("qualquer coisa")
    checar(f"{classe.__name__} carimba [{passo}]",
           erro.passo == passo and str(erro).startswith(f"[{passo}]")
           and isinstance(erro, cs.FalhaNaCaptacao))

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
sys.exit(1 if falhas else 0)
