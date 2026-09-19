"""Traduz o anúncio cru da OLX para o vocabulário do imóvel da Imob Easy,
diz o que ainda falta perguntar ao proprietário, e levanta as dúvidas que o
Tel precisa CONFERIR antes de cadastrar.

POR QUE ESTE ARQUIVO EXISTE
---------------------------
A captação é nossa: o proprietário anuncia o imóvel dele na OLX e o Tel manda
o link para a plataforma, em vez de redigitar tudo no admin do site. Só que o
anúncio do proprietário é um formulário preenchido às pressas por leigo, e o
`extrair_olx.py` -- de propósito -- não converte NADA: devolve `"R$ 390.000"`,
`"138m²"`, `"5 ou mais"`. Alguém tem que traduzir isso, e é aqui.

Este módulo é puro: só `re` e `unicodedata`, nenhuma rede, nenhum banco. Quem
cadastra no site é outro arquivo; quem guarda o rascunho é a tabela
`captacoes`. Aqui só se decide o que o dado da OLX quer dizer.

O QUE FOI MEDIDO EM 02/09/2026, e cada linha custou uma requisição
-----------------------------------------------------------------
Amostra: 217 anúncios únicos de imóveis de Manaus (5 páginas de listagem) e 7
anúncios individuais abertos um a um.

1. `size` SIGNIFICA TRÊS COISAS, e o rótulo que diz qual delas some.
   Na OLX o campo tem um `label` que a listagem entrega:
       Apartamentos                -> "Área útil"      (96 anúncios)
       Casas                       -> "Área construída" (90)
       Terrenos / Comércio         -> "Tamanho"        (13)
   O `extrair_olx.extrair()` guarda só `name` e `value`, então o rótulo NÃO
   chega aqui. Por isso quem decide é a `category`: em terreno e comércio o
   `size` é o TERRENO, e escrever terreno em `area_util` é o erro de 10x que
   o CLAUDE.md já registra sobre a coluna "Área" do nosso próprio card.

2. `"5 ou mais"` NÃO É NÚMERO. Aparece em 59 dos 217: banheiros 37, vagas 12,
   quartos 10. `int("5 ou mais")` levanta ValueError; ignorar o campo perde o
   dado. Vira 5 -- e vira dúvida, porque o real pode ser 7.

3. `condominio` e `iptu` chegam como `"R$ 0"` na MAIORIA das vezes em que
   chegam: 58 de 89 condomínios e 30 de 72 IPTUs. Um dos "R$ 0" é de um
   anúncio com `re_complex_features` = "Condomínio fechado, Piscina, Portaria"
   -- ou seja, é o campo que o anunciante pulou, não taxa que não existe.
   Aqui vira None (não sei) e nunca 0 (não tem).

4. A OLX NÃO TEM CAMPO DE SUÍTE. Zero dos 217. `suites` sai sempre None e vai
   para a lista do que falta perguntar. O CLAUDE.md registra que o extrator do
   nosso próprio catálogo inventava `suites=0` quando não achava a palavra
   "suíte" -- não repetir isso aqui.

5. `garage_spaces` é o TOTAL de vagas. O nosso banco separa coberta de
   descoberta, e o CLAUDE.md diz que os 39 imóveis conferidos batem com a
   soma. Então `vagas_cobertas` sai None e é pergunta.

6. O ANUNCIANTE ERRA A CATEGORIA. Em 3 dos 217 o título diz "casa" e o
   `real_estate_type` diz apartamento (ex.: 1531756564, "CASA DISPONÍVEL PARA
   VENDA NO MORADA DOS PÁSSAROS", que a OLX classificou como "Venda -
   apartamento padrão"). Não dá para bloquear por isso; dá para avisar.

7. `real_estate_type` FALTA em 7 dos 217, e `category` sozinha não separa casa
   de rua de casa de condomínio -- e as duas existem em peso no nosso catálogo
   (322 casas de condomínio contra 75 casas). Sem certeza, `tipo` fica None e
   entra na lista de perguntas, que é o lugar certo de um "não sei".

8. Vocabulário do nosso lado, lido da tabela `imoveis` no mesmo dia:
       tipo    : Apartamento 605, Casa de condomínio 322, Lote em Condomínio 94,
                 Casa 75, Sala/Andar 21, Flat 21, Cobertura 20, Prédio 5,
                 Loja/Ponto 4, Apartamento em Via Pública 3, Galpão/Depósito 1,
                 Lote 1
       mobilia : exatamente três textos, minúsculos e com parênteses (ver
                 MOBILIA_*). Não é campo livre.
       caracteristicas : é ARRAY de texto no Postgres, não string.
   A OLX tem um só "Mobiliado" e nós temos três níveis: preencher o nível
   exato é chute, então preenche e AVISA.

9. Faixas do nosso próprio catálogo, para calibrar as dúvidas (imóveis com
   área entre 20 e 2.000 m²):
       venda   : R$/m² p2 750, mediana 5.595, p98 13.218  (954 imóveis)
       aluguel : R$/m² p2 14,48, mediana 49,36, p98 132,35 (145 imóveis)
   Os limiares aqui são bem mais largos que esses percentis de propósito:
   dúvida demais vira ruído e o Tel para de ler.

O CASO QUE MOTIVOU `duvidas()`
------------------------------
O primeiro anúncio que o projeto abriu, sem escolher, era uma fazenda de
12.000 hectares com `priceValue: "R$ 1.500"` e `priceLabel: "Aluguel"` -- e
era R$ 1.500 POR HECTARE, à venda. Nenhum campo do anúncio estava
"faltando": todos estavam preenchidos e todos mentiam juntos. A defesa não é
recusar o anúncio, é gritar o absurdo: 1.500 dividido por 120.000.000 m² dá
R$ 0,0000125 por m², e qualquer piso razoável pega isso.

    .venv/bin/python teste_captacao_campos.py
"""
import re
import unicodedata

