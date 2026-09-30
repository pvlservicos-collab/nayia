"""
De que imóveis o Tel está falando quando ele DESCREVE em vez de dar código.

O PEDIDO (Tel, 14/09): "esse mesmo comando que eu estou te passando aqui para
enviar imóveis para corretor, coloca na Nay". Os três que ele tinha passado:

    envia toda as casas que temos para locação até 4.200 para corretora
    Flavia Soares 92 9131-8844

    manda para Ana 92 9396-5797 os imóveis que ela está pedindo
    os dois acquarelle que ela está pedindo de 2 e 3 quartos que temos
    disponível para locação
    e a casa do morada do pássaros, envia as informações e as fotos para ela.

    envia para o número da corretora parceira Waldyrene 92 9307-2954 ...
    (+ a lista que a própria Nay gera, que já tinha caminho)

MEDIDO ANTES DE ESCREVER: a lista colada já funcionava; o pedido da Ana não
achava nada; e o da Flávia era PERIGOSO -- o parser lia "4.200" como os
códigos 4 e 200, que não existem, e o site devolve página vazia que o envio
aceitava. A Flávia receberia dois cards "📍 Imóvel 4".

A POLÍTICA É A DA LISTA OFICIAL (`nay_lista_de_imoveis`): imóvel nosso, com
anúncio no ar. "Que temos disponível" é exatamente isso, e foi o que eu fiz à
mão nos três pedidos. O que fica de fora -- fora do site, de parceiro -- é
DITO na resposta, nunca sumido.

TUDO QUE NÃO FECHA VIRA PERGUNTA. "a casa do morada do pássaros" com duas
casas nossas no ar seria escolher por ele; "os dois acquarelle" com três
candidatos também. Envio de WhatsApp não desfaz.

A leitura do texto é pura (testável sem banco); o casamento contra o catálogo
fica em `imoveis_do_pedido`, que é quem conversa com a tabela.
"""
import re

from interpretar_comando import (NOME_DA_CATEGORIA, _FALA_DE_LOCACAO,
                                 _FALA_DE_VENDA)
from montar_destinos import e_comercial, e_residencial
from quando_da_visita import sem_acento

# Mais que isso numa leva só é recado para o corretor ler por uma hora -- e
# ~1 minuto de envio por imóvel com fotos. O da Waldyrene (8 imóveis) levou 12.
# Acima do teto ela não manda: devolve quantos são e pede para estreitar.
LIMITE_POR_ENVIO = 15

# Palavras que não identificam condomínio nenhum. "morada DO pássaros" (como o
# Tel escreveu) e "Morada DOS Pássaros" (como está no cadastro) têm que casar.
_VAZIAS = {
    "a", "o", "as", "os", "e", "de", "do", "da", "dos", "das", "no", "na",
    "nos", "nas", "em", "um", "uma", "para", "pra", "pro", "com", "que",
}

# O que pode vir LOGO ANTES de um nome de condomínio de uma palavra só sem
# que o Tel esteja nomeando outro lugar. `_palavras` já tirou artigo e
# preposição; ficam os verbos, a quantidade e o tipo de imóvel.
_ANTES_DO_NOME = {
    "manda", "mande", "mandar", "envia", "envie", "enviar", "repassa",
    "dois", "duas", "tres", "todos", "todas", "toda", "todo", "esse", "esses",
    "essa", "essas", "este", "estes", "esta", "estas", "aquele", "aquela",
    "casa", "casas", "apartamento", "apartamentos", "ap", "aps", "apto", "aptos",
    "sala", "salas", "lote", "lotes", "cobertura", "flat", "sobrado",
    "condominio", "cond", "residencial", "edificio", "ed", "predio", "parque",
    "torre", "bloco", "imovel", "imoveis", "opcao", "opcoes",
}

_QUANTIDADE = {"dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5,
               "seis": 6, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6}

# "os dois acquarelle" -- a quantidade PRECISA do artigo, senão "2 quartos"
# viraria "dois imóveis".
_QUANTIDADE_RE = re.compile(
    r"\b(?:os|as)\s+(dois|duas|tres|quatro|cinco|seis|[2-6])\b(?!\s*(?:quartos?|qtos?|qts?|suites?))")
_TODOS_RE = re.compile(r"\btod[oa]s?\b")

# "de 2 e 3 quartos", "3 e 2 qtos" (é como a Ana escreveu), "2 ou 3 quartos",
# "2/3 quartos", "3 quartos".
_QUARTOS_RE = re.compile(
    r"((?:\b\d\s*(?:,|e|ou|/|a)\s*)*\b\d)\s*(?:quartos?|qtos?|qts?|dormit\w*)")

# Teto e piso de valor. O token é resolvido por `nay_valor_escrito` no banco,
# a mesma leitura das linhas coladas -- "4.200", "4.2k", "4 mil" dão o mesmo.
# A ORDEM DAS ALTERNATIVAS É O QUE FAZ "3 milhões" VALER TRÊS MILHÕES: com
# "mil" antes, o casador pega "3 mil", tropeça no "hões" e volta para o número
# solto -- e "até 3 milhões" vira "até R$ 3.000", que foi o que ele mediu em
# 15/09. Do mais comprido para o mais curto, sempre.
_VALOR = r"(?:r\$\s*)?(\d[\d.,]*\s*(?:milh\w*|mil|mi|k|m)?)\b"
# "de 3200 A ATÉ 5.000" (Tel, 28/09): ele escreve as duas ligações juntas,
# e só "a" ou só "até" casavam -- a faixa inteira era perdida e sobrava o
# teto, mandando também o que estava ABAIXO do piso. A alternativa mais
# longa vem primeiro, senão o "a" casa sozinho e o "ate" sobra na frente
# do valor, que não casa mais.
_FAIXA_RE = re.compile(r"\bde\s+" + _VALOR + r"\s+(?:a\s+ate|ate|a)\s+" + _VALOR)
_TETO_RE = re.compile(r"\b(?:ate|no maximo|maximo de|max)\s+" + _VALOR)
_PISO_RE = re.compile(r"\b(?:a partir de|acima de|minimo de)\s+" + _VALOR)

