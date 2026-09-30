#!/usr/bin/env python3
"""Colhe, de quem pede para entrar no grupo Alto Padrão, por onde ele anuncia.

O PEDIDO (Tel, 23/09/2026): "preciso filtrar os corretores então quero saber
quem são os corretores que postam no instagram que quero avaliar o instagram
deles". As três perguntas são as dele, palavra por palavra.

POR QUE EXISTE: em 23/09, às 20:35, seis pessoas chegaram em poucos minutos
respondendo ao anúncio do grupo -- Marcos, Heber, Nora, Ane, Izaías, Ana. A Nay
escalou TODAS ao Tel com "vou confirmar isso certinho e já te respondo", que é
a promessa que a regra `promessa_ou_sem_resposta` proíbe. Nenhuma das seis foi
perguntada por onde anuncia, e o Tel ficou com seis pendências e nenhum dado.

MEDIDO ANTES DE ESCREVER, em 6.114 mensagens recebidas: **nenhum** corretor
tinha dado o Instagram espontaneamente. O dado não existe no banco. Só existe
se for perguntado -- por isso isto é um colhedor, não um relatório.

AS PAREDES, cada uma de um falso positivo medido no corpus real:

  * "Posta no grupo anunciar easy 3227" é o comando do TEL, e ele escreveu 14
    dessas em 23/09. O telefone dele é cortado, e os verbos de postagem também
    -- ele também escreve pelo `@lid`.
  * "Portal do Rio Negro" é CONDOMÍNIO, não portal imobiliário. Das 15
    mensagens com "portal" no corpus, 5 são o condomínio. Por isso os portais
    são lidos por NOME (olx, vivareal, zap...), nunca pela palavra "portal".
  * "Esse tá no grupo da EASY?", "Os imóveis que você posta nos grupos podem
    ser anunciados?" e "vou anunciar seus imóveis do grupo" falam de grupo e
    NÃO são pedido de entrada. Por isso "grupo" sozinho não basta: precisa de
    um verbo de entrar junto.
  * "alto padrão" sozinho BASTA, e é decisão de desenho: o grupo se chama
    assim e ninguém fala dele sem dizer o nome. O custo de um falso positivo
    aqui é uma pergunta a mais; o de um falso negativo é o Tel perder um
    corretor.

UMA PERGUNTA POR PESSOA, para sempre (`perguntado_em`). Sem isso, cada "sobre
o grupo" dele refaz as três perguntas e a conversa vira interrogatório.

Regra 4 do projeto: simulação por padrão. Só manda com `--escrever`.

    .venv/bin/python filtrar_alto_padrao.py            # mostra o que faria
    .venv/bin/python filtrar_alto_padrao.py --escrever
"""
import argparse
import datetime
import os
import re
from zoneinfo import ZoneInfo

import db
from enviar_zapi import enviar_texto
from tel_whatsapp import enviar_ao_tel
from quando_da_visita import sem_acento

FUSO_MANAUS = ZoneInfo("America/Manaus")

TEL_FINAL = "94717316"

# "alto padrão", "alto-padrão", "altopadrao", "alto  padrao".
ALTO_PADRAO_RE = re.compile(r"alto[\s\-]*padrao", re.IGNORECASE)

# "grupo" só conta com um verbo de ENTRAR junto. Medido: sem esta exigência,
# "Esse tá no grupo da EASY?" e o comando de postagem do Tel entram.
ENTRAR_NO_GRUPO_RE = re.compile(
    r"(?:particip|entrar|entro|fazer parte|faco parte|me adicion|me inclu|"
    r"me coloc|me pos?e|como faco|quero estar|estar no grupo|ser do grupo|"
    # "Sobre o grupo" e "Sobre seu grupo Alto-Padrao" sao as formas reais
    # da Nora e do Marcos, em 23/09. Nenhum dos falsos positivos medidos
    # ("Esse ta no grupo da EASY?", "Coloca no grupo", "vou anunciar seus
    # imoveis do grupo") traz a palavra "sobre".
    r"\bsobre\b|interesse|gostaria)",
    re.IGNORECASE)
