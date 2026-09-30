"""
Cadastra no admin da Imob Easy o imóvel que a captação montou a partir do
anúncio do proprietário na OLX -- o passo que hoje o Tel faz redigitando à mão.

Caso real que motiva o arquivo (pedido do Tel, 02/09/2026): "a gente faz a
captação de imóveis diretamente com o proprietário... eu quero pegar esse
anúncio dele no OLX e colocar no site da imobeasy.com já cadastrado". O imóvel
é NOSSO; o anúncio da OLX é do proprietário. Não há republicação de terceiro.

ESTADO, sem rodeio: NÃO TEMOS A SENHA DO ADMIN. Nada aqui foi executado contra
o formulário de verdade. O que está medido e o que está deduzido:

  MEDIDO em 02/09/2026, do Mac, sem login (é reprodutível: `--medir`):
    * GET /admin -> 302 para /entrar (Rails + Devise).
    * O formulário de /entrar é, literalmente:
        <form id="new_user" action="/entrar" method="post">
          <input type="hidden" name="utf8" value="✓">
          <input type="hidden" name="authenticity_token" value="...">
          <input type="email"    name="user[email]">
          <input type="password" name="user[password]">
          <input type="hidden"   name="user[remember_me]" value="0">
      O token também vem em <meta name="csrf-token">, com valor DIFERENTE do
      que está no formulário -- por isso `_token` prefere o do formulário.
    * Quais rotas do admin EXISTEM, sem logar: no Rails o `authenticate_user!`
      só roda depois de a rota casar, então 302 para /entrar prova que a rota
      existe e 404 prova que não existe. Resultado:
        /admin/imoveis            302   (existe)
        /admin/imoveis/new        302   (existe)  <- o formulário de cadastro
        /admin/imoveis/<id>       302   (existe)
        /admin/anuncios/new       302   (existe)  <- OUTRO recurso, ver abaixo
        /admin/imoveis/<id>/edit  404   (NÃO existe, para id nenhum)
        /admin/imovel/new         404
        /admin/properties/new     404
    * Um anúncio que não existe: /anuncios/999999 -> 302 para /nao-encontrado.
      É assim que `conferir` sabe que o imóvel não está publicado, em vez de
      engolir um 404 achando que leu a página.
    * Os rótulos que o site PUBLICA, lidos de 12 anúncios reais, um de cada
      tipo (é a melhor pista que existe hoje sobre o que o formulário pede):
        Bairro 12/12 | Banheiros 10/12 | Vagas 7/12 | Aceita Permuta? 7/12 |
        Aceita Financiamento? 7/12 | Área 6/12 | Quartos 6/12 |
        Área Construída 6/12 | Vagas Cobertas 6/12 | Condomínio 5/12 |
        Sol 4/12 | Salas 4/12 | Complemento 3/12 | Tamanho do Terreno 3/12 |
        Área total 2/12 | Frente 2/12 | Fundo 2/12 | Tipo de Cobertura 1/12 |
        Pé Direito 1/12 | Nível 1/12 | IPTU 1/12 | Andares 1/12 |
        Elevadores 1/12 | Área Total 1/12
      Repare em "Área total" e "Área Total": o próprio site diverge no
      maiúsculo. Por isso a leitura casa rótulo sem acento e sem caixa.

  DEDUZIDO, e portanto DESLIGADO: os nomes dos campos do formulário
  (`imovel[bairro]` etc.) em `MAPA_PROVISORIO`. Ninguém os leu. `cadastrar`
  se RECUSA a postar com um mapa que tem `confirmado_em = None`.

Por que a recusa e não "tenta e vê no que dá": o Rails descarta em silêncio
todo parâmetro que não está no `permit` do controller. Um nome errado não dá
erro nenhum -- o imóvel é criado com o campo VAZIO, e ninguém percebe até o
corretor perguntar a metragem. Formulário de terceiro muda sem aviso, e pior
que parar é continuar gravando no campo errado. É o mesmo padrão de portão
que fecha do resto do projeto: só passa o que provar que pode.

A PERGUNTA MAIS CARA QUE FICOU EM ABERTO: `/admin/imoveis/new` e
`/admin/anuncios/new` são rotas DIFERENTES. Se "imóvel" e "anúncio" forem dois
cadastros, criar só o imóvel não publica nada -- e a varredura horária
(`sincronizar_catalogo.py`), que lê o site público, nunca vai ver o que
cadastramos. A plataforma diria "cadastrado" e o imóvel não existiria para a
Nay. Isso precisa ser respondido no primeiro minuto com a senha na mão.

O que este arquivo NÃO faz, de propósito: não escreve na tabela `imoveis`
(decisão de arquitetura -- quem traz o imóvel para o banco é a varredura), não
guarda credencial (só IMOBEASY_EMAIL / IMOBEASY_SENHA do ambiente) e não
converte dado da OLX (quem converte é quem chama; ver o cabeçalho de
`extrair_olx.py` e a fazenda de 12.000 hectares).

    .venv/bin/python captacao_site.py --plano            # o que fazer com a senha
    .venv/bin/python captacao_site.py --medir            # refaz as medições acima
    .venv/bin/python captacao_site.py --conferir 3985    # conferência pública, sem login
"""
import os
import re
import sys
import unicodedata