# VALOR SOLTO É VALOR EXATO. "Grand Prix / 2 quartos sendo 1 suíte / 3.5k"
# não casa pela linha (o único Grand Prix de locação é o 4159, a R$ 4.000) e
# cairia aqui; sem ler o "3.5k", o leitor mandaria o de 4k -- que foi
# justamente o que ficou de fora de propósito no pedido da Waldyrene em 14/09.
# Dinheiro perto não é dinheiro igual. Só conta como valor o que TEM cara de
# valor ("3.5k", "2.600", "4 mil"), senão "o 5718" viraria preço.
_VALOR_SOLTO_RE = re.compile(
    r"(?:r\$\s*)?\b(\d+[.,]?\d*\s*milh\w*|\d+[.,]\d+\s*(?:k|mil|m)\b"
    r"|\d+\s*(?:k|mil)\b|\d{1,3}\.\d{3}\b)")

# E "DE <NÚMERO>" TAMBÉM É VALOR, mesmo sem ponto nem sufixo (Tel, 25/09).
# "envia o parque imperial de 2750 para locação": o 2750 não tem cara de
# dinheiro pela regra acima -- e por isso caía na faixa dos códigos e virava
# "2750: nao achei esse codigo no site".
#
# O "de" é a marca. Ele chama o imóvel de "o 5750", nunca de "de 5750", e
# quando escreve "de" já nomeou o condomínio antes. MEDIDO no corpus: zero
# mensagens com "de <número de 3 a 5 dígitos>", então a marca não disputa com
# nada que já exista.
#
# A cauda de unidade fica de fora, senão "área de 250m2" viraria preço de 250.
# Os quartos já saíram do texto antes daqui (`sem_quartos`), então "de 2
# quartos" nunca chega -- e o mínimo de três dígitos também o excluiria.
# O SUFIXO DE DINHEIRO TAMBÉM FICA DE FORA, e isto o teste pegou: "de 700 mil"
# casa nas DUAS regras e o valor entrava duplicado -- ['700 mil', '700'] --,
# abrindo a porta para casar um imóvel de R$ 700. Quando há sufixo, a regra de
# cima já leu o valor inteiro e esta não tem nada a acrescentar.
_VALOR_APOS_DE_RE = re.compile(
    r"\bde\s+(\d{3,7})(?!\d)"
    r"(?!\s*(?:m2|m²|mil\b|milh\w*|k\b|m\b|quartos?|qtos?|qts?|su[ií]tes?|vagas?|banheiros?|dormit))")


# COMERCIAL E RESIDENCIAL SÃO USO, NÃO CATEGORIA (15/09). O Tel pediu que a
# faixa de valor valesse "para imóvel comercial e residencial", e pela
# categoria isso não fecha: `nay_categoria_do_imovel` só conhece "sala", e só
# a que está em condomínio. Medido no catálogo de hoje: dos 25 comerciais no
# ar, 9 (Loja/Ponto, Prédio, Galpão/Depósito e uma Sala solta) NÃO TÊM
# categoria nenhuma -- filtro por categoria nunca os acharia.
#
# Então o perfil filtra pelo TIPO do cadastro, com a mesma regra que decide o
# grupo "🟢 Comercial" (`montar_destinos.e_comercial`). Uma cópia só.
_PERFIL_COMERCIAL_RE = re.compile(
    r"\bcomercia\w*\b|\bgalp\w*\b|\bdeposito\b|\bpredios?\b")

# "residencial" é palavra de NOME DE CONDOMÍNIO ("Residencial Ponta Negra I"),
# e por isso ela só vale como perfil quando está sozinha como qualificador --
# no plural, depois de "imóvel", ou antes de preposição/limite. "Residencial
# Acquarelle de 3 quartos" continua sendo o condomínio, não o perfil.
_PERFIL_RESIDENCIAL_RE = re.compile(
    r"\bresidenciais\b"
    r"|\b(?:imove(?:l|is)|opc\w*|coisas?)\s+residencial\b"
    r"|\bresidencial\s+(?:para|de|em|ate|no|na|nos|nas|com|acima|entre|a)\b")


def _perfil(t):
    """Uso do imóvel que a frase pede: 'comercial', 'residencial' ou nada."""
    if _PERFIL_COMERCIAL_RE.search(t):
        return "comercial"
    if _PERFIL_RESIDENCIAL_RE.search(t):
        return "residencial"
    return None


def _categorias(t):
    """As categorias de `nay_categoria_do_imovel` que a frase cobre.

    "casa" sozinha são AS DUAS -- de condomínio e de rua. Foi assim que o
    pedido da Flávia ("todas as casas") foi atendido à mão: escolher uma só
    esconderia metade das casas.
    """
    cats = set()
    if re.search(r"\bcasas?\b|\bsobrados?\b", t):
        # "FORA DE CONDOMÍNIO" É VIA PÚBLICA, e vem ANTES -- a ordem é o
        # conserto. A busca por "condom" casa dentro de "fora de condomínio",
        # então a frase que PEDE casa de rua mandava justamente a de
        # condomínio. Medido em 27/09 com a frase dele: "casas para ela até
        # 3.000 fora de condomínio" devolvia o 5551 (que É de condomínio) e
        # escondia o 1327 e o 5709, que são as de rua.
        if re.search(r"\b(fora|sem)\s+(de\s+|do\s+)?condom"
                     r"|\bnao\s+(e|eh|sao)\s+(de\s+)?condom"
                     r"|\bnenhum\s+condom", t):
            cats.add("casa_via_publica")
        elif re.search(r"condom", t):
            cats.add("casa_condominio")
        elif re.search(r"\brua\b|via\s*publica|avulsa", t):
            cats.add("casa_via_publica")
        else:
            cats |= {"casa_condominio", "casa_via_publica"}
    if re.search(r"\bapartamentos?\b|\baptos?\b|\baps?\b|\bcoberturas?\b|\bflats?\b", t):
        cats |= {"apartamento", "apartamento_via_publica"}
    if re.search(r"\bsalas?\b|\bcomerciais\b|\bcomercial\b|\blojas?\b", t):
        cats.add("sala")
    if re.search(r"\blotes?\b|\bterrenos?\b", t):
        cats.add("lote")
    return cats


