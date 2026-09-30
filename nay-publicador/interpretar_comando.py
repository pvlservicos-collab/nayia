"""
Doc 28, passo 8: interpreta o comando do Tel em linguagem natural e
devolve uma descrição estruturada da operação -- nunca decide sozinho o
que fazer com texto que não bate em nenhum padrão conhecido.

Parser estruturado por peça (ação, códigos, dias, horário), não regex
único tentando casar a frase inteira. Cada peça é extraída e validada
separadamente, o que é o que dá a "folga de variação de escrita" sem
virar interpretação livre: variações de maiúscula, acento, espaçamento
e sinônimo de dia da semana são toleradas; o vocativo "Nay" no começo da
frase é descartado antes de tudo (VOCATIVO_RE); qualquer coisa fora dos
padrões reconhecidos cai em 'nao_reconhecido', explicitamente.

Um limite que o vocativo torna mais fácil de encostar, nomeado aqui de
propósito: descartado o "Nay", QUALQUER frase que comece com um dos
verbos e tenha um número vira envio real. "Nay, solta essa foto do 5750
pra mim ver" posta o 5750 nos grupos. A fronteira de palavra do
POSTAR_RE cobre a classe dos falsos positivos gramaticais ("publicamos",
"postaram"), mas não cobre o uso conversacional de um verbo legítimo --
pra isso a rede seria uma confirmação antes do envio, que não existe.

Devolve sempre um dict com 'acao':
  {'acao': 'postar_agora', 'codigos': [...]}
  {'acao': 'criar_vaga', 'tipo_recorrencia': 'diaria', 'horario': time, 'codigos': [...],
   'destino': None|'easy'|'alto_padrao'|'comercial'}
  {'acao': 'criar_vaga', 'tipo_recorrencia': 'semanal', 'horario': time,
   'dias_semana': [...], 'codigos': [...]}          # convenção Postgres, 0=domingo
  {'acao': 'liberar_vaga', 'codigo': '...', 'motivo': 'vendido'|'alugado'}
  {'acao': 'remover_da_grade', 'codigo': '...'}  # tira/remove -- só reorganiza horário
  {'acao': 'marcar_taxa', 'codigo': '...', 'incluso': True|False}
  {'acao': 'listar_categoria', 'categoria': '...', 'negocio': 'locacao'|'venda'}
  {'acao': 'disparar_lista', 'categoria': '...', 'negocio': '...',
   'destino': 'parceiros'|'easy'|'comercial'}
  {'acao': 'agendar_lista', 'categoria': '...', 'negocio': '...',
   'destino': '...', 'horario': 'HH:MM', 'tipo_recorrencia': '...'}
  {'acao': 'remover_lista_da_grade', 'categoria': '...', 'negocio': '...'}
  {'acao': 'listar_vagas'}
  {'acao': 'agenda_de_visitas'}
  {'acao': 'postar_easy', 'codigo': '...'}
  {'acao': 'nao_reconhecido', 'texto': '...'}
"""
import datetime
import re

CODIGO_RE = re.compile(r"\b\d{1,6}\b")

# O Tel fala com a Nay pelo WhatsApp, então chama ela pelo nome antes do
# comando -- "Nay posta o 2943" (caso real de 27/08, que não funcionou).
# Todos os caminhos daqui são ancorados em ^, então o vocativo empurrava
# a frase inteira pra nao_reconhecido: posta, VENDEU, tira e VAGAS
# morriam. Só o Easy escapava, porque EASY_RE usa search em vez de match.
#
# Whitelist literal e fechada de propósito -- só "nay", uma vez, no
# começo, com @ opcional (menção) e a pontuação que vier logo depois. O
# \b é o que impede "Nayara"/"Naiara"/"Naysa" de virarem comando. NÃO
# cobre "oi Nay posta ...", apelido, nem menção por número: isso seria
# adivinhar, e este parser não adivinha (docstring acima). Se o Tel
# escrever assim algum dia, a resposta de nao_reconhecido já lista os
# exemplos que funcionam e serve de aviso barato.
VOCATIVO_RE = re.compile(r"^@?nay\b[\s,:;.!-]*", re.IGNORECASE)

# hora: "14h", "14h30", "14:00", "14 horas", "9 e meia", "meio-dia", "meia-noite"
HORA_RE = re.compile(
    r"\b(?P<hm>\d{1,2})\s?(?:h|hr|hrs|hs)(?P<hm_min>\d{2})?\b"
    r"|\b(?P<hm2>\d{1,2}):(?P<hm2_min>\d{2})\b"
    r"|\b(?P<horas>\d{1,2})\s+horas?\b"
    r"|\b(?P<meia>\d{1,2})\s+e\s+meia\b"
    r"|\b(?P<meiodia>meio[\s-]?dia)\b"
    r"|\b(?P<meianoite>meia[\s-]?noite)\b"
    # "as 8 da manhã", "as 7 da noite", "as 2 da tarde" (Tel, 27/09: ele pediu
    # variantes). Vem POR ÚLTIMO na alternância: as formas com "h" ou ":" são
    # mais específicas e têm que ganhar. Sem período explícito nada muda --
    # "as 8" sozinho continua fora, porque 8h e 20h são duas coisas.
    r"|\b(?P<periodo>\d{1,2})\s*(?:h|hr|hrs|hs)?\s+(?:da|de)\s+"
    r"(?P<periodo_qual>manh[ãa]|tarde|noite)\b",
    re.IGNORECASE,
)

# "as 08" -- A HORA SEM O "h" (Tel, 27/09: "posta 5713 no grupo lotado
# segunda, quarta e sexta as 08"). Fora de contexto ela é perigosa: "envia as
# 2 casas" viraria 2h, e "os 2" é a resposta de desambiguação de 12/09. Por
# isso ela NÃO entra no `HORA_RE` -- é consultada só como último recurso, e só
# quando a frase JÁ fala de agenda (tem dia da semana ou "todo dia"), onde um
# número depois de "as" não tem outra leitura.
#
# 0 a 23 apenas, e `(?![:\d])` para não morder a primeira metade de "08:00" --
# aquela o `HORA_RE` já lê, e lê melhor.
HORA_SOLTA_RE = re.compile(
    r"\b[àa]s?\s+(?P<solta>[01]?\d|2[0-3])\s*(?:h|hs|hr|hrs)?\b(?![:\d])",
    re.IGNORECASE)

# verbo de postar: qualquer texto que comece com um destes
VERBOS_POSTAR = ("posta", "postar", "publica", "publicar", "solta", "dispara", "disparar")

# Casa com FRONTEIRA de palavra, não com prefixo solto. Antes isto era
# um str.startswith(VERBOS_POSTAR), que não sabe onde a palavra termina:
# "postagem", "postado", "postaram", "publicamos", "publicado",
# "soltaram" e até "disparate" contavam como verbo de postar.
#
# Isso era inofensivo enquanto o vocativo travava a frase toda em
# nao_reconhecido. No instante em que VOCATIVO_RE passou a descartar o
# "Nay", "Nay, publicamos o 5750 ontem?" -- uma PERGUNTA -- viraria
# postar_agora e sairia de verdade em 9 grupos de corretor. Mensagem de
# WhatsApp não tem desfazer; a fronteira tinha que entrar no mesmo
# commit que o vocativo, não depois.
POSTAR_RE = re.compile(r"^(" + "|".join(VERBOS_POSTAR) + r")\b")

AGENDA_VISITAS_RE = re.compile(
    r"^agenda\s+de\s+visitas?"
    r"|^visitas?\s+agendadas?"
    r"|^visitas?\s+do\s+dia"
    r"|^visitas?\s+de\s+hoje"
    r"|^agenda$",
    re.IGNORECASE,
)

# verbo de liberar vaga: VENDEU/VENDIDO/VENDIDA, ALUGOU/ALUGADO/ALUGADA
VERBOS_LIBERAR = ("vendeu", "vendido", "vendida", "alugou", "alugado", "alugada")
LIBERAR_RE = re.compile(r"^(" + "|".join(VERBOS_LIBERAR) + r")\b\s*(.*)")

# A MESMA COISA COM O CÓDIGO NA FRENTE: "5712 Alugado". Pedido do Tel em
# 09/09 -- é como ele escreve quando está olhando a grade, que agora lista
# código primeiro. Tolera o que ele põe no meio ("5712 - alugado",
# "5712 ja alugou", "5712: vendido").
#
# O código vem PRIMEIRO e sozinho: `^\d{3,5}` e nada de dígito antes, senão
# "posta 5712 alugado" cairia aqui em vez do caminho de postar.
LIBERAR_CODIGO_RE = re.compile(
    r"^(\d{3,5})\s*[-–—:,]?\s*(?:ja|já)?\s*(" + "|".join(VERBOS_LIBERAR) + r")\b")


# "5729 incluso a tx" -- a taxa de condomínio já está no aluguel.
#
# POR QUE ISTO PRECISOU DE COMANDO (09/09): o site NÃO publica esse dado em
# lugar nenhum -- conferido no HTML inteiro do 5729, nem o rótulo "Taxa de
# Condomínio" existe lá. Ele veio da importação de agosto, então dos 182
# imóveis de locação disponíveis só 92 têm a informação, e os que faltam são
# exatamente os RECENTES. Sem um jeito de marcar, todo imóvel novo entra sem.
#
# O código vem primeiro, igual ao "5712 Alugado" -- é como o Tel escreve
# olhando a grade.
#
# POR QUE OLHAR A FRASE INTEIRA e não a ordem das palavras: a primeira versão
# exigia a negação colada ("sem tx") e errou os dois casos que mais importam --
# "5729 sem a tx" não era reconhecido e "5729 tx nao inclusa" era lido como
# INCLUSA, o oposto. Errar para o lado do "incluso" faz o corretor levar
# cliente com a conta errada.
TAXA_CODIGO_RE = re.compile(r"^(\d{3,5})\s*[-–—:,]?\s*([^\d]{2,40})$")
_FALA_DE_TAXA = re.compile(r"\b(tx|taxa|condominio|condomínio|cond)\b")
_FALA_DE_INCLUSAO = re.compile(r"\b(inclus[ao]|inclu[íi]d[ao]|inclui)\b")
_NEGA = re.compile(r"\b(nao|não|sem)\b")


# "Nay lista de apartamento para locação". Pedido do Tel em 09/09.
#
# As categorias saem do jeito que ele fala, não do jeito que o cadastro
# escreve: "casa de condomínio", "casa de via pública", "salas comerciais".
# Cada uma casa por PALAVRA-CHAVE e a ordem importa -- "casa de condomínio"
# precisa ser testada antes de "casa", senão vira via pública.
LISTA_RE = re.compile(r"^lista\s+(?:de\s+|dos\s+|das\s+)?(.+)$")

# "Nay dispara lista de apartamento para locação" -- a mesma lista, mas
# MANDADA para os grupos. Pedido do Tel em 09/09.
#
# TEM QUE SER TESTADO ANTES DO `POSTAR_RE`: "dispara" é verbo de postar, então
# sem esta guarda "dispara lista de apartamento" cairia no caminho de postar
# imóvel e viraria "não entendi" -- ou pior, procuraria código na frase.
#
# A PALAVRA "LISTA" É OPCIONAL desde 09/09 (tarde). Eu montei esta gramática a
# partir da frase que ele escreveu aqui ("dispara lista de apartamento para
# locação") e exigi "lista"; no WhatsApp ele escreveu **"dispara apartamentos
# para locação no anunciar easy"** e ouviu "não entendi". Exemplo escrito não é
# o jeito de falar.
DISPARAR_LISTA_RE = re.compile(
    r"^(?:dispar[ae]r?|post[ae]r?|publica[r]?|manda[r]?|envia[r]?|solta[r]?)\s+"
    r"(?:as?\s+|os?\s+)?(lista\b\s*(?:de\s+|dos\s+|das\s+)?)?(.*)$")

# SEM a palavra "lista", só estes substantivos abrem o caminho. O `_CATEGORIAS`
# é frouxo de propósito -- "conjunto", "comercial" e "loja" caem em `sala`, e
# ali isso é bom, porque quem escreveu "lista" já disse o que quer. Sem
# "lista", frouxo viraria disparo em 13 grupos por causa de um "conjunto"
# no meio de uma frase.
_SUBSTANTIVO_DE_CATEGORIA = re.compile(
    r"\b(apartamentos?|aptos?|coberturas?|flats?|casas?|sobrados?|"
    r"salas?\s+comerciais?|salas?|lojas?|lotes?|terrenos?)\b")

# "no anunciar easy", "no easy", "no grupo do easy".
_FALA_DO_EASY = re.compile(r"\beasy\b")

# Para o TIRA saber que é a lista, e não um imóvel.
_FALA_DE_LISTA = re.compile(r"\blistas?\b")

# Repetir o disparo é pedido legítimo -- é como ele passa por cima da trava de
# repetição. Sem uma frase de escape a trava viraria parede definitiva.
# Cauda que é negócio, não gente: "...para locação", "...para venda". Sem
# isto a parede de pessoa recusaria o comando que o Tel escreveu.
_CAUDA_DE_LISTA_RE = re.compile(
    r"\b(loca[çc][ãa]o|locacao|alug\w*|venda|vender|vendas|compra|"
    r"parceiros?|corretores?|nós|nos)\b", re.IGNORECASE)

_DE_NOVO = re.compile(r"\bde\s*novo\b|\bnovamente\b|\bmesmo\s+assim\b|"
                      r"\bde\s+qualquer\s+(?:jeito|forma)\b|\brepete\b|"
                      r"\brepetir\b|\bmanda\s+de\s+novo\b|\bfor[çc]a\b")