import requests
from bs4 import BeautifulSoup

from extrair_pagina import USER_AGENT

BASE = "https://imobeasy.com"
URL_ENTRAR = f"{BASE}/entrar"
URL_PUBLICA = BASE + "/anuncios/{codigo}"
TIMEOUT = 30

# Os passos, na ordem em que acontecem. Toda falha carrega um deles: às 22h,
# "deu erro" não diz se é para trocar a senha, arrumar o mapa do formulário ou
# reenviar uma foto.
PASSO_CREDENCIAL = "credencial"
PASSO_LOGIN = "login"
PASSO_SESSAO = "sessao"
PASSO_FORMULARIO = "formulario"
PASSO_FOTO = "foto"
PASSO_CONFERENCIA = "conferencia"


class FalhaNaCaptacao(RuntimeError):
    """Erro que sabe em QUAL passo aconteceu."""

    passo = "desconhecido"

    def __init__(self, mensagem, detalhe=None, passo=None):
        if passo:
            self.passo = passo
        super().__init__(f"[{self.passo}] {mensagem}")
        self.mensagem = mensagem
        self.detalhe = detalhe


class FalhaDeCredencial(FalhaNaCaptacao):
    passo = PASSO_CREDENCIAL


class FalhaDeLogin(FalhaNaCaptacao):
    passo = PASSO_LOGIN


class FalhaDeSessao(FalhaNaCaptacao):
    """Estávamos logados e caiu no meio -- o admin devolveu a tela de login."""

    passo = PASSO_SESSAO


class FalhaDeFormulario(FalhaNaCaptacao):
    passo = PASSO_FORMULARIO


class FalhaDeFoto(FalhaNaCaptacao):
    passo = PASSO_FOTO


class FalhaDeConferencia(FalhaNaCaptacao):
    passo = PASSO_CONFERENCIA


class MapaDoFormulario:
    """Onde fica cada coisa no admin: as URLs e o nome de cada campo.

    `confirmado_em` é a data em que ALGUÉM ABRIU o formulário de verdade e
    conferiu nome por nome. `None` significa "deduzido, nunca visto", e nesse
    estado `cadastrar` se recusa a postar. Não preencha esta data sem ter
    aberto /admin/imoveis/new logado e lido o HTML.
    """

    def __init__(self, url_form, url_criar, campos, prefixo="imovel",
                 url_ler=URL_PUBLICA, campo_foto=None, url_fotos=None,
                 fotos_no_mesmo_post=False, confirmado_em=None):
        self.url_form = url_form
        self.url_criar = url_criar
        self.campos = dict(campos)
        self.prefixo = prefixo
        self.url_ler = url_ler
        self.campo_foto = campo_foto
        self.url_fotos = url_fotos
        self.fotos_no_mesmo_post = fotos_no_mesmo_post
        self.confirmado_em = confirmado_em

    @property
    def confirmado(self):
        return bool(self.confirmado_em)

    def nome_no_form(self, campo):
        """`quartos` -> `imovel[quartos]`. Sem prefixo, devolve o nome cru."""
        nome = self.campos[campo]
        return f"{self.prefixo}[{nome}]" if self.prefixo else nome


# DEDUZIDO do que o site publica + convenção do Rails. NÃO CONFIRMADO: o
# `confirmado_em=None` é o que segura o `cadastrar`. Os nomes à direita são
# chute educado; os da esquerda são os do nosso banco, para o chamador não
# precisar aprender um vocabulário novo.
MAPA_PROVISORIO = MapaDoFormulario(
    url_form=f"{BASE}/admin/imoveis/new",
    url_criar=f"{BASE}/admin/imoveis",
    prefixo="imovel",
    campos={
        "tipo": "tipo",
        "bairro": "bairro",
        "logradouro": "logradouro",
        "complemento": "complemento",
        "condominio_nome": "condominio",
        "area_util": "area_util",
        "area_total": "area_total",
        "quartos": "quartos",
        "suites": "suites",
        "banheiros": "banheiros",
        "salas": "salas",
        "vagas": "vagas",
        "vagas_cobertas": "vagas_cobertas",
        "sol": "sol",
        "andar": "andar",
        "valor_venda": "valor_venda",
        "valor_aluguel": "valor_aluguel",
        "taxa_condominio": "taxa_condominio",
        "iptu": "iptu",
        "mobilia": "mobilia",
        "descricao": "descricao",
        "aceita_permuta": "aceita_permuta",
        "aceita_financiamento": "aceita_financiamento",
        # `caracteristicas` e coluna real de `imoveis` (conferido no banco) e o
        # tradutor da OLX preenche ela a partir de `re_features` -- entao sem
        # esta linha o campo ficava fora do mapa e a publicacao era barrada por
        # "o formulario nao tem onde por". O nome a direita e chute, como todos
        # os outros: quem confirma e o `confirmado_em`, na hora que a senha
        # chegar. Se o formulario de verdade nao tiver este campo, TIRAR daqui
        # -- o Rails descarta parametro fora do `permit` em silencio, e campo
        # que some sem aviso e pior que campo que falta com aviso.
        "caracteristicas": "caracteristicas",
        # Nosso, nao do site: a anotacao do Tel sobre a captacao nao vai para o
        # imobeasy.com. Fica de fora do mapa DE PROPOSITO.
    },
    campo_foto="imovel[fotos][]",
    fotos_no_mesmo_post=False,
    url_fotos=None,
    confirmado_em=None,
)