# --- vocabulário da Imob Easy -------------------------------------------
# Os três textos de `imoveis.mobilia`, copiados como estão no banco (com os
# parênteses, sem acento e em minúsculas). Não inventar variação: a busca da
# Nay compara texto.
MOBILIA_MOBILIADO = "mobiliado (moveis + cama + tudo)"
MOBILIA_SEMI = "semi-mobiliado (moveis planejados + ar)"
MOBILIA_SO_AR = "so ar-condicionado"

# Os 16 campos que a plataforma preenche. A ordem aqui é a de exibição do
# formulário; a ordem das PERGUNTAS é a de ORDEM_DA_PERGUNTA, que é outra.
CAMPOS = (
    "tipo", "bairro", "logradouro", "area_util", "quartos", "suites",
    "banheiros", "vagas", "vagas_cobertas", "valor_venda", "valor_aluguel",
    "taxa_condominio", "iptu", "mobilia", "descricao", "caracteristicas",
)

ROTULOS = {
    "tipo": "Tipo do imóvel",
    "bairro": "Bairro",
    "logradouro": "Rua / avenida",
    "area_util": "Área útil (m²)",
    "quartos": "Quartos",
    "suites": "Suítes",
    "banheiros": "Banheiros",
    "vagas": "Vagas de garagem",
    "vagas_cobertas": "Vagas cobertas",
    "valor": "Valor de venda ou de aluguel",
    "valor_venda": "Valor de venda",
    "valor_aluguel": "Valor do aluguel",
    "taxa_condominio": "Taxa de condomínio",
    "iptu": "IPTU",
    "mobilia": "Mobília",
    "descricao": "Descrição",
    "caracteristicas": "Características",
}

# Sem estes o anúncio não vira card no site: não dá para publicar imóvel sem
# dizer o que é, onde fica, quanto custa e de que tamanho.
OBRIGATORIOS = frozenset({"tipo", "bairro", "valor", "area_util", "quartos",
                          "banheiros", "vagas"})

# A ordem em que se pergunta ao proprietário: primeiro o que identifica o
# imóvel, depois o que descreve, por último o texto longo. `valor` é um
# pseudo-campo -- ele fecha `valor_venda` OU `valor_aluguel`, nunca os dois.
ORDEM_DA_PERGUNTA = (
    "tipo", "bairro", "valor", "area_util", "quartos", "banheiros", "vagas",
    "suites", "vagas_cobertas", "logradouro", "taxa_condominio", "iptu",
    "mobilia", "caracteristicas", "descricao",
)

# Perguntas que não fazem sentido num terreno. Perguntar quantos banheiros tem
# um lote vazio queima a paciência do proprietário na primeira captação.
SEM_SENTIDO_EM_LOTE = frozenset({"quartos", "banheiros", "vagas", "suites",
                                 "vagas_cobertas", "mobilia"})

# --- limiares das dúvidas ------------------------------------------------
# Todos calibrados contra o catálogo real (ver item 9 do cabeçalho) e todos
# folgados de propósito: aqui erra-se para o lado de não avisar.
VENDA_MINIMA = 50_000          # pedido do Tel; a menor venda real são 80.000
VENDA_MAXIMA = 20_000_000      # a maior venda real são 10.000.000
ALUGUEL_MAXIMO = 20_000        # pedido do Tel; existem aluguéis reais acima
ALUGUEL_MINIMO = 300           # o menor aluguel real são 900
AREA_MINIMA = 15               # 21 dos 1.115 imóveis com área estão abaixo
AREA_MAXIMA = 2_000            # 2 dos 1.115 estão acima
VENDA_M2_MIN, VENDA_M2_MAX = 500, 25_000        # p2 750, p98 13.218
ALUGUEL_M2_MIN, ALUGUEL_M2_MAX = 8, 300         # p2 14,48, p98 132,35
# Terreno vale por m² numa faixa MUITO mais larga que imóvel construído: os 95
# lotes do nosso catálogo vão de R$ 288 a R$ 26.071 por m² (mediana 960).
# Usar a faixa de apartamento aqui acusaria lote normal, e dúvida que sempre
# aparece o Tel para de ler.
TERRENO_M2_MIN, TERRENO_M2_MAX = 150, 30_000
TERRENO_ALUGUEL_M2_MIN, TERRENO_ALUGUEL_M2_MAX = 0.5, 300