_CATEGORIAS = (
    # (categoria, regex do que ele escreve)
    ("sala",                   r"sala|comercial|loja|conjunto"),
    ("casa_condominio",        r"casa.*condom|condom.*casa"),
    ("casa_via_publica",       r"casa.*(via\s*p[úu]blica|rua|avulsa)|"
                               r"(via\s*p[úu]blica|rua).*casa"),
    ("apartamento_via_publica", r"(apart|ap\b|apto).*(via\s*p[úu]blica|rua)"),
    ("apartamento",            r"apart|apto|\bap\b|cobertura|flat"),
    ("lote",                   r"lote|terreno"),
    # "casa" sozinho, depois de todas as formas específicas
    ("casa_via_publica",       r"casa|sobrado"),
)


# Como CHAMAR cada categoria quando for preciso perguntar. Fica colado em
# `_CATEGORIAS` de propósito: quem acrescentar uma categoria vê na mesma tela
# o nome que a pergunta oferece -- senão a pergunta envelhece calada.
NOME_DA_CATEGORIA = {
    "apartamento": "apartamento",
    "apartamento_via_publica": "apartamento em via pública",
    "casa_condominio": "casa em condomínio",
    "casa_via_publica": "casa em via pública",
    "sala": "sala comercial",
    "lote": "lote",
}
NOMES_DE_CATEGORIA = tuple(NOME_DA_CATEGORIA.values())

# O NEGÓCIO TEM QUE ESTAR ESCRITO. Pedido do Tel em 09/09: *"quando eu mandar
# assim ela tem que me perguntar se é para venda ou locação"*. Antes, "Nay
# lista de apartamentos" devolvia a de locação calada -- e a de venda, que ele
# também precisa, ele nunca receberia sem saber que faltava uma palavra.
#
# As duas formas que ele usa: com e sem o "para" ("para locação", "locação").
# Por isso não se exige preposição nenhuma -- basta a palavra aparecer.
_FALA_DE_VENDA = re.compile(
    r"\bvend[ae]s?\b|\bvender\b|\bcompra\b|\bcomprar\b|\bvendido\b")
# O PLURAL CONTA (15/09). "locações" -- e "locacoes", que é como chega depois
# do `sem_acento` do pedido descrito -- não casava `loca[çc][ãa]o\b`, e o pedido
# "todas as locações no bairro X" ficava SEM negócio. Medido no pedido que o Tel
# mandou para a Nay e ela não soube responder.
_FALA_DE_LOCACAO = re.compile(
    r"\bloca[çc][ãaoõ]\w*\b|\balug\w*\b|\barrend\w*\b|\blocar\b")


def _categoria_e_negocio(resto):
    """A categoria e o negócio que o Tel escreveu depois da palavra "lista".

    UM LUGAR SÓ, lido pelo comando que MOSTRA a lista e pelo que a DISPARA nos
    grupos. Duas cópias desta leitura divergiriam sozinhas -- é o padrão 4.3 do
    HISTORICO, e aqui a divergência mandaria para 13 grupos uma lista diferente
    da que ele conferiu na tela.

    O NEGÓCIO VOLTA NULO QUANDO ELE NÃO DISSE, e quem chama PERGUNTA. Não
    existe padrão: escolher locação calado fazia a lista de venda -- que ele
    também usa -- nunca chegar, e ele não tinha como saber que faltava uma
    palavra. Falar dos dois ("venda e locação") também é nulo: duas listas
    diferentes, e supor qual seria escolher por ele.
    """
    quer_venda = bool(_FALA_DE_VENDA.search(resto))
    quer_locacao = bool(_FALA_DE_LOCACAO.search(resto))
    if quer_venda and not quer_locacao:
        negocio = "venda"
    elif quer_locacao and not quer_venda:
        negocio = "locacao"
    else:
        negocio = None

    for categoria, padrao in _CATEGORIAS:
        if re.search(padrao, resto):
            return categoria, negocio
    return None, negocio


def _interpretar_disparo_de_lista(texto):
    """"Nay dispara lista de apartamento para locação".

    O DESTINO PADRÃO são os grupos de parceiros, que é o que ele já faz hoje.
    Mencionar "easy" manda só para o grupo de todas as fotos.

    SEM CATEGORIA NÃO DISPARA -- devolve `categoria: None`, e o publicador
    pergunta em vez de escolher. O segundo exemplo dele ("dispara lista no
    imóveis para anunciar easy") não diz qual lista, e adivinhar aqui manda
    texto para até 13 grupos sem nenhum desfazer.
    """
    m = DISPARAR_LISTA_RE.match(texto)
    if not m:
        return None
    disse_lista = bool(m.group(1))
    resto = m.group(2)

    # HORA NA FRASE = ele quer a lista TODO DIA, não agora. Pedido do Tel em
    # 10/09: *"preciso disparar a lista de imóveis todo dia, tem essa função?"*
    # -- a grade só sabia guardar código de imóvel.
    m_hora = HORA_RE.search(resto)

    # A HORA SAI ANTES DE PROCURAR CÓDIGO. `CODIGO_RE` aceita 2 dígitos, então
    # "as 08:00" virava os "códigos" 08 e 00 e a frase inteira era descartada
    # como se falasse de um imóvel. É a mesma lição que o caminho de imóvel já
    # trazia escrita: a hora é o único trecho com dígito que não é código.
    sem_hora = (resto[:m_hora.start()] + " " + resto[m_hora.end():]
                if m_hora else resto)

    # CÓDIGO NA FRASE = é sobre UM IMÓVEL, não sobre uma categoria. "posta a
    # casa 5750" tem a palavra "casa" e não é lista nenhuma; sem esta guarda o
    # comando que ele mais usa viraria disparo de lista.
    if CODIGO_RE.search(sem_hora):
        return None

    # Sem "lista" e sem substantivo de categoria não é este comando -- deixa o
    # caminho antigo decidir, que é quem sabe ler código, vaga e envio privado.
    if not disse_lista and not _SUBSTANTIVO_DE_CATEGORIA.search(resto):
        return None

    # VALOR ESCRITO NÃO É LISTA DE CATEGORIA (15/09). "Nay envia casa para
    # venda de 250k a 600k" caía aqui e virava disparo da lista INTEIRA de
    # casas para venda em todos os grupos parceiros -- com a faixa de valor
    # ignorada, porque a lista da categoria só conhece o piso do GRUPO.
    #
    # Filtro de valor é pedido de imóveis específicos, e pedido tem
    # destinatário. Sai daqui e deixa o caminho do envio decidir -- que hoje
    # responde "para quem?" quando ele esquece de dizer.
    if _cauda_e_pedido(resto):
        return None

    # PESSOA NA CAUDA NÃO DISPARA. "Nay envia a lista de apartamento pro
    # Sergio" é pedido plausível, e sem esta parede ele mandaria a lista para
    # 13 grupos -- o mesmo erro que a recusa do `Nay posta o 5750 pro Rogério`
    # já evita desde 31/08, com o mesmo custo: postagem em grupo não desfaz.
    m_envio = ENVIO_RE.match(texto)
    if m_envio:
        cauda = m_envio.group(3)
        if not CAUDA_NAO_E_PESSOA_RE.search(cauda) \
                and not _CAUDA_DE_LISTA_RE.search(cauda):
            return {"acao": "envio_recusado", "motivo": (
                f'"{cauda.strip()}" parece uma pessoa, e a lista eu só sei '
                f'mandar para os grupos -- não disparei nada. Se você quer '
                f'ver a lista aqui, é "Nay lista de <categoria> para locação"; '
                f'para mandar nos grupos, "Nay dispara lista de <categoria> '
                f'para locação".')}

    categoria, negocio = _categoria_e_negocio(resto)
    destino = _destino_da_lista(resto)

    if m_hora:
        recorrencia = _recorrencia_do_trecho(sem_hora)
        if not recorrencia:
            # Fala de horário e não deu para entender quando: NÃO agenda e
            # NÃO dispara agora. Adivinhar aqui criaria uma vaga que manda a
            # lista em 13 grupos todo dia, e ele só descobriria depois.
            return {"acao": "agenda_incompleta", "texto": texto}
        return {"acao": "agendar_lista", "categoria": categoria,
                "negocio": negocio, "destino": destino,
                "horario": _horario_do_match(m_hora), **recorrencia}

    return {"acao": "disparar_lista", "categoria": categoria,
            "negocio": negocio, "destino": destino,
            "de_novo": bool(_DE_NOVO.search(resto))}



def _destino_da_lista(trecho):
    """Para qual leva de grupos vai a lista: 'easy', 'comercial' ou 'parceiros'.

    Era um `if` de duas saídas repetido em três lugares (disparo, agendamento
    e o TIRA da grade). Com a chegada do Comercial (27/09) viraria o mesmo
    `if` de TRÊS saídas em três lugares -- e destino que diverge entre agendar
    e tirar deixa vaga que não se consegue mais apagar, porque o DELETE casa
    por `destino`.

    O COMERCIAL VEM ANTES DO EASY: "posta lista de sala comercial no grupo
    comercial do easy" não existe, mas se existisse o grupo dito por último é
    o que ele nomeou, e o Comercial é o específico.
    """
    if COMERCIAL_GRUPO_RE.search(trecho):
        return "comercial"
    return "easy" if _FALA_DO_EASY.search(trecho) else "parceiros"


def _interpretar_lista(texto):
    """Devolve o comando de lista, ou None."""
    m = LISTA_RE.match(texto)
    if not m:
        return None
    categoria, negocio = _categoria_e_negocio(m.group(1))
    if not categoria:
        return None
    return {"acao": "listar_categoria", "categoria": categoria,
            "negocio": negocio}


def _interpretar_taxa(texto):
    r"""Devolve o comando de taxa inclusa, ou None quando não é isso.

    A NEGATIVA existe porque o Tel precisa poder DESFAZER: marcar taxa inclusa
    num imóvel que não tem faz o corretor levar cliente com a conta errada, e
    sem isso não haveria como corrigir sem alguém entrar no banco.

    O `[^\d]` no resto da frase é parede: "5729 taxa 450" NÃO é este comando --
    é alguém informando o valor da taxa, que é outra coisa.
    """
    m = TAXA_CODIGO_RE.match(texto)
    if not m:
        return None
    resto = m.group(2)
    if not _FALA_DE_TAXA.search(resto):
        return None
    nega = bool(_NEGA.search(resto))
    if not _FALA_DE_INCLUSAO.search(resto) and not nega:
        return None
    return {"acao": "marcar_taxa", "codigo": m.group(1), "incluso": not nega}


def _motivo_do_verbo(verbo):
    """"alugou"/"alugado"/"alugada" viram 'alugado'; o resto, 'vendido'.

    O motivo não é enfeite: é ele que decide a palavra do aviso que vai para
    o grupo, e dizer "vendido" de um imóvel alugado é erro que sai para
    dezenas de corretores sem desfazer."""
    return "alugado" if verbo.startswith("alug") else "vendido"

# verbo de tirar da grade: TIRA/TIRAR, REMOVE/REMOVER. Faz na tabela
# exatamente o mesmo que VERBOS_LIBERAR (tira o código das vagas), mas
# é uma ação separada de propósito: "vendeu"/"alugou" vai ganhar
# significado real no futuro (marcar vendido no site), então não pode
# ser usado só pra reorganizar horário.
VERBOS_REMOVER = ("tira", "tirar", "remove", "remover")
REMOVER_RE = re.compile(r"^(" + "|".join(VERBOS_REMOVER) + r")\b\s*(.*)")

# comando dedicado do grupo "IMÓVEIS PARA ANUNCIAR EASY": as duas
# palavras em qualquer ordem, em qualquer lugar do texto, tolerando o
# que vier no meio ("no nosso grupo anunciar easy código X",
# "anunciar no easy o X", etc.)
EASY_RE = re.compile(r"\banunciar\b.*\beasy\b|\beasy\b.*\banunciar\b", re.IGNORECASE | re.DOTALL)

# O GRUPO "IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY" (Tel, 25/09).
#
# "esse grupo foi criado só para enviar imóvel alto padrão para alguns
# corretores, eles anunciam esses imóveis que vamos colocar lá. quando o
# comando for: Nay envia para o grupo alto padrão 4567, ela só vai enviar
# este imóvel que pedir".
#
# DUAS MARCAS SÃO EXIGIDAS, "alto padrão" E uma de grupo/easy/anunciar, e a
# segunda não é enfeite: sem ela, "Nay envia o 5750 pro corretor do alto
# padrão" -- uma PESSOA -- viraria postagem num grupo de 11 corretores, e
# postagem em grupo não desfaz. Com a exigência, essa frase segue para o
# ENVIO_RE e vira envio privado (ou recusa), que é o certo.
# O GRUPO "🟢 Comercial - OFERTA e BUSCA 🔍" (Tel, 27/09).
#
# "posta no grupo comercial 5763 (desta forma manda no grupo)". Medido antes
# de escrever: essa frase virava `postar_agora` e o "no grupo comercial" era
# IGNORADO -- o imóvel saía em TODOS os grupos elegíveis.
#
# DUAS MARCAS SÃO EXIGIDAS, como no alto padrão, e pelo mesmo motivo: sem a
# marca de grupo, "posta o 5763 para o corretor comercial" -- uma PESSOA --
# viraria postagem em grupo, e postagem em grupo não desfaz. Com a exigência,
# a frase segue para o ENVIO_RE e vira envio privado, que é o certo.
#
# E "sala comercial" NÃO basta: "posta lista de sala comercial" fala do TIPO
# do imóvel, não do grupo. Por isso a marca de grupo tem que estar colada em
# "comercial" -- "no grupo comercial", "no comercial".
# O VERBO que abre um comando de GRUPO. O `POSTAR_RE` sozinho não bastava:
# ele conhece posta/publica/solta/dispara, e o Tel também escreve "manda no
# grupo comercial o 5763" e "envia para o grupo comercial" -- é como ele já
# fala com o Alto Padrão. Quem impede isso de roubar um envio a PESSOA é o
# `COMERCIAL_GRUPO_RE`, que exige o grupo nomeado colado à preposição:
# "para o corretor comercial" tem "corretor" no meio e não casa.
_VERBO_DE_GRUPO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?:post|public|solt|dispar|envi|m[a]?nd|repass|encaminh)\w*\b",
    re.IGNORECASE)