def e_titulo_ou_recado(linha):
    """Linha que não descreve imóvel: o título da lista e o recado em volta.

    Medido no pedido da Waldyrene: "✅ APARTAMENTOS DISPONÍVEIS PARA" e "ela
    pediu os imóveis abaixo:" viravam "não achei imóvel para ..." na resposta.
    Não é erro -- é a moldura da mensagem.
    """
    s = (linha or "").strip()
    if not s:
        return True
    if s.endswith(":"):
        return True
    # Começa com emoji/símbolo: pode ser o TÍTULO que a própria Nay escreve ou,
    # desde 15/09, um IMÓVEL -- o Tel pôs ✅ colado na frente de cada linha da
    # lista e passou o título para "🔥 ... 🔥". A regra anterior ("começa com
    # emoji é título") descartaria TODOS os imóveis de uma lista colada, e a
    # Nay responderia que não achou nada, em silêncio.
    #
    # O que separa é o " / ": toda linha de `nay_linha_da_lista` tem, nenhum
    # título tem. "Caixa alta = título" não serve -- medido em 15/09, 12 das
    # 858 linhas reais começam com palavra em caixa alta (condomínio cadastrado
    # assim).
    if not (s[0].isalnum() or s[0] in "\"'("):
        return " / " not in s
    return False


# A MOBÍLIA COMO FILTRO (Tel, 28/09): "envia o imóvel para o Walter no tarumã
# e ponta negra até 3.500 mas que esteja **só marcado como mobiliado**".
#
# "SÓ MOBILIADO" EXCLUI O SEMI, e é o ponto todo do pedido dele. Medido no
# catálogo: `mobiliado` e `mobiliado (moveis + cama + tudo)` são 38 imóveis;
# `semi-mobiliado` e `semi-mobiliado (moveis planejados + ar)` são outros 74.
# Quem pede mobiliado e recebe semi recebe imóvel errado.
#
# A ORDEM IMPORTA: "semi-mobiliado" CONTÉM "mobiliado". O semi é lido primeiro,
# senão toda frase com semi cairia em mobiliado -- e é o erro que manda os 74.
_SEMI_MOBILIADO_RE = re.compile(r"\bsemi[\s-]*mobiliad\w*", re.IGNORECASE)
_MOBILIADO_RE = re.compile(r"\bmobiliad\w*|\bcom\s+mobili\w*", re.IGNORECASE)
_SEM_MOBILIA_RE = re.compile(
    r"\bsem\s+mobili\w*|\bvazi[oa]s?\b|\bdesmobiliad\w*", re.IGNORECASE)


def _mobilia(t):
    """'mobiliado', 'semi', 'sem' -- ou None quando a frase não fala disso.

    `t` já vem sem acento. Devolve None sempre que ele não pediu: filtro que
    aparece sozinho tiraria imóvel de todo pedido que não menciona mobília.
    """
    if _SEM_MOBILIA_RE.search(t):
        return "sem"
    if _SEMI_MOBILIADO_RE.search(t):
        return "semi"
    if _MOBILIADO_RE.search(t):
        return "mobiliado"
    return None


def ler_pedido(texto):
    """As marcas que a frase traz. Não consulta nada."""
    t = sem_acento(texto)

    quartos = set()
    for m in _QUARTOS_RE.finditer(t):
        quartos |= {int(d) for d in re.findall(r"\d", m.group(1))}
    # quartos saem ANTES de ler valor: "de 2 a 3 quartos" não é faixa de preço
    sem_quartos = _QUARTOS_RE.sub(" ", t)

    piso = teto = None
    m = _FAIXA_RE.search(sem_quartos)
    if m:
        piso, teto = m.group(1), m.group(2)
    else:
        m = _TETO_RE.search(sem_quartos)
        teto = m.group(1) if m else None
        m = _PISO_RE.search(sem_quartos)
        piso = m.group(1) if m else None

    resto = _TETO_RE.sub(" ", _PISO_RE.sub(" ", _FAIXA_RE.sub(" ", sem_quartos)))
    valores = [m.group(1) for m in _VALOR_SOLTO_RE.finditer(resto)]
    valores += [m.group(1) for m in _VALOR_APOS_DE_RE.finditer(resto)]

    venda = bool(_FALA_DE_VENDA.search(t))
    locacao = bool(_FALA_DE_LOCACAO.search(t))
    negocio = "venda" if venda and not locacao else \
              "locacao" if locacao and not venda else None

    m = _QUANTIDADE_RE.search(t)
    return {
        "quartos": quartos,
        "piso": piso,
        "teto": teto,
        "valores": valores,
        "negocio": negocio,
        "categorias": _categorias(t),
        "perfil": _perfil(t),
        "mobilia": _mobilia(t),
        "todos": bool(_TODOS_RE.search(t)),
        "quantidade": _QUANTIDADE.get(m.group(1)) if m else None,
        "titulo": e_titulo_ou_recado(texto),
    }


def _palavras(texto):
    return [p for p in re.findall(r"[a-z0-9]+", sem_acento(texto))
            if p not in _VAZIAS]