# Condomínio e IPTU tinham piso (o "R$ 0") e NENHUM teto -- e é por cima que o
# anunciante erra. Medido em 02/09/2026 contra 244 anúncios de Manaus: 15 dos
# 214 campos de taxa gravados eram absurdos e passavam calados, entre eles
# `condominio: "R$ 330.000"`, `"R$ 108.223"` e um terreno de R$ 90.000 com
# `condominio` E `iptu` iguais a R$ 90.000 -- o anunciante repetiu o preço do
# imóvel nos três campos. Taxa de R$ 90 mil publicada no site mata o negócio
# na primeira pergunta que o corretor fizer à Nay.
# Os limiares vêm da tabela `imoveis` no mesmo dia, e são folgados de propósito:
#   taxa_condominio > 0: 178 imóveis, min 50, p2 180, mediana 592, máx 3.898,50
#   iptu            > 0: 156 imóveis, p2 77,53, mediana 750, máx 8.000
CONDOMINIO_MINIMO = 50         # não existe UM condomínio abaixo de 50 no nosso
CONDOMINIO_MAXIMO = 15_000     # ~4x o maior real (3.898,50)
IPTU_MINIMO = 10               # 3 dos 156 estão abaixo; é dúvida, não bloqueio
IPTU_MAXIMO = 20_000           # 2,5x o maior real (8.000)

# Telefone brasileiro em texto corrido: DDD (com ou sem parênteses) seguido de
# 8 ou 9 dígitos. Exige o DDD justamente para não confundir com CEP, que tem 8
# dígitos seguidos e aparece em descrição de imóvel.
_TELEFONE = re.compile(r"(?:\(\d{2}\)|\b\d{2})\s*9?\s*\d{4}[-.\s]?\d{4}\b")
_CHAMADA_DE_CONTATO = ("whatsapp", "whats app", "zap", "chama no", "ligue",
                       "me liga", "entre em contato pelo")


def _chave(texto):
    """Normaliza para comparar: sem acento, minúsculo, pontuação virando
    espaço. A OLX escreve "condominio fechado" sem acento e "rua pública" com
    -- comparar cru erraria metade das vezes."""
    if texto is None:
        return ""
    sem_acento = "".join(
        c for c in unicodedata.normalize("NFD", str(texto))
        if unicodedata.category(c) != "Mn")
    return " ".join(re.sub(r"[^0-9a-zA-Z]+", " ", sem_acento).lower().split())


def _numero(bruto):
    """`"R$ 390.000"` -> 390000.0, `"138m²"` -> 138.0, `"Sob consulta"` -> None.

    O ponto é separador de MILHAR em real; só a vírgula é decimal. Trocar os
    dois de lugar transformaria R$ 1.800.000 em R$ 1,8."""
    if bruto is None:
        return None
    if isinstance(bruto, bool):
        return None
    if isinstance(bruto, (int, float)):
        return float(bruto)
    limpo = re.sub(r"[^\d,]", "", str(bruto)).replace(",", ".")
    if not limpo or limpo.count(".") > 1:
        return None
    try:
        return float(limpo)
    except ValueError:
        return None


def _contagem(bruto):
    """`"3"` -> 3, `"5 ou mais"` -> 5, ausente -> None.

    O `"5 ou mais"` vira 5 e vira dúvida: é o piso do que a OLX sabe, não o
    número. Descartar o campo seria pior -- perderia-se a informação de que há
    pelo menos cinco."""
    if bruto is None:
        return None
    achado = re.search(r"\d+", str(bruto))
    return int(achado.group()) if achado else None


def _vagas_do_anunciante(bruto):
    """`garage_spaces` zerado é campo pulado, NÃO "não tem vaga".

    Medido em 02/09/2026, em 200 anúncios de Manaus lidos da listagem: 6 dos
    148 que trazem `garage_spaces` mandam `"0"`, e o que eles são fica claro
    ao olhar: `1508281340` é apartamento padrão de 95 m², 3 quartos, 2
    banheiros, condomínio de R$ 660 -- e "0 vagas". `1521838114` é outro de
    99 m² e 3 quartos. Apartamento assim em Manaus tem vaga; o proprietário
    é que não preencheu, do mesmo jeito que deixa o condomínio em "R$ 0"
    (47 dos 137 medidos no mesmo dia).

    Gravar 0 aqui é a afirmação "este imóvel não tem vaga", e é ela que chega
    ao corretor pela boca da Nay. None é "não sei", vira pergunta obrigatória
    e o proprietário responde. Zero que o TEL digitar na plataforma continua
    valendo como resposta -- esta função só desconfia do formulário da OLX."""
    contagem = _contagem(bruto)
    return None if contagem == 0 else contagem


def _texto(bruto):
    """Texto vazio da OLX é ausência, não string vazia."""
    if bruto is None:
        return None
    limpo = str(bruto).strip()
    return limpo or None