# OS QUATRO GRUPOS DE MAIOR MOVIMENTO, sob um apelido só (Tel, 27/09): o
# "📍CREDENCIADOS | Corretores Performance", o "Top imóveis venda e aluguéis",
# o "Novos Negócios Imobiliários - AM" e o "FECHANDO PARCERIAS 1.0". Ele os
# chamou de "grupo lotado"; "movimentado" entra junto porque foi a palavra com
# que ele descreveu a ideia ("o movimento é maior").
#
# Mesma forma do `COMERCIAL_GRUPO_RE`: o grupo tem que vir COLADO à
# preposição. É o que impede "manda o 5713 pro corretor do grupo lotado" --
# uma pessoa -- de virar postagem em quatro grupos.
LOTADO_GRUPO_RE = re.compile(
    r"\b(?:nos?|pros?|para\s+os?|aos?)\s+(?:grupos?\s+)?"
    r"(?:lotad|movimentad)[oa]s?\b"
    r"|\bgrupos?\s+(?:lotad|movimentad)[oa]s?\b",
    re.IGNORECASE)

COMERCIAL_GRUPO_RE = re.compile(
    r"\b(?:no|pro|para\s+o|ao)\s+(?:grupo\s+)?comercial\b"
    r"|\bgrupo\s+comercial\b",
    re.IGNORECASE)

# O ESCAPE da recusa por faixa. A frase que ela devolve na recusa ensina esta
# resposta, e a lição de 12/09 é que TODA frase que a Nay escreve faz parte da
# gramática -- lá ela perguntou "ou os dois?", ele copiou "os dois" e a
# resposta caiu no agente, porque o parser não lia a própria pergunta dela.
FORCAR_ALTO_PADRAO_RE = re.compile(
    r"\b(?:mesmo\s+assim|assim\s+mesmo|confirmo|pode\s+postar\s+mesmo|"
    r"[ée]\s+alto\s+padr[aã]o\s+sim|manda\s+assim\s+mesmo)\b",
    re.IGNORECASE)

_ALTO_PADRAO = r"\balto[\s\-]*padr[aã]o\b"

# DOIS GRUPOS SE CHAMAM "ALTO PADRÃO", e a diferença entre eles é qual recebe
# (27/09):
#
#   🟢 Alto Padrão - OFERTA e BUSCA 🔍      uma foto, só condomínio
#   IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY  todas as fotos
#
# Até hoje "no grupo alto padrão" ia para o de ANUNCIAR EASY, e o de OFERTA e
# BUSCA não tinha comando nenhum. O Tel pediu o segundo e escolheu a
# separação: **"alto padrão" passa a ser o OFERTA e BUSCA**, e o de Anunciar
# Easy exige dizer "anunciar" ou "easy". Foi decisão dele, perguntada porque
# postagem em grupo não desfaz e as duas leituras eram plausíveis.
_ANUNCIAR_EASY = r"\b(?:easy|anunciar)\b"
ALTO_PADRAO_EASY_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?:envi|m[a]?n+d|post|public|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b"
    r"(?=[\s\S]*" + _ALTO_PADRAO + r")"
    r"(?=[\s\S]*" + _ANUNCIAR_EASY + r")",
    re.IGNORECASE)

# E O OFERTA e BUSCA: "no grupo alto padrão" ou "no grupo padrão" -- ele
# escreveu as duas, quatro das cinco frases sem o "alto". O `\s+` cobre o
# espaço duplo que o WhatsApp dele manda ("no grupo  padrão").
#
# Vem DEPOIS do `ALTO_PADRAO_EASY_RE` no dispatch, e a ordem é a regra: quem
# diz "easy" ou "anunciar" está falando do outro grupo, e o específico ganha.
_PADRAO_GRUPO = (r"\b(?:nos?|pros?|para\s+os?|aos?)\s+(?:grupos?\s+)?"
                 r"(?:alto[\s\-]*)?padr[aã]o\b"
                 r"|\bgrupos?\s+(?:alto[\s\-]*)?padr[aã]o\b")
ALTO_PADRAO_BUSCA_RE = re.compile(_PADRAO_GRUPO, re.IGNORECASE)

# ENVIO PRIVADO: "Nay manda o 5750 pro Sergio". O Tel pediu isto em 31/08
# depois de tres tentativas frustradas de mandar imoveis ao Gustavo -- nao
# existia caminho nenhum para enviar imovel a um corretor sem ele escrever
# primeiro, e eu cheguei a redigir uma promessa que o mecanismo nao cumpria.
#
# A PREPOSICAO E OBRIGATORIA e e ela que separa isto de `posta` (que vai
# para os 14 grupos). "Nay posta o 5750" nao casa; "Nay posta o 5750 pro
# Rogerio" casa e e RECUSADO com explicacao, porque `posta` nao manda para
# uma pessoa.
#
# O corpo e GULOSO de proposito: em "manda todos os acquarelle para locacao
# para o Sergio" o preguicoso pararia na primeira preposicao e o destino
# viraria "locacao para o Sergio".
#
# Este literal vive em QUATRO lugares (o Python aqui, e tres nos do n8n:
# `Comando do Tel`, `Rotear para o agente` e `Achar codigo na resposta`).
# O quarto e o menos obvio: sem ele, "Nay envia as FOTOS do 5750 pro
# Sergio" faz o gatilho de fotos ler o texto do proprio Tel e mandar as
# fotos para o chat DELE.
ENVIO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)"
    r"(?:a|ar|e|ei|ou|o)?\b"
    r"([\s\S]*)"
    r"(?:\bpara\b|\bpra\b|\bpro\b|\bp/)"
    r"\s*([\s\S]+?)\s*$",
    re.IGNORECASE,
)

# TELEFONE NA FRENTE, SEM PREPOSICAO: "envia (92) 98478-7190 o 3210".
#
# O CASO (Tel, 23/09): ele escreveu exatamente isso, a frase nao casou o
# `ENVIO_RE` -- que EXIGE "para/pra/pro" -- e foi parar no AGENTE, que
# escalou de volta para ele: "perguntou uma coisa que eu ainda nao sei
# responder". O imovel nao saiu, e ele so descobriu porque leu a resposta.
#
# A PREPOSICAO NAO PODE SER AFROUXADA no `ENVIO_RE`: e ela que separa o envio
# privado do `posta`, que vai para os 19 grupos. Entao esta forma ganha regex
# PROPRIA, e ela e estreita de proposito -- so vale com TELEFONE, que e
# inequivoco. Com nome ("envia Sergio o 3210") continuaria sem casar, porque
# "envia Sergio" e "envia [para] Sergio" nao se distinguem de "envia [o] 3210
# [para] Sergio" sem adivinhar.
#
# O telefone tem 10 ou 11 digitos depois de tirar pontuacao (com ou sem o 9),
# e o codigo tem 3 a 5 -- e por isso os dois nao se confundem.
ENVIO_TELEFONE_NA_FRENTE_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(envi|m[a]?nd|repass|encaminh)(?:a|ar|e|ei|ou|o)?\b\s*"
    r"(?:para\s+|pra\s+|pro\s+|p/\s*)?"          # a preposicao e OPCIONAL aqui
    # O `55` na frente e opcional: e a forma que o banco guarda
    # (`5592994629241`) e que ele as vezes cola de volta. Sem ele, o "55" era
    # lido como DDD e sobrava "41" no fim -- que viraria o codigo 41.
    r"(?P<tel>(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4})"
    r"\s+(?P<corpo>"
    # COM a palavra "codigo": 2 a 5 digitos. O catalogo tem um imovel de dois
    # digitos (o 45, Apartamento na Compensa) e 14 de tres. Palavra do Tel em
    # 23/09: "o codigo e 150 tem vezes que pode ser ate 2 numeros".
    r"c[oó]d(?:igo)?s?\b[\s:=.-]*\d{2,5}"
    r"(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{2,5})*"
    r"|"
    # SEM ela, o minimo continua sendo TRES. "os 2" quer dizer "os dois" --
    # e a forma que desempata a lista, documentada em 12/09 -- e com dois
    # digitos livres ela viraria o imovel 2. O marcador e o que paga a
    # licenca de descer para dois.
    r"(?:o|os|a|as)?\s*\d{3,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{3,5})*"
    r")\s*$",
    re.IGNORECASE,
)

# O marcador "codigo" na frente do numero. E o que libera dois digitos.
MARCADOR_CODIGO_RE = re.compile(r"^\s*c[oó]d(?:igo)?s?\b", re.IGNORECASE)

# "Nay codigo 5719" -- ele respondendo a pergunta de desambiguacao. A forma
# com a palavra "codigo" na frente e do Tel (11/09) e e a unica que nao
# colide: o codigo puro ("5719") ja cai no ramo `Achar codigo` do n8n, que
# manda o card e TODAS as fotos para o chat dele mesmo.
ESCOLHER_CODIGO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?:c[óo]digos?|cods?)\b[\s:=-]*"
    r"((?:\d{3,5}[\s,;]*(?:e\s+)?)+)$",
    re.IGNORECASE,
)

# AS RESPOSTAS NATURAIS a "qual desses?" -- a licao de 12/09.
#
# Ele respondeu **"os dois"** e a frase caiu no AGENTE de IA, que devolveu uma
# lista de imoveis sem nexo. O pior: a PROPRIA pergunta dela dizia "ou os
# dois", entao ela induziu a resposta que nao sabia ler. Aceitar so a forma
# canonica `codigo NNNN` e pedir para o comando morrer na primeira resposta
# humana -- e a pergunta que nao resolve na volta e laco fechado, nao
# desambiguacao.
#
# "SIM" E "ISSO" SOZINHOS NAO ENTRAM. Ele usa "isso" como confirmacao
# generica (medido nas mensagens reais dele). Com uma lista em aberto, um
# "isso" sobre outro assunto mandaria a carteira sem ele ter pedido. Eles
# valem so COLADOS num quantificador: "sim, os dois".
# "me manda" FICA DE FORA. No vocabulario medido dele, "me manda o 2539" e
# como ele pede o card PARA SI -- o "me" nomeia OUTRO destinatario, e ler isso
# como "manda para a corretora" e mandar a carteira achando que ele pediu para
# ver. Ele tem formas de sobra sem o "me", e a pergunta agora ensina uma.
#
# "tudo" FICA DE FORA por outro motivo: ela pede "DESCARTAR TUDO SIM" para
# confirmar descarte de pendencia, e ele digita o pedaco que lembra. "tudo
# sim" com uma lista em aberto mandaria a carteira inteira enquanto ele pensa
# que descartou pendencias. Duas confirmacoes competindo pela mesma palavra.
# "todos" cobre o sentido sem disputar nada.
_ANTES_DA_ESCOLHA = (
    r"(?:(?:sim|isso|ok|blz|beleza|pode|quero|vai|bora|manda|mande|mandar|"
    r"envia|envie|enviar|pode\s+mandar|pode\s+enviar)"
    r"[\s,;.!]*)*")

_ESCOLHA_TODOS = r"ambos|ambas|tod[oa]s"
# O DIGITO CRU FICA DE FORA, e exige o artigo: "os 2" e escolha, "2" nao e
# nada. Duas licoes deste projeto dizem isso -- `CODIGO_RE` aceitando 2
# digitos fez "as 08:00" virar os codigos 08 e 00, e o valor 4000 virou o
# imovel 4000. Digito curto solto nao e intencao. Pior: "2" como resposta a
# "qual?" quer dizer "o segundo", nao "dois deles".
_ESCOLHA_NUMERO_PALAVRA = r"dois|duas|tr[êe]s|quatro|cinco"
_ESCOLHA_NUMERO_COM_ARTIGO = r"[2-5]"
_ESCOLHA_POSICAO = r"primeir[oa]|segund[oa]|terceir[oa]|[úu]ltim[oa]"

ESCOLHA_NATURAL_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?" + _ANTES_DA_ESCOLHA
    + r"(?:(?P<artigo>[oa]s?)\s+)?"
    + r"(?:(?P<todos>" + _ESCOLHA_TODOS + r")"
      r"|(?P<numero>" + _ESCOLHA_NUMERO_PALAVRA + r")"
      r"|(?P<numero_digito>" + _ESCOLHA_NUMERO_COM_ARTIGO + r")"
      r"|(?P<posicao>" + _ESCOLHA_POSICAO + r"))"
    + r"\b(?P<cauda>[^\n]*)$",
    re.IGNORECASE,
)

# "5719 e 5728" sem a palavra codigo. DOIS OU MAIS de proposito: o codigo
# SOZINHO ja tem caminho proprio -- o ramo `Achar codigo` do fluxo dispara
# para `^\d{3,5}$` e manda o card com todas as fotos. Ele digita codigo puro
# o tempo todo (medido: "5611" 13 vezes), e roubar isso quebraria o caminho
# que ele mais usa.
ESCOLHA_SO_CODIGOS_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?" + _ANTES_DA_ESCOLHA
    + r"(?:[oa]s?\s+)?"
      r"(\d{3,5}(?:\s*(?:,|;|\+|/|e)\s*(?:[oa]s?\s+)?\d{3,5})+)"
      r"[\s.!]*$",
    re.IGNORECASE,
)

# CAUDA COM DESTINATARIO E ENVIO, NAO ESCOLHA. A primeira versao desta
# gramatica roubou "Nay envia todos os acquarelle para locacao para o corretor
# Sergio" -- um comando de envio inteiro: o "envia" cabe no prefixo educado e
# o "todos" no quantificador. Pegou no teste, nao em producao.
#
# A escolha NUNCA tem destinatario: ele ja esta guardado na lista em aberto.
#
# NAO ABRO EXCECAO PARA PRONOME. Com a escolha natural no FIM do dispatch, o
# ENVIO_RE pega "manda os dois pra ela" antes e recusa DIZENDO o motivo
# ("nao achei corretor chamado ela") -- que e resposta honesta. Abrir aqui
# seria codigo morto no Python e divergencia com o no do n8n.
_CAUDA_COM_DESTINO = re.compile(r"\b(?:para|pra|pro|p/)\s+", re.IGNORECASE)