def _radical(palavra):
    """A palavra sem o "s" do plural. "vistas" e "vista" têm que casar.

    MEDIDO em 15/09, no pedido dele: o cadastro tem "Vistas dos Cedros" e ele
    escreveu "envia o VISTA dos cedros para locação". A Nay respondeu "não
    consegui identificar nenhum imóvel assim" -- o imóvel existia, estava no
    ar, e a única diferença era um "s".

    Bruto de propósito: não é radical de verdade, é só o plural mais comum do
    português. Um stemmer inteiro traria "morada"/"morar" junto, e aí nomes
    diferentes começariam a casar entre si.
    """
    return palavra[:-1] if len(palavra) > 3 and palavra.endswith("s") else palavra


def casar_condominios(texto, condominios):
    """Os condomínios cujo nome INTEIRO aparece na frase.

    `condominios` é [(nome, chave)], com a chave de `nay_chave_condominio` (o
    nome sem "condomínio", "residencial", "parque"...). Casa quando TODAS as
    palavras da chave estão na frase -- "os dois acquarelle que ela está
    pedindo" contém "acquarelle", e "a casa do morada do pássaros" contém
    "morada" e "passaros".

    A PALAVRA INTEIRA, não pedaço: "Moradas do Parque" não casa com "morada".
    E vale o nome MAIS COMPRIDO que casou -- "Residencial Ponta Negra I" não
    pode perder para um condomínio chamado só "Negra".

    Chave sem nenhuma palavra de 4 letras ou mais não casa nada: "Casa",
    "Apartamento" e rótulos parecidos existem como `condominio_nome` e casariam
    com qualquer frase.
    """
    sequencia = _palavras(texto)
    presentes = set(sequencia)
    radicais = {_radical(p) for p in presentes}
    achados = []
    for nome, chave in condominios:
        palavras = _palavras(chave)
        if not palavras or not any(len(p) >= 4 for p in palavras):
            continue
        # O PLURAL SÓ VALE COM DUAS PALAVRAS OU MAIS. "vista dos cedros" casa
        # "Vistas dos Cedros" porque as DUAS palavras batem; com uma palavra
        # só, a tolerância transformaria "morada" em "Moradas do Parque" --
        # nome diferente, condomínio diferente, e o Tel não teria escrito.
        #
        # Medido contra o catálogo inteiro (388 condomínios, 776 frases): a
        # tolerância não faz nenhum nome exato casar com condomínio errado.
        if not (set(palavras) <= presentes
                or (len(palavras) >= 2
                    and {_radical(p) for p in palavras} <= radicais)):
            continue
        # NOME DE UMA PALAVRA SÓ COLADO A UMA PALAVRA DESCONHECIDA NÃO CASA.
        # Medido na prova de 14/09: "a casa do xanadu imperial" casou com o
        # "Parque Imperial" (chave "imperial"). Falhou fechado só porque ali não
        # há casa; com "apartamento" no lugar mandaria o 5717 -- um condomínio
        # que ele não pediu. Quem nomeia outro lugar escreve a palavra do nome
        # logo antes; quem pede este escreve "o", "do", "apartamento", "parque".
        if len(palavras) == 1:
            nome_inteiro = set(_palavras(nome))
            if any(i > 0 and sequencia[i - 1] not in _ANTES_DO_NOME
                   and sequencia[i - 1] not in nome_inteiro
                   for i, p in enumerate(sequencia) if p == palavras[0]):
                continue
        achados.append((len(palavras), nome))
    if not achados:
        return []
    maior = max(n for n, _ in achados)
    return sorted({nome for n, nome in achados if n == maior})


def casar_bairros(frase_normalizada, bairros):
    """Os bairros que a frase nomeia. `bairros` é [(nome, chave)], os dois já
    normalizados por `nay_normalizar_lugar` NO BANCO.

    POR QUE A NORMALIZAÇÃO VEM DE LÁ: é ela que faz "parque dez" virar
    "parque 10" e "pq" virar "parque". Repetir isso em Python seria a segunda
    cópia de uma regra de casamento de lugar -- o padrão 4.3 do HISTORICO.

    Duas faixas, a mesma ideia do casamento de condomínio:
      * o nome INTEIRO escrito ("flores", "compensa", "parque das laranjeiras");
      * ou METADE das palavras e NUNCA UMA SÓ -- é o que faz "parque dez" achar
        "Parque 10 de Novembro" sem que "parque" sozinho arraste todo bairro
        que começa com Parque. Medido: com uma palavra só, "parque dez" também
        casaria "Parque das Laranjeiras".

    Devolve TODOS os que casaram: ele lista vários de uma vez ("flores, paz,
    parque dez, compensa").
    """
    presentes = set(frase_normalizada.split())
    achados = []
    for nome, chave in bairros:
        palavras = [p for p in (chave or "").split() if p not in _VAZIAS]
        if not palavras:
            continue
        tem = [p for p in palavras if p in presentes]
        if len(tem) == len(palavras):
            achados.append(nome)
        elif len(tem) >= 2 and len(tem) * 2 >= len(palavras):
            achados.append(nome)
    return sorted(set(achados))