# Rótulo publicado -> nosso nome de campo. É o que `conferir` consegue ler
# HOJE, sem login. Vários rótulos caem no mesmo campo porque o site troca o
# nome conforme o tipo: apartamento tem "Área", casa separa "Tamanho do
# Terreno" de "Área Construída".
ROTULOS = {
    "bairro": "bairro",
    "condominio": "condominio_nome",
    "complemento": "complemento",
    "logradouro": "logradouro",
    "area": "area_util",
    "area construida": "area_util",
    "area total": "area_total",
    "tamanho do terreno": "area_total",
    "quartos": "quartos",
    "banheiros": "banheiros",
    "salas": "salas",
    "vagas": "vagas",
    "vagas cobertas": "vagas_cobertas",
    "sol": "sol",
    "andar": "andar",
    "andares": "andares",
    "taxa de condominio": "taxa_condominio",
    "iptu": "iptu",
    "aceita permuta?": "aceita_permuta",
    "aceita financiamento?": "aceita_financiamento",
    "frente": "frente",
    "fundo": "fundo",
    "pe direito": "pe_direito",
    "elevadores": "elevadores",
    "tipo de cobertura": "tipo_de_cobertura",
}

# O que a página pública deixa conferir. Campo enviado que não está aqui não é
# "conferido e certo": entra em `nao_conferidos` no relatório, e o relatório
# diz isso em voz alta.
CONFERIVEIS = set(ROTULOS.values()) | {"quartos", "suites", "valor_venda",
                                       "valor_aluguel", "tipo"}


def nova_sessao():
    s = requests.Session()
    s.headers.update({"User-Agent": USER_AGENT})
    return s


def _status(resposta):
    return getattr(resposta, "status_code", None)


def _texto(resposta):
    return getattr(resposta, "text", "") or ""


def _local(resposta):
    return (getattr(resposta, "headers", None) or {}).get("Location", "") or ""


def credenciais(email=None, senha=None):
    """Credencial NUNCA em código: só do ambiente, e a falta vira erro que diz
    o nome exato da variável -- ninguém adivinha `IMOBEASY_SENHA` às 22h."""
    email = email or os.environ.get("IMOBEASY_EMAIL")
    senha = senha or os.environ.get("IMOBEASY_SENHA")
    faltando = [n for n, v in (("IMOBEASY_EMAIL", email),
                               ("IMOBEASY_SENHA", senha)) if not v]
    if faltando:
        raise FalhaDeCredencial(
            f"falta {' e '.join(faltando)} no ambiente. Nenhuma credencial "
            "mora no código: exporte a variável (ou ponha no .env e carregue) "
            "antes de rodar.")
    return email, senha


def _token(texto_html, action="/entrar", passo=PASSO_LOGIN):
    """Tira o `authenticity_token` do formulário.

    Prefere o do FORMULÁRIO ao do <meta csrf-token>: medido em 02/09, os dois
    vêm com valores diferentes na mesma página, e é o do formulário que o
    Rails espera naquele POST.
    """
    sopa = BeautifulSoup(texto_html or "", "html.parser")
    for form in sopa.find_all("form"):
        if action and action not in (form.get("action") or ""):
            continue
        campo = form.find("input", attrs={"name": "authenticity_token"})
        if campo and campo.get("value"):
            return campo["value"]
    meta = sopa.find("meta", attrs={"name": "csrf-token"})
    if meta and meta.get("content"):
        return meta["content"]
    raise FalhaNaCaptacao(
        f"não achei o authenticity_token na página (form action={action!r}). "
        "Ou a página mudou, ou o que voltou não é a página que eu pedi.",
        passo=passo)


def _e_pagina_de_login(texto_html):
    """A tela de login chegando onde devia vir outra coisa é sessão caída, não
    'formato mudou'. Confundir os dois manda consertar a coisa errada."""
    texto_html = texto_html or ""
    return 'id="new_user"' in texto_html or 'name="user[password]"' in texto_html