# AS PROPRIAS LINHAS DA LISTA CASAVAM A ESCOLHA. Medido: "2 quartos sendo 1
# suite / 2.6k" devolvia {quantos: 2}, e o no `Comando do Tel` percorre o
# texto LINHA POR LINHA. Qualquer colagem cujo cabecalho nao case o ENVIO_RE
# -- ele reenvia sem o cabecalho, ou com codigo nele -- caia no laco, e uma
# linha de PRECO disparava o envio da carteira.
#
# Entao a cauda nao pode ter vocabulario de imovel. Isto e a mesma familia do
# `valor_nao_e_codigo.sql`: tirar o que e descricao antes de ler intencao.
_CAUDA_DE_IMOVEL = re.compile(
    r"\b(?:quartos?|su[íi]tes?|vagas?|dormit[óo]rios?|banheiros?|"
    r"mobiliad[oa]s?|semi|climatizad[oa]s?|andar|torre|bloco)\b"
    r"|\d\s*(?:k\b|m2|m²)|r\$|/",
    re.IGNORECASE)

# "os dois no grupo", "manda os dois no easy": ele esta falando de GRUPO, e a
# escolha manda para UMA PESSOA. `CAUDA_NAO_E_PESSOA_RE` e a parede que separa
# as duas coisas no resto do arquivo, e a escolha nasceu sem consultar ela --
# ele acharia que postou em 14 grupos e nao postou.

_NUMERO_ESCRITO = {"dois": 2, "duas": 2, "tres": 3, "três": 3,
                   "quatro": 4, "cinco": 5,
                   "2": 2, "3": 3, "4": 4, "5": 5}
_POSICAO_ESCRITA = {"primeiro": 1, "primeira": 1, "segundo": 2, "segunda": 2,
                    "terceiro": 3, "terceira": 3,
                    "ultimo": -1, "ultima": -1, "último": -1, "última": -1}

# Verbos que mandam para GRUPO. Se aparecerem com destinatario pessoal, a
# resposta e recusa que ensina -- nunca disparo.
VERBOS_DE_GRUPO = ("post", "public", "dispar", "solt")

# A cauda que é SÓ o negócio: "para locação", "pra venda", "de aluguel". Não
# é destinatário e não é grupo -- é o fim de um pedido a que faltou dizer
# para quem.
_NEGOCIO_NA_CAUDA_RE = re.compile(
    r"^(?:loca[çc][ãaoõ]\w*|alug\w*|arrend\w*|vend[ae]s?|vender|venda)"
    r"[\s.!,;]*$", re.IGNORECASE)

# Cauda que nao e pessoa. Nao pode ser lista exata: "pro grupo de anunciar
# da easy 5750" e cauda de GRUPO e nao casaria com nenhuma entrada fixa --
# viraria envio privado para um "corretor" com esse nome. Basta MENCIONAR.
# NEGÓCIO NA CAUDA TAMBÉM NÃO É PESSOA (15/09). "posta o jardim das cerejeiras
# para locação" tem "para", e a cauda virava o nome de um corretor -- a
# resposta real era "POSTA manda para os grupos e nao sei mandar para uma
# pessoa com esse verbo", que não tem nada a ver com o que ele pediu.
CAUDA_NAO_E_PESSOA_RE = re.compile(
    r"\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores"
    r"|loca[çc][ãa]o|venda|aluguel|alugar|vender)\b",
    re.IGNORECASE,
)

# Vocabulário de repetição alternada que o parser AINDA NÃO sabe montar.
# Sem esta guarda o silêncio é perigoso, e foi medido em 27/08 contra o
# parser em produção:
#   "posta o 5750 a cada 15 dias"        -> postar_agora ['5750', '15']
#        posta o 5750 E TENTA O IMÓVEL 15, na hora, em 14 grupos
#   "posta o 5750 de 15 em 15 dias"      -> postar_agora ['5750','15','15']
#   "posta o 5750 segunda sim segunda nao as 13h30" -> vaga SEMANAL
#        o Tel pediu para pular uma semana e o imóvel sai em todas
#   "posta o 5750 toda segunda quinzenal as 13h30"  -> vaga SEMANAL
#
# Os dois primeiros são irreversíveis (WhatsApp não desfaz) e os dois
# últimos mentem em silêncio, que é pior do que recusar. Enquanto a
# gramática de vaga alternante não existir, tudo isso vira
# nao_reconhecido explícito -- o princípio do arquivo é não adivinhar, e
# adivinhar "toda semana" quando o Tel escreveu "semana sim, semana não"
# é adivinhação com custo.
#
# Quando a alternância for implementada, esta guarda sai e a gramática
# entra nas TRÊS cópias no mesmo commit (aqui, e nos nós 'Comando do Tel'
# e 'Rotear para o agente' do n8n) -- Parte 4.3 do HISTORICO.
ALTERNANCIA_RE = re.compile(
    r"quinzen"
    r"|\balterna[dnr]"                 # alternado, alternada, alternando, alternar
    r"|\baltern[aâ]ncia"
    r"|\bsemana\s+sim\b"
    r"|\b(seg|ter[cç]|qua|qui|sex|s[áa]b|dom)\w*\s+sim\b"
    r"|\ba\s+cada\s+(\d+|uma?|dois|duas)\s+(dias?|semanas?)"
    r"|\bde\s+\d+\s+em\s+\d+\s+dias?",
    re.IGNORECASE,
)

TODO_DIA_RE = re.compile(
    r"todo\s+(santo\s+)?dia|todos?\s+os\s+dias|diariamente", re.IGNORECASE
)

# convenção Postgres EXTRACT(DOW): 0=domingo ... 6=sábado (mesma do
# schema de vagas e do agendador.py). Formas com e sem hífen porque o
# Tel escreve dos dois jeitos.
DIAS_SEMANA_NOMES = {
    "domingo": 0, "dom": 0,
    "segunda-feira": 1, "segunda feira": 1, "segunda": 1, "seg": 1,
    "terca-feira": 2, "terça-feira": 2, "terca feira": 2, "terça feira": 2,
    "terca": 2, "terça": 2, "ter": 2,
    "quarta-feira": 3, "quarta feira": 3, "quarta": 3, "qua": 3,
    "quinta-feira": 4, "quinta feira": 4, "quinta": 4, "qui": 4,
    "sexta-feira": 5, "sexta feira": 5, "sexta": 5, "sex": 5,
    "sabado": 6, "sábado": 6, "sab": 6, "sáb": 6,
}


def _horario_do_match(m):
    if m.group("hm2") is not None:
        return datetime.time(int(m.group("hm2")), int(m.group("hm2_min") or 0))
    if m.group("hm") is not None:
        return datetime.time(int(m.group("hm")), int(m.group("hm_min") or 0))
    if m.group("horas") is not None:
        return datetime.time(int(m.group("horas")), 0)
    if m.group("meia") is not None:
        return datetime.time(int(m.group("meia")), 30)
    if m.group("meiodia") is not None:
        return datetime.time(12, 0)
    if m.group("meianoite") is not None:
        return datetime.time(0, 0)
    if m.group("periodo") is not None:
        h = int(m.group("periodo"))
        qual = m.group("periodo_qual").lower()
        if qual.startswith("manh"):
            # "12 da manhã" é meio-dia na fala dele, não zero.
            return datetime.time(0 if h == 0 else h, 0)
        # tarde e noite: 12 já é o próprio meio-dia, o resto soma 12.
        return datetime.time(h if h >= 12 else h + 12, 0)
    raise AssertionError("HORA_RE casou mas nenhum grupo nomeado bateu -- bug no regex")


# TELEFONE NA FRENTE + UM CÓDIGO É ENVIO, mesmo com o verbo torto (Tel, 28/09).
#
# O CASO: ele escreveu "92 8192-5962 **evia** o 964" -- faltou o "n". Nenhuma
# gramática casou, a frase foi ao agente, e a Nay respondeu a ELE como se
# fosse um corretor pedindo o imóvel: "Bom dia, Imob! Claro, já te mando!",
# com o card e as fotos. O imóvel nunca chegou à corretora.
#
# A PALAVRA DELE: "toda vez que vier mensagem da imob easy e do Tel é um
# comando para enviar o imóvel e não para receber, para ela não poder
# confundir e fazer isso".
#
# POR QUE ISTO É SEGURO AQUI, e não seria em qualquer lugar: só mensagem dos
# números DELE chega ao publicador (o `POST /comando` é chamado pelo nó que já
# conferiu quem escreveu). Então "telefone na frente" não é um palpite sobre
# um estranho -- é ele dando um destino.
#
# TRÊS EXIGÊNCIAS, e cada uma tira um falso positivo medido no histórico dele:
#
#   * COMEÇA com o telefone. "DEVOLVER (92) 99511-8525 estou verificando..."
#     e "NAO CORRETOR (92) 98427-1973" começam com a palavra de comando, e
#     continuam indo para onde sempre foram.
#   * UM código só, de 3 a 5 dígitos. Sem o piso, "Devolver (92) 98644-8395
#     temos uma casa na ponta negra de 4 mil" colhia o "4" de "4 mil".
#   * ÚLTIMO RECURSO: só roda depois de todo o resto ter dito
#     "nao_reconhecido", então não rouba comando nenhum.
_TELEFONE_NA_FRENTE_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"((?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*9?\d{4}[\s.-]*\d{4})\b",
    re.IGNORECASE)   # sem isto, "Nay 92 ..." com maiúscula não casava
_CODIGO_DE_3_A_5_RE = re.compile(r"(?<![\d.,])(\d{3,5})(?![\d.,])")

# OUTRO COMANDO NA FRASE FECHA ESTA PORTA. "92 9951-9275 posta o 5737" tem
# telefone e um código, mas `posta` manda para os GRUPOS -- e a regra de
# 31/08 é que postar e enviar para uma pessoa nunca se misturam: "Nay posta o
# 5750 pro Rogério" é RECUSADO com explicação, nunca postado. Sem esta
# guarda, o último recurso transformaria um `posta` mal escrito num envio
# privado, que é a confusão que aquela parede existe para impedir.
_OUTRO_COMANDO_RE = re.compile(
    r"\b(post|public|dispar|solt|tir|remov|retir|vende|vendid|aluga|alugad|"
    r"vaga|lista|agenda|resposta|descart|pendencia|corretor|devolv)\w*\b",
    re.IGNORECASE)


def _envio_pelo_telefone_na_frente(texto):
    """"92 8192-5962 evia o 964" -- o destino e o código, sem verbo que preste.

    Devolve o comando de envio, ou None. Ver o comentário acima para as três
    exigências e o falso positivo que cada uma tira.
    """
    m = _TELEFONE_NA_FRENTE_RE.match(texto or "")
    if not m:
        return None
    destino = m.group(1).strip()
    resto = (texto[:m.start(1)] + " " + texto[m.end(1):])
    if _OUTRO_COMANDO_RE.search(resto):
        return None
    codigos = _CODIGO_DE_3_A_5_RE.findall(_TELEFONE_RE.sub(" ", resto))
    if len(codigos) != 1:
        return None
    return {"acao": "enviar_para_corretor", "codigos": codigos,
            "corpo": f"o {codigos[0]}", "destino": destino,
            "nome_dito": None, "pedido": "",
            "texto": f"envia o {codigos[0]} para {destino}"}


def interpretar_comando(texto):
    resultado = _interpretar(texto)

    # ÚLTIMO RECURSO, antes de desistir: telefone na frente + um código é
    # envio, mesmo com o verbo torto. Ver `_envio_pelo_telefone_na_frente`.
    if resultado["acao"] == "nao_reconhecido":
        pelo_telefone = _envio_pelo_telefone_na_frente(texto)
        if pelo_telefone:
            return pelo_telefone

    # `enviar_sem_destino` junto: a resposta DEVOLVE a frase dele com o destino
    # no fim, para ele reenviar. Devolver a versão sem o vocativo daria uma
    # frase que a própria gramática não reconhece -- o ramo sem "para" exige o
    # "Nay" na frente.
    if resultado["acao"] in ("nao_reconhecido", "enviar_sem_destino"):
        # Devolve o que o Tel escreveu DE VERDADE, não a versão já sem o
        # vocativo. A resposta do publicador cita esse texto de volta pra
        # ele ("Não entendi o comando ..."); citar uma frase que ele não
        # escreveu confunde em vez de ajudar.
        resultado["texto"] = texto
    return resultado


# TELEFONE ANTES DO VERBO: "92 9454-0289 envia todos os apartamentos no
# condominio verona para este numero".
#
# O CASO (Tel, 24/09, DUAS VEZES em poucos minutos): ele escreve o destino
# primeiro, como quem abre a conversa pelo contato, e so depois diz o que
# mandar. Nenhuma das gramaticas cobria isso -- todas esperam o verbo na
# frente -- e as duas frases cairam em "nao_reconhecido".
#
# O CONSERTO E UMA REESCRITA, nao um parser novo: a frase vira a forma
# canonica ("<verbo> <resto> para <telefone>") e segue pelo caminho de
# sempre. Assim o pedido DESCRITO ("todos os apartamentos no condominio
# verona", "o amazonas flat para locacao de 2k") continua sendo resolvido por
# `pedido_de_imoveis`, sem uma segunda copia da regra de leitura.
TELEFONE_ANTES_DO_VERBO_RE = re.compile(
    r"^\s*(?P<tel>(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4})"
    r"[\s,;:.-]+"
    # `en+vi` porque ele digitou "ennvia". O teclado do celular repete letra,
    # e recusar um comando por causa de um "n" a mais custa um imovel nao
    # enviado -- foi assim que a frase do Verona morreu.
    r"(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?P<verbo>en+vi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b"
    r"(?P<resto>[\s\S]*)$",
    re.IGNORECASE,
)