def _texto_livre(dados_olx):
    """Título e descrição juntos, já normalizados, para procurar palavra.

    O `str()` não é enfeite: `titulo` e `descricao` saem do JSON da OLX sem
    conversão nenhuma (`extrair_olx` devolve `subject` e `body` crus), e
    concatenar `"" + 3.7` levanta TypeError -- que aqui derrubaria justamente
    `duvidas()`, a função que existe para proteger o Tel."""
    return _chave(f"{dados_olx.get('titulo') or ''} "
                  f"{dados_olx.get('descricao') or ''}")


def _reais(valor, casas=0):
    """`1234567.8` -> `"1.234.567"`; com `casas=2` -> `"1.234.567,80"`.

    O `f"{v:,.2f}"` do Python devolve o formato americano (`1,234,567.80`), e
    corrigir com dois `replace` em sequência não funciona: o segundo desfaz o
    primeiro. Por isso o separador passa por um caractere que não existe no
    texto antes de virar ponto."""
    return (f"{valor:,.{casas}f}"
            .replace(",", "\x00").replace(".", ",").replace("\x00", "."))


def _metros(area):
    """`42.0` -> `"42"`, `120000000.0` -> `"120.000.000"`, `42.5` -> `"42,5"`.

    O `f"{area:g}"` vira `"1.2e+08"` numa fazenda, e notação científica dentro
    de um aviso de WhatsApp não diz nada a ninguém."""
    if float(area).is_integer():
        return _reais(area)
    return _reais(area, 2).rstrip("0").rstrip(",")


def _e_ou_mais(bruto):
    """O anunciante marcou o topo da lista ("5 ou mais"), não um número."""
    return bruto is not None and not str(bruto).strip().isdigit() \
        and re.search(r"\d", str(bruto)) is not None


def _dinheiro_do_anunciante(bruto):
    """Condomínio e IPTU: `"R$ 0"` é campo pulado, não taxa inexistente.

    Medido: 58 dos 89 condomínios preenchidos e 30 dos 72 IPTUs vêm zerados,
    inclusive em prédio com piscina e portaria. Zero aqui é "não sei"."""
    valor = _numero(bruto)
    if valor is None or valor <= 0:
        return None
    return valor


def _negocio(dados_olx):
    """Venda ou aluguel, por dois caminhos independentes.

    Devolve (escolhido, pelo_tipo, pelo_rotulo). O `real_estate_type` vem de
    uma lista fechada que o anunciante escolheu e por isso decide; o
    `priceLabel` é o segundo par de olhos e serve para levantar dúvida quando
    os dois discordam."""
    campos_olx = dados_olx.get("campos") or {}
    tipo_olx = _chave(campos_olx.get("real_estate_type"))
    pelo_tipo = None
    if tipo_olx.startswith("venda"):
        pelo_tipo = "venda"
    elif tipo_olx.startswith("aluguel"):
        pelo_tipo = "aluguel"

    rotulo = _chave(dados_olx.get("preco_rotulo"))
    pelo_rotulo = None
    if rotulo.startswith("aluguel"):
        pelo_rotulo = "aluguel"
    elif rotulo.startswith("preco") or rotulo.startswith("venda"):
        pelo_rotulo = "venda"

    return (pelo_tipo or pelo_rotulo), pelo_tipo, pelo_rotulo


def _tipo(campos_olx):
    """Traduz `category` + `real_estate_type` + `re_types` para o vocabulário
    de `imoveis.tipo`, e devolve None quando a OLX não deu para decidir.

    Casa de rua e casa de condomínio são tipos DIFERENTES no nosso cadastro e
    ambos existem em peso (75 e 322). Quando a OLX só diz "Casas", chutar o
    mais comum acertaria 8 de 10 e erraria calado nos outros 2 -- então não
    chuta: devolve None e a pergunta vai para o proprietário."""
    tipo_olx = _chave(campos_olx.get("real_estate_type"))
    categoria = _chave(campos_olx.get("category"))
    subtipo = _chave(campos_olx.get("re_types"))
    complexo = _chave(campos_olx.get("re_complex_features"))
    em_condominio = ("condominio" in tipo_olx or "condominio" in subtipo
                     or "condominio fechado" in complexo)

    # Cobertura e kitnet antes de apartamento: os dois textos da OLX contêm a
    # palavra "apartamento" ("Venda - apartamento cobertura").
    if "cobertura" in tipo_olx or "cobertura" in subtipo:
        return "Cobertura"
    if "kitchenette" in tipo_olx or "kitnet" in subtipo:
        return None  # a OLX tem Kitnet; o nosso cadastro não tem esse tipo
    if "apartamento" in tipo_olx or categoria == "apartamentos":
        return "Apartamento"
    if "casa" in tipo_olx or categoria == "casas":
        if em_condominio:
            return "Casa de condomínio"
        if "rua publica" in tipo_olx or "vila" in tipo_olx:
            return "Casa"
        return None  # "Casas" sem detalhe: pode ser qualquer um dos dois
    if "terreno" in tipo_olx or "lote" in subtipo:
        return "Lote em Condomínio" if em_condominio else "Lote"
    # A categoria "Terrenos, sítios e fazendas" é UMA SÓ na OLX e cobre coisas
    # que no nosso cadastro não são a mesma: lote tem tipo, sítio e fazenda
    # não têm nenhum. Sem o `real_estate_type` para separar, não se decide.
    # Comércio e indústria cobre Sala/Andar, Loja/Ponto, Galpão e Prédio de
    # uma vez só, e também não fecha sozinha.
    return None