def entrar(email=None, senha=None, sessao=None, url_entrar=URL_ENTRAR):
    """GET /entrar, pega o token, POST, devolve a sessão com o cookie.

    Só considera logado quando CONSEGUE PROVAR: o Devise, quando a senha está
    errada, responde 200 e redesenha o mesmo formulário -- se a gente tratasse
    200 como sucesso, seguiria cadastrando deslogado e cada POST seguinte
    voltaria a tela de login sem nada ser criado.
    """
    email, senha = credenciais(email, senha)
    sessao = sessao or nova_sessao()

    try:
        resposta = sessao.get(url_entrar, timeout=TIMEOUT)
    except Exception as erro:                                # pragma: no cover
        raise FalhaDeLogin(f"não consegui abrir {url_entrar}: {erro}") from erro
    if _status(resposta) != 200:
        raise FalhaDeLogin(
            f"{url_entrar} devolveu {_status(resposta)} em vez de 200; nem "
            "cheguei a mandar usuário e senha.")

    token = _token(_texto(resposta), "/entrar", passo=PASSO_LOGIN)
    dados = {
        "utf8": "✓",
        "authenticity_token": token,
        "user[email]": email,
        "user[password]": senha,
        "user[remember_me]": "0",
    }
    try:
        entrou = sessao.post(url_entrar, data=dados, allow_redirects=False,
                             timeout=TIMEOUT)
    except Exception as erro:                                # pragma: no cover
        raise FalhaDeLogin(f"o POST do login falhou: {erro}") from erro

    codigo = _status(entrou)
    if codigo in (301, 302, 303, 307, 308) and "/entrar" not in _local(entrou):
        return sessao
    # A senha NUNCA entra na mensagem de erro: este texto vai para log e pode
    # ir para o WhatsApp do Tel.
    raise FalhaDeLogin(
        f"o admin não me deixou entrar (status {codigo}, Location "
        f"{_local(entrou)!r}). Devise responde assim quando e-mail ou senha "
        f"estão errados. Confira IMOBEASY_EMAIL (usei {email!r}).")


def _arquivo(foto):
    """Aceita caminho, (nome, bytes) ou {'nome':..., 'conteudo':...}.

    Recusa arquivo vazio e arquivo que não começa com assinatura de imagem.
    Não é frescura: baixar foto da OLX devolve **404 com um JPEG de verdade
    dentro** (quadrado cinza de ~49 KB), e página de erro salva com nome .jpg
    é o mesmo acidente com outra roupa. A assinatura pega a segunda; a
    primeira só o status HTTP do download pega, no módulo que baixa.
    """
    if isinstance(foto, dict):
        nome, conteudo = foto.get("nome"), foto.get("conteudo")
    elif isinstance(foto, (tuple, list)) and len(foto) == 2:
        nome, conteudo = foto
    else:
        caminho = str(foto)
        nome = os.path.basename(caminho)
        try:
            with open(caminho, "rb") as arq:
                conteudo = arq.read()
        except OSError as erro:
            raise FalhaDeFoto(f"não consegui ler a foto {caminho!r}: {erro}") from erro

    if not nome:
        raise FalhaDeFoto("foto sem nome de arquivo.")
    if not conteudo:
        raise FalhaDeFoto(f"a foto {nome!r} veio VAZIA (0 byte). Não subo: "
                          "imóvel com foto em branco é pior que sem foto.")
    assinaturas = (b"\xff\xd8\xff", b"\x89PNG\r\n\x1a\n", b"RIFF", b"GIF8")
    if not conteudo.startswith(assinaturas):
        raise FalhaDeFoto(
            f"a foto {nome!r} não parece imagem (começa com "
            f"{conteudo[:8]!r}). Provavelmente é página de erro salva com "
            "nome de foto.")
    tipo = "image/png" if conteudo.startswith(b"\x89PNG") else "image/jpeg"
    return nome, conteudo, tipo


def _para_o_form(valor):
    """Booleano vira "1"/"0", nunca str(True)/str(False).

    Isto é armadilha de verdade, não capricho: o Rails trata como FALSO só
    `false, 0, "0", "f", "false", "off"` -- QUALQUER outra coisa é verdadeiro.
    Mandar o `str(False)` do Python, que é "False", grava **Sim** no site. Um
    imóvel que não aceita permuta passaria a aceitar, sem erro nenhum e sem
    ninguém perceber até alguém propor uma permuta.

    E `None` NÃO passa por aqui: `str(None)` é a palavra "None", que o Rails
    grava como texto -- e, pela mesma regra de cima, lê como VERDADEIRO num
    campo de sim/não. Quem chama é que decide não mandar o campo (`cadastrar`
    pula o None); se um None chegar até aqui é porque essa decisão se perdeu no
    caminho, e aí é melhor parar do que escrever "None" no site.
    """
    if valor is None:
        raise FalhaDeFormulario(
            "tentei mandar um campo com valor None para o formulário. None é "
            "'não sei', e 'não sei' não se escreve no site: o campo tem que "
            "ficar de fora do envio. Isso é erro de quem montou o cadastro.")
    if isinstance(valor, bool):
        return "1" if valor else "0"
    return valor if isinstance(valor, str) else str(valor)


def _codigo_da_resposta(resposta):
    """O código do imóvel recém-criado, do Location do redirect."""
    alvo = _local(resposta) or ""
    achado = re.search(r"/(?:imoveis|anuncios)/(\d+)", alvo)
    return achado.group(1) if achado else None