GRUPO_RE = re.compile(r"\bgrupos?\b", re.IGNORECASE)

# Os comandos do Tel. Ele escreve isto dezenas de vezes por dia e o `@lid`
# faz o telefone dele não bastar como parede.
COMANDO_DO_TEL_RE = re.compile(
    r"^\s*(?:@?nay\b[\s,;:.!?-]*)?(post|publi|dispar|envi|mand|tir|remov)",
    re.IGNORECASE)

# PORTAL É LIDO POR NOME. A palavra "portal" sozinha é o condomínio Portal do
# Rio Negro em 5 das 15 mensagens do corpus.
PORTAIS = [
    ("OLX", r"\bolx\b"),
    ("VivaReal", r"viva\s*real"),
    ("ZAP", r"\bzap\s*im[oó]ve|\bzap\b(?!\s*(?:tb|tamb|meu|dela|dele|e\s+meu))"),
    ("QuintoAndar", r"quinto\s*andar"),
    ("ImovelWeb", r"im[oó]vel\s*web|imovelweb"),
    ("Chaves na Mão", r"chaves?\s*na\s*m[aã]o"),
    ("Casa Mineira", r"casa\s*mineira"),
    ("Loft", r"\bloft\b"),
    ("Imovelweb/Grupo OLX", r"\bgrupo\s*olx\b"),
]

# @nome, instagram.com/nome, "meu insta é nome".
INSTAGRAM_URL_RE = re.compile(
    r"(?:https?://)?(?:www\.)?instagram\.com/([A-Za-z0-9._]{2,30})", re.I)
# LINK DE POST NÃO TEM PERFIL. O corpus traz um, da Nara em 12/09:
# `instagram.com/p/DdMIZgSkb08/`. Sem esta lista, "p" viraria o @ dela.
CAMINHO_SEM_PERFIL = {"p", "reel", "reels", "tv", "explore", "stories",
                      "accounts", "direct"}
ARROBA_RE = re.compile(r"@([A-Za-z0-9._]{2,30})")
# O SEPARADOR É OBRIGATÓRIO. Com ele opcional, "Como está no Instagram amanhã
# tem pessoa ver" -- frase real do José Antonio, 19/09 -- devolvia "amanh"
# como se fosse o perfil dele. Medido pelo teste antes de ir para o ar.
INSTA_SOLTO_RE = re.compile(
    r"\binsta(?:gram)?\s*(?:[ée]|eh|:|-|=)\s*@?([A-Za-z0-9._]{3,30})", re.I)

# "@" de e-mail não é Instagram. É a forma que mais aparece no corpus.
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")

NAO_TEM_RE = re.compile(
    r"\b(nao tenho|n tenho|nao uso|n uso|nao trabalho|nao anuncio|"
    r"nenhum|so no whats|apenas whats)\b", re.IGNORECASE)


def saudacao(agora):
    h = agora.astimezone(FUSO_MANAUS).hour
    if h < 12:
        return "bom dia"
    if h < 18:
        return "boa tarde"
    return "boa noite"


def pede_alto_padrao(texto):
    """Ele está pedindo para entrar no grupo Alto Padrão?

    Duas portas: citou o nome do grupo, ou falou de grupo COM verbo de entrar.
    O comando do Tel é cortado antes das duas.
    """
    bruto = str(texto or "")
    if not bruto.strip():
        return False
    if COMANDO_DO_TEL_RE.search(bruto):
        return False
    t = sem_acento(bruto)
    if ALTO_PADRAO_RE.search(t):
        return True
    return bool(GRUPO_RE.search(t) and ENTRAR_NO_GRUPO_RE.search(t))