def _mobilia(dados_olx, campos_olx):
    """Só a lista de itens da OLX (`re_features`) diz que é mobiliado; o texto
    livre só serve para BAIXAR o nível para semi.

    A OLX tem um único "Mobiliado" e nós temos três níveis. Ler "mobiliado" da
    descrição pegaria "não mobiliado" junto, então o positivo vem só do campo
    estruturado, que é lista de marcar."""
    itens = _chave(campos_olx.get("re_features"))
    if "mobiliado" not in itens:
        return None
    texto = _texto_livre(dados_olx)
    if "semi mobiliado" in texto or "semimobiliado" in texto:
        return MOBILIA_SEMI
    return MOBILIA_MOBILIADO


def _caracteristicas(campos_olx):
    """Junta os dois campos de lista da OLX num array de texto, sem repetir.

    "Piscina" aparece nos dois (28 vezes no imóvel e 49 no condomínio) e
    entraria duas vezes no array. Lista vazia vira None: array vazio no banco
    afirma "não tem característica nenhuma", e isso não foi medido."""
    itens = []
    for chave in ("re_features", "re_complex_features"):
        bruto = campos_olx.get(chave)
        if not bruto:
            continue
        for item in str(bruto).split(","):
            item = item.strip()
            if item and item not in itens:
                itens.append(item)
    return itens or None


def _area_util(campos_olx):
    """`size` só vira área útil quando a categoria garante que é do imóvel.

    Em terreno e comércio o rótulo da OLX é "Tamanho" e o número é do TERRENO.
    Gravar isso em `area_util` é o mesmo erro de 10x que o CLAUDE.md registra
    sobre a coluna "Área" do nosso card -- por isso ali fica None e vira
    pergunta."""
    bruto = campos_olx.get("size")
    if not bruto:
        return None
    categoria = _chave(campos_olx.get("category"))
    if categoria.startswith("terrenos") or categoria.startswith("comercio"):
        return None
    area = _numero(bruto)
    # `size` zerado é campo pulado, igual ao "R$ 0" de condomínio -- e imóvel
    # de 0 m² não existe. Sem esta linha o `"0"` (texto) virava 0.0 e o `0`
    # (número) virava None, dois resultados para o mesmo dado da OLX; e o 0.0
    # ainda calava a pergunta, porque `o_que_falta` só pergunta o que é None.
    if area is not None and area <= 0:
        return None
    return area


def traduzir(dados_olx):
    """Recebe o dict cru do `extrair_olx.do_link()` e devolve os 16 campos do
    imóvel no vocabulário da Imob Easy.

    Campo que a OLX não mandou fica None -- NUNCA zero. Zero é "não tem";
    None é "não sei". Confundir os dois já fez a Nay dizer a um corretor que
    um apartamento não tinha vaga."""
    dados_olx = dados_olx or {}
    campos_olx = dados_olx.get("campos") or {}

    negocio, _, _ = _negocio(dados_olx)
    preco = _numero(dados_olx.get("preco_texto"))
    if preco is not None and preco <= 0:
        preco = None  # "R$ 0" de preço é anúncio sem preço, não imóvel de graça

    return {
        "tipo": _tipo(campos_olx),
        "bairro": _texto(dados_olx.get("bairro")),
        "logradouro": _texto(dados_olx.get("logradouro")),
        "area_util": _area_util(campos_olx),
        "quartos": _contagem(campos_olx.get("rooms")),
        # A OLX não tem campo de suíte em nenhum dos 217 anúncios medidos.
        # Deduzir do título é o bug do `suites=0` que o CLAUDE.md registra:
        # aqui é None, e `duvidas()` avisa quando o texto menciona suíte.
        "suites": None,
        "banheiros": _contagem(campos_olx.get("bathrooms")),
        # `garage_spaces` é o TOTAL; o banco separa coberta de descoberta.
        # Zero da OLX é campo pulado, não ausência de vaga -- ver
        # `_vagas_do_anunciante`, que mede por que.
        "vagas": _vagas_do_anunciante(campos_olx.get("garage_spaces")),
        "vagas_cobertas": None,
        "valor_venda": preco if negocio == "venda" else None,
        "valor_aluguel": preco if negocio == "aluguel" else None,
        "taxa_condominio": _dinheiro_do_anunciante(campos_olx.get("condominio")),
        "iptu": _dinheiro_do_anunciante(campos_olx.get("iptu")),
        "mobilia": _mobilia(dados_olx, campos_olx),
        "descricao": _texto(dados_olx.get("descricao")),
        "caracteristicas": _caracteristicas(campos_olx),
    }