# "para ela", "para este numero" -- o destino dito por PRONOME. Com o telefone
# ja na frente, essas palavras nao nomeiam ninguem novo: sao a mesma pessoa.
# Deixa-las no corpo faria o `ENVIO_RE`, que e guloso pela ULTIMA preposicao,
# disputar o destino com o telefone.
DESTINO_POR_PRONOME_RE = re.compile(
    r"\s*\b(?:para|pra|pro|p/)\s+"
    r"(?:ela|ele|elas|eles|"
    r"(?:o\s+|esse\s+|este\s+|esta\s+|essa\s+)?n[uú]mero(?:\s+(?:dela|dele))?|"
    r"(?:esse|este)\s+contato|(?:esse|este)\s+whats(?:app)?)\b",
    re.IGNORECASE,
)


def _verbo_canonico(bruto):
    """"ennvia" vira "envia".

    A letra repetida e o teclado do celular, nao outra palavra. Canonizar AQUI
    -- e nao afrouxar o `ENVIO_RE` -- mantem a tolerancia num lugar so: a
    gramatica de envio ja vive em sete copias, e cada afrouxamento nelas e
    sete edicoes e sete chances de divergir.
    """
    v = re.sub(r"(.)\1+", r"\1", (bruto or "").lower())
    if v.startswith("envi"):
        return "envia"
    if v.startswith(("mand", "mnd", "md")):
        return "manda"
    if v.startswith("repas"):
        return "repassa"
    if v.startswith("encamin"):
        return "encaminha"
    return "envia"


def _telefone_antes_do_verbo(texto):
    """Reescreve "<telefone> envia X" como "envia X para <telefone>".

    Devolve None quando a frase nao e dessa forma -- e ai nada muda.
    """
    m = TELEFONE_ANTES_DO_VERBO_RE.match(texto or "")
    if not m:
        return None
    resto = DESTINO_POR_PRONOME_RE.sub("", m.group("resto")).strip()
    resto = re.sub(r"^[\s,;:.-]+|[\s,;:.-]+$", "", resto)
    if not resto:
        return None
    return f"{_verbo_canonico(m.group('verbo'))} {resto} para {m.group('tel').strip()}"


def _interpretar(texto):
    # TELEFONE ANTES DO VERBO, antes de tudo: e uma REESCRITA para a forma
    # canonica, entao tem que acontecer antes de qualquer ramo ler a frase.
    reescrito = _telefone_antes_do_verbo(texto)
    if reescrito:
        texto = reescrito

    # Um desconto só, aqui, antes de tudo: os cinco caminhos abaixo
    # derivam de t/tl, e os dois sub-parsers recebem t -- então este
    # ponto cobre dispatch E extração de código/horário de uma vez.
    # Fazer por caminho, ou lá no n8n, seria a mesma regra em dois
    # lugares: o padrão que o HISTORICO-APRENDIZADO.md, Parte 4.3,
    # registra como o bug mais caro do projeto.
    t = VOCATIVO_RE.sub("", texto.strip(), count=1).strip()
    tl = t.lower()

    if tl == "vagas":
        return {"acao": "listar_vagas"}

    if AGENDA_VISITAS_RE.match(tl):
        return {"acao": "agenda_de_visitas"}

    # "Nay codigo 5719" -- a resposta dele à pergunta de desambiguação.
    # ANTES de tudo que lê código, porque é uma frase curta que só existe
    # para responder, e deixar qualquer outro ramo pegá-la primeiro faria a
    # pergunta virar laço fechado.
    # "sim" / "não" a uma pergunta que ela fez. Nenhum comando existente é
    # feito SÓ destas palavras, então o lugar cedo não rouba nada; e "sim, os
    # dois" não casa aqui (tem "os dois"), segue para a escolha da lista.
    resposta = resposta_ao_tel(texto)
    if resposta:
        return {"acao": "responder_pergunta", "resposta": resposta}

    # `codigo NNNN` pode morar CEDO: a palavra "codigo" e uma MARCA que nenhuma
    # outra gramatica deste projeto usa. As formas naturais ("os dois") nao tem
    # marca nenhuma -- sao prefixo de frases que ja significam outra coisa --
    # e por isso moram no FIM do dispatch, depois de todo mundo.
    escolha = _interpretar_escolha_de_codigo(t)
    if escolha:
        return escolha

    # A LISTA COLADA: cabeçalho de envio na primeira linha, itens embaixo.
    # ANTES do disparo de lista (que sequestraria "esses apartamentos") e
    # muito antes do ENVIO_RE, cujo corpo guloso engoliria a lista inteira
    # dentro do destinatário.
    lista = _interpretar_envio_de_lista(t)
    if lista:
        return lista

    # ANTES do LIBERAR_RE e do POSTAR_RE: "dispara" e "posta" são verbos dos
    # dois, e "dispara lista" não é nem liberar nem postar imóvel.
    disparo = _interpretar_disparo_de_lista(tl)
    if disparo:
        return disparo

    m = LIBERAR_RE.match(tl)
    if m:
        codigos = CODIGO_RE.findall(m.group(2))
        if len(codigos) == 1:
            return {"acao": "liberar_vaga", "codigo": codigos[0],
                    "motivo": _motivo_do_verbo(m.group(1))}
        return {"acao": "nao_reconhecido", "texto": texto}

    # "5712 Alugado" -- o código na frente. Fica DEPOIS do LIBERAR_RE e de
    # tudo que começa com verbo, para não roubar frase nenhuma.
    m = LIBERAR_CODIGO_RE.match(tl)
    if m:
        return {"acao": "liberar_vaga", "codigo": m.group(1),
                "motivo": _motivo_do_verbo(m.group(2))}

    taxa = _interpretar_taxa(tl)
    if taxa:
        return taxa

    lista = _interpretar_lista(tl)
    if lista:
        return lista

    # antes do EASY_RE de propósito: "remove o 5750 do anunciar easy" é
    # intenção de tirar, não de postar. Se caísse no EASY_RE, viraria
    # postar_easy e mandaria o imóvel pro grupo -- envio de WhatsApp não
    # tem desfazer, tirar da grade tem.
    m = REMOVER_RE.match(tl)
    if m:
        # "tira a lista de apartamento para locação da grade". Sem isto ele
        # cria uma vaga de lista e NÃO tem como desfazer -- capacidade que
        # falta vira promessa quebrada, e aqui viraria disparo diário eterno.
        if _FALA_DE_LISTA.search(m.group(2)):
            categoria, negocio = _categoria_e_negocio(m.group(2))
            destino = _destino_da_lista(m.group(2))
            return {"acao": "remover_lista_da_grade", "categoria": categoria,
                    "negocio": negocio, "destino": destino}
        codigos = CODIGO_RE.findall(m.group(2))
        if len(codigos) == 1:
            return {"acao": "remover_da_grade", "codigo": codigos[0]}
        return {"acao": "nao_reconhecido", "texto": texto}

    # O GRUPO ALTO PADRÃO vem ANTES do EASY_RE e do POSTAR_RE, e a ordem é o
    # que segura o comando no lugar certo. O nome do grupo é "IMÓVEIS ALTO
    # PADRÃO PARA ANUNCIAR EASY": ele CONTÉM "anunciar easy", então o EASY_RE
    # casaria e o imóvel iria para o grupo Easy de sempre. E "posta no grupo
    # alto padrão 4567" casaria o POSTAR_RE e sairia nos 17 grupos de uma vez.
    # Medido em 25/09, antes de escrever: "Nay publica no alto padrão easy o
    # 4567" caía em `postar_agora`.
    # O DE ANUNCIAR EASY VEM PRIMEIRO: quem escreveu "easy" ou "anunciar"
    # está falando dele, e o específico tem que ganhar do geral.
    if ALTO_PADRAO_EASY_RE.match(t):
        return _interpretar_postar_alto_padrao_easy(t)

    # E o 🟢 Alto Padrão - OFERTA e BUSCA 🔍, que é o "alto padrão" dele desde
    # 27/09 -- e também o "grupo padrão", sem o "alto", que ele escreveu em
    # quatro das cinco frases. Sem esta regra aquelas quatro caíam no
    # POSTAR_RE e saíam nos dezessete grupos.
    if ALTO_PADRAO_BUSCA_RE.search(t) and _VERBO_DE_GRUPO_RE.match(t):
        return _interpretar_postar_alto_padrao(t)

    # O GRUPO COMERCIAL, pela MESMA razão de ordem: "posta no grupo comercial
    # 5763" casa o POSTAR_RE e sairia nos 17 grupos. Medido antes de escrever.
    #
    # Vem DEPOIS do disparo de lista, que já rodou lá em cima -- por isso
    # "posta lista de sala comercial no grupo comercial" não cai aqui, e é o
    # que a exigência de UM código também garante: a lista não tem código.
    if COMERCIAL_GRUPO_RE.search(t) and _VERBO_DE_GRUPO_RE.match(t):
        return _interpretar_postar_comercial(t)

    # OS QUATRO GRUPOS DE MAIOR MOVIMENTO (Tel, 27/09). Mesma posição e mesma
    # razão do Comercial: "posta 5713 no grupo lotado" casaria o POSTAR_RE e
    # sairia nos 17 de uma vez.
    if LOTADO_GRUPO_RE.search(t) and _VERBO_DE_GRUPO_RE.match(t):
        return _interpretar_postar_lotado(t)

    # ANTES do EASY_RE: "manda o 5750 pro corretor anunciar, ele e da easy"
    # cai no EASY_RE hoje (que usa search no texto inteiro) e vira postagem
    # no grupo Easy com todas as fotos. Com o envio na frente, vira recusa.
    # O TELEFONE NA FRENTE vem antes do ENVIO_RE. Nao ha disputa -- aquele
    # exige preposicao e esta forma nao tem --, mas a ordem deixa explicito
    # que a forma mais estreita decide primeiro.
    porfone = _interpretar_envio_telefone_na_frente(t)
    if porfone:
        return porfone

    m = ENVIO_RE.match(t)
    if m:
        r = _interpretar_envio(t, m)
        if r is not None:
            return r

    # E O PEDIDO SEM NENHUM "PARA" (15/09): "Nay envia locação de 3k a 6k nos
    # bairros parque dez, flores e compensa". Não casa o ENVIO_RE -- que exige
    # o "para" do destinatário -- e cairia em "não reconhecido", calado.
    #
    # Só com VALOR ESCRITO, a mesma marca da parede de cima: "Nay envia a
    # lista", "Nay envia vagas" e o resto da gramática continuam intocados.
    # O "nay" é conferido no TEXTO CRU: `t` já perdeu o vocativo na primeira
    # linha de `_interpretar`, e exigi-lo ali não casaria nunca.
    if _SEM_PARA_RE.match(texto.strip()) and _cauda_e_pedido(t) \
            and not _codigos_do_pedido(t):
        return {"acao": "enviar_sem_destino",
                "pedido": _limpar_pedido(t), "texto": t}

    if EASY_RE.search(tl):
        return _interpretar_postar_easy(t)

    if POSTAR_RE.match(tl):
        return _interpretar_posta(t)

    # POR ULTIMO, e nao por acaso: "os dois", "ambos", "o primeiro". Elas nao
    # tem palavra-marca, entao sao PREFIXO de frases que ja significam outra
    # coisa. Medido com a versao que rodava cedo:
    #
    #   "manda todos os acquarelle para locacao para o Sergio" -- frase citada
    #   no proprio codigo como forma viva do envio -- virava escolha, com o
    #   "Sergio" DESCARTADO, e a carteira ia para o destinatario guardado na
    #   lista em aberto. Envio para a pessoa errada, que este projeto trata
    #   como o pior resultado possivel.
    #
    #   "manda os dois pro Sergio" e "os dois no grupo" iam pelo mesmo caminho.
    #
    # Aqui no fim, o ENVIO_RE, o disparo de lista e o EASY_RE ja pegaram o que
    # e deles, e sobra so o que realmente nao e mais nada.
    escolha = _interpretar_escolha_natural(t)
    if escolha:
        return escolha

    # A RESPOSTA À PERGUNTA DO `posta <nome>` (15/09): "locação", "5725",
    # "3.6k". Palavras que sozinhas não são comando nenhum -- por isso ficam
    # NO FIM, onde só chega o que ninguém mais quis, e por isso quem confere
    # se existe pergunta aberta é o publicador (é ele que vê o banco).
    #
    # O portão do n8n só deixa estas frases chegarem aqui QUANDO há pergunta
    # aberta (`nay_pergunta_aberta_do_tel`); sem pergunta, "5725" continua
    # sendo o código puro de sempre, que manda o card no chat dele.
    posta = _interpretar_escolha_do_posta(t)
    if posta:
        return posta

    return {"acao": "nao_reconhecido", "texto": texto}


# O TELEFONE ESCRITO, onde quer que ele esteja na frase (14/09). O Tel escreve
# o destino de três jeitos -- "para corretora Flavia Soares 92 9131-8844" no
# FIM, "para Ana 92 9396-5797 os imóveis que ela está pedindo" no MEIO, e
# "para o número da corretora parceira Waldyrene 92 9307-2954 ..." -- e o
# ENVIO_RE, que pega a ÚLTIMA preposição, só acerta o primeiro. No da Ana a
# preposição seguinte ("para locação", "para ela") vira destinatário.
#
# Com telefone escrito, o telefone É o destino: `_resolver_corretor` casa por
# ele, e o que sobra da frase é o pedido. Sem os lookarounds de dígito, o 55 do
# DDI grudado no DDD quebrava a leitura.
_TELEFONE_RE = re.compile(
    r"(?<!\d)(?:\+?55\s*)?\(?\d{2}\)?\s*9?\s*\d{4}\s*[-.]?\s*\d{4}(?!\d)")

