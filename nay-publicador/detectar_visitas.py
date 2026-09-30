"""
Põe na grade a visita que o corretor pediu, lendo as mensagens dele.

O CASO (12/09): a corretora Renata agendou uma visita para segunda e a Nay não
colocou na grade. A causa não foi ela ter falhado em achar -- é que **NADA NO
SISTEMA ESCREVIA NA TABELA `visita`**. A tabela, o cron de alertas e o comando
`Nay agenda de visitas` existiam desde 11/09; o mecanismo de ENTRADA, não. As
duas visitas que apareceram na grade naquele dia tinham sido inseridas à mão.

É o anti-padrão que o próprio projeto registra: *"antes de escrever regra no
prompt, pergunte: com que ferramenta ela faria isso?"*. Capacidade ausente
vira promessa.

POR QUE UM CRON, e não uma ferramenta do agente: a Nay está PAUSADA para
corretores (`config.atendimento_pausado`), então o agente não roda para eles.
As mensagens continuam sendo gravadas pelo `Gravar na fila`. Varrer a tabela
funciona com ela pausada ou não.

POR QUE SEPARADO DO `alertar_visitas.py`, e não dentro dele:
  1. o alertador é o APAGADOR -- a primeira coisa que ele faz é
     `DELETE FROM visita WHERE data_hora <= agora`. Escritor no mesmo processo
     significa visita mal-datada escrita e apagada no mesmo minuto, sem deixar
     rastro. Erro que some é pior que erro que aparece;
  2. o alertador nasceu sem simulação, e um detector que escreve na agenda do
     dono não pode subir sem ter rodado em seco contra as mensagens reais
     (regra 4 do projeto);
  3. o alertador manda cinco tipos de mensagem para o WhatsApp do Tel. Não se
     mexe nele para acrescentar um escritor.

O QUE O TEL DECIDIU (12/09), depois de ver a medição:
  * ela PODE pôr direto na grade, e o que passou ela mesma retira (o
    `_limpar_passadas` do alertador já faz isso, então engano envelhece
    sozinho);
  * quando a mensagem tem hora mas NÃO diz o dia -- 64% dos casos -- ela
    PERGUNTA. Não chuta: assumir "hoje" acerta 69%, e errar manda ele no dia
    errado.

A MEDIÇÃO QUE DESENHOU AS EXCLUSÕES (6.114 mensagens, 34 dias): um detector
ingênuo "palavra de visita E hora" casa 54 mensagens, e **36 delas (67%) não
são agendamento novo**. Cada exclusão daqui é uma família contada.

    .venv/bin/python detectar_visitas.py            # simulação, não escreve
    .venv/bin/python detectar_visitas.py --escrever
"""
import argparse
import datetime
import os
import re
from zoneinfo import ZoneInfo

import db
from enviar_zapi import enviar_texto
from tel_whatsapp import enviar_ao_tel, finais_do_tel
from quando_da_visita import quando, sem_acento

FUSO_MANAUS = ZoneInfo("America/Manaus")

# Os 8 ÚLTIMOS DÍGITOS de cada número do Tel -- a comparação é por eles
# porque a Z-API entrega ora com o 9 na frente, ora sem. Vira lista em 28/09,
# quando ele pediu um segundo número "como se fosse ele": os comandos de
# grade DELE casam o detector ("posta o 2943 todo dia às 08h"), e do número
# novo casariam igual.
FINAIS_DO_TEL_PADRAO = "94717316"

# O vocabulário de visita é o MESMO de `nay_pede_visita` (pedidos_do_turno.sql),
# que já governa o aviso ao agente. Repetir a lista aqui criaria a segunda
# cópia de uma regra de reconhecimento -- então a consulta chama a função.
_PEDE_REMARCAR = re.compile(r"\b(remarc|reagend)", re.IGNORECASE)