def _rotulo_da_pergunta(campo, campos):
    """A pergunta das vagas cobertas fica muito mais fácil de responder quando
    já traz o total que a OLX deu: "quantas das 2 são cobertas"."""
    if campo == "vagas_cobertas":
        vagas = campos.get("vagas")
        if vagas == 1:
            return "A vaga é coberta?"
        if isinstance(vagas, int) and vagas > 1:
            return f"Quantas das {vagas} vagas são cobertas?"
    return ROTULOS.get(campo, campo)


def _faz_sentido_perguntar(campo, campos):
    tipo = campos.get("tipo") or ""
    if tipo.startswith("Lote") and campo in SEM_SENTIDO_EM_LOTE:
        return False
    # Vaga coberta só existe se houver vaga. Zero vagas é resposta, não lacuna.
    if campo == "vagas_cobertas" and campos.get("vagas") == 0:
        return False
    return True


def o_que_falta(campos):
    """O que ainda precisa ser perguntado ao proprietário, em ordem de
    pergunta: obrigatórios primeiro, cada grupo na ordem de ORDEM_DA_PERGUNTA.

    Devolve lista de dicts `{"campo", "rotulo", "obrigatorio"}`. `valor` é um
    pseudo-campo: só aparece quando NEM venda NEM aluguel foram preenchidos,
    porque um anúncio é uma coisa ou outra e perguntar os dois confunde.

    CHAMAR DE NOVO A CADA RESPOSTA. A lista muda conforme o que já foi
    respondido: quando o `tipo` vira qualquer Lote, as perguntas de quarto,
    banheiro, vaga, suíte e mobília somem sozinhas.

    RESSALVA, e ela é de propósito: só Lote poda pergunta. Um `Galpão/Depósito`
    ou uma `Sala/Andar` ainda são perguntados "Quantos quartos?", porque
    ninguém decidiu ainda o que se pergunta de imóvel comercial -- e três dos
    quatro tipos comerciais do catálogo (`Sala/Andar`, `Loja/Ponto`, `Prédio`)
    têm banheiro e vaga de verdade. Inventar a regra aqui seria escrever regra
    de negócio que o Tel não pediu; a poda por Lote está medida, esta não."""
    campos = campos or {}
    faltando = []
    for campo in ORDEM_DA_PERGUNTA:
        if campo == "valor":
            preenchido = (campos.get("valor_venda") is not None
                          or campos.get("valor_aluguel") is not None)
        else:
            preenchido = campos.get(campo) is not None
        if preenchido or not _faz_sentido_perguntar(campo, campos):
            continue
        faltando.append({
            "campo": campo,
            "rotulo": _rotulo_da_pergunta(campo, campos),
            "obrigatorio": campo in OBRIGATORIOS,
        })
    # `sorted` é estável, então a ordem de ORDEM_DA_PERGUNTA sobrevive dentro
    # de cada grupo.
    return sorted(faltando, key=lambda item: not item["obrigatorio"])