def achar_instagram(texto):
    """O @ dele, ou None. E-mail nunca conta."""
    bruto = str(texto or "")
    achado = INSTAGRAM_URL_RE.search(bruto)
    if achado:
        perfil = achado.group(1).strip(".").lower()
        if perfil not in CAMINHO_SEM_PERFIL:
            return perfil
        return None
    # Tira os e-mails antes de procurar "@": é a forma que mais aparece.
    limpo = EMAIL_RE.sub(" ", bruto)
    achado = ARROBA_RE.search(limpo)
    if achado:
        return achado.group(1).strip(".").lower()
    achado = INSTA_SOLTO_RE.search(limpo)
    if achado:
        nome = achado.group(1).strip(".").lower()
        # "instagram: otimo" não é um @.
        if nome not in ("sim", "nao", "tambem", "otimo", "bom", "com"):
            return nome
    return None


def achar_portais(texto):
    """Os portais citados pelo NOME, na ordem em que aparecem na lista."""
    t = sem_acento(str(texto or ""))
    return [nome for nome, padrao in PORTAIS if re.search(padrao, t, re.I)]


def montar_pergunta(agora, nome=None):
    """As três perguntas, na palavra do Tel."""
    quem = f" {nome.split()[0]}" if nome and nome.split() else ""
    return (
        f"oi{quem}, {saudacao(agora)}, tudo bem?\n\n"
        "você trabalha anunciando pelo instagram anunciando alto padrão ou "
        "por portais imobiliários? se usa portais, quais seriam?\n\n"
        "e o seu instagram, pode me enviar caso trabalhe por lá?")


def montar_aviso_ao_tel(nome, telefone, instagram, portais):
    """O que o Tel recebe quando alguém responde.

    SEM ISTO A TABELA NÃO SERVE PARA NADA. A palavra dele foi "quero avaliar o
    instagram deles" -- avaliar exige ver, e ele não abre o banco. É o mesmo
    buraco que a pendência tinha antes de 01/09: o dado era colhido e morria
    numa tabela que ninguém lia.
    """
    fone = re.sub(r"[^0-9]", "", str(telefone or ""))[-11:]
    bonito = f"({fone[:2]}) {fone[2:7]}-{fone[7:]}" if len(fone) == 11 else fone
    linhas = [f"🔎 Alto Padrão — {nome or 'sem nome'} ({bonito})"]
    if instagram:
        linhas.append(f"• instagram: instagram.com/{instagram}")
    else:
        linhas.append("• instagram: não mandou")
    linhas.append(f"• portais: {', '.join(portais) if portais else 'nenhum citado'}")
    return "\n".join(linhas)


def _mensagens_novas(conn, limite=None, desde=None):
    """As recebidas ainda não olhadas.

    NÃO exige corretor aprovado, ao contrário do `detectar_visitas`. Aqui a
    pessoa está CHEGANDO -- Heber mandou CRECI e CNAI na primeira mensagem e
    não está em `corretores`. Exigir cadastro deixaria de fora exatamente
    quem o Tel quer filtrar.
    """
    # O `desde` entra NA CONSULTA, não pelo carimbo. Gravar o carimbo para
    # depois lê-lo funciona só quando se está escrevendo -- em simulação o
    # `--desde` virava letra morta e o cron varria o histórico inteiro,
    # devolvendo 11 fichas de agosto como se fossem de hoje. Foi assim que eu
    # quase relatei ao Tel falso positivo que não existia.
    piso = ("%s" if desde is not None
            else "coalesce((SELECT nullif(valor,'')::bigint FROM config "
                 "           WHERE chave = 'alto_padrao_ate_id'), 0)")
    params = [TEL_FINAL]
    if desde is not None:
        params.append(desde)
    if limite:
        params.append(limite)
    with conn.cursor() as cur:
        cur.execute(
            "SELECT m.id, m.telefone, m.nome, m.texto, m.criada_em "
            "  FROM mensagens m "
            " WHERE m.direcao = 'recebida' "
            "   AND coalesce(btrim(m.texto),'') <> '' "
            "   AND right(regexp_replace(m.telefone,'[^0-9]','','g'),8) <> %s "
            "   AND m.id > " + piso +
            " ORDER BY m.id" + (" LIMIT %s" if limite else ""),
            tuple(params))
        return cur.fetchall()