# PASSADO. "Não o de hj que eu agendei contigo às 16 hrs lembra" e "Um tinha me
# confirmado mais cedo 17h" -- as duas falam de visita que já existe. Registrar
# de novo põe linha duplicada na grade.
_PASSADO_RE = re.compile(
    r"\b(agendei|marquei|marcamos|combinei|combinamos|ficou|ficamos|"
    r"tinha|tinham|havia|lembra|lembras|falei|disse|era|foi)\b",
    re.IGNORECASE)

# PERGUNTA SOBRE VISITA QUE JÁ EXISTE. "queria confirmar com você se está tudo
# certo para a visita das 11h", "Passando para confirmar a visita às 17h40".
# São informativas, não pedidos -- e a hora ali é a da visita que já está (ou
# deveria estar) na grade.
_SOBRE_A_QUE_EXISTE_RE = re.compile(
    r"\bconfirm\w*\b.{0,30}\bvisita\b"
    r"|\bvisita\b.{0,30}\bconfirm\w*"
    r"|\bta\s+de\s+pe\b|\bta\s+confirmad|\besta\s+confirmad"
    r"|\btenho\s+outra\s+visita\b"
    r"|\btudo\s+certo\b|\bcontinua\s+(de\s+pe|valendo)\b",
    re.IGNORECASE)

# CANCELAMENTO. A hora que aparece em "Nay cancela a visita???! Já são 13:17"
# é o RELÓGIO, não o horário. Isto não vira visita: vira remoção.
_CANCELA_RE = re.compile(
    r"\bcancel\w*|\bdesmarc\w*|\bdesist\w*"
    r"|\bnao\s+(vai\s+dar|vou\s+poder|vamos\s+poder|da\s+mais)\b",
    re.IGNORECASE)

_CANCELOU_ANTES_RE = re.compile(
    r"\b(tinha|havia|ja)\s+(cancelad|desmarcad|desistid)", re.IGNORECASE)

# COMANDO DO TEL. Excluir só pelo telefone NÃO exclui o Tel: ele chega como
# `@lid` (medido: 5 mensagens dele, e 79 recebidas com @lid não resolvido), e
# os comandos de grade dele casam o detector -- "posta o 2943 todo dia às 08h",
# "dispara apartamentos para locação todo dia às 7H". Medido: 15 mensagens.
_COMANDO_DO_TEL_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?"
    r"(posta|postar|publica|publicar|dispara|disparar|solta|tira|tirar|"
    r"remove|remover|retira|retirar|vendeu|vendido|alugou|alugado|vagas|"
    r"lista|agenda|resposta|descarta|descartar|pendencias)\b",
    re.IGNORECASE)


def detectar_visitas(conexao=None, agora=None, escrever=False,
                     tel_whatsapp=None, enviar=None, limite=None):
    destino = tel_whatsapp or os.environ.get("TEL_WHATSAPP")
    enviar = enviar or enviar_texto
    # O LEQUE DOS DOIS NÚMEROS (28/09) é embrulhado AQUI, uma vez, e não em
    # cada chamada: são vários pontos de envio neste arquivo, e um deles
    # esquecido mandaria o alerta só para um número -- falha silenciosa, do
    # tipo que só aparece quando alguém repara que não recebeu.
    _enviar_um = enviar
    enviar = lambda d, t: enviar_ao_tel(d, t, _enviar_um)
    fechar = conexao is None
    conn = conexao or db.conectar()
    try:
        momento = agora or datetime.datetime.now(FUSO_MANAUS)

        # PRIMEIRA RODADA NÃO PROCESSA HISTÓRICO. Sem esta parede, subir o
        # detector mandaria de uma vez as ações de 34 dias de mensagens --
        # doze avisos de um jato, sobre conversa que já morreu, e os
        # cancelamentos apagariam visita de hoje por causa de mensagem do mês
        # passado. O carimbo nasce no fim da fila e o cron anda daí para a
        # frente.
        if escrever and _sem_carimbo(conn):
            ultimo = _ultimo_id(conn)
            if ultimo:
                _marcar_ate(conn, ultimo)
            return []

        mensagens = _mensagens_novas(conn, limite)
        relato = []
        for m in mensagens:
            acao = _decidir(conn, m, momento)
            if acao:
                relato.append(acao)
                if escrever:
                    _aplicar(conn, acao, destino, enviar, momento)
        if escrever and mensagens:
            _marcar_ate(conn, max(m["id"] for m in mensagens))
        return relato
    finally:
        if fechar:
            conn.close()