def cadastrar(sessao, campos, fotos=(), mapa=MAPA_PROVISORIO):
    """Monta e envia o formulário do admin. Devolve {'codigo', 'url', ...}.

    Três portões, todos fechando por padrão:
      1. mapa não confirmado -> não posta (ver o cabeçalho do arquivo);
      2. campo que não está no mapa -> não posta, porque o Rails DESCARTA EM
         SILÊNCIO o parâmetro que não conhece e o imóvel nasceria sem ele;
      3. só um redirect conta como sucesso -- o Rails redesenha o formulário
         com status 200 quando a validação reprova, e isso *parece* ter dado
         certo.
    """
    if not mapa.confirmado:
        raise FalhaDeFormulario(
            "o mapa do formulário nunca foi conferido contra o admin de "
            "verdade (confirmado_em=None), então eu não sei o nome real de "
            "nenhum campo. Postar assim grava o imóvel com os campos vazios e "
            "SEM ERRO NENHUM. Rode `captacao_site.py --plano` para ver o que "
            "fazer quando a senha chegar.")

    desconhecidos = sorted(c for c in campos if c not in mapa.campos)
    if desconhecidos:
        raise FalhaDeFormulario(
            f"não sei em que campo do formulário colocar: "
            f"{', '.join(desconhecidos)}. Ou acrescente ao mapa, ou tire do "
            "cadastro -- o Rails jogaria fora sem avisar.")

    try:
        pagina = sessao.get(mapa.url_form, timeout=TIMEOUT)
    except Exception as erro:                                # pragma: no cover
        raise FalhaDeFormulario(
            f"não consegui abrir {mapa.url_form}: {erro}") from erro
    if _e_pagina_de_login(_texto(pagina)):
        raise FalhaDeSessao(
            f"{mapa.url_form} devolveu a tela de login: a sessão caiu (ou o "
            "`entrar` nunca deu certo). Nada foi cadastrado.")
    if _status(pagina) != 200:
        raise FalhaDeFormulario(
            f"{mapa.url_form} devolveu {_status(pagina)}. Nada foi cadastrado.")

    # `action=None`: o authenticity_token do Rails é por SESSÃO, não por
    # formulário -- qualquer form da página serve, e fixar a action daria
    # precisão de mentira sobre uma página que ninguém leu ainda.
    dados = {"utf8": "✓",
             "authenticity_token": _token(_texto(pagina), None,
                                          passo=PASSO_FORMULARIO)}
    for campo, valor in campos.items():
        # None é "não sei", e não sei NÃO É ZERO nem string vazia. Mandar
        # vazio apagaria no site um dado que talvez já estivesse lá.
        if valor is None:
            continue
        dados[mapa.nome_no_form(campo)] = _para_o_form(valor)

    arquivos = [_arquivo(f) for f in fotos]
    # O portão confere a rota QUE VAI SER USADA, não "uma das duas está
    # preenchida". Com o `or` de antes, mapa meio preenchido -- `campo_foto`
    # sim, `url_fotos` não, que é EXATAMENTE a forma do MAPA_PROVISORIO hoje --
    # passava daqui, CRIAVA o imóvel e só então estourava no envio da foto.
    # Sobrava um imóvel no ar sem foto nenhuma, e o operador que repetisse o
    # comando criava um segundo. Portão que fecha depois do POST não é portão.
    if arquivos:
        if mapa.fotos_no_mesmo_post and not mapa.campo_foto:
            raise FalhaDeFoto(
                f"recebi {len(arquivos)} foto(s) para mandar no mesmo POST do "
                "cadastro, mas o mapa não diz o NOME do campo de arquivo "
                "(`campo_foto`), então não sei por onde subir. Prefiro não "
                "cadastrar a cadastrar sem foto e deixar você achando que subiu.")
        if not mapa.fotos_no_mesmo_post and not mapa.url_fotos:
            raise FalhaDeFoto(
                f"recebi {len(arquivos)} foto(s) para mandar depois do "
                "cadastro, mas o mapa não tem `url_fotos`: não sei por onde "
                "subir foto neste admin. Prefiro não cadastrar a cadastrar sem "
                "foto e deixar você achando que subiu.")

    envio = None
    if arquivos and mapa.fotos_no_mesmo_post:
        envio = {mapa.campo_foto: [(n, c, t) for n, c, t in arquivos]}

    try:
        resposta = sessao.post(mapa.url_criar, data=dados, files=envio,
                               allow_redirects=False, timeout=TIMEOUT)
    except Exception as erro:                                # pragma: no cover
        raise FalhaDeFormulario(
            f"o POST para {mapa.url_criar} falhou: {erro}. O imóvel PODE ter "
            "sido criado -- confira no admin antes de tentar de novo.") from erro

    codigo_http = _status(resposta)
    if _e_pagina_de_login(_texto(resposta)):
        raise FalhaDeSessao("o POST voltou na tela de login. Nada foi criado.")
    if codigo_http not in (301, 302, 303, 307, 308):
        raise FalhaDeFormulario(
            f"o admin respondeu {codigo_http} em vez de redirecionar. É assim "
            "que o Rails devolve formulário reprovado na validação: o imóvel "
            "NÃO foi criado. Provável campo obrigatório faltando.")

    codigo = _codigo_da_resposta(resposta)
    if not codigo:
        raise FalhaDeFormulario(
            f"o cadastro foi aceito (redirect para {_local(resposta)!r}) mas "
            "não achei o código do imóvel na resposta. O IMÓVEL PROVAVELMENTE "
            "FOI CRIADO -- procure no admin antes de repetir, senão vira "
            "cadastro duplicado.")

    resultado = {"codigo": codigo, "url": URL_PUBLICA.format(codigo=codigo),
                 "fotos_enviadas": len(arquivos) if mapa.fotos_no_mesmo_post else 0}
    if arquivos and not mapa.fotos_no_mesmo_post:
        resultado["fotos_enviadas"] = enviar_fotos(sessao, codigo, arquivos, mapa)
    return resultado