def desempatar_condominio_e_bairro(nomes, bairros, chave_de=None):
    """Quando o nome de um cabe dentro do nome do outro, o MAIS ESPECÍFICO fica.

    Os dois casadores olham a mesma frase sem saber um do outro, e quando um
    nome contém o outro os dois casam. A consulta então vira condomínio E
    bairro, não sobra imóvel nenhum, e o Tel ouve "não achei imóvel para ...".

    Aconteceu nos DOIS sentidos, e cada um custou um pedido perdido:

      * 15/09 -- "parque das laranjeiras" é BAIRRO, e o casador de condomínio
        achou "Condomínio Laranjeiras" e "Residencial Laranjeiras". Aqui o
        BAIRRO é o específico: cai o condomínio.

      * 25/09 -- "o mirante das flores" é CONDOMÍNIO, em Ponta Negra, e o
        casador de bairro achou "Flores". Aqui o CONDOMÍNIO é o específico:
        cai o bairro. A recusa dizia "(entendi: locação; no Mirante Das
        Flores; no bairro Flores)" -- ela leu os dois e cruzou.

    O critério é conter, não parecer: só cai o lado cujas palavras estão
    TODAS dentro do outro. "Residencial Ponta Negra I" continua de pé mesmo
    com o bairro Ponta Negra na frase, porque o "i" não está lá.

    Devolve `(nomes, bairros)`.
    """
    if not nomes or not bairros:
        return nomes, bairros
    chave_de = chave_de or {}

    palavras_dos_bairros = {p for b in bairros for p in _palavras(b)}
    nomes = [n for n in nomes
             if not set(_palavras(chave_de.get(n, n))) <= palavras_dos_bairros]

    # O segundo passo olha os nomes QUE SOBRARAM. Sem isso, quando os dois
    # lados se contêm um ao outro os dois cairiam e o pedido ficaria sem
    # lugar nenhum -- que é o mesmo "não achei" por outro caminho.
    if not nomes:
        return nomes, bairros
    palavras_dos_nomes = {p for n in nomes
                          for p in _palavras(chave_de.get(n, n))}
    bairros = [b for b in bairros
               if not set(_palavras(b)) <= palavras_dos_nomes]
    return nomes, bairros


def _resumo_do_pedido(f, nomes, bairros, teto_txt, piso_txt):
    """O que ela ENTENDEU da frase, em português.

    Vai na recusa porque recusa que não diz o que entendeu não ensina nada: o
    Tel escreveu "as casas de locação no parque dez até 4.000" e a resposta foi
    só "não achei imóvel para <a frase dele>". Com o resumo ele vê na hora que
    ela leu CASA -- e que o que existe ali é apartamento.
    """
    partes = []
    if f["categorias"] and not (f["perfil"] == "comercial"
                                and set(f["categorias"]) <= {"sala"}):
        partes.append(", ".join(sorted(NOME_DA_CATEGORIA.get(c, c)
                                       for c in f["categorias"])))
    if f["perfil"]:
        partes.append("imóvel " + f["perfil"])
    if f["quartos"]:
        partes.append(" e ".join(str(q) for q in sorted(f["quartos"])) + " quartos")
    if f["negocio"]:
        partes.append("locação" if f["negocio"] == "locacao" else "venda")
    # A MOBÍLIA ENTRA NO RESUMO como tudo o mais: recusa que não diz o que
    # entendeu não ensina nada, e aqui ele precisa ver que ela leu "só
    # mobiliado" e não "semi".
    if f.get("mobilia"):
        partes.append({"mobiliado": "só mobiliado",
                       "semi": "semi-mobiliado",
                       "sem": "sem mobília"}[f["mobilia"]])
    if nomes:
        partes.append("no " + ", ".join(nomes))
    if bairros:
        partes.append("no bairro " + ", ".join(bairros))
    if teto_txt and piso_txt:
        partes.append(f"de {piso_txt} a {teto_txt}")
    elif teto_txt:
        partes.append(f"até {teto_txt}")
    elif piso_txt:
        partes.append(f"a partir de {piso_txt}")
    return "; ".join(partes)


def condominios_parecidos(frase, condominios, limite=3):
    """Os nomes do catálogo que compartilham palavra com o que ele escreveu.

    PARA A RECUSA DIZER ALGO ÚTIL. Em 15/09 ele mandou "envia o vista dos
    cedros para locação para 92 9191-3793" e ouviu "não consegui identificar
    nenhum imóvel assim" -- sem nenhuma pista de que o cadastro escreve
    "Vistas dos Cedros". Recusa que não ensina faz ele tentar de novo às
    cegas.

    Só palavra de 4 letras ou mais conta: "casa", "dos" e "do" apontariam
    metade do catálogo.
    """
    presentes = {_radical(p) for p in frase.split() if len(p) >= 4}
    if not presentes:
        return []
    pontos = []
    for nome, chave in condominios:
        palavras = [p for p in _palavras(chave) if len(p) >= 4]
        if not palavras:
            continue
        batem = sum(1 for p in palavras if _radical(p) in presentes)
        if batem:
            pontos.append((batem / len(palavras), batem, nome))
    if not pontos:
        return []
    pontos.sort(reverse=True)
    # SÓ OS MELHORES, não os três primeiros: com "vista dos cedros" casando
    # inteiro o "Vistas dos Cedros", oferecer também o "Vista das Mangueiras"
    # (que bate meia palavra) faz a pista virar ruído.
    melhor = pontos[0][0]
    return [nome for r, _, nome in pontos[:limite] if r == melhor]