# "Nay envia <pedido>" sem destinatário nenhum. O @nay NÃO é opcional aqui:
# sem ele, qualquer frase do Tel que comece com "manda" e tenha um preço
# dentro viraria comando de envio.
_SEM_PARA_RE = re.compile(
    r"^\s*@?nay\b[\s,;:.!?-]*"
    r"(?:envi|m[a]?nd|repass|encaminh|mostr|dispar|solt)\w*\b\s+",
    re.IGNORECASE)

_VERBO_NO_COMECO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?:envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)\w*\b\s*",
    re.IGNORECASE)

# "esses imóveis", "os imóveis que ela está pedindo": a moldura do pedido,
# não o pedido. Sem esta parede ela entraria como mais uma linha a resolver.
_PEDIDO_VAZIO_RE = re.compile(
    r"^(?:(?:esses|estes|essas|estas|os|as|uns|umas)\s+)?"
    r"(?:im[oó]veis|op[cç][oõ]es|an[uú]ncios)?"
    r"(?:\s+que\s+(?:ela|ele|o\s+cliente|a\s+cliente)\s+(?:est[aá]\s+)?"
    r"(?:pedi\w*|quer\w*|precis\w*|gostou))?\s*[.,;:!]*$",
    re.IGNORECASE)

# VALOR NÃO É CÓDIGO, também aqui. Medido em 14/09: "envia toda as casas ...
# até 4.200 para corretora Flavia Soares" devolvia `codigos: ["4", "200"]` --
# imóveis que não existem, e o site devolve página vazia que o envio aceitava.
# A corretora receberia dois cards "📍 Imóvel 4". É a lição de
# `valor_nao_e_codigo.sql`, que o lado Python nunca tinha trazido.
# E "DE <NÚMERO>" É PREÇO, NÃO CÓDIGO (Tel, 25/09). Ele escreveu "envia o
# parque imperial de 2750 para locação" e recebeu "2750: nao achei esse codigo
# no site" -- o 2750 caiu na faixa dos códigos do catálogo (45 a 5755) e foi
# lido como imóvel.
#
# O ARTIGO É O QUE SEPARA: ele chama o imóvel de "o 5750", nunca de "de 5750".
# Quando escreve "de", está dizendo o valor -- e em geral já nomeou o
# condomínio antes, como aqui.
#
# MEDIDO no corpus inteiro antes de escrever: **zero** mensagens, dele ou de
# qualquer corretor, trazem "de <número de 3 a 5 dígitos>". Nenhum falso
# positivo possível no histórico -- o que não é prova de que nunca haverá, mas
# é a melhor evidência disponível.
#
# A cauda de unidade fica de fora: "área de 250m2" não é preço de 250.
_NAO_E_CODIGO_RE = re.compile(
    r"r\$\s*[\d.,]+"
    r"|\b\d+[.,]\d+\s*(?:k|mil|m)\b|\b\d+\s*(?:k|mil)\b"
    r"|\b\d{1,3}(?:[.,]\d{3})+\b"
    r"|\b(?:at[eé]|por|acima\s+de|a\s+partir\s+de|m[aá]ximo(?:\s+de)?)\s+\d[\d.,]*"
    r"|\bde\s+\d{3,7}(?!\d)"
    r"(?!\s*(?:m2|m²|quartos?|qtos?|qts?|su[ií]tes?|vagas?|banheiros?|dormit))"
    r"|\b\d+\s*(?:quartos?|qtos?|su[ií]tes?|vagas?|banheiros?|m2|m²)",
    re.IGNORECASE)


def _separar_destino_por_telefone(linha):
    """(telefone, nome que ele escreveu, o resto da frase), ou None."""
    tel = _TELEFONE_RE.search(linha or "")
    if not tel:
        return None
    antes = linha[:tel.start()]
    preps = list(re.finditer(r"\b(?:para|pra|pro)\b|\bp/", antes, re.IGNORECASE))
    if not preps:
        return None
    prep = preps[-1]
    nome = re.sub(
        r"\b(?:o|a)\s+n[uú]mero\s+d[aoe]s?\b|\bn[uú]mero\b|\bcorretor[ae]?s?\b"
        r"|\bparceir[oa]s?\b|^\s*(?:o|a|da|do)\b",
        " ", antes[prep.end():], flags=re.IGNORECASE)
    nome = re.sub(r"\s+", " ", nome).strip(" ,.;:-")
    # o artigo que sobra na frente: "da Waldyrene" -> "Waldyrene"
    nome = re.sub(r"^(?:d[aoe]s?|o|a)\s+", "", nome, flags=re.IGNORECASE)
    return tel.group(0).strip(), (nome or None), \
        antes[:prep.start()] + " " + linha[tel.end():]


def _limpar_pedido(resto):
    """O pedido sem o verbo do começo e sem a moldura."""
    t = _VERBO_NO_COMECO_RE.sub("", resto or "", count=1)
    t = re.sub(r"\s+", " ", t).strip(" ,.;:-")
    return "" if _PEDIDO_VAZIO_RE.match(t) else t


def _cauda_e_pedido(cauda):
    """A cauda do "para" descreve IMÓVEL, em vez de nomear destinatário?

    A marca é o VALOR ESCRITO: destinatário não tem dinheiro no nome. Só isso
    -- "para locação", "para venda", "pro grupo" seguem sendo cauda de
    destino, e a lista de categoria ("Nay dispara apartamentos para locação")
    não pode ser roubada por esta parede.

    O import mora AQUI DENTRO de propósito: `pedido_de_imoveis` importa este
    módulo, e no topo isso seria import circular.
    """
    from pedido_de_imoveis import ler_pedido
    f = ler_pedido(cauda or "")
    return bool(f["teto"] or f["piso"] or f["valores"])


def _codigos_do_pedido(texto):
    r"""Os códigos de 3 a 5 dígitos, depois de tirar telefone e valor.

    Três a cinco, e não o `\d{1,6}` do CODIGO_RE: não existe código de 1 ou 2
    dígitos neste catálogo (o menor tem 3), e é justamente o número curto que
    é quarto, suíte ou pedaço de preço.
    """
    limpo = _TELEFONE_RE.sub(" ", texto or "")
    limpo = _NAO_E_CODIGO_RE.sub(" ", limpo)
    return re.findall(r"(?<!\d)\d{3,5}(?!\d)", limpo)


# "sim" e "não" do Tel, quando a Nay fez uma pergunta a ele (14/09). O MESMO
# literal de `regex_resposta_ao_tel.js`; `casos_resposta_ao_tel.json` roda os
# dois lados. Só chega aqui quando o nó viu pergunta aberta
# (`nay_pergunta_aberta_do_tel`) -- sozinho, este padrão casaria qualquer "ok"
# da conversa, e quem confere se há pergunta de verdade é o publicador.
RESPOSTA_SIM_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?=[\s\S]*\b(?:sim|s|pode|isso|ok|okay|beleza|blz|confirm[oa]|confirmado|"
    r"quero|bora|manda|posta|postar|poste|reposta|repostar|claro|certo|novamente)\b)"
    r"(?:(?:sim|s|pode|isso|ok|okay|beleza|blz|confirm[oa]|confirmado|quero|bora|"
    r"manda|posta|postar|poste|reposta|repostar|claro|certo|mesmo|com\s+certeza|"
    r"de\s+novo|novamente|outra\s+vez|por\s+favor|pfv|pf|nay)(?:[\s,;.!]+|$)){1,8}$",
    re.IGNORECASE)
RESPOSTA_NAO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(?:n[aã]o|n|deixa(?:\s+quieto)?|esquece|cancela|agora\s+n[aã]o|melhor\s+n[aã]o)"
    r"(?:[\s,;.!]+(?:n[aã]o|precisa|posta|postar|obrigad[oa]|nay|por\s+enquanto|agora|quieto))*"
    r"[\s,;.!]*$",
    re.IGNORECASE)

# "posta no anunciar easy de novo o 1885": o Tel dizendo, ele mesmo, que é para
# repetir. Não precisa de pergunta -- a frase já é a confirmação.
_DE_NOVO_RE = re.compile(r"\b(?:de\s+novo|novamente|outra\s+vez|reposta\w*)\b", re.IGNORECASE)


def resposta_ao_tel(texto):
    t = (texto or "").strip()
    if RESPOSTA_SIM_RE.match(t):
        return "sim"
    if RESPOSTA_NAO_RE.match(t):
        return "nao"
    return None


def _interpretar_escolha_de_codigo(texto):
    """"Nay codigo 5719" -- ele escolhendo entre os candidatos que ela ofereceu.

    A PERGUNTA SÓ VALE SE A RESPOSTA RESOLVER. Este projeto já teve o funil
    em que o corretor escolhia o nome oferecido e ouvia a mesma pergunta
    (`nay_disponibilidade_no_condominio`, 01/09) -- laço fechado, não
    desambiguação. Então a gramática da resposta nasce junto com a pergunta.

    A FORMA É `codigo NNNN`, e não o código puro, de propósito: "5719"
    sozinho já cai no ramo `Achar codigo` do n8n, que manda o card e TODAS as
    fotos para o chat do próprio Tel. Ele pediu "Nay codigo 5719" e é
    exatamente a forma que não colide.

    Aceita mais de um porque a linha dele veio repetida e são dois imóveis
    diferentes: "Nay codigo 5719 e 5728".
    """
    m = ESCOLHER_CODIGO_RE.match(texto)
    if not m:
        return None
    codigos = re.findall(r"\d{3,5}", m.group(1))
    if not codigos:
        return None
    # `dict.fromkeys` em vez de set: repetir o mesmo código é engano, e a
    # ordem em que ele escreveu é a ordem em que o corretor recebe.
    return {"acao": "escolher_codigos",
            "codigos": list(dict.fromkeys(codigos)),
            "texto": texto}


def _interpretar_envio_telefone_na_frente(texto):
    """"envia (92) 98478-7190 o 3210" -- o telefone antes do codigo.

    E a forma que o Tel usou em 23/09 e que caiu no agente, porque o
    `ENVIO_RE` exige preposicao. Aqui ela e opcional, e o que segura a
    gramatica no lugar e o TELEFONE: 10 ou 11 digitos, que nenhum codigo de
    imovel tem.
    """
    m = ENVIO_TELEFONE_NA_FRENTE_RE.match(texto)
    if not m:
        return None
    corpo = m.group("corpo")
    # Dois digitos so valem quando ele ESCREVEU "codigo". Ver o comentario da
    # regex: sem o marcador, "os 2" e a escolha da lista, nao o imovel 2.
    faixa = r"\d{2,5}" if MARCADOR_CODIGO_RE.match(corpo) else r"\d{3,5}"
    codigos = re.findall(faixa, corpo)
    if not codigos:
        return None
    return {"acao": "enviar_para_corretor",
            "codigos": list(dict.fromkeys(codigos)),
            "corpo": m.group("corpo").strip(),
            "destino": m.group("tel").strip(),
            "texto": texto}


def _interpretar_escolha_natural(texto):
    """"os dois", "ambos", "o primeiro", "5719 e 5728" -- ele respondendo.

    O CASO (12/09): ele respondeu **"os dois"** e a frase caiu no AGENTE, que
    devolveu uma lista de imoveis sem nexo. A pergunta dela dizia "ou os
    dois" -- ela induziu a resposta que nao sabia ler. Pergunta que nao
    resolve na volta e laco fechado, nao desambiguacao.

    QUEM RESOLVE O QUE "OS DOIS" SIGNIFICA e o publicador, que tem a lista em
    aberto na mao. Aqui so se le a INTENCAO: todos, uma quantidade, ou uma
    posicao. O parser nao conhece os candidatos e nao pode inventar.
    """
    m = ESCOLHA_SO_CODIGOS_RE.match(texto)
    if m:
        codigos = re.findall(r"\d{3,5}", m.group(1))
        return {"acao": "escolher_codigos",
                "codigos": list(dict.fromkeys(codigos)), "texto": texto}

    m = ESCOLHA_NATURAL_RE.match(texto)
    if not m:
        return None

    # "manda todos os apartamentos para locacao" e a LISTA, nao a escolha --
    # e a lista dispara em 13 grupos. Cauda que fala de categoria ou de lista
    # devolve None e deixa o dispatch seguir para o caminho certo.
    cauda = m.group("cauda") or ""
    if _SUBSTANTIVO_DE_CATEGORIA.search(cauda.lower()) or _FALA_DE_LISTA.search(cauda.lower()):
        return None
    if _CAUDA_COM_DESTINO.search(cauda):
        return None
    if _CAUDA_DE_IMOVEL.search(cauda):
        return None
    if CAUDA_NAO_E_PESSOA_RE.search(cauda.lower()):
        return None

    # "os 2" e escolha; "2" sozinho nao e nada. O artigo e o que separa.
    if m.group("numero_digito") and not m.group("artigo"):
        return None

    if m.group("todos"):
        return {"acao": "escolher_codigos", "todos": True, "texto": texto}

    escrito = m.group("numero") or m.group("numero_digito")
    if escrito:
        quantos = _NUMERO_ESCRITO.get(escrito.lower())
        if not quantos:
            return None
        return {"acao": "escolher_codigos", "quantos": quantos, "texto": texto}

    posicao = _POSICAO_ESCRITA.get(m.group("posicao").lower())
    if not posicao:
        return None
    return {"acao": "escolher_codigos", "posicao": posicao, "texto": texto}