def enviar_fotos(sessao, codigo, fotos, mapa=MAPA_PROVISORIO):
    """Sobe as fotos uma a uma. Devolve quantas subiram.

    Uma a uma, e não em lote, por causa de uma coisa medida no publicador: com
    lote, falhar a sétima não diz quais seis entraram, e reenviar o lote
    inteiro duplica as seis.
    """
    if not mapa.url_fotos:
        raise FalhaDeFoto(
            "o mapa não tem `url_fotos`: não sei por onde subir foto neste "
            "admin. Isso se descobre abrindo o formulário logado.")
    enviadas = 0
    for foto in fotos:
        nome, conteudo, tipo = foto if isinstance(foto, tuple) and len(foto) == 3 \
            else _arquivo(foto)
        alvo = mapa.url_fotos.format(codigo=codigo)
        try:
            resposta = sessao.post(
                alvo, files={mapa.campo_foto or "foto": (nome, conteudo, tipo)},
                allow_redirects=False, timeout=TIMEOUT)
        except Exception as erro:                            # pragma: no cover
            raise FalhaDeFoto(
                f"a foto {nome!r} (a {enviadas + 1}ª) falhou no envio: {erro}. "
                f"As {enviadas} anteriores JÁ SUBIRAM -- não reenvie tudo.") from erro
        # A sessão pode cair NO MEIO das fotos, e aí o admin devolve a tela de
        # login com status 200 -- que está na lista de "deu certo" logo abaixo.
        # Sem esta checagem, um imóvel que subiu 1 de 12 fotos era relatado
        # como 12 de 12: o operador só descobriria abrindo o anúncio.
        if _e_pagina_de_login(_texto(resposta)):
            raise FalhaDeSessao(
                f"a sessão caiu na foto {nome!r} (a {enviadas + 1}ª): o admin "
                f"devolveu a tela de login. As {enviadas} anteriores JÁ "
                "SUBIRAM -- entre de novo e mande só as que faltam, senão as "
                "primeiras ficam duplicadas.")
        if _status(resposta) not in (200, 201, 204, 301, 302, 303):
            raise FalhaDeFoto(
                f"a foto {nome!r} (a {enviadas + 1}ª) foi recusada com status "
                f"{_status(resposta)}. As {enviadas} anteriores já subiram.")
        enviadas += 1
    return enviadas


def _sem_acento(texto):
    sem = unicodedata.normalize("NFKD", str(texto))
    return "".join(c for c in sem if not unicodedata.combining(c))


def _chave(texto):
    """Rótulo/valor comparável: sem acento, sem caixa, sem espaço sobrando.
    Existe porque o próprio site escreve "Área total" e "Área Total"."""
    return re.sub(r"\s+", " ", _sem_acento(texto).strip().lower())


def _vazio(valor):
    return valor is None or (isinstance(valor, str) and not valor.strip())


def _booleano(valor):
    """Só palavra de sim/não vira booleano. Número NÃO vira: se 1 virasse
    True, `quartos=1` casaria com um "Sim" gravado em outro campo."""
    if isinstance(valor, bool):
        return valor
    if not isinstance(valor, str):
        return None
    return {"sim": True, "s": True, "nao": False, "n": False}.get(_chave(valor))


_SO_NUMERO = re.compile(r"^\s*(?:r\$)?\s*(-?[\d.,]+)\s*(?:m2|m²|m|reais)?\s*$", re.I)


def _numero(valor):
    """Número, ou None quando não dá para PROVAR que é número.

    "Rua 3 de Maio" não vira 3 -- por isso o casamento é da string inteira, não
    de um pedaço dela.

    A página mistura dois formatos, medido no mesmo dia: área vem "150.0 m2"
    (ponto decimal) e dinheiro vem "R$  1.700,00" (ponto de milhar). Regra: com
    vírgula, o ponto é milhar; sem vírgula, ponto seguido de exatamente três
    dígitos é milhar ("1.700" = 1700) e o resto é decimal ("150.0" = 150.0).
    """
    if isinstance(valor, bool):
        return None
    if isinstance(valor, (int, float)):
        return float(valor)
    if not isinstance(valor, str):
        return None
    achado = _SO_NUMERO.match(valor)
    if not achado:
        return None
    bruto = achado.group(1)
    if "," in bruto:
        bruto = bruto.replace(".", "").replace(",", ".")
    elif re.fullmatch(r"-?\d{1,3}(?:\.\d{3})+", bruto):
        bruto = bruto.replace(".", "")
    try:
        return float(bruto)
    except ValueError:
        return None


def _mesmo_valor(enviado, gravado):
    """True só quando dá para PROVAR que são o mesmo valor.

    Sem prova, devolve False e o campo aparece como divergência: um alarme à
    toa custa um olhar; um "conferido" errado custa o imóvel anunciado com o
    dado do vizinho.
    """
    if _vazio(enviado) and _vazio(gravado):
        return True
    if _vazio(enviado) or _vazio(gravado):
        return False
    be, bg = _booleano(enviado), _booleano(gravado)
    if be is not None and bg is not None:
        return be == bg
    ne, ng = _numero(enviado), _numero(gravado)
    if ne is not None and ng is not None:
        return abs(ne - ng) < 0.01
    if ne is None and ng is None:
        return _chave(enviado) == _chave(gravado)
    return False