def _registrar_pedido(conn, m, escrever):
    """Abre a ficha dele. Não reabre nem reescreve o que já está lá."""
    if not escrever:
        return
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO corretor_alto_padrao (telefone, nome, pediu_texto) "
            "VALUES (%s, %s, %s) ON CONFLICT (telefone) DO NOTHING",
            (m["telefone"], m.get("nome"), (m["texto"] or "")[:400]))
    conn.commit()


def _guardar_resposta(conn, telefone, instagram, portais, escrever):
    """Complementa: nunca apaga o que já foi respondido antes."""
    if not escrever:
        return
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE corretor_alto_padrao SET "
            "  instagram = coalesce(instagram, %s), "
            "  anuncia_instagram = coalesce(anuncia_instagram, %s), "
            "  portais = coalesce(portais, %s), "
            "  anuncia_portais = coalesce(anuncia_portais, %s), "
            "  respondido_em = coalesce(respondido_em, now()) "
            " WHERE telefone = %s",
            (instagram, True if instagram else None,
             ", ".join(portais) or None, True if portais else None, telefone))
    conn.commit()


def _a_perguntar(conn):
    """Fichas abertas que ainda não receberam as três perguntas."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT telefone, nome FROM corretor_alto_padrao "
            " WHERE perguntado_em IS NULL ORDER BY pediu_em")
        return cur.fetchall()


def _marcar_perguntado(conn, telefone, escrever):
    if not escrever:
        return
    with conn.cursor() as cur:
        cur.execute("UPDATE corretor_alto_padrao SET perguntado_em = now() "
                    " WHERE telefone = %s", (telefone,))
    conn.commit()


def _sem_carimbo(conn):
    """Nunca rodou ainda?"""
    with conn.cursor() as cur:
        cur.execute("SELECT valor FROM config WHERE chave = 'alto_padrao_ate_id'")
        linha = cur.fetchone()
    return not (linha and str(linha["valor"] or "").strip())


def _ultimo_id(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT coalesce(max(id),0) AS id FROM mensagens")
        return cur.fetchone()["id"]


def _marcar_ate(conn, ate_id, escrever):
    if not escrever:
        return
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO config (chave, valor) VALUES ('alto_padrao_ate_id', %s) "
            "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor",
            (str(ate_id),))
    conn.commit()


def filtrar(conexao=None, agora=None, escrever=False, enviar=None,
            limite=None, desde=None, tel_whatsapp=None):
    """Lê o que chegou, abre ficha de quem pediu, pergunta, e colhe respostas.

    Devolve a lista do que fez, para o log e para o teste.
    """
    agora = agora or datetime.datetime.now(FUSO_MANAUS)
    enviar = enviar or enviar_texto
    # O LEQUE DOS DOIS NÚMEROS (28/09) é embrulhado AQUI, uma vez, e não em
    # cada chamada: são vários pontos de envio neste arquivo, e um deles
    # esquecido mandaria o alerta só para um número -- falha silenciosa, do
    # tipo que só aparece quando alguém repara que não recebeu.
    _enviar_um = enviar
    enviar = lambda d, t: enviar_ao_tel(d, t, _enviar_um)
    destino_tel = tel_whatsapp or os.environ.get("TEL_WHATSAPP")
    fechar = conexao is None
    conn = conexao or db.conectar()
    feito = []
    try:
        # A PRIMEIRA RODADA NÃO PROCESSA HISTÓRICO. Sem isto, o carimbo nasce
        # em zero, o cron varre as 19 mil mensagens do banco e manda as três
        # perguntas para todo mundo que já citou "alto padrão" desde agosto.
        # É a mesma lição que o `detectar_visitas` já traz escrita -- lá o
        # sintoma teria sido visita fantasma; aqui é uma enxurrada de mensagem
        # para corretor que não pediu nada. Para colher quem já chegou, o
        # `--desde ID` diz de onde começar, de propósito e na mão.
        if desde is None and _sem_carimbo(conn):
            ate = _ultimo_id(conn)
            _marcar_ate(conn, ate, escrever)
            return [{"o_que": "nasceu", "ate_id": ate}]

        novas = _mensagens_novas(conn, limite, desde)
        # Quem já tem ficha: a resposta dele às três perguntas é lida aqui.
        with conn.cursor() as cur:
            cur.execute("SELECT telefone, perguntado_em FROM corretor_alto_padrao")
            fichas = {right8(l["telefone"]): l for l in cur.fetchall()}

        ultimo = None
        for m in novas:
            ultimo = m["id"]
            fone8 = right8(m["telefone"])
            if pede_alto_padrao(m["texto"]):
                if fone8 not in fichas:
                    _registrar_pedido(conn, m, escrever)
                    fichas[fone8] = {"telefone": m["telefone"],
                                     "perguntado_em": None}
                    feito.append({"o_que": "ficha", "telefone": m["telefone"],
                                  "nome": m.get("nome"),
                                  "texto": (m["texto"] or "")[:60]})
            # A RESPOSTA só é lida de quem JÁ FOI PERGUNTADO. Sem isso, o @ de
            # uma conversa qualquer viraria o Instagram de alguém.
            ficha = fichas.get(fone8)
            if ficha and ficha.get("perguntado_em"):
                insta = achar_instagram(m["texto"])
                portais = achar_portais(m["texto"])
                if (insta or portais) and not ficha.get("respondido_em"):
                    _guardar_resposta(conn, ficha["telefone"], insta, portais,
                                      escrever)
                    ficha["respondido_em"] = "agora"
                    feito.append({"o_que": "resposta",
                                  "telefone": ficha["telefone"],
                                  "instagram": insta, "portais": portais})
                    # UMA VEZ SÓ por pessoa: o `respondido_em` acima é o que
                    # impede o Tel de receber o mesmo aviso a cada mensagem
                    # seguinte em que o corretor repetir o @ dele.
                    if destino_tel:
                        enviar(destino_tel,
                               montar_aviso_ao_tel(m.get("nome"),
                                                   ficha["telefone"],
                                                   insta, portais))

        # Agora as perguntas. Uma por pessoa, para sempre.
        for f in _a_perguntar(conn):
            texto = montar_pergunta(agora, f.get("nome"))
            enviar(f["telefone"], texto)
            _marcar_perguntado(conn, f["telefone"], escrever)
            feito.append({"o_que": "pergunta", "telefone": f["telefone"],
                          "texto": texto})

        if ultimo is not None:
            _marcar_ate(conn, ultimo, escrever)
        return feito
    finally:
        if fechar:
            conn.close()


def right8(telefone):
    return re.sub(r"[^0-9]", "", str(telefone or ""))[-8:]


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--escrever", action="store_true",
                   help="grava e MANDA de verdade. Sem isto, só mostra.")
    p.add_argument("--limite", type=int, default=None)
    p.add_argument("--desde", type=int, default=None,
                   help="começa a ler a partir deste id de mensagem. "
                        "É o único jeito de olhar para trás.")
    args = p.parse_args()

    def _simular(destino, texto):
        print(f"  [simulado] para {destino}:\n    "
              + texto.replace("\n", "\n    "))

    feitas = filtrar(escrever=args.escrever, limite=args.limite,
                     desde=args.desde,
                     enviar=None if args.escrever else _simular)
    for f in feitas:
        if f["o_que"] == "nasceu":
            print(f"  primeira rodada: carimbo nasce no fim da fila "
                  f"(id {f['ate_id']}). Nada do histórico foi lido.")
        elif f["o_que"] == "ficha":
            print(f"  ficha aberta: {f['nome']} ({f['telefone']}) "
                  f"-- disse: {f['texto']!r}")
        elif f["o_que"] == "resposta":
            print(f"  resposta de {f['telefone']}: "
                  f"instagram={f['instagram']!r} portais={f['portais']}")
    total = len([f for f in feitas if f["o_que"] == "pergunta"])
    if not args.escrever:
        print(f"\n(simulação -- {total} pergunta(s) sairiam. use --escrever)")
    else:
        print(f"\n{total} pergunta(s) enviada(s).")