def _interpretar_envio_de_lista(texto):
    """A lista colada: cabeçalho de envio na primeira linha, itens embaixo.

    O PEDIDO (Tel, 11/09):

        Nay envia esses imóveis para o número 92994717316
        Arezzo Residencial / 2 quartos / 2.5k
        Ariranhas / 2 quartos / 2.6k (incluso a tx)

    As linhas de baixo são saída da PRÓPRIA Nay (`nay_linha_da_lista`) -- ele
    cola de volta a lista que ela mandou. Quem descobre o código de cada uma
    é `nay_imoveis_da_linha`, no banco.

    CÓDIGO NO CABEÇALHO CAI NO CAMINHO ANTIGO. "Nay manda o 5718 pro Sergio"
    seguido de qualquer coisa continua sendo o envio de sempre -- este ramo
    só pega o cabeçalho que NÃO diz qual imóvel, que é a forma em que a lista
    embaixo é a única fonte.
    """
    linhas = texto.split("\n")
    if len(linhas) < 2:
        return None
    itens = [l.strip() for l in linhas[1:] if l.strip()]
    if not itens:
        return None

    m = ENVIO_RE.match(linhas[0].strip())
    if not m:
        return None

    verbo = m.group(1).lower()
    cauda = m.group(3).strip()

    destino, nome_dito = cauda, None
    pedido = m.group(2).strip()
    pelo_telefone = _separar_destino_por_telefone(linhas[0].strip())
    if pelo_telefone:
        destino, nome_dito, resto = pelo_telefone
        pedido = _limpar_pedido(resto)
    # "pro grupo", "pra grade": não é pessoa, segue o caminho antigo.
    elif CAUDA_NAO_E_PESSOA_RE.search(cauda.lower()):
        return None
    else:
        pedido = _limpar_pedido(pedido)

    # Código no cabeçalho: ele já disse qual imóvel, a lista embaixo é outra
    # coisa. Deixa o ENVIO_RE de sempre resolver.
    if _codigos_do_pedido(pedido):
        return None

    if verbo in VERBOS_DE_GRUPO:
        return {
            "acao": "envio_recusado",
            "motivo": (
                "POSTA manda para os grupos e nao sei mandar para uma pessoa com "
                "esse verbo. Se e para o " + cauda + ", escreve: Nay envia esses "
                "imoveis pro " + cauda + " e cola a lista embaixo. Nao mandei nada."
            ),
            "texto": texto,
        }

    # O que ele escreveu no cabeçalho, depois do telefone ("os dois acquarelle
    # ..." numa linha só), é pedido também -- vem antes da lista.
    return {"acao": "enviar_lista_para_corretor",
            "destino": destino,
            "nome_dito": nome_dito,
            "linhas": ([pedido] if pedido else []) + itens,
            "texto": texto}


def _interpretar_envio(texto, m):
    """Devolve a acao de envio privado, ou None para deixar o dispatch seguir.

    None (e nao "nao_reconhecido") quando a cauda nao e pessoa: assim
    "manda o 5750 pro grupo" continua caindo no POSTAR_RE, como sempre fez.
    """
    verbo = m.group(1).lower()
    corpo = m.group(2).strip()
    # O DESTINO PARA NA PRIMEIRA QUEBRA DE LINHA, sempre. O corpo e a cauda
    # do ENVIO_RE sao gulosos e casam `\n`: com um texto de varias linhas, a
    # lista inteira cai aqui dentro e `_resolver_corretor` limpa os
    # nao-digitos do bloco todo -- o telefone vira a colagem dos numeros de
    # todas as linhas. Medido com a lista do Tel: 25 digitos, e os oito
    # ultimos ("21262126") nao sao o telefone dele.
    #
    # Hoje nada disso chega porque o no do n8n quebra em linhas antes. Esta
    # parede existe para o dia em que ele passar a mandar o texto inteiro --
    # que e exatamente o que o envio de LISTA precisa que ele faca.
    cauda = m.group(3).split("\n")[0].strip()
    cauda_l = cauda.lower().strip(" .!?,")

    pelo_telefone = _separar_destino_por_telefone(texto.split("\n")[0])

    # "pro grupo", "pra grade", "pro grupo de anunciar da easy": nao e pessoa.
    # Com telefone escrito o destino e uma pessoa, diga a cauda o que disser.
    if not pelo_telefone and CAUDA_NAO_E_PESSOA_RE.search(cauda_l):
        # CAUDA DE NEGÓCIO COM VERBO DE ENVIO É PEDIDO SEM DESTINATÁRIO
        # (15/09): "envia o vista dos cedros para locação" -- o único "para"
        # da frase é o de "para locação", então não há destinatário nenhum, e
        # cair fora daqui deixava a frase morrer em "não entendi o comando".
        #
        # VERBO DE GRUPO NÃO: "posta o jardim das cerejeiras para locação" tem
        # caminho próprio (`postar_por_nome`), que é quem sabe postar.
        if verbo not in VERBOS_DE_GRUPO and _NEGOCIO_NA_CAUDA_RE.match(cauda_l):
            return {"acao": "enviar_sem_destino",
                    "pedido": _limpar_pedido(corpo + " para " + cauda),
                    "texto": texto}
        return None

    # CAUDA COM DINHEIRO DENTRO NÃO É DESTINATÁRIO, É O PRÓPRIO PEDIDO
    # (15/09). Ele escreveu, sem destino nenhum:
    #
    #   Nay envia casa PARA VENDA em condomínio de 250 mil a 600 mil nos
    #   bairros parque dez, flores e compensa
    #
    # O único "para" da frase é o de "para venda", e como o casador é guloso
    # a cauda vira "venda em condomínio de 250 mil a 600 mil nos bairros
    # parque dez, flores e compensa" -- ela sairia procurando um CORRETOR com
    # esse nome. "Nay envia imóvel comercial para locação de 3 mil a 8 mil"
    # daria o mesmo.
    #
    # A MARCA É O VALOR ESCRITO. "para o Sergio", "pro grupo" e "para
    # locação" (a lista de categoria, que tem caminho próprio e não pode ser
    # roubada aqui) não têm dinheiro na cauda. Sem telefone e com valor, é
    # pedido -- e a resposta é perguntar para quem, mostrando o que entendeu.
    if not pelo_telefone and _cauda_e_pedido(cauda):
        return {"acao": "enviar_sem_destino",
                "pedido": _limpar_pedido(corpo + " para " + cauda),
                "texto": texto}

    # Agendamento nao se mistura com envio: "manda o 5750 pro Sergio todo
    # dia as 9h" seria uma vaga, e vaga posta em GRUPO. Recusa em vez de
    # criar coisa errada.
    if HORA_RE.search(texto) or TODO_DIA_RE.search(texto) or ALTERNANCIA_RE.search(texto):
        return {
            "acao": "envio_recusado",
            "motivo": "Envio para corretor nao aceita horario nem repeticao. "
                      "Para agendar, use posta; para mandar agora, tire o horario.",
            "texto": texto,
        }

    # Verbo de grupo com destinatario pessoal: recusa que ensina.
    if verbo in VERBOS_DE_GRUPO:
        return {
            "acao": "envio_recusado",
            "motivo": (
                "POSTA manda para os grupos e nao sei mandar para uma pessoa com "
                "esse verbo. Se e para o " + cauda + ", escreve: Nay envia <imovel> "
                "pro " + cauda + ". Se era para os grupos, tira o destinatario. "
                "Nao mandei nada."
            ),
            "texto": texto,
        }

    destino, nome_dito, pedido = cauda, None, _limpar_pedido(corpo)
    if pelo_telefone:
        destino, nome_dito, resto = pelo_telefone
        pedido = _limpar_pedido(resto)
    codigos = _codigos_do_pedido(pedido)
    return {
        "acao": "enviar_para_corretor",
        "codigos": codigos,
        "corpo": corpo,
        "destino": destino,
        "nome_dito": nome_dito,
        # Sem código, o que ele DESCREVEU vira pedido -- "toda as casas que
        # temos para locação até 4.200" -- e o publicador resolve no catálogo.
        "pedido": "" if codigos else pedido,
        "texto": texto,
    }


def _interpretar_postar_easy(texto):
    # O EASY TAMBÉM AGENDA (27/09). Ele nunca teve guarda nenhuma aqui:
    # "posta no anunciar easy o 5750 todo dia as 8h" postava na hora e o
    # horário sumia, igual ao Comercial e ao Alto Padrão.
    vaga = _vaga_no_grupo(texto, "easy")
    if vaga:
        return vaga
    # Telefone fora antes de procurar código: o Easy também é grupo, e um
    # telefone com 4 dígitos que casem um código real postaria o imóvel
    # errado. Ver `_codigos_sem_telefone`.
    codigos = _codigos_sem_telefone(texto)
    if len(codigos) != 1:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "postar_easy", "codigo": codigos[0],
            "de_novo": bool(_DE_NOVO_RE.search(texto))}


def _vaga_no_grupo(texto, destino):
    """Ele pediu HORÁRIO para um imóvel num grupo de apelido? Devolve a vaga.

    O PEDIDO (Tel, 27/09): "posta no grupo comercial o 5763 segunda, quarta e
    sexta as 08h ... quero colocar dias diferentes de dia".

    ANTES DE HOJE ISSO POSTAVA NA HORA e engolia o horário em silêncio; depois
    virou recusa, porque o CHECK `vagas_imovel_ou_lista` exigia
    `destino IS NULL` na vaga de imóvel. `vaga_de_grupo.sql` afrouxa o CHECK e
    a recusa vira agendamento.

    DELEGA PARA `_interpretar_posta` EM VEZ DE REESCREVER. Ali já moram a hora
    em nove grafias, os dias da semana, a retirada do telefone antes de
    procurar código e a recusa de "a cada 15 dias" -- reescrever seria a
    segunda cópia de uma gramática que já existe, que é o padrão mais caro
    deste projeto. O que muda é uma linha: o destino carimbado no fim.

    Devolve None quando não há horário nenhum (o comando é postagem imediata),
    e devolve o que `_interpretar_posta` disse quando ele falou de agenda mas
    faltou alguma coisa -- `agenda_incompleta` é resposta melhor que um post
    que ele não pediu.
    """
    if not (HORA_RE.search(texto) or _fala_de_agenda(texto)):
        return None
    r = _interpretar_posta(texto)
    if (r or {}).get("acao") != "criar_vaga":
        return r
    # UM CÓDIGO SÓ, como no comando imediato destes grupos: ele descreveu no
    # singular, e uma vaga com vários postaria em cadeia todo dia.
    if len(r.get("codigos") or []) != 1:
        return {"acao": "agenda_incompleta", "texto": texto}
    r["destino"] = destino
    return r


def _interpretar_postar_lotado(texto):
    """"posta 5713 no grupo lotado todo dia as 12:30" -- um código, quatro grupos.

    Mesmo desenho do Comercial e do Alto Padrão. A diferença mora no banco:
    "lotado" é o primeiro apelido COLETIVO, com quatro grupos em vez de um
    (`grupo_lotado.sql`). O código daqui não muda por causa disso --
    `grupos_com_apelido` sempre devolveu lista.

    A VAGA VEM ANTES DA CONTAGEM DE CÓDIGOS: `as 08:00` vira os "códigos" 08 e
    00, e a frase com hora escrita assim cairia em "não reconheci".
    """
    vaga = _vaga_no_grupo(texto, "lotado")
    if vaga:
        return vaga
    codigos = _codigos_sem_telefone(texto)
    if len(codigos) != 1:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "postar_lotado", "codigo": codigos[0],
            "de_novo": bool(_DE_NOVO_RE.search(texto))}


def _interpretar_postar_comercial(texto):
    """"posta no grupo comercial 5763" -- um código, um grupo.

    Mesmo desenho do `_interpretar_postar_alto_padrao`, inclusive tirar o
    telefone antes de procurar código: um telefone cujos 4 dígitos casem um
    código real postaria o imóvel errado no grupo.

    UM código só, pelo mesmo motivo de lá: ele descreveu no singular, e
    aceitar vários postaria em cadeia sem ele ter pedido.
    A VAGA VEM ANTES DA CONTAGEM DE CÓDIGOS, e isso não é estilo: `as 08:00`
    vira os "códigos" 08 e 00 (`CODIGO_RE` aceita 2 dígitos), então a frase com
    hora escrita assim caía em "não reconheci" antes de chegar ao
    agendamento. É a mesma lição que o caminho da vaga já trazia escrita: a
    HORA SAI DO TEXTO ANTES de procurar código.
    """
    vaga = _vaga_no_grupo(texto, "comercial")
    if vaga:
        return vaga
    codigos = _codigos_sem_telefone(texto)
    if len(codigos) != 1:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "postar_comercial", "codigo": codigos[0],
            "de_novo": bool(_DE_NOVO_RE.search(texto))}


def _interpretar_postar_alto_padrao_easy(texto):
    """"Nay publica no alto padrão easy o 4567" -- o grupo de TODAS AS FOTOS.

    Era o dono do nome "alto padrão" até 27/09. Passou a exigir "anunciar" ou
    "easy" na frase, por decisão do Tel, quando o segundo grupo de alto padrão
    ganhou comando.
    """
    vaga = _vaga_no_grupo(texto, "alto_padrao_easy")
    if vaga:
        return vaga
    codigos = _codigos_sem_telefone(texto)
    if len(codigos) != 1:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "postar_alto_padrao_easy", "codigo": codigos[0],
            "de_novo": bool(_DE_NOVO_RE.search(texto)),
            "forcar": bool(FORCAR_ALTO_PADRAO_RE.search(texto))}