def _valores_publicados(texto_html):
    """Lê a página pública e devolve {nosso_campo: texto cru}.

    Cru de propósito: quem converte é `_mesmo_valor`, e só para comparar. É a
    mesma disciplina de `extrair_olx.py`.
    """
    sopa = BeautifulSoup(texto_html or "", "html.parser")
    valores = {}
    for rotulo in sopa.find_all("label", class_="form-control-label"):
        nome = ROTULOS.get(_chave(rotulo.get_text(" ", strip=True)))
        if not nome:
            continue
        span = rotulo.find_next_sibling("span", class_="form-control")
        if not span:
            continue
        texto = span.get_text(" ", strip=True)
        if nome == "quartos":
            # "3 (sendo 3 suítes)" -- e quando a página NÃO diz suíte, suítes
            # fica AUSENTE, nunca 0. Inventar suites=0 é bug conhecido do
            # extrator do catálogo; não repetir aqui.
            numero = re.search(r"(\d+)", texto)
            valores["quartos"] = numero.group(1) if numero else texto
            suites = re.search(r"(\d+)\s*su[ií]te", texto)
            if suites:
                valores["suites"] = suites.group(1)
            continue
        valores[nome] = texto

    cabecalho = sopa.find("h5", class_="mg-b-0 tx-black")
    if cabecalho:
        valores["tipo"] = cabecalho.get_text(strip=True).split("/")[0].strip()

    # Os valores só existem no <meta name="description">: a seção de valores
    # vem comentada no HTML visível (mesma descoberta de buscar_imovel.py).
    meta = sopa.find("meta", attrs={"name": "description"})
    if meta and meta.get("content"):
        for quantia, rotulo in re.findall(
                r"R\$\s*([\d.,]+)\s*\((venda|aluguel)\)", meta["content"]):
            valores["valor_venda" if rotulo == "venda" else "valor_aluguel"] = quantia
    return valores


def conferir(sessao, codigo, enviado=None, mapa=MAPA_PROVISORIO, estourar=True):
    """Lê o imóvel DE VOLTA e compara com o que foi enviado.

    Não é enfeite: formulário de terceiro muda sem aviso, e o Rails descarta
    parâmetro que não conhece sem dar erro -- sem esta leitura, o sintoma
    aparece semanas depois, num corretor perguntando a metragem.

    Por padrão lê a página PÚBLICA (`/anuncios/<codigo>`), que funciona sem
    login e é justamente a que a varredura horária vai ler. Se o imóvel não
    estiver lá, a Nay também não vai conhecê-lo -- então "não achei" aqui é
    resposta útil, não falha da conferência.

    `enviado=None` só prova que o imóvel existe e é legível. Com `enviado`,
    compara campo a campo. Campo que a página pública não mostra entra em
    `nao_conferidos`: nunca contado como conferido.
    """
    sessao = sessao or nova_sessao()
    url = (mapa.url_ler or URL_PUBLICA).format(codigo=codigo)
    try:
        resposta = sessao.get(url, timeout=TIMEOUT, allow_redirects=False)
    except Exception as erro:                                # pragma: no cover
        raise FalhaDeConferencia(f"não consegui abrir {url}: {erro}") from erro

    status = _status(resposta)
    if status in (301, 302, 303, 307, 308) or status == 404:
        destino = _local(resposta)
        if "/entrar" in destino:
            raise FalhaDeSessao(f"{url} mandou para o login: a sessão caiu.")
        raise FalhaDeConferencia(
            f"o imóvel {codigo} não está publicado em {url} (status {status}"
            + (f", foi para {destino!r}" if destino else "") + "). Se você "
            "acabou de cadastrar, o cadastro pode ter dado certo e o ANÚNCIO "
            "não ter sido criado -- são coisas separadas no admin.")
    if status != 200:
        raise FalhaDeConferencia(f"{url} devolveu {status}.")
    if _e_pagina_de_login(_texto(resposta)):
        raise FalhaDeSessao(f"{url} devolveu a tela de login: a sessão caiu.")

    gravados = _valores_publicados(_texto(resposta))
    if not gravados:
        raise FalhaDeConferencia(
            f"abri {url} com status 200 e não achei campo NENHUM dentro. Ou o "
            "site mudou o formato da página, ou não é a página do imóvel. Não "
            "vou chamar isso de conferido.")

    relatorio = {"codigo": str(codigo), "url": url, "ok": True,
                 "conferidos": [], "divergencias": [], "nao_conferidos": [],
                 "gravados": gravados}
    for campo, valor in (enviado or {}).items():
        if campo not in CONFERIVEIS:
            relatorio["nao_conferidos"].append(campo)
            continue
        if campo not in gravados:
            if _vazio(valor):
                continue
            relatorio["divergencias"].append(
                {"campo": campo, "enviado": valor, "gravado": None,
                 "motivo": "não apareceu na página"})
            continue
        if _mesmo_valor(valor, gravados[campo]):
            relatorio["conferidos"].append(campo)
        else:
            relatorio["divergencias"].append(
                {"campo": campo, "enviado": valor, "gravado": gravados[campo],
                 "motivo": "diferente do que foi enviado"})

    relatorio["ok"] = not relatorio["divergencias"]
    if relatorio["divergencias"] and estourar:
        detalhe = "; ".join(
            f"{d['campo']}: enviei {d['enviado']!r}, o site tem "
            f"{d['gravado']!r} ({d['motivo']})" for d in relatorio["divergencias"])
        raise FalhaDeConferencia(
            f"o imóvel {codigo} ficou diferente do que eu mandei -> {detalhe}",
            detalhe=relatorio)
    return relatorio