def duvidas(dados_olx, campos=None):
    """Avisos para o Tel CONFERIR antes de cadastrar. NENHUM deles bloqueia.

    Devolve lista de dicts `{"campo", "aviso"}`, do mais grave para o menos:
    valor e área primeiro (foi valor e área que produziram a fazenda de 12.000
    hectares anunciada como aluguel de R$ 1.500), depois o que a OLX
    classificou, depois o que ficou de fora, por último o texto.

    `campo` pode ser None quando o aviso é do anúncio inteiro."""
    dados_olx = dados_olx or {}
    campos_olx = dados_olx.get("campos") or {}
    if campos is None:
        campos = traduzir(dados_olx)

    achados = []

    def avisar(campo, aviso):
        achados.append({"campo": campo, "aviso": aviso})

    venda = campos.get("valor_venda")
    aluguel = campos.get("valor_aluguel")

    categoria = _chave(campos_olx.get("category"))
    e_terreno_ou_comercio = (categoria.startswith("terrenos")
                             or categoria.startswith("comercio"))

    # A conferência de valor NÃO pode depender de `area_util` ter sido aceita.
    # A fazenda de 12.000 hectares que motivou esta função é exatamente uma
    # categoria em que `traduzir()` recusa o `size` como área útil -- e sem
    # esta linha o único caso que se sabe real passaria batido, com a função
    # inteira parecendo funcionar.
    area = campos.get("area_util")
    if area is None:
        area = _numero(campos_olx.get("size"))

    # --- 1. valor fora da faixa do nosso próprio catálogo -----------------
    if venda is not None and venda < VENDA_MINIMA:
        avisar("valor_venda",
               f"venda de R$ {_reais(venda)} está abaixo de"
               f" R$ {_reais(VENDA_MINIMA)} -- confira se o anúncio não está"
               " com preço por lote, por hectare ou por parcela.")
    if venda is not None and venda > VENDA_MAXIMA:
        avisar("valor_venda",
               f"venda de R$ {_reais(venda)} é maior que qualquer imóvel do"
               " nosso catálogo -- confira se não sobrou um zero.")
    if aluguel is not None and aluguel > ALUGUEL_MAXIMO:
        avisar("valor_aluguel",
               f"aluguel de R$ {_reais(aluguel)} passa de"
               f" R$ {_reais(ALUGUEL_MAXIMO)} -- confira se o valor não é de"
               " venda.")
    if aluguel is not None and aluguel < ALUGUEL_MINIMO:
        avisar("valor_aluguel",
               f"aluguel de R$ {_reais(aluguel)} é baixo demais para o nosso"
               " catálogo -- confira se não é diária, taxa ou parcela.")

    # --- 2. área absurda ---------------------------------------------------
    if area is not None and area < AREA_MINIMA:
        avisar("area_util",
               f"área de {_metros(area)} m² é pequena demais -- confira se o anunciante"
               " não digitou a frente do terreno no lugar da área.")
    if area is not None and area > AREA_MAXIMA:
        avisar("area_util",
               f"área de {_metros(area)} m² é grande demais para imóvel urbano --"
               " confira se não é área de terreno ou de fazenda.")

    # --- 3. preço por m² fora de faixa ------------------------------------
    # É o cruzamento que pega a fazenda: cada campo sozinho parecia plausível.
    if e_terreno_ou_comercio:
        faixa_venda = (TERRENO_M2_MIN, TERRENO_M2_MAX)
        faixa_aluguel = (TERRENO_ALUGUEL_M2_MIN, TERRENO_ALUGUEL_M2_MAX)
    else:
        faixa_venda = (VENDA_M2_MIN, VENDA_M2_MAX)
        faixa_aluguel = (ALUGUEL_M2_MIN, ALUGUEL_M2_MAX)

    for valor, campo, (minimo, maximo) in ((venda, "valor_venda", faixa_venda),
                                           (aluguel, "valor_aluguel", faixa_aluguel)):
        if not valor or not area:
            continue
        por_m2 = valor / area
        if minimo <= por_m2 <= maximo:
            continue
        # Com 2 casas, o R$ 0,0000125/m² da fazenda vira "R$ 0,00" e o aviso
        # perde justamente o número que prova o absurdo.
        casas = 2 if por_m2 >= 1 else 6
        avisar(campo,
               f"dá R$ {_reais(por_m2, casas)} por m²"
               f" (R$ {_reais(valor)} / {_metros(area)} m²) -- fora da faixa de"
               f" R$ {_reais(minimo, 2)} a R$ {_reais(maximo)} por m² do nosso"
               " catálogo.")

    # --- 4. venda ou aluguel: os dois sinais discordam, ou não existem -----
    negocio, pelo_tipo, pelo_rotulo = _negocio(dados_olx)
    if pelo_tipo and pelo_rotulo and pelo_tipo != pelo_rotulo:
        avisar("valor_venda" if negocio == "venda" else "valor_aluguel",
               f"a OLX classificou como {pelo_tipo} no tipo do anúncio e como"
               f" {pelo_rotulo} no rótulo do preço -- o valor foi gravado como"
               f" {negocio}.")
    if negocio is None and _numero(dados_olx.get("preco_texto")):
        avisar("valor",
               f"a OLX não disse se é venda ou aluguel, então o preço"
               f" {dados_olx.get('preco_texto')!r} não foi gravado em campo"
               " nenhum.")

    # --- 5. o que a OLX classificou, e o que ela errou --------------------
    tipo_olx = campos_olx.get("real_estate_type")
    categoria_olx = campos_olx.get("category")
    if campos.get("tipo") is None and (tipo_olx or categoria_olx):
        disse = " / ".join(repr(x) for x in (categoria_olx, tipo_olx) if x)
        avisar("tipo",
               f"a OLX diz {disse}, e isso não fecha um tipo do nosso cadastro"
               " -- escolha na mão.")

    texto_livre = _texto_livre(dados_olx)
    tipo_olx_chave = _chave(tipo_olx)
    if "casa" in texto_livre and "apartamento" in tipo_olx_chave:
        avisar("tipo", "o texto do anúncio fala em casa, mas a OLX classificou"
                       " como apartamento -- o anunciante costuma errar aqui.")
    if ("apartamento" in texto_livre or " apto" in texto_livre) \
            and "casa" in tipo_olx_chave:
        avisar("tipo", "o texto do anúncio fala em apartamento, mas a OLX"
                       " classificou como casa -- confira antes de cadastrar.")

    # --- 6. contagem que é piso, não número --------------------------------
    for chave_olx, campo, nome in (("rooms", "quartos", "quartos"),
                                   ("bathrooms", "banheiros", "banheiros"),
                                   ("garage_spaces", "vagas", "vagas")):
        bruto = campos_olx.get(chave_olx)
        if _e_ou_mais(bruto):
            avisar(campo, f"a OLX diz {str(bruto).strip()!r} em {nome}: foi"
                          f" gravado {campos.get(campo)}, mas pode ser mais.")
    if campos.get("quartos") == 0:
        avisar("quartos", "o anúncio diz zero quartos -- confira se não é"
                          " kitnet, sala ou terreno.")
    if campos.get("banheiros") == 0:
        avisar("banheiros", "o anúncio diz zero banheiros -- confira se o"
                            " proprietário não pulou o campo.")
    # A vaga zerada NÃO vira 0 (ver `_vagas_do_anunciante`), então aqui o
    # aviso é sobre a pergunta que passou a existir, não sobre um valor.
    if _contagem(campos_olx.get("garage_spaces")) == 0:
        avisar("vagas", "a OLX manda zero vagas, que é o que aparece quando o"
                        " proprietário pula o campo -- ficou como não"
                        " informado e entrou na lista de perguntas.")

    # --- 7. o que a OLX mandou e foi deliberadamente deixado de fora -------
    if campos_olx.get("size") and e_terreno_ou_comercio:
        avisar("area_util",
               f"a OLX manda {campos_olx['size']!r}, mas em"
               f" {categoria_olx!r} esse número é o TAMANHO DO TERRENO, não a"
               " área útil -- por isso não foi gravado.")
    elif campos_olx.get("size") and categoria == "casas":
        avisar("area_util",
               f"a OLX chama {campos_olx['size']!r} de \"área construída\", que"
               " não é a mesma coisa que área útil -- confira o número.")

    for chave_olx, campo, nome in (("condominio", "taxa_condominio", "condomínio"),
                                   ("iptu", "iptu", "IPTU")):
        bruto = campos_olx.get(chave_olx)
        if bruto is not None and _dinheiro_do_anunciante(bruto) is None:
            avisar(campo, f"o anunciante deixou o {nome} em {str(bruto).strip()!r}"
                          " -- ficou como não informado, não como isento.")

    # A taxa tinha piso ("R$ 0") e nenhum TETO, e é por cima que o anunciante
    # erra: ele repete o preço do imóvel no campo de condomínio. Medido no
    # mesmo dia, em 244 anúncios, 15 dos 214 campos de taxa gravados eram
    # absurdos e nenhum levantava aviso. Isto não bloqueia -- o valor continua
    # gravado, e o Tel decide.
    for campo, nome, minimo, maximo in (
            ("taxa_condominio", "condomínio", CONDOMINIO_MINIMO, CONDOMINIO_MAXIMO),
            ("iptu", "IPTU", IPTU_MINIMO, IPTU_MAXIMO)):
        taxa = campos.get(campo)
        if taxa is None:
            continue
        if taxa < minimo:
            avisar(campo, f"{nome} de R$ {_reais(taxa, 2)} é baixo demais para"
                          f" ser real -- o piso do nosso catálogo é"
                          f" R$ {_reais(minimo)}, e valor simbólico costuma ser"
                          " campo pulado, igual ao 'R$ 0'.")
        elif taxa > maximo:
            preco_do_imovel = venda or aluguel
            comparacao = ""
            if preco_do_imovel and taxa >= preco_do_imovel:
                # É o caso medido: `condominio` e `iptu` iguais ao preço.
                comparacao = (" -- é o MESMO valor do imóvel ou mais, sinal de"
                              " que o anunciante repetiu o preço no campo errado")
            avisar(campo, f"{nome} de R$ {_reais(taxa, 2)} passa de"
                          f" R$ {_reais(maximo)}, que é muito acima de qualquer"
                          f" {nome} do nosso catálogo{comparacao}.")

    achado_suite = re.search(r"(\d+)\s*suite", texto_livre)
    if achado_suite:
        avisar("suites", f"o texto do anúncio fala em {achado_suite.group(1)}"
                         " suíte(s), mas a OLX não tem esse campo -- confirme"
                         " com o proprietário antes de gravar.")
    elif "suite" in texto_livre:
        avisar("suites", "o texto do anúncio menciona suíte sem dizer quantas"
                         " -- confirme com o proprietário.")

    # --- 8. mobília: um só rótulo na OLX, três níveis no nosso cadastro ----
    if campos.get("mobilia"):
        avisar("mobilia",
               f"a OLX tem um único \"Mobiliado\" e nós temos três níveis:"
               f" ficou {campos['mobilia']!r} -- confirme o nível.")
    else:
        itens = _chave(campos_olx.get("re_features"))
        if "ar condicionado" in itens:
            avisar("mobilia",
                   "o anúncio marca ar-condicionado e não marca mobiliado --"
                   f" pode ser {MOBILIA_SO_AR!r}, mas isso não foi afirmado.")

    # --- 9. o anúncio inteiro ---------------------------------------------
    municipio = _chave(dados_olx.get("municipio"))
    if municipio and municipio != "manaus":
        avisar(None, f"o anúncio é de {dados_olx.get('municipio')!r}, fora de"
                     " Manaus -- confira se é da nossa área.")

    # `str()` pelo mesmo motivo de `_texto_livre`: a descrição vem crua do
    # JSON da OLX, e `re.search` num int levanta TypeError aqui dentro.
    descricao = str(dados_olx.get("descricao") or "")
    tem_contato = bool(_TELEFONE.search(descricao)) or any(
        palavra in _chave(descricao) for palavra in _CHAMADA_DE_CONTATO)
    if tem_contato:
        avisar("descricao",
               "a descrição do anúncio parece trazer telefone ou pedido de"
               " contato do proprietário -- tirar antes de publicar, senão o"
               " corretor fala direto com o dono.")

    if not dados_olx.get("fotos"):
        avisar(None, "o anúncio não trouxe nenhuma foto.")

    return achados
