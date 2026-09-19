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
  {'acao': 'criar_vaga', 'tipo_recorrencia': 'diaria', 'horario': time, 'codigos': [...]}
  {'acao': 'criar_vaga', 'tipo_recorrencia': 'semanal', 'horario': time,
   'dias_semana': [...], 'codigos': [...]}          # convenção Postgres, 0=domingo
  {'acao': 'liberar_vaga', 'codigo': '...'}      # vendeu/alugou -- imóvel saiu do mercado
  {'acao': 'remover_da_grade', 'codigo': '...'}  # tira/remove -- só reorganiza horário
  {'acao': 'listar_vagas'}
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
    r"|\b(?P<meianoite>meia[\s-]?noite)\b",
    re.IGNORECASE,
)

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

# verbo de liberar vaga: VENDEU/VENDIDO/VENDIDA, ALUGOU/ALUGADO/ALUGADA
VERBOS_LIBERAR = ("vendeu", "vendido", "vendida", "alugou", "alugado", "alugada")
LIBERAR_RE = re.compile(r"^(" + "|".join(VERBOS_LIBERAR) + r")\b\s*(.*)")

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

# Verbos que mandam para GRUPO. Se aparecerem com destinatario pessoal, a
# resposta e recusa que ensina -- nunca disparo.
VERBOS_DE_GRUPO = ("post", "public", "dispar", "solt")

# Cauda que nao e pessoa. Nao pode ser lista exata: "pro grupo de anunciar
# da easy 5750" e cauda de GRUPO e nao casaria com nenhuma entrada fixa --
# viraria envio privado para um "corretor" com esse nome. Basta MENCIONAR.
CAUDA_NAO_E_PESSOA_RE = re.compile(
    r"\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b",
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
    raise AssertionError("HORA_RE casou mas nenhum grupo nomeado bateu -- bug no regex")


def interpretar_comando(texto):
    resultado = _interpretar(texto)
    if resultado["acao"] == "nao_reconhecido":
        # Devolve o que o Tel escreveu DE VERDADE, não a versão já sem o
        # vocativo. A resposta do publicador cita esse texto de volta pra
        # ele ("Não entendi o comando ..."); citar uma frase que ele não
        # escreveu confunde em vez de ajudar.
        resultado["texto"] = texto
    return resultado


def _interpretar(texto):
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

    m = LIBERAR_RE.match(tl)
    if m:
        codigos = CODIGO_RE.findall(m.group(2))
        if len(codigos) == 1:
            return {"acao": "liberar_vaga", "codigo": codigos[0]}
        return {"acao": "nao_reconhecido", "texto": texto}

    # antes do EASY_RE de propósito: "remove o 5750 do anunciar easy" é
    # intenção de tirar, não de postar. Se caísse no EASY_RE, viraria
    # postar_easy e mandaria o imóvel pro grupo -- envio de WhatsApp não
    # tem desfazer, tirar da grade tem.
    m = REMOVER_RE.match(tl)
    if m:
        codigos = CODIGO_RE.findall(m.group(2))
        if len(codigos) == 1:
            return {"acao": "remover_da_grade", "codigo": codigos[0]}
        return {"acao": "nao_reconhecido", "texto": texto}

    # ANTES do EASY_RE: "manda o 5750 pro corretor anunciar, ele e da easy"
    # cai no EASY_RE hoje (que usa search no texto inteiro) e vira postagem
    # no grupo Easy com todas as fotos. Com o envio na frente, vira recusa.
    m = ENVIO_RE.match(t)
    if m:
        r = _interpretar_envio(t, m)
        if r is not None:
            return r

    if EASY_RE.search(tl):
        return _interpretar_postar_easy(t)

    if POSTAR_RE.match(tl):
        return _interpretar_posta(t)

    return {"acao": "nao_reconhecido", "texto": texto}


def _interpretar_envio(texto, m):
    """Devolve a acao de envio privado, ou None para deixar o dispatch seguir.

    None (e nao "nao_reconhecido") quando a cauda nao e pessoa: assim
    "manda o 5750 pro grupo" continua caindo no POSTAR_RE, como sempre fez.
    """
    verbo = m.group(1).lower()
    corpo = m.group(2).strip()
    cauda = m.group(3).strip()
    cauda_l = cauda.lower().strip(" .!?,")

    # "pro grupo", "pra grade", "pro grupo de anunciar da easy": nao e pessoa.
    if CAUDA_NAO_E_PESSOA_RE.search(cauda_l):
        return None

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

    codigos = CODIGO_RE.findall(corpo)
    return {
        "acao": "enviar_para_corretor",
        "codigos": codigos,
        "corpo": corpo,
        "destino": cauda,
        "texto": texto,
    }


def _interpretar_postar_easy(texto):
    codigos = CODIGO_RE.findall(texto)
    if len(codigos) != 1:
        return {"acao": "nao_reconhecido", "texto": texto}
    return {"acao": "postar_easy", "codigo": codigos[0]}


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


def _interpretar_posta(texto):
    # Antes de qualquer extração: o texto inteiro, não só o trecho antes da
    # hora. "a cada 15 dias" vem DEPOIS do código, e é justamente ali que o
    # 15 seria colhido como se fosse imóvel.
    if ALTERNANCIA_RE.search(texto):
        return {"acao": "nao_reconhecido", "texto": texto}

    m_hora = HORA_RE.search(texto)

    if not m_hora:
        # Se o texto fala de agenda -- dia da semana, "toda semana", "todo
        # dia" -- e a hora nao foi entendida, NAO posta. Postagem em 14
        # grupos nao tem desfazer; pedir a hora de novo custa uma frase.
        if _fala_de_agenda(texto):
            return {"acao": "agenda_incompleta", "texto": texto}
        codigos = CODIGO_RE.findall(texto)
        if not codigos:
            return {"acao": "nao_reconhecido", "texto": texto}
        return {"acao": "postar_agora", "codigos": codigos}

    horario = _horario_do_match(m_hora)

    # Tira a hora do texto: e o unico trecho com digito que nao e codigo.
    # Assim "as 17hr o 5717" e "o 5717 as 17hr" dao no mesmo -- antes so a
    # segunda ordem funcionava, e a primeira virava disparo imediato.
    sem_hora = texto[: m_hora.start()] + " " + texto[m_hora.end():]

    matches_codigo = list(CODIGO_RE.finditer(sem_hora))
    codigos = [m.group() for m in matches_codigo]
    if not codigos:
        return {"acao": "agenda_incompleta", "texto": texto}

    # Os dias podem estar em qualquer lugar; procura no texto todo sem a
    # hora e sem os codigos, para nao confundir numero com dia.
    trecho_dias = CODIGO_RE.sub(" ", sem_hora)

    if TODO_DIA_RE.search(trecho_dias):
        return {
            "acao": "criar_vaga", "tipo_recorrencia": "diaria",
            "horario": horario, "codigos": codigos,
        }

    dias_encontrados = set()
    for nome, numero in DIAS_SEMANA_NOMES.items():
        if re.search(r"\b" + re.escape(nome) + r"\b", trecho_dias, re.IGNORECASE):
            dias_encontrados.add(numero)
    if dias_encontrados:
        return {
            "acao": "criar_vaga", "tipo_recorrencia": "semanal",
            "horario": horario, "dias_semana": sorted(dias_encontrados),
            "codigos": codigos,
        }

    return {"acao": "nao_reconhecido", "texto": texto}