def _interpretar_postar_alto_padrao(texto):
    """"posta 5750 no grupo alto padrão" -- o 🟢 Alto Padrão - OFERTA e BUSCA 🔍.

    DESDE 27/09 É ESTE que responde por "alto padrão", por decisão do Tel. O
    de ANUNCIAR EASY, que respondia antes, passou a exigir "anunciar"/"easy"
    e mora em `_interpretar_postar_alto_padrao_easy`.

    Mesmo desenho do `_interpretar_postar_easy`, inclusive tirar o telefone
    antes de procurar código: um telefone cujos 4 dígitos casem um código real
    postaria o imóvel errado num grupo de 11 corretores.

    UM código só, de propósito. O Tel descreveu o comando no singular ("é um
    código que vou colocar lá"), e aceitar vários aqui postaria em cadeia sem
    ele ter pedido -- cada um com todas as fotos.
    A VAGA VEM ANTES DA CONTAGEM DE CÓDIGOS, e isso não é estilo: `as 08:00`
    vira os "códigos" 08 e 00 (`CODIGO_RE` aceita 2 dígitos), então a frase com
    hora escrita assim caía em "não reconheci" antes de chegar ao
    agendamento. É a mesma lição que o caminho da vaga já trazia escrita: a
    HORA SAI DO TEXTO ANTES de procurar código.
    """
    vaga = _vaga_no_grupo(texto, "alto_padrao")
    if vaga:
        return vaga
    codigos = _codigos_sem_telefone(texto)
    if len(codigos) != 1:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "postar_alto_padrao", "codigo": codigos[0],
            "de_novo": bool(_DE_NOVO_RE.search(texto)),
            "forcar": bool(FORCAR_ALTO_PADRAO_RE.search(texto))}


def _fala_de_agenda(texto):
    """O texto tem intencao de agendar, mesmo que a hora nao tenha sido
    entendida? Dia da semana, "toda semana", "todo dia", "toda terca"."""
    if TODO_DIA_RE.search(texto):
        return True
    if re.search(r"\btod[oa]s?\s+(a|as|o|os)?\s*(semana|semanas|dia|dias)\b",
                 texto, re.IGNORECASE):
        return True
    for nome in DIAS_SEMANA_NOMES:
        if re.search(r"\b" + re.escape(nome) + r"\b", texto, re.IGNORECASE):
            return True
    return False


# "de segunda a sexta" é UM INTERVALO, não dois dias (Tel, 27/09). Antes o
# laço abaixo colhia só as duas pontas e a vaga saía SEGUNDA e SEXTA -- três
# dias a menos, sem erro nenhum na tela. Resultado errado em silêncio é pior
# que recusa, e este saía confirmado como se estivesse certo.
_NOMES_DE_DIA = "|".join(sorted((re.escape(n) for n in DIAS_SEMANA_NOMES),
                                key=len, reverse=True))
_INTERVALO_DIAS_RE = re.compile(
    r"\b(?:de|da|das)\s+(" + _NOMES_DE_DIA + r")s?\s+"
    r"(?:a|à|as|às|ate|até|ao|aos)\s+(" + _NOMES_DE_DIA + r")s?\b",
    re.IGNORECASE)


def _dias_do_intervalo(de, ate):
    """Os dias de `de` até `ate`, na convenção do Postgres (0=domingo).

    DÁ A VOLTA quando o fim vem antes do começo: "de sexta a segunda" é
    sexta, sábado, domingo e segunda -- 5,6,0,1 --, não uma lista vazia.
    """
    d, a = DIAS_SEMANA_NOMES[de.lower()], DIAS_SEMANA_NOMES[ate.lower()]
    dias, atual = [d], d
    while atual != a:
        atual = (atual + 1) % 7
        dias.append(atual)
    return sorted(set(dias))


def _recorrencia_do_trecho(trecho):
    """"todo dia" ou os dias da semana. Devolve None quando não diz nenhum.

    UM LUGAR SÓ: a grade de imóvel (`posta o 5750 todo dia às 14h`) e a de
    lista (`dispara apartamentos para locação todo dia às 9h`) leem daqui. Duas
    leituras de recorrência lado a lado divergiriam na primeira edição -- o
    padrão 4.3 do HISTORICO.
    """
    if TODO_DIA_RE.search(trecho):
        return {"tipo_recorrencia": "diaria"}
    dias = set()
    # O INTERVALO VEM PRIMEIRO e o trecho dele sai do texto: senão o laço
    # abaixo acharia as duas pontas de novo e o resultado seria o mesmo de
    # antes -- só as pontas.
    resto = trecho
    for m in _INTERVALO_DIAS_RE.finditer(trecho):
        dias.update(_dias_do_intervalo(m.group(1), m.group(2)))
        resto = resto.replace(m.group(0), " ")
    # `s?` no fim porque ele escreve no plural: "às segundas, quartas e
    # sextas". Sem isso a frase inteira virava "não reconheci".
    for nome, numero in DIAS_SEMANA_NOMES.items():
        if re.search(r"\b" + re.escape(nome) + r"s?\b", resto, re.IGNORECASE):
            dias.add(numero)
    if dias:
        return {"tipo_recorrencia": "semanal", "dias_semana": sorted(dias)}
    return None


# O que sobra da frase depois de tirar o verbo, o negócio e a moldura. O que
# NÃO é nome de lugar: preposição, artigo e as palavras de comando.
_MOLDURA_DO_POSTA = {
    "o", "a", "os", "as", "do", "da", "dos", "das", "de", "no", "na", "nos",
    "nas", "em", "um", "uma", "para", "pra", "pro", "por", "com", "e", "que",
    "nay", "imovel", "imóvel", "imoveis", "imóveis", "condominio", "condomínio",
    "cond", "residencial", "predio", "prédio", "edificio", "edifício", "ed",
    "ai", "aí", "isso", "esse", "essa", "este", "esta", "agora", "hoje",
    "favor", "pfv", "pf", "ja", "já", "grupos", "grupo", "anunciar", "easy",
}

_NEGOCIO_NO_POSTA_RE = re.compile(
    r"\b(?:para|pra|pro|de|em|p/)?\s*"
    r"(?:loca[çc][ãaoõ]\w*|alug\w*|arrend\w*|vend[ae]s?|vender|venda)\b",
    re.IGNORECASE)


def _negocio_escrito(texto):
    """'locacao', 'venda' ou None -- o que ele escreveu, sem adivinhar.

    Os dois juntos ("venda e locação") dão None de propósito: aí a pergunta
    continua de pé, e perguntar custa uma frase.
    """
    venda = bool(_FALA_DE_VENDA.search(texto.lower()))
    locacao = bool(_FALA_DE_LOCACAO.search(texto.lower()))
    if venda and not locacao:
        return "venda"
    if locacao and not venda:
        return "locacao"
    return None


def _nome_do_posta(texto):
    """O nome do lugar dentro de "posta o jardim das cerejeiras para locação".

    Tira o verbo do começo, o negócio (em qualquer posição -- ele escreve
    "posta PARA LOCAÇÃO o jardim das cerejeiras" também) e a moldura.

    Devolve None quando não sobra nome de verdade: "posta ai", "posta isso"
    não podem virar busca de condomínio -- viram a ajuda de sempre, que ensina
    as formas que ela reconhece.
    """
    t = _VERBO_NO_COMECO_RE.sub("", texto or "", count=1)
    t = _NEGOCIO_NO_POSTA_RE.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip(" ,.;:-")
    if not t:
        return None
    palavras = [p for p in re.split(r"[\s,;]+", t)
                if p.lower().strip(".:;-") not in _MOLDURA_DO_POSTA]
    # Pelo menos uma palavra de nome de verdade -- é o mesmo piso de
    # `casar_condominios`, que não casa chave sem palavra de 4 letras.
    if not any(len(re.sub(r"[^0-9a-zA-ZÀ-ÿ]", "", p)) >= 4 for p in palavras):
        return None
    return " ".join(palavras).strip()


# "locação", "é locação", "para venda", "aluguel" -- ele respondendo qual lado.
_ESCOLHA_NEGOCIO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:[eé]\s+|eh\s+|para\s+|pra\s+|pro\s+|de\s+)?"
    r"(loca[çc][ãaoõ]\w*|alug\w*|arrend\w*|vend[ae]s?|vender|venda)\b"
    r"[\s.!,;]*$", re.IGNORECASE)

# "5725", "o 5725", "codigo 5725" -- o código que ela ofereceu.
_ESCOLHA_CODIGO_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:o\s+|no\s+|esse\s+|c[óo]digo\s+|cod\s+)?"
    r"(\d{3,5})\b[\s.!,;]*$", re.IGNORECASE)

# "3.6k", "o de 3.6k", "R$ 3.600", "3600" -- o valor que ela ofereceu. O
# número puro de 3 a 5 dígitos é CÓDIGO antes de ser valor: é o que ela
# imprime na frente de cada opção, e é o que ele copia.
#
# UM OU DOIS DÍGITOS NÃO SÃO VALOR: "1" e "2" são o que ele escreveria se
# estivesse contando as opções na tela -- e a pergunta dela não as numera,
# imprime o CÓDIGO na frente. Virar "R$ 1" ali seria responder qualquer coisa.
_ESCOLHA_VALOR_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:o\s+|a\s+)?(?:de\s+|por\s+)?(?:r\$\s*)?"
    r"(\d[\d.,]*\s*(?:milh\w*|mil|mi|k|m)|\d{1,3}[.,]\d{3}|\d{3,})\b[\s.!,;]*$",
    re.IGNORECASE)


def _interpretar_escolha_do_posta(texto):
    """A resposta curta dele à pergunta do `posta <nome>`.

    Não olha banco nenhum -- diz só O QUE ELE ESCREVEU. Se existe pergunta
    aberta para isso responder é o publicador que confere; sem pergunta, a
    resposta dele é "não tenho nenhuma pergunta sua esperando resposta".
    """
    t = (texto or "").strip()
    if not t:
        return None
    m = _ESCOLHA_NEGOCIO_RE.match(t)
    if m:
        neg = "venda" if _FALA_DE_VENDA.search(m.group(1).lower()) else "locacao"
        return {"acao": "escolha_do_posta", "negocio": neg, "texto": t}
    m = _ESCOLHA_CODIGO_RE.match(t)
    if m:
        return {"acao": "escolha_do_posta", "codigo": m.group(1), "texto": t}
    m = _ESCOLHA_VALOR_RE.match(t)
    if m:
        return {"acao": "escolha_do_posta", "valor": m.group(1).strip(), "texto": t}
    return None


def _codigos_sem_telefone(texto):
    """Os códigos do texto, com o TELEFONE tirado antes.

    O CASO (23/09): `posta (92) 98478-7190 o 3210` devolvia os "códigos"
    ['92', '98478', '7190', '3210'] -- o telefone inteiro virava imóvel. Ali
    só o 3210 existia, mas um telefone terminado em 4500 postaria o imóvel
    4500 nos 19 grupos, e postagem em grupo não desfaz.

    É a mesma família do `valor_nao_e_codigo.sql`, que já tira o VALOR pelo
    mesmo motivo ("Paga até 4000" virava o imóvel 4000): **número que tem
    outro significado sai antes de procurar código, nunca depois**.

    `_TELEFONE_RE` exige forma de telefone (8+ dígitos com DDD e separador),
    então hora ("às 14h") e recorrência ("a cada 15 dias") passam intactas --
    quem cuida delas é o `HORA_RE`, antes daqui.
    """
    return CODIGO_RE.findall(_TELEFONE_RE.sub(" ", texto or ""))


def _interpretar_posta(texto):
    # Antes de qualquer extração: o texto inteiro, não só o trecho antes da
    # hora. "a cada 15 dias" vem DEPOIS do código, e é justamente ali que o
    # 15 seria colhido como se fosse imóvel.
    if ALTERNANCIA_RE.search(texto):
        return {"acao": "nao_reconhecido", "texto": texto}

    m_hora = HORA_RE.search(texto)

    # A HORA SEM O "h" só é tentada aqui, depois do `HORA_RE` falhar e só
    # quando a frase fala de agenda. Ver `HORA_SOLTA_RE`.
    hora_solta = None
    if not m_hora and _fala_de_agenda(texto):
        hora_solta = HORA_SOLTA_RE.search(texto)

    if not m_hora and not hora_solta:
        # Se o texto fala de agenda -- dia da semana, "toda semana", "todo
        # dia" -- e a hora nao foi entendida, NAO posta. Postagem em 14
        # grupos nao tem desfazer; pedir a hora de novo custa uma frase.
        if _fala_de_agenda(texto):
            return {"acao": "agenda_incompleta", "texto": texto}
        codigos = _codigos_sem_telefone(texto)
        if not codigos:
            # PELO NOME DO CONDOMÍNIO (Tel, 15/09): "Posta o jardim das
            # cerejeiras". Literal dele: *"eu nunca lembro por código e
            # preciso que neste caso quando eu pedir pelo nome do condomínio,
            # ela procure"*. Quem resolve o nome contra o catálogo é o
            # publicador (precisa de banco); aqui só se lê o nome e, se ele
            # disse, o negócio.
            nome = _nome_do_posta(texto)
            if nome:
                return {"acao": "postar_por_nome", "nome": nome,
                        "negocio": _negocio_escrito(texto), "texto": texto}
            return {"acao": "nao_reconhecido", "texto": texto}
        return {"acao": "postar_agora", "codigos": codigos}

    m_usado = m_hora or hora_solta
    horario = (_horario_do_match(m_hora) if m_hora
               else datetime.time(int(hora_solta.group("solta")), 0))

    # Tira a hora do texto: e o unico trecho com digito que nao e codigo.
    # Assim "as 17hr o 5717" e "o 5717 as 17hr" dao no mesmo -- antes so a
    # segunda ordem funcionava, e a primeira virava disparo imediato.
    sem_hora = texto[: m_usado.start()] + " " + texto[m_usado.end():]

    matches_codigo = list(CODIGO_RE.finditer(sem_hora))
    codigos = [m.group() for m in matches_codigo]
    if not codigos:
        return {"acao": "agenda_incompleta", "texto": texto}

    # Os dias podem estar em qualquer lugar; procura no texto todo sem a
    # hora e sem os codigos, para nao confundir numero com dia.
    trecho_dias = CODIGO_RE.sub(" ", sem_hora)

    recorrencia = _recorrencia_do_trecho(trecho_dias)
    if not recorrencia:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "criar_vaga", "horario": horario, "codigos": codigos,
            **recorrencia}