def condominios_do_catalogo(conn):
    """[(nome, chave)] de todo condomínio de verdade que existe no catálogo.

    UM LUGAR SÓ porque são dois os caminhos que casam nome de condomínio: o
    pedido descrito ("os dois acquarelle") e o `posta <nome>` (15/09). A
    chave é a de `nay_chave_condominio` -- o nome sem "condomínio",
    "residencial", "parque".
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT DISTINCT nay_condominio_de_verdade(tipo, condominio_nome) AS nome, "
            "       nay_chave_condominio(condominio_nome) AS chave "
            "  FROM imoveis "
            " WHERE nay_condominio_de_verdade(tipo, condominio_nome) IS NOT NULL")
        return [(l["nome"], l["chave"]) for l in cur.fetchall()]


LIMITE_LEITURAS_DE_MOBILIA = 40


def _casa_mobilia(valor, pedido):
    """O rótulo casa o que ele pediu? `valor` é o texto do cadastro."""
    v = (valor or "").strip().lower()
    if pedido == "semi":
        return v.startswith("semi")
    if pedido == "mobiliado":
        return v.startswith("mobiliad")
    if pedido == "sem":
        # SEM MOBÍLIA INCLUI O VAZIO e o "so ar-condicionado": quem pede sem
        # mobília não quer ouvir "não tenho nenhum" por causa de campo em
        # branco, e ar-condicionado não é móvel.
        return v == "" or v.startswith("so ar") or v.startswith("sem")
    return True


def _mobilia_conferida(conn, codigos, buscar=None, pausa=None):
    """A mobília de cada código, LIDA NO SITE. Devolve {codigo: rótulo}.

    O PEDIDO (Tel, 28/09): "quando eu coloco mobiliado ou semi-mobiliado a Nay
    precisa olhar no sistema para saber se está marcado na caixa esta opção
    para poder enviar o correto".

    ELE ESTÁ CERTO, e a medida mostra o tamanho: dos 20 candidatos do pedido
    dele, SEIS divergiam -- todos com a coluna VAZIA no banco e a caixa
    marcada no anúncio. O pedido "só semi-mobiliado" devolvia 5 imóveis; os
    certos eram 9. Quatro que ele deveria receber ficavam de fora, calados.

    POR QUE O BANCO ATRASA: `preencher_do_anuncio` só olha imóvel de LOCAÇÃO
    (`coalesce(valor_aluguel,0) > 0` no escopo padrão) e só grava onde a
    coluna está VAZIA -- nunca atualiza o que já tem valor. Então imóvel de
    venda nunca ganha mobília, e o que veio da importação de agosto nunca
    muda.

    GRAVA O QUE APRENDE, então o banco converge: a lista, o card e a próxima
    busca passam a ver o mesmo. Escreve também por cima do que já existia --
    aqui o site é a autoridade, que é o que ele pediu.

    FALHA ISOLADA: anúncio que não abre fica com o valor do banco. E anúncio
    fora do ar não zera nada -- é a armadilha do dict truthy, já registrada.
    """
    import time as _time
    from buscar_imovel import buscar_imovel as _buscar_padrao
    buscar = buscar or _buscar_padrao
    pausa = pausa if pausa is not None else _time.sleep

    with conn.cursor() as cur:
        cur.execute("SELECT codigo::text AS c, mobilia FROM imoveis "
                    " WHERE codigo::text = ANY(%s)", (list(codigos),))
        conhecido = {l["c"]: l["mobilia"] for l in cur.fetchall()}

    for i, cod in enumerate(list(codigos)[:LIMITE_LEITURAS_DE_MOBILIA]):
        if i:
            pausa(1.5)
        try:
            imovel = buscar(cod)
        except Exception:
            continue
        if not imovel or not imovel.get("tipo"):
            continue          # fora do ar: não zera o que o banco sabe
        do_site = (imovel.get("mobilia") or "").strip()
        if not do_site or do_site == (conhecido.get(cod) or "").strip():
            continue
        conhecido[cod] = do_site
        try:
            with conn.cursor() as cur:
                cur.execute("UPDATE imoveis SET mobilia = %s, sincronizado_em = now() "
                            " WHERE codigo::text = %s", (do_site, cod))
            conn.commit()
        except Exception:
            try:
                conn.rollback()
            except Exception:
                pass
    return conhecido


def _sem_os_valores(texto):
    """O texto sem os trechos de VALOR -- faixa, teto e piso.

    POR QUE EXISTE (Tel, 28/09): ele escreveu "só semi-mobiliado de 3200 a até
    5.000" e recebeu o IMÓVEL 3200 (Palacio das Águas, sem valor de aluguel).
    O `nay_codigos_citados` roda antes de tudo em `imoveis_do_pedido` e leu o
    piso da faixa como código.

    A FUNÇÃO DO BANCO JÁ TIRA VALOR, e bem -- "Paga até 4000" não vira o
    imóvel 4000. Mas ela reconhece dinheiro pela CARA ("3.5k", "2.600",
    "4 mil"), e "3200" cru não tem cara de dinheiro nenhuma. Quem sabe que
    aquilo é dinheiro é a POSIÇÃO: veio depois de "de", dentro de uma faixa.

    Por isso a limpeza mora aqui, onde a faixa é lida, e não lá: seria pedir
    a uma regra de aparência que adivinhasse contexto.
    """
    t = sem_acento(texto or "")
    t = _QUARTOS_RE.sub(" ", t)
    return _TETO_RE.sub(" ", _PISO_RE.sub(" ", _FAIXA_RE.sub(" ", t)))


def imoveis_do_pedido(conn, texto, buscar=None, pausa=None):
    """O que esta frase pede, resolvido contra o catálogo.

    Devolve um dict com `tipo`:
      'ignorar'  -- moldura da mensagem, não pede imóvel nenhum
      'codigos'  -- resolveu; `codigos` é o que mandar
      'ambiguo'  -- mais de um e ele não disse quantos; `codigos` são os candidatos
      'nada'     -- pediu e não temos; `motivo` diz o que ficou de fora
    """
    f = ler_pedido(texto)
    if f["titulo"]:
        return {"tipo": "ignorar"}

    # O CÓDIGO É PROCURADO NO TEXTO SEM OS VALORES. "de 3200 a até 5.000"
    # trazia o imóvel 3200 -- ver `_sem_os_valores`. É a mesma lição do
    # "as 08:00" que virava os códigos 08 e 00: número com outro significado
    # sai ANTES de procurar código, nunca depois.
    with conn.cursor() as cur:
        cur.execute("SELECT nay_codigos_citados(%s) AS c", (_sem_os_valores(texto),))
        linha = cur.fetchone()
    citados = [str(c) for c in ((linha or {}).get("c") or [])]
    if citados:
        return {"tipo": "codigos", "codigos": citados}

    # A FRASE NORMALIZADA PELO BANCO SERVE AOS DOIS casamentos -- condomínio e
    # bairro. É ela que faz "parque dez" virar "parque 10" e "pq" virar
    # "parque", e a chave do condomínio já é guardada assim: "Life Parque Dez"
    # tem chave "life 10". Sem passar por aqui, esse nome nunca casava --
    # medido em 15/09, junto com o caso do "Vistas dos Cedros".
    with conn.cursor() as cur:
        cur.execute("SELECT nay_normalizar_lugar(%s, true) AS frase", (texto,))
        frase = ((cur.fetchone() or {}).get("frase") or texto)

    condominios = condominios_do_catalogo(conn)
    nomes = casar_condominios(frase, condominios)

    # O BAIRRO (15/09). O Tel pediu "apartamento para locação no bairro, flores,
    # paz, parque dez, compensa, parque das laranjeiras até 3.000" e a Nay
    # respondeu que não achou nada: o pedido descrito não lia bairro nenhum.
    with conn.cursor() as cur:
        cur.execute(
            "SELECT DISTINCT i.bairro AS nome, "
            "       nay_normalizar_lugar(i.bairro, true) AS chave "
            "  FROM imoveis i WHERE coalesce(i.bairro,'') <> ''")
        bairros_do_catalogo = [(l["nome"], l["chave"]) for l in cur.fetchall()]
    bairros = casar_bairros(frase, bairros_do_catalogo)

    # O BAIRRO GANHA DO CONDOMÍNIO QUANDO O NOME DELE ESTÁ DENTRO DO BAIRRO.
    # Medido no pedido que falhou: "parque das laranjeiras" é BAIRRO, e o
    # casador de condomínio também achou "Condomínio Laranjeiras" e
    # "Residencial Laranjeiras" (chave "laranjeiras", palavra que está na
    # frase). A consulta virava bairro E condomínio ao mesmo tempo e não
    # sobrava nada -- a resposta ao Tel foi "não achei imóvel para ...".
    #
    # Só cai o condomínio cujas palavras estão TODAS dentro do nome do bairro.
    # "Residencial Ponta Negra I" continua de pé mesmo com o bairro Ponta
    # Negra na frase, porque o "i" não está no nome do bairro.
    nomes, bairros = desempatar_condominio_e_bairro(
        nomes, bairros, dict(condominios))

    # SÓ CATEGORIA NÃO BASTA. "a casa do morada do passaro", com o nome errado
    # a ponto de não casar, não pode virar "todas as casas" -- ia a carteira
    # inteira. Categoria sozinha só vale com "todas" ou com teto de valor,
    # que é o pedido da Flávia.
    if not nomes and not bairros and not (f["todos"] or f["teto"] or f["piso"]):
        if f["categorias"] or f["quartos"] or f["perfil"]:
            return {"tipo": "nada",
                    "motivo": f"não entendi de qual imóvel: {texto.strip()}"}
        return {"tipo": "ignorar"}

    teto = valor_escrito(conn, f["teto"])
    piso = valor_escrito(conn, f["piso"])
    filtros, params = [], []
    if nomes:
        filtros.append("nay_condominio_de_verdade(i.tipo, i.condominio_nome) = ANY(%s)")
        params.append(nomes)
    if bairros:
        filtros.append("i.bairro = ANY(%s)")
        params.append(bairros)
    # "SALA COMERCIAL" É O JEITO DELE DE DIZER COMERCIAL. Foi assim que ele
    # escreveu a regra do grupo: "sala comercial, prédio comercial, galpão".
    # Com a categoria `sala` junto do perfil, o pedido voltaria só as salas em
    # condomínio e esconderia loja, galpão e prédio -- então quando a única
    # categoria lida é a que veio da própria palavra "comercial", vale o perfil.
    categorias = set(f["categorias"])
    if f["perfil"] == "comercial" and categorias <= {"sala"}:
        categorias = set()
    if categorias:
        filtros.append("nay_categoria_do_imovel(i.tipo, i.condominio_nome) = ANY(%s)")
        params.append(sorted(categorias))
    if f["quartos"]:
        filtros.append("i.quartos = ANY(%s)")
        params.append(sorted(f["quartos"]))
    # A MOBÍLIA (28/09). `mobiliado` casa por PREFIXO e é isso que exclui o
    # semi: "semi-mobiliado" começa com "semi", nunca com "mobiliad". Os
    # rótulos reais do catálogo são "mobiliado (moveis + cama + tudo)" e
    # "semi-mobiliado (moveis planejados + ar)", por isso o `%` no fim.
    #
    # "SEM MOBÍLIA" INCLUI O VAZIO de propósito: 138 imóveis não têm o campo
    # preenchido, e quem pede sem mobília não quer ouvir "não tenho nenhum".
    # A MOBÍLIA NÃO FILTRA AQUI, e isso é o conserto de 28/09: filtrada no
    # SQL, ela usaria o valor do banco -- que está VAZIO em imóvel de venda e
    # desatualizado no que veio da importação. O candidato certo nunca
    # entraria na lista para ser conferido. Então a consulta sai LARGA e a
    # mobília é decidida depois, contra o site. Ver `_mobilia_conferida`.
    if f["negocio"] == "locacao":
        filtros.append("coalesce(i.valor_aluguel,0) > 0")
    elif f["negocio"] == "venda":
        filtros.append("coalesce(i.valor_venda,0) > 0")
    # O valor compara com o CUSTO CHEIO, como o título da lista: taxa por fora
    # soma. Sem negócio escrito, vale o lado em que o imóvel tem preço.
    exatos = [v for v in (valor_escrito(conn, x) for x in f["valores"]) if v]
    if exatos:
        filtros.append("(i.valor_aluguel = ANY(%s) OR i.valor_venda = ANY(%s))")
        params += [exatos, exatos]
    # A FAIXA VALE DE UM LADO SÓ. "casa em condomínio de 250k a 600k" não diz
    # o negócio -- é o valor que diz, e era isso que o Tel queria dizer com
    # "aqui pelo valor já sabe que é venda". Com teto e piso escritos como
    # dois filtros independentes, um imóvel de VENDA a 1.000.000 com ALUGUEL
    # de 5.000 passaria na faixa: o piso pelo lado da venda, o teto pelo lado
    # da locação. Nenhum dos dois lados cabe na faixa, e ele receberia o card.
    limites = [(l, op) for l, op in ((teto, "<="), (piso, ">=")) if l is not None]
    if limites and f["negocio"]:
        for limite, op in limites:
            filtros.append(f"nay_custo_cheio(i.codigo::text, %s) {op} %s")
            params += [f["negocio"], limite]
    elif limites:
        loc = " AND ".join(["coalesce(i.valor_aluguel,0) > 0"] +
                           [f"nay_custo_cheio(i.codigo::text,'locacao') {op} %s"
                            for _, op in limites])
        ven = " AND ".join(["coalesce(i.valor_venda,0) > 0"] +
                           [f"i.valor_venda {op} %s" for _, op in limites])
        filtros.append(f"(({loc}) OR ({ven}))")
        params += [l for l, _ in limites] * 2
    onde = " AND ".join(filtros) or "true"

    with conn.cursor() as cur:
        cur.execute(
            "SELECT i.codigo::text AS codigo, i.tipo AS tipo, i.mobilia AS mobilia, "
            "       nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AS no_ar, "
            "       coalesce(i.e_parceiro,false) AS parceiro "
            "  FROM imoveis i WHERE " + onde +
            " ORDER BY coalesce(i.valor_aluguel, i.valor_venda), i.codigo", params)
        todos = cur.fetchall()

    # O perfil é pelo TIPO, e o tipo mora no Python (`montar_destinos`), que é
    # quem também decide o grupo "🟢 Comercial". Filtrar aqui, e não no SQL,
    # é o que evita a segunda cópia da regra -- em SQL ela viraria um regex
    # solto que ninguém lembraria de mexer junto.
    if f["perfil"]:
        vale = e_comercial if f["perfil"] == "comercial" else e_residencial
        todos = [l for l in todos if vale({"tipo": l["tipo"]})]

    # A MOBÍLIA, CONFERIDA NO SITE (28/09). Só os que podem ser mandados são
    # lidos -- imóvel de parceiro ou fora do ar não vai sair de qualquer jeito,
    # e cada leitura custa 1,5s de pausa.
    if f.get("mobilia"):
        podem = [l["codigo"] for l in todos if l["no_ar"] and not l["parceiro"]]
        conferida = _mobilia_conferida(conn, podem, buscar=buscar, pausa=pausa)
        todos = [l for l in todos
                 if _casa_mobilia(conferida.get(l["codigo"], l.get("mobilia")),
                                  f["mobilia"])]

    nossos = [l["codigo"] for l in todos if l["no_ar"] and not l["parceiro"]]
    if not nossos:
        fora = [l["codigo"] for l in todos if not l["no_ar"] and not l["parceiro"]]
        parc = [l["codigo"] for l in todos if l["parceiro"]]
        partes = []
        if fora:
            partes.append("fora do site: " + ", ".join(fora[:8]))
        if parc:
            partes.append("de parceiro: " + ", ".join(parc[:8]))
        entendi = _resumo_do_pedido(f, nomes, bairros, f["teto"], f["piso"])
        if partes:
            detalhe = f" (não temos no ar; {'; '.join(partes)})"
        else:
            detalhe = f" (entendi: {entendi})" if entendi else ""
        return {"tipo": "nada", "entendi": entendi,
                "motivo": texto.strip() + detalhe}

    # Limite de valor é pedido de TODOS os que cabem nele -- "acquarelle até
    # 4k", "de 250k a 600k", "a partir de 6 mil" não são pergunta de qual.
    if f["todos"] or f["teto"] or f["piso"]:
        return {"tipo": "codigos", "codigos": nossos}
    if f["quantidade"] and len(nossos) == f["quantidade"]:
        return {"tipo": "codigos", "codigos": nossos}
    if not f["quantidade"] and len(nossos) == 1:
        return {"tipo": "codigos", "codigos": nossos}
    # A PERGUNTA MOSTRA O QUE CADA UM É, na linha da própria lista -- com só o
    # link ele teria que abrir anúncio por anúncio para escolher.
    with conn.cursor() as cur:
        cur.execute(
            "SELECT i.codigo::text AS codigo, nay_linha_da_lista(i.codigo::text, "
            "  nay_categoria_do_imovel(i.tipo, i.condominio_nome), "
            "  CASE WHEN coalesce(i.valor_aluguel,0) > 0 AND %s IS DISTINCT FROM 'venda' "
            "       THEN 'locacao' ELSE 'venda' END) AS linha "
            "  FROM imoveis i WHERE i.codigo::text = ANY(%s)",
            (f["negocio"], nossos))
        descricoes = {l["codigo"]: l["linha"] for l in cur.fetchall()}
    return {"tipo": "ambiguo", "codigos": nossos, "descricoes": descricoes}


def valor_escrito(conn, token):
    """O número que este pedaço de texto vale, pelo BANCO.

    Sem conversão nenhuma aqui: "600 mil", "3 milhões" e "1.2M" são lidos por
    `nay_valor_escrito`, a mesma função que lê o valor da linha colada. Era o
    Python que trocava "mil" por "k" antes de perguntar -- e por isso
    "milhões" passava batido e virava R$ 3.000.
    """
    if not token:
        return None
    with conn.cursor() as cur:
        cur.execute("SELECT nay_valor_escrito(%s) AS v", (token.strip(),))
        linha = cur.fetchone()
    return (linha or {}).get("v")