def _sem_carimbo(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT valor FROM config "
                    " WHERE chave = 'visita_detector_ate_id'")
        linha = cur.fetchone()
    return not (linha and str(linha["valor"] or "").strip())


def _ultimo_id(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT max(id) AS ultimo FROM mensagens")
        linha = cur.fetchone()
    return linha["ultimo"] if linha else None


def _mensagens_novas(conn, limite=None):
    finais = finais_do_tel() or [FINAIS_DO_TEL_PADRAO]
    """As mensagens ainda não olhadas, do mais antigo para o mais novo.

    `direcao = 'recebida'` NÃO É DETALHE: a saída do próprio
    `alertar_visitas.py` está na tabela como 'enviada' -- "☀️ Visitas de HOJE
    (12/09): - ✓ 10h00 — Acquarelle..." casa o detector inteiro. Sem o filtro,
    o cron lê a própria agenda e a reescreve, que é o bug do portão de fotos
    lendo o envelope de áudio, agora com o texto já pronto na mesa.

    SÓ DE CORRETOR APROVADO. Medido: 15 das 54 mensagens que casariam vêm de
    quem não é corretor -- proprietários falando de chave, clientes, e spam de
    outra imobiliária. O preço é perder pedido de quem não está cadastrado; o
    remédio é cadastrar, e a recusa do envio privado já ensina isso.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT m.id, m.telefone, m.nome, m.texto, m.criada_em, m.origem "
            "  FROM mensagens m "
            "  JOIN corretores c "
            "    ON right(regexp_replace(c.telefone,'[^0-9]','','g'),8) "
            "     = right(regexp_replace(m.telefone,'[^0-9]','','g'),8) "
            "   AND c.aprovado AND c.ativo "
            " WHERE m.direcao = 'recebida' "
            "   AND coalesce(btrim(m.texto),'') <> '' "
            "   AND right(regexp_replace(m.telefone,'[^0-9]','','g'),8) <> ALL(%s) "
            "   AND m.id > coalesce((SELECT nullif(valor,'')::bigint FROM config "
            "                         WHERE chave = 'visita_detector_ate_id'), 0) "
            "   AND nay_pede_visita(m.texto) "
            " ORDER BY m.id" + (" LIMIT %s" if limite else ""),
            (finais, limite) if limite else (finais,))
        return cur.fetchall()


# RESPOSTA AUTOMÁTICA DE COMÉRCIO NÃO É AGENDAMENTO (Tel, 28/09).
#
# O CASO: a grade amanheceu com "08h00 — Nancy Souza Corretora agradece seu
# contato. / Atendemos de segunda a sexta das 8h às 17h..." O Tel: "essa
# mensagem não é de visita, como pode ver é o horário dela de atendimento".
#
# Era o WhatsApp Business dela respondendo sozinho, e o texto trazia as três
# coisas que o detector procura: a palavra VISITA ("Realizamos visitas com
# horário marcado"), uma HORA ("das 8h") e um DIA ("de segunda a sexta").
#
# DOIS SINAIS, e o primeiro é estrutural: **compromisso tem UMA hora, horário
# de funcionamento tem FAIXA**. É a mesma família do "faixa de preço não é
# hora" que já mora em `quando_da_visita` -- número com outro significado sai
# antes, nunca depois.
#
# MEDIDO em 10.172 mensagens recebidas: 178 teriam dia e hora entendidos (as
# candidatas a virar visita) e esta guarda barra EXATAMENTE 3 -- as três
# cópias da resposta da Nancy, e as três casam os dois sinais. Nenhum falso
# positivo no corpus inteiro.
#
# A FAIXA EXIGE "h" OU ":" NO SEGUNDO NÚMERO de propósito: sem isso "de 2 a 3
# quartos" viraria faixa de horário.
_FAIXA_DE_HORARIO_RE = re.compile(
    r"\b(?:das?|de)\s+\d{1,2}\s*(?:h(?:oras|rs|s)?)?(?:[:h]\d{2})?\s*"
    r"(?:as|ate|a)\s+\d{1,2}\s*(?:h|:)",
    re.IGNORECASE)

_RESPOSTA_AUTOMATICA_RE = re.compile(
    r"\batendemos\b|\bhorario\s+de\s+(?:atendimento|funcionamento)\b"
    r"|\bfuncionamos\b|\bagradec\w*\s+(?:o\s+)?seu\s+contato\b"
    r"|\bretornaremos\b|\bem\s+breve\s+retorn\w*"
    r"|\b(?:mensagem|resposta)\s+automatica\b"
    r"|\bdomingo\s+fechado\b|\bfechad[oa]\s+aos?\s+domingos?\b",
    re.IGNORECASE)


def _decidir(conn, m, agora):
    """O que fazer com esta mensagem, ou None para deixá-la passar."""
    texto = m["texto"] or ""
    t = sem_acento(texto)

    # O Tel escapando pelo @lid. O telefone já foi filtrado; isto pega a
    # mensagem dele que chegou com identidade não resolvida.
    if _COMANDO_DO_TEL_RE.match(texto.strip()):
        return None

    # RESPOSTA AUTOMÁTICA: nem visita, nem cancelamento. Vem antes de tudo
    # porque "Domingo fechado" casaria o `_CANCELA_RE` e APAGARIA da grade uma
    # visita de verdade -- o dano seria maior que o de hoje.
    if _FAIXA_DE_HORARIO_RE.search(t) or _RESPOSTA_AUTOMATICA_RE.search(t):
        return None

    # "Eu tinha cancelado uma visita para ele" fala do passado: apagar por
    # causa disso tiraria da grade uma visita que nada tem a ver.
    if _CANCELA_RE.search(t) and not _CANCELOU_ANTES_RE.search(t):
        return {"tipo": "cancelar", "msg": m}

    # Sobre visita que já existe, ou no passado: não é pedido novo. O
    # "remarcar" escapa de propósito -- ele fala do passado E pede o novo.
    if not _PEDE_REMARCAR.search(t):
        if _SOBRE_A_QUE_EXISTE_RE.search(t) or _PASSADO_RE.search(t):
            return None

    # "amanhã" É RELATIVO À MENSAGEM, não ao relógio de agora. Com o
    # carimbo, o cron de minuto em minuto dá no mesmo; sem ele, a primeira
    # rodada sobre o histórico leria 34 dias de "amanhã" como amanhã e
    # encheria a grade de visita que já aconteceu.
    data_hora, faltou = quando(texto, m["criada_em"].astimezone(agora.tzinfo))

    if faltou == "hora":
        return None          # "quero agendar uma visita" sem hora não é grade
    if faltou == "dia":
        return {"tipo": "perguntar_dia", "msg": m}

    # Visita no passado não entra: o alertador apagaria no minuto seguinte e o
    # Tel nunca saberia que ela existiu.
    if data_hora <= agora:
        return None

    return {"tipo": "registrar", "msg": m, "data_hora": data_hora}


def _visita_aberta_do_corretor(conn, telefone):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, descricao, data_hora FROM visita "
            " WHERE right(regexp_replace(coalesce(corretor_telefone,''),"
            "                            '[^0-9]','','g'),8) = right(%s,8) "
            " ORDER BY data_hora LIMIT 1",
            (re.sub(r"[^0-9]", "", telefone or ""),))
        return cur.fetchone()


def _aplicar(conn, acao, destino, enviar, agora):
    m = acao["msg"]
    t = sem_acento(m["texto"] or "")
    nome = (m["nome"] or "").strip() or m["telefone"]
    trecho = " / ".join(l.strip() for l in (m["texto"] or "").split("\n")
                        if l.strip())[:180]

    if acao["tipo"] == "cancelar":
        aberta = _visita_aberta_do_corretor(conn, m["telefone"])
        if not aberta:
            return
        with conn.cursor() as cur:
            cur.execute("DELETE FROM visita WHERE id = %s", (aberta["id"],))
        conn.commit()
        enviar(destino, f'❌ tirei da agenda: {aberta["descricao"]} '
                        f'({nome})\nele escreveu: "{trecho}"')
        return

    if acao["tipo"] == "perguntar_dia":
        # NÃO CHUTA O DIA. A pergunta carrega o comando PRONTO, que é o padrão
        # do projeto para quando falta contexto -- a resposta dele volta
        # auto-contida e não depende de nada guardado.
        enviar(destino,
               f'📅 {nome} falou de visita e não disse o dia:\n"{trecho}"\n\n'
               f'que dia? me manda: Nay visita <dia> <hora> {nome.split()[0]} '
               f'<imovel>')
        return

    # REMARCAR TROCA, não empilha. Medido: a Amanda pediu "as 09horas" e 72
    # minutos depois "A visita vai ser as 11 horas". Duas linhas na grade
    # fariam o Tel ir às 9h e não ter ninguém.
    #
    # MAS SÓ NO MESMO DIA, ou quando ele diz a palavra. A primeira versão
    # trocava sempre que o corretor tivesse QUALQUER visita aberta, e isso
    # apagou de verdade a visita de segunda da Renata quando ela marcou outra
    # -- corretor que agenda dois imóveis em dias diferentes tem DUAS visitas,
    # não uma que muda. Pego na prova de ponta a ponta, não em produção.
    aberta = _visita_aberta_do_corretor(conn, m["telefone"])
    if aberta and not _PEDE_REMARCAR.search(t):
        if aberta["data_hora"].astimezone(agora.tzinfo).date() \
                != acao["data_hora"].date():
            aberta = None
    with conn.cursor() as cur:
        if aberta:
            cur.execute(
                "UPDATE visita SET data_hora = %s, descricao = %s, "
                "       confirmada = false, alerta_90min_em = NULL "
                " WHERE id = %s",
                (acao["data_hora"], trecho, aberta["id"]))
            conn.commit()
            enviar(destino, f'🔁 {nome} mudou a visita para '
                            f'{acao["data_hora"].strftime("%d/%m %Hh%M")}:\n"{trecho}"')
            return
        cur.execute(
            "INSERT INTO visita (codigo, descricao, corretor, "
            "  corretor_telefone, data_hora, confirmada, criada_em) "
            "VALUES (NULL, %s, %s, %s, %s, false, %s)",
            (trecho, nome, m["telefone"], acao["data_hora"], m["criada_em"]))
    conn.commit()
    enviar(destino, f'📌 pus na agenda: {acao["data_hora"].strftime("%d/%m %Hh%M")} '
                    f'— {nome}\n"{trecho}"\n\nnão confirmada ainda.')


def _marcar_ate(conn, ate_id):
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO config (chave, valor) VALUES "
            "  ('visita_detector_ate_id', %s) "
            "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor",
            (str(ate_id),))
    conn.commit()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--escrever", action="store_true",
                   help="grava de verdade. Sem isto, só mostra o que faria.")
    p.add_argument("--limite", type=int, default=None)
    args = p.parse_args()

    achados = detectar_visitas(escrever=args.escrever, limite=args.limite)
    for a in achados:
        m = a["msg"]
        quando_txt = a.get("data_hora")
        print(f'{a["tipo"]:14s} #{m["id"]:<6} {(m["nome"] or "")[:26]:28s} '
              f'{quando_txt.strftime("%d/%m %Hh%M") if quando_txt else "":12s} '
              f'{(m["texto"] or "")[:64]!r}')
    if not args.escrever:
        print(f"\n(simulação -- {len(achados)} ações, nada foi escrito. "
              "use --escrever)")