PLANO = """
O QUE FAZER NO MINUTO EM QUE A SENHA DO ADMIN CHEGAR
(nada abaixo foi executado -- não temos credencial)

  export IMOBEASY_EMAIL='...'   # nunca em arquivo do repositório
  export IMOBEASY_SENHA='...'

1. Provar o login (2 min)
   .venv/bin/python -c "import captacao_site as c; c.entrar(); print('entrei')"
   Se falhar, a mensagem já diz que é o passo [login].

2. Ler o formulário de cadastro (15 min) -- é o passo que destrava tudo
   GET https://imobeasy.com/admin/imoveis/new   (rota existe: medido, 302)
   Salve o HTML e liste os campos:
     grep -o 'name="[^"]*"' novo.html | sort -u
   Anote o prefixo real (`imovel[...]`? `anuncio[...]`?), o nome de cada
   campo, os <select> e seus <option value> (tipo, sol, bairro costumam ser
   select: mandar texto onde o Rails espera id grava vazio), e o campo de
   foto (múltiplo? `[]` no fim?).

3. Responder a pergunta que decide a arquitetura (10 min)
   /admin/imoveis/new e /admin/anuncios/new são rotas DIFERENTES (medido).
   Cadastre UM imóvel pela interface, na mão, e veja se ele aparece sozinho em
   https://imobeasy.com/anuncios/<codigo>. Se NÃO aparecer, publicar é um
   segundo cadastro, e sem ele a varredura horária nunca vê o imóvel -- a
   plataforma diria "cadastrado" e a Nay continuaria dizendo "não encontrei".

4. Descobrir para onde vai o POST e como sobe foto (10 min)
   O <form action=...> do passo 2 responde a primeira. Para a foto, olhe se o
   input de arquivo está no mesmo form (então fotos_no_mesmo_post=True) ou se
   existe uma tela separada de fotos (então url_fotos).

5. Preencher MAPA_PROVISORIO com os nomes REAIS e só então pôr a data em
   `confirmado_em`. Enquanto estiver None, `cadastrar` se recusa a postar --
   é o portão que impede o cadastro mudo com todos os campos vazios.

6. Primeiro cadastro de verdade: UM imóvel, com foto, e rodar `conferir` logo
   depois. Só depois disso ligar a plataforma na captação.

Tempo total com a senha na mão: cerca de 45 minutos, sendo que o passo 3 é o
único que pode mudar o desenho do resto.
"""


def _medir():
    """Refaz, ao vivo, as medições do cabeçalho. Só GET, só leitura, sem
    login: no Rails, 302 para /entrar prova que a rota existe e 404 prova que
    não. Serve para saber se o site mudou desde 02/09/2026."""
    import time
    sessao = nova_sessao()
    print("--- o formulário de /entrar ---")
    pagina = sessao.get(URL_ENTRAR, timeout=TIMEOUT)
    print(f"  GET /entrar -> {pagina.status_code}")
    sopa = BeautifulSoup(pagina.text, "html.parser")
    for form in sopa.find_all("form"):
        print(f"  form action={form.get('action')!r} method={form.get('method')!r}")
        for campo in form.find_all("input"):
            print(f"    {campo.get('name')!r} tipo={campo.get('type')!r}")
    print("\n--- rotas do admin (302=existe, 404=não existe) ---")
    for rota in ("/admin", "/admin/imoveis", "/admin/imoveis/new",
                 "/admin/anuncios/new", "/admin/imoveis/1",
                 "/admin/imoveis/1/edit"):
        resposta = sessao.get(BASE + rota, timeout=TIMEOUT, allow_redirects=False)
        print(f"  {rota:26} {resposta.status_code} {resposta.headers.get('Location','')}")
        time.sleep(1.5)   # regra do projeto: não martelar o site
    return 0


def main():
    argumentos = sys.argv[1:]
    if not argumentos or argumentos[0] == "--plano":
        print(PLANO.strip())
        return 0
    if argumentos[0] == "--medir":
        return _medir()
    if argumentos[0] == "--conferir" and len(argumentos) > 1:
        try:
            relatorio = conferir(None, argumentos[1], estourar=False)
        except FalhaNaCaptacao as erro:
            print(erro)
            return 1
        print(f"{relatorio['url']}")
        for campo, valor in sorted(relatorio["gravados"].items()):
            print(f"  {campo:18} = {valor!r}")
        return 0
    print("Uso: captacao_site.py [--plano | --medir | --conferir <codigo>]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
