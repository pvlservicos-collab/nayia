"""
Doc 28, passo 3: busca um imóvel direto na página do anúncio individual
(imobeasy.com/anuncios/<codigo>), não na listagem.

Usado pelo publicador de grupos porque um imóvel captado hoje ainda não
está na cópia sincronizada do banco (naydb) -- só no site tem a versão
atual. Reaproveita USER_AGENT e _parse_valor de extrair_pagina.py.

Uso:
    .venv/bin/python buscar_imovel.py 5643
"""
import re
import sys

import requests
from bs4 import Comment, BeautifulSoup

from extrair_pagina import USER_AGENT, _parse_valor

BASE_URL = "https://imobeasy.com/anuncios"


def baixar_anuncio(codigo, timeout=15):
    resp = requests.get(
        f"{BASE_URL}/{codigo}",
        headers={"User-Agent": USER_AGENT},
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.text


def _campo(soup, rotulo, dentro_de_comentario=True):
    """O valor ao lado do rótulo, OLHANDO TAMBÉM DENTRO DOS COMENTÁRIOS HTML.

    POR QUE O COMENTÁRIO (14/09): o Tel reclamou que o card do 5718 saía sem
    "(incluso a tx)", e eu respondi que o dado não existia -- baseado na tabela.
    Estava errado. O anúncio TRAZ o campo:

        <label class="form-control-label">Incluso no Aluguel</label>
        <span class="form-control">Água, Taxa de Gás, Taxa de Condomínio, IPTU</span>

    só que o site envolve esse bloco inteiro em `<!-- ... -->`, e o
    BeautifulSoup trata comentário como texto opaco: `soup.find("label", ...)`
    não entra ali. Por isso o extrator via a página e não via o campo.

    Medido em 14/09: no 5718 ficam DENTRO do comentário os rótulos "Valor de
    Aluguel", "Aceita Financiamento?" e "Incluso no Aluguel" -- três campos que
    nunca chegaram ao card por este motivo, e um deles é o valor do aluguel.

    O CLAUDE.md dizia "o site NÃO publica esse dado -- conferido no HTML
    inteiro do 5729". A conferência de então olhou o texto renderizado, não o
    HTML; a frase ficou errada por um ano de decisões.
    """
    def procurar(raiz):
        label = raiz.find(
            "label", class_="form-control-label",
            string=lambda s: s and s.strip() == rotulo,
        )
        if not label:
            return None
        span = label.find_next_sibling("span", class_="form-control")
        return span.get_text(" ", strip=True) if span else None

    achado = procurar(soup)
    if achado or not dentro_de_comentario:
        return achado
    for comentario in soup.find_all(string=lambda t: isinstance(t, Comment)):
        achado = procurar(BeautifulSoup(str(comentario), "html.parser"))
        if achado:
            return achado
    return None


def _campo_int(soup, rotulo):
    texto = _campo(soup, rotulo)
    if not texto:
        return None
    m = re.search(r"(\d+)", texto)
    return int(m.group(1)) if m else None


def _tipo(soup):
    # O h5 do topo traz "{tipo} / {tipo} - {condominio ou bairro}" -- só
    # o tipo interessa aqui, o resto já vem de outros campos.
    h5 = soup.find("h5", class_="mg-b-0 tx-black")
    if not h5:
        return None
    texto = h5.get_text(strip=True)
    return texto.split("/")[0].strip() or None


def _id_da_imagem(url):
    """O trecho estavel da URL: '000/118/179'. A galeria serve 'huge' e o
    og:image serve 'medium', entao comparar a URL inteira nunca casa."""
    m = re.search(r"/images/(\d+/\d+/\d+)/", url or "")
    return m.group(1) if m else None


def _capa_primeiro(soup, fotos):
    """Poe a foto de CAPA na frente, sem perder nem duplicar nenhuma.

    A capa e a que o site usa em `og:image` -- a mesma que o Tel escolhe no
    admin. Ate 31/08 mandavamos a primeira da galeria, e ele viu um imovel
    sair no grupo com a foto errada. Medido: em 4 de 5 imoveis a capa NAO
    era a primeira.

    Se o og:image nao existir ou nao casar com nenhuma foto, devolve a
    lista como veio -- nunca deixa o imovel sem foto por causa disto.
    """
    if not fotos:
        return fotos
    og = soup.find("meta", property="og:image")
    alvo = _id_da_imagem(og.get("content") if og else None)
    if not alvo:
        return fotos
    for i, url in enumerate(fotos):
        if _id_da_imagem(url) == alvo:
            if i == 0:
                return fotos
            return [fotos[i]] + fotos[:i] + fotos[i + 1:]
    return fotos


# AS CARACTERÍSTICAS DO IMÓVEL que o Tel marca no admin (pedido de 14/09). A
# página só mostra as MARCADAS (conferido no 1885: "Edícula", "Escritório",
# "Semi-Mobiliado"), e TODAS as da seção entram no card -- decisão dele, depois
# de ver que apartamento tem itens que a lista de casa não tem ("Varanda
# Gourmet", "Varanda com cortina de vidro").
#
# A PAREDE É A SEÇÃO, não uma lista. Logo abaixo, com a MESMA marcação HTML,
# vem "Características do Condomínio" -- e ali, no 2665, estão "Piscina",
# "Hidromassagem" e "Gerador de Energia". Sem cortar no título seguinte, o card
# diria ao corretor que o APARTAMENTO tem piscina e hidromassagem.
#
# Esta lista é a que o Tel copiou da tela do admin de casa. Ela serve para
# padronizar a grafia do que aparece nela (o "Caixa d’água" com apóstrofo
# curvo); item que não está aqui entra com o texto da página.
CARACTERISTICAS_DO_IMOVEL = (
    "Gerador", "Geminada", "Closet", "Conceito aberto", "Piscina", "Edícula",
    "Área para construir piscina", "Caixa d’água", "Poço", "Banheira",
    "Hidromassagem", "Fechadura eletrônica", "Escritório", "Cerca elétrica",
    "Câmera de segurança", "Alarme", "Cofre", "Semi-Mobiliado", "Mobiliado",
    "Climatizado", "Decorado",
)


def _chave_da_caracteristica(texto):
    import unicodedata
    t = unicodedata.normalize("NFD", str(texto or "")).lower()
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    # o admin escreve "Caixa d’água" com apóstrofo curvo; página e lista têm
    # que casar com qualquer um dos dois
    t = t.replace("’", "'").replace("`", "'")
    return re.sub(r"\s+", " ", t).strip()


_NOME_POR_CHAVE = {_chave_da_caracteristica(n): n for n in CARACTERISTICAS_DO_IMOVEL}


def _caracteristicas_do_imovel(soup):
    """As características MARCADAS, na ordem da página, só da seção do imóvel.

    A seção é o `div.row` que vem depois do título "Características do Imóvel"
    e termina no título seguinte -- que é o "Características do Condomínio".
    """
    titulo = soup.find(
        "div", class_="slim-card-title",
        string=lambda s: s and _chave_da_caracteristica(s) == "caracteristicas do imovel")
    if not titulo:
        return []
    achadas = []
    for irmao in titulo.find_next_siblings():
        if "slim-card-title" in (irmao.get("class") or []):
            break                      # começou a seção do condomínio
        for item in irmao.find_all("div", class_="col-md-4"):
            texto = item.get_text(" ", strip=True)
            if not texto:
                continue
            nome = _NOME_POR_CHAVE.get(_chave_da_caracteristica(texto)) or texto
            if nome not in achadas:
                achadas.append(nome)
    return achadas


def _observacao(soup):
    """A OBS que o Tel escreve no admin, para sair no card (pedido de 14/09).

    ONDE ELA MORA, conferido no 5738: numa seção própria, "Observações", logo
    depois da descrição, com o texto num `<p>`:

        OBS: Apartamento nunca habitado vendido porteira fechada.

    Ele falou em "descrição do imóvel", então linha começando com "OBS:" DENTRO
    da descrição também vale.

    O QUE NÃO PODE ENTRAR: o rodapé da mesma página diz "Tem uma observação
    sobre esse anúncio? Você é o proprietário? ... Clique Aqui!". Procurar a
    palavra no HTML inteiro traria isso para o card de 14 grupos -- por isso a
    leitura é por SEÇÃO, e na descrição só a linha que COMEÇA com "OBS".

    Devolve o texto sem o rótulo ("OBS:" é do card), ou None.
    """
    partes = []

    def secao(nome):
        titulo = soup.find(
            "div", class_="slim-card-title",
            string=lambda s: s and _chave_da_caracteristica(s) == nome)
        if not titulo:
            return []
        textos = []
        for irmao in titulo.find_next_siblings():
            if "slim-card-title" in (irmao.get("class") or []):
                break
            for span in irmao.find_all("span", class_="form-control"):
                textos.append(span.get_text("\n", strip=True))
        return textos

    # SÓ O QUE COMEÇA COM "OBS:". Medido no 1885: a seção "Observações" dele
    # guarda a descrição ANTIGA inteira (mais de mil caracteres, "Uma das
    # melhores quadras do condomínio..."), sem rótulo nenhum. Pegar a seção
    # toda publicaria isso em 14 grupos. A marca "OBS:" é o que o Tel disse
    # que usa -- "todos que estiver OBS:".
    #
    # E "OBS" EM MAIÚSCULO, de propósito. O mesmo 1885 tem, no meio daquele
    # texto antigo colado de outro lugar, "Obs :1 Sala Íntima podendo servir de
    # brinquedoteca;" e "Obs: todas as suites com banheiro no blindex..." --
    # anotações de uma listagem antiga, não a observação para publicar. O Tel
    # escreve "OBS:" em maiúsculo nas duas mensagens em que pediu isto, e o
    # catálogo confirma: das 5 descrições no ar com "obs:" no começo da linha,
    # as 2 em maiúsculo são notas de publicar ("OBS: Aceita financiamento e Fgts
    # como entrada") e as 3 em "Obs" são sobra de texto colado.
    rotulo = re.compile(r"^\s*OBS\s*[:\-–]\s*")
    for bloco in secao("observacoes") + secao("descricao do anuncio"):
        for linha in bloco.split("\n"):
            if rotulo.match(linha):
                linha = rotulo.sub("", linha).strip()
                if linha:
                    partes.append(linha)

    vistas = []
    for p in partes:
        if p not in vistas:
            vistas.append(p)
    return " ".join(vistas) or None


def extrair_imovel(html, codigo):
    soup = BeautifulSoup(html, "html.parser")

    tipo = _tipo(soup)
    condominio = _campo(soup, "Condomínio")
    bairro = _campo(soup, "Bairro")

    # Apartamentos têm um único rótulo "Área"; casas separam "Tamanho do
    # Terreno" (lote) de "Área Construída" -- a segunda é a equivalente a
    # area_util e é a que interessa aqui.
    # QUAL rótulo trouxe a área importa para o card: o Tel pediu "265m2 de área
    # construída" quando o site diz "Área Construída" (casa) e só "49m2" quando
    # diz "Área" (apartamento). Sem guardar de onde veio, o card teria que
    # adivinhar pelo tipo -- e tipo novo no cadastro quebraria a adivinhação.
    area_construida_txt = _campo(soup, "Área Construída")
    area_txt = area_construida_txt or _campo(soup, "Área")
    area_e_construida = area_construida_txt is not None
    area = None
    if area_txt:
        m = re.search(r"([\d.]+)", area_txt)
        area = int(float(m.group(1))) if m else None

    quartos_txt = _campo(soup, "Quartos")
    quartos = suites = None
    if quartos_txt:
        m = re.search(r"(\d+)", quartos_txt)
        quartos = int(m.group(1)) if m else None
        m_suites = re.search(r"(\d+)\s*su[ií]te", quartos_txt)
        suites = int(m_suites.group(1)) if m_suites else 0

    banheiros = _campo_int(soup, "Banheiros")
    vagas_cobertas = _campo_int(soup, "Vagas Cobertas")
    # Quando os dois rótulos aparecem juntos, "Vagas" é só a parcela
    # descoberta, não o total -- confirmado contra o texto livre de
    # observações do código 5615 ("4 vagas amplas sendo 2 cobertas" com
    # Vagas=2 e Vagas Cobertas=2 na página). O total é a soma dos dois;
    # quando só um dos rótulos existe, o outro entra como 0 e a soma dá
    # o valor certo de qualquer jeito.
    vagas_descobertas = _campo_int(soup, "Vagas")
    vagas = None
    if vagas_descobertas is not None or vagas_cobertas is not None:
        vagas = (vagas_descobertas or 0) + (vagas_cobertas or 0)

    # A seção "Informações de Valores" fica comentada no HTML visível da
    # página; os valores só aparecem em <meta name="description">, no
    # formato "R$ X (aluguel) / R$ Y (venda)" quando o imóvel tem os dois.
    valor_venda = valor_aluguel = None
    meta = soup.find("meta", attrs={"name": "description"})
    if meta and meta.get("content"):
        for valor_txt, rotulo_valor in re.findall(
            r"R\$\s*([\d.,]+)\s*\((venda|aluguel)\)", meta["content"]
        ):
            valor = _parse_valor("R$ " + valor_txt)
            if rotulo_valor == "venda":
                valor_venda = valor
            else:
                valor_aluguel = valor

    fotos = [
        (a["href"] if a["href"].startswith("http") else "https://imobeasy.com" + a["href"])
        for a in soup.select("ul#imagens a.gallery-item[href]")
    ]
    fotos = _capa_primeiro(soup, fotos)

    # ACEITA FINANCIAMENTO. O Tel pediu isto no card do disparo (02/09) para o
    # imóvel em VIA PÚBLICA à venda: casa de rua muitas vezes não pode ser
    # financiada -- documentação, contrato de gaveta -- e o corretor descobre
    # isso depois de já ter levado o cliente.
    #
    # O site responde "Sim"/"Não" e às vezes não traz o campo (o 2943 é um
    # desses). Ausente fica None e a linha simplesmente não sai: dizer "não
    # financia" de um imóvel que financia é pior que não dizer nada.
    aceita_financiamento = _campo(soup, "Aceita Financiamento?")
    # OS DOIS QUE O TEL PEDIU EM 14/09, e os dois vêm da PÁGINA -- não do
    # banco. "Lances de Escada" é rótulo visível; "Incluso no Aluguel" mora
    # dentro do comentário, e é por isso que ninguém o via.
    lances_de_escada = _campo(soup, "Lances de Escada")
    incluso_no_aluguel = _campo(soup, "Incluso no Aluguel")

    # Face solar. O Tel pediu no card do disparo (02/09): nascente e poente
    # mudam o preço e a conversa, e o corretor pergunta sempre.
    sol = _campo(soup, "Sol")

    caracteristicas = _caracteristicas_do_imovel(soup)
    # A MOBÍLIA DA PÁGINA MANDA MAIS QUE A DO BANCO. O card sempre leu mobília
    # da tabela (veio da importação de agosto); a página tem o dado vivo, que é
    # o que o Tel acabou de marcar no admin.
    mobilia = ("semi-mobiliado" if "Semi-Mobiliado" in caracteristicas else
               "mobiliado" if "Mobiliado" in caracteristicas else None)

    return dict(
        codigo=str(codigo),
        tipo=tipo,
        aceita_financiamento=aceita_financiamento,
        lances_de_escada=lances_de_escada,
        incluso_no_aluguel=incluso_no_aluguel,
        sol=sol,
        caracteristicas=caracteristicas,
        mobilia=mobilia,
        observacao=_observacao(soup),
        area_e_construida=area_e_construida,
        condominio=condominio,
        bairro=bairro,
        area=area,
        quartos=quartos,
        suites=suites,
        banheiros=banheiros,
        vagas=vagas,
        vagas_cobertas=vagas_cobertas,
        valor_venda=valor_venda,
        valor_aluguel=valor_aluguel,
        fotos=fotos,
    )


def _complementar_do_banco(imovel):
    """Preenche o que o SITE NÃO PUBLICA, lendo a nossa tabela.

    Medido em 02/09: `mobilia` (414 imóveis) e "incluso no aluguel" (95) não
    aparecem em nenhum rótulo da página do anúncio -- vieram da importação de
    agosto e só existem no nosso banco. O Tel pediu os dois no card. Em 14/09
    entrou "lances de escada" pelo mesmo motivo e pelo mesmo caminho.

    POR QUE ISTO NÃO QUEBRA A REGRA de "o publicador lê ao vivo": o site
    continua sendo a fonte de tudo que ele publica. O banco entra só como
    COMPLEMENTO, e falha em silêncio -- imóvel cadastrado agora, que ainda não
    está na tabela, sai sem essas duas linhas em vez de não sair. A propriedade
    que importa (cadastrou agora, posta agora) fica de pé.
    """
    try:
        import db
        conexao = db.conectar()
    except Exception:
        return imovel
    try:
        with conexao.cursor() as cur:
            cur.execute(
                "SELECT mobilia, sol, taxa_condominio, "
                "       nay_linha_da_taxa(taxa_condominio, "
                "                         taxa_condominio_em) AS linha_da_taxa, "
                "       extras->>'incluso no aluguel' AS incluso, "
                "       extras->>'lances de escada'   AS lances "
                "  FROM imoveis WHERE codigo = %s", (int(imovel["codigo"]),))
            linha = cur.fetchone()
        if linha:
            # o banco só entra quando a página não marcou mobília
            if not imovel.get("mobilia"):
                imovel["mobilia"] = linha["mobilia"] or None
            # A PÁGINA MANDA MAIS QUE O BANCO nestes dois, e a ordem importa.
            # O site é o cadastro vivo: o 5718 traz "Taxa de Condomínio" no
            # incluso e "3" nos lances, e a tabela está vazia nos dois --
            # porque a varredura lê a LISTAGEM, que não tem esses campos.
            #
            # O banco entra só onde a página calou. Ali mora o que o Tel marcou
            # à mão pelo comando `NNNN incluso a tx` (o 5729 é assim: o site
            # não diz e ele marcou), e jogar isso fora apagaria decisão dele.
            if not imovel.get("incluso_no_aluguel"):
                imovel["incluso_no_aluguel"] = linha["incluso"] or None
            if not imovel.get("lances_de_escada"):
                imovel["lances_de_escada"] = linha["lances"] or None
            # A taxa entra para o AVISO ao Tel. Medido em 14/09: 50 dos 85
            # imóveis de locação no mercado não têm nenhuma informação de taxa,
            # e é por isso que o card sai sem "(incluso a tx)" -- o dado falta,
            # a regra funciona.
            imovel["taxa_condominio"] = linha["taxa_condominio"]
            # E DESDE 03/10 ENTRA NO CARD TAMBÉM, como linha própria -- mas só
            # quando é recente. Quem decide e quem formata é
            # `nay_linha_da_taxa`, no banco: o card do publicador e o
            # `nai_card_do_banco` são DOIS montadores do mesmo card, e a regra
            # de validade não pode ter duas cópias. Aqui só se imprime o texto
            # que vem de lá. `taxa_do_card.sql`.
            imovel["linha_da_taxa"] = linha["linha_da_taxa"]
            # O SITE MANDA MAIS QUE O BANCO no `sol`: o 5719 tem "Nascente" na
            # página e vazio na tabela. Então o banco só entra quando a página
            # não trouxe -- é o caso das casas, que não têm o rótulo "Sol".
            if not imovel.get("sol"):
                imovel["sol"] = linha["sol"] or None
    except Exception:
        pass                      # complemento nunca derruba o envio
    finally:
        try:
            conexao.close()
        except Exception:
            pass
    return imovel


def anuncio_encontrado(imovel):
    """O site ACHOU o anúncio? Todo caminho que ENVIA card pergunta isto antes.

    Código que não existe (ou saiu do site) não dá erro: `/anuncios/2944`
    devolve 302 para `/nao-encontrado`, o requests segue, a página responde 200
    e `extrair_imovel` devolve um dict com tudo None -- que é TRUTHY. Em 14/09 o
    Tel pediu "Posta no grupo anunciar easy 2944" e o grupo recebeu
    "📍 Imóvel 2944 / Código: 2944", sem foto nem valor. Antes disso a mesma
    página vazia já tinha ido para corretor ("até 4.200" lido como o código 4).

    Os quatro campos vêm SÓ da página -- `_complementar_do_banco` não preenche
    nenhum deles --, então imóvel que saiu do site e continua na tabela também
    responde "não achei", que é a regra: só vai para fora o que está no ar.
    """
    return bool(imovel) and any(
        imovel.get(c) for c in ("tipo", "valor_venda", "valor_aluguel", "fotos"))


# O PISO DE PLAUSIBILIDADE DO VALOR (03/10/2026).
#
# O CASO: ele mandou o card do 9013 pedindo o formato novo, e escreveu
# "Venda: R$ 690.000". A tabela diz `valor_venda = 690`. Não era erro de
# digitação dele -- é o CADASTRO que está em MILHARES: medido no mesmo dia, três
# imóveis do catálogo novo estão assim, todos postáveis agora:
#
#     9008  venda 900    (900.000)
#     9010  venda 590    (590.000)
#     9013  venda 690    (690.000)   <- o do exemplo dele, origem 'crm'
#
# Os três entraram pelo cadastro novo -- dois pela captação (`olx`) e o 9013
# pelo CRM, que é de 03/10 e tem UM imóvel. Um `posta no grupo anunciar easy o
# 9013` hoje mandaria "Venda: R$ 690" para 19 grupos de corretor, e postagem
# não desfaz.
#
# POR QUE É PISO E NÃO CONSERTO: multiplicar por mil seria ADIVINHAR. "690" pode
# ser 690.000 (e certamente é, num apartamento de 70m2 no Dom Pedro), mas quem
# diz o preço é ele, não eu. Então o portão recusa e a recusa DIZ o número que
# está lá, para ele corrigir na fonte -- o mesmo desenho do
# `aviso_fora_do_ar`: não afirma o que não dá para ver, e diz o que fazer.
#
# OS PISOS SÃO MEDIDOS, não escolhidos: no catálogo no mercado a menor venda
# legítima é 80.000 (754 imóveis acima de 10.000, 3 abaixo) e o menor aluguel
# legítimo é acima de 300 (95 imóveis, nenhum abaixo). Há uma ordem de grandeza
# de folga entre o piso e o dado real.
VENDA_MINIMA_PLAUSIVEL = 10000
ALUGUEL_MINIMO_PLAUSIVEL = 300


def _reais(v):
    """"690" e "2,50" -- sem arredondar para zero um valor que tem centavos,
    senão a recusa mostraria um número que não está no cadastro."""
    return (f"{v:,.0f}".replace(",", ".") if float(v) == int(float(v))
            else f"{v:.2f}".replace(".", ","))


def valor_implausivel(imovel):
    """O motivo, em texto, quando um valor do card não pode ser verdade.

    Devolve None quando está tudo bem -- é o formato que o chamador usa para
    decidir entre postar e recusar.

    Valor AUSENTE não é implausível: imóvel só de venda não tem aluguel, e
    `anuncio_encontrado` já cuida do caso em que não há valor nenhum.
    """
    if not imovel:
        return None
    venda = imovel.get("valor_venda") or 0
    aluguel = imovel.get("valor_aluguel") or 0
    if 0 < venda < VENDA_MINIMA_PLAUSIVEL:
        # O "se é X.000" é um PALPITE declarado como palpite, e vale porque é o
        # conserto em 3 de 3 casos medidos. Quem confirma é ele.
        #
        # SÓ COM VALOR INTEIRO: "R$ 2,50.000" não é número nenhum, e uma recusa
        # que escreve bobagem faz ele desconfiar do resto dela.
        if float(venda) == int(float(venda)):
            return (f"a venda está cadastrada como R$ {_reais(venda)} -- se o "
                    f"certo é R$ {_reais(venda)}.000, o cadastro está em milhares")
        return (f"a venda está cadastrada como R$ {_reais(venda)} -- esse valor "
                f"não pode ser o preço de um imóvel")
    if 0 < aluguel < ALUGUEL_MINIMO_PLAUSIVEL:
        return (f"o aluguel está cadastrado como R$ {_reais(aluguel)} -- esse "
                f"valor não pode ser um aluguel de verdade")
    return None


# ----------------------------------------------------------------------
# O SEGUNDO CATÁLOGO (Tel, 30/09).
#
# Ele mandou "Posta no grupo anunciar easy o 9003" e ela respondeu que o
# anúncio não estava no ar. A resposta estava CERTA para o que ela sabia: este
# módulo lê ao vivo de `imobeasy.com/anuncios/<codigo>`, e ali o 9003
# redireciona para /nao-encontrado.
#
# MAS O IMÓVEL EXISTE. Ele nasceu no site NOVO, `imobeasy.online`, que não
# guarda página por anúncio -- é HTML estático que lê de
# `api.imobeasy.online`, e essa API grava direto no naydb. Medido: o 9003 está
# em `imoveis` (Edifício Firenze, Parque 10, aluguel 5.000) e as 16 fotos dele
# estão em `imovel_fotos`, servidas pelo `.online`.
#
# Ou seja: hoje existem DOIS catálogos. O antigo, que a varredura raspa, e o
# novo, que nasce no banco. Os códigos do novo começam em 9001.
#
# POR QUE ISTO NÃO FURA A REGRA "o publicador lê AO VIVO": a regra existe para
# garantir "cadastrou agora, posta agora" -- que o publicador nunca poste a
# partir de cópia velha. Para o catálogo novo, o banco É a fonte viva: é onde o
# cadastro do site grava, no mesmo instante. Ler do site antigo um imóvel que
# nunca esteve lá não é frescor, é ausência.
#
# POR QUE NÃO USO O `/api/imovel-card/` DA API, que já devolve o card pronto no
# mesmo formato: porque ele é uma SEGUNDA cópia da regra de card. O projeto
# trata "cópia diverge sozinha" como o bug mais caro, e o card do publicador é
# o que o Tel vem moldando há semanas (lances de escada, incluso a tx, valor
# curto). Um montador só continua mandando -- daqui sai o mesmo dicionário, e
# `montar_mensagem` segue sendo o único que escreve card.
def _do_banco(codigo):
    """O imóvel montado da tabela, no MESMO formato que a página devolve.

    Devolve None quando não há linha -- e aí quem chama continua dando a
    resposta de sempre ("não está no ar"), que para um código inexistente é a
    verdade.
    """
    try:
        import db
        conexao = db.conectar()
    except Exception:
        return None
    try:
        with conexao.cursor() as cur:
            cur.execute(
                "SELECT codigo::text AS codigo, tipo, condominio_nome, bairro, "
                "       area_util, quartos, suites, banheiros, vagas, "
                "       vagas_cobertas, valor_venda, valor_aluguel, sol, "
                "       mobilia, descricao, "
                "       extras->>'incluso no aluguel' AS incluso, "
                "       extras->>'lances de escada'   AS lances, "
                "       extras->>'aceita financiamento' AS financia, "
                "       taxa_condominio, "
                "       nay_linha_da_taxa(taxa_condominio, "
                "                         taxa_condominio_em) AS linha_da_taxa, "
                "       nay_esta_no_mercado(disponivel, bloqueado, "
                "                           publicado_no_site) AS no_mercado "
                "  FROM imoveis WHERE codigo::text = %s", (str(codigo),))
                # `caracteristicas` fica de fora: no card ela não entra, e o
                # que o card usa dela (mobília) já vem na coluna própria.
            linha = cur.fetchone()
            if not linha:
                return None
            # A ORDEM DAS FOTOS É A DO CADASTRO, e a capa vem primeiro --
            # `_fotos_para_grupo` manda só a primeira para 9 dos 10 grupos, e
            # mandar uma foto do banheiro como capa seria pior que não postar.
            cur.execute(
                "SELECT url FROM imovel_fotos WHERE codigo::text = %s "
                "   AND coalesce(btrim(url),'') <> '' "
                " ORDER BY e_capa DESC NULLS LAST, ordem NULLS LAST, id",
                (str(codigo),))
            fotos = [f["url"] for f in cur.fetchall()]
    except Exception:
        return None
    finally:
        try:
            conexao.close()
        except Exception:
            pass

    # SEM `tipo` NÃO SE POSTA. É a mesma parede do caminho do site: dicionário
    # sem tipo significa que não se aprendeu nada, e o card sairia
    # "📍 Imóvel 9003 / Código: 9003" -- que foi exatamente o bug do Easy
    # postando o 2944 vazio.
    if not (linha.get("tipo") or "").strip():
        return None

    # A TRAVA DO "ESTÁ NO AR", que no catálogo antigo era o próprio site
    # responder. Aqui não há página para consultar, então o análogo é a regra
    # que o projeto já declara como única para "pode ser oferecido":
    # `nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)`.
    #
    # Sem ela, o segundo caminho postaria em 14 grupos o rascunho que o Tel
    # ainda não publicou e o imóvel que já saiu -- e postagem não desfaz.
    # Medido em 30/09: o 9002 está com `publicado_no_site = false` (rascunho) e
    # o 9001 com `disponivel = false`; só o 9003 está no ar.
    #
    # Devolver None aqui faz cair na recusa que já existe ("o anúncio não está
    # no ar no site -- publica no site e me pede de novo"), que para rascunho é
    # exatamente a instrução certa.
    if linha.get("no_mercado") is not True:
        return None

    return dict(
        codigo=str(codigo),
        tipo=linha["tipo"],
        aceita_financiamento=linha["financia"],
        lances_de_escada=linha["lances"],
        incluso_no_aluguel=linha["incluso"],
        # A TAXA, nas duas formas: o número cru para o aviso ao Tel (o
        # `(incluso a tx)` do publicador) e a linha pronta para o card, que só
        # vem preenchida quando a taxa é recente. `taxa_do_card.sql`.
        #
        # ESTE É O CAMINHO DO CATÁLOGO NOVO, e a taxa não chegava por aqui: a
        # consulta não a trazia. Todo 9xxx passa por esta função -- inclusive o
        # 9013, que é o imóvel do exemplo dele.
        taxa_condominio=(float(linha["taxa_condominio"])
                         if linha["taxa_condominio"] is not None else None),
        linha_da_taxa=linha["linha_da_taxa"],
        sol=linha["sol"],
        caracteristicas=None,
        mobilia=linha["mobilia"],
        observacao=None,
        # O card só diz "área construída" quando a página rotula assim; a
        # tabela guarda `area_util`, então aqui é sempre área comum.
        area_e_construida=False,
        condominio=linha["condominio_nome"],
        bairro=linha["bairro"],
        area=int(linha["area_util"]) if linha["area_util"] else None,
        quartos=linha["quartos"],
        suites=linha["suites"],
        banheiros=linha["banheiros"],
        vagas=linha["vagas"],
        vagas_cobertas=linha["vagas_cobertas"],
        valor_venda=float(linha["valor_venda"]) if linha["valor_venda"] else None,
        valor_aluguel=float(linha["valor_aluguel"]) if linha["valor_aluguel"] else None,
        fotos=fotos,
    )


def buscar_no_site(codigo):
    """SÓ o site antigo, sem cair no banco. Devolve None quando não está no ar.

    POR QUE ISTO EXISTE SEPARADO (30/09): dois trabalhos do projeto têm o site
    como a PRÓPRIA garantia, e para eles o segundo caminho não é ajuda, é a
    quebra silenciosa:

      * `_atualizar_valores_do_site` relê o preço no site na hora de disparar a
        lista, porque o Tel muda o valor no admin e dispara em seguida. Lendo
        do banco ela compara o banco com o banco, nunca acha diferença, e a
        promessa "a lista sempre sai com o valor do site" morre sem avisar.

      * `varrer_fotos.conferir` existe para dizer "as fotos do site são a
        verdade, troque as nossas". Lendo do banco, a comparação dá sempre
        igual, ela carimba `fotos_conferidas_em` e declara conferido sem ter
        olhado nada -- um vigia que vira carimbo.

    Nos dois casos nada falharia e nada avisaria. Por isso a distinção é
    explícita aqui em vez de um parâmetro booleano: quem precisa do site pede o
    site pelo nome.
    """
    try:
        imovel = _complementar_do_banco(extrair_imovel(baixar_anuncio(codigo),
                                                       codigo))
    except Exception:
        return None
    return imovel if (imovel and (imovel.get("tipo") or "").strip()) else None


def buscar_imovel(codigo):
    """O imóvel, do site antigo OU do banco -- nesta ordem.

    O SITE ANTIGO MANDA quando tem o anúncio: é ele que o corretor abre, e o
    que está no ar tem que ser o que a Nay diz.

    O BANCO ENTRA quando a página não traz nada. Página morta devolve um dict
    TRUTHY com tudo None (o site redireciona para /nao-encontrado e o
    `raise_for_status` não levanta), então o teste é pelo `tipo` -- a mesma
    parede que o resto do projeto usa para distinguir "achei" de "abriu".
    """
    try:
        html = baixar_anuncio(codigo)
        do_site = _complementar_do_banco(extrair_imovel(html, codigo))
    except Exception:
        do_site = None
    if do_site and (do_site.get("tipo") or "").strip():
        return do_site
    return _do_banco(codigo) or do_site


def main():
    if len(sys.argv) != 2:
        print("Uso: buscar_imovel.py <codigo>", file=sys.stderr)
        sys.exit(1)

    codigo = sys.argv[1]
    try:
        imovel = buscar_imovel(codigo)
    except requests.RequestException as exc:
        print(f"Falha ao baixar o anúncio {codigo}: {exc}", file=sys.stderr)
        sys.exit(1)

    for chave, valor in imovel.items():
        if chave == "fotos":
            print(f"fotos ({len(valor)}):")
            for url in valor:
                print(f"  {url}")
        else:
            print(f"{chave}: {valor}")


if __name__ == "__main__":
    main()
