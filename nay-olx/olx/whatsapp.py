"""A NAY DO WHATSAPP DOS CLIENTES DA OLX: o número de captação (92 8595-6408), pela Z-API da captação.

Pedro, 16/10/2026: "agora o nosso objetivo vai ser chamar a pessoa para o WhatsApp ... a nay de whatsapp vai assumir já
sabendo as coisas que a da olx mandou, e lá ela vai perguntar se quer agendar visita ou receber mais opções", o roteiro
("até que valor? quais bairros? se for 3 quartos, serve 2? condomínio com elevador abaixo de 500 mil: serve escada? tem
crédito aprovado ou gostaria de fazer uma simulação? ok, muito grata, vou pegar as opções no meu sistema") e "a nay vai
mandar os imóveis com a mesma tecnologia que a nay de parceria usa ... cada imóvel separadinho card + fotos, aí espera
carregar todas as fotos e vai para o próximo".

COMO RODA: uma linha própria (thread) dentro do serviço nay-olx, a cada 5 s, com a sua conexão ao banco:
  1. ABRE quem a Nay da OLX passou (privado.olx_lead_whatsapp, etapa 'nova'): a primeira mensagem já sabe o que foi
     conversado na OLX. Quem a equipe já chamou por este número não é aberto: fica com a equipe.
  2. RESPONDE quem escreveu e ficou `whatsapp_silencio_s` em silêncio. O modelo segue o roteiro e diz a ação:
     buscar (olx_cliente_buscar, a regra da Nay de Parceria; os imóveis saem um por vez: card, fotos, espera, o próximo),
     visita (anota imóvel e horário e avisa a equipe no grupo), equipe, encerrar.
  3. SAI quando alguém da equipe escreve para a pessoa por este número, e não volta sozinha (a regra da OLX, 386). O que
     ela mesma manda fica em privado.olx_cliente_enviada: o eco da Z-API não é "gente respondendo".
Chave `whatsapp_responde` (privado.olx_config): nao | teste (só os números de `whatsapp_teste`) | sim.
A conversa mora em captacao_mensagens: é por ali que o CRM mostra a aba Captação. O texto que ela manda é gravado lá
como 'resposta'; as fotos aparecem pelo eco da Z-API.
A VISITA com o proprietário e os corretores (Raquel, Neila, Katherine) ainda é da equipe: falta o número deles.
"""
from __future__ import annotations

import json
import logging
import re
import threading
import time
import unicodedata
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher

from olx import banco, grupo, modelo, nay, visita

log = logging.getLogger("olx.whatsapp")
try:
    from zoneinfo import ZoneInfo
    MANAUS = ZoneInfo("America/Manaus")
except Exception:  # noqa: BLE001 -- sem a base de fusos (Windows): Manaus é -4 o ano todo
    MANAUS = timezone(timedelta(hours=-4))

MAX_BALOES = 3
MAX_IMOVEIS = 5
MAX_FOTOS = 12
ENTRE_ENVIOS_S = 1.5
DEPOIS_DAS_FOTOS_S = 8.0       # "espera carregar todas as fotos e vai para o próximo"
LIMITE_DE_MENSAGENS = 60       # mensagens dela nesta conversa: depois disso, a equipe
CAMPOS_DOS_FILTROS = ("finalidade", "tipo", "teto", "bairros", "qualquer_bairro", "quartos", "aceita_menos_quartos",
                      "aceita_escada", "financiamento", "mobilia")


class ErroDeEnvio(Exception):
    pass


PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Você fala pelo WhatsApp com quem se interessou por um anúncio
nosso na OLX e deixou o número. Você já sabe o que essa pessoa conversou na OLX (está abaixo): NUNCA pergunte de novo o que
ela já disse lá. Às vezes é alguém que escreveu DIRETO para este número, sem OLX (o sistema diz "ORGÂNICO"): aí vale a
parte QUANDO VEIO DIRETO.

=== O CAMINHO ===
1. ABERTURA (a primeira mensagem, quando ainda não há conversa no WhatsApp): lembre que vocês falaram pela OLX sobre o
   imóvel (o condomínio ou o bairro), responda o que tiver ficado pendente lá se a ficha tiver a resposta (se não tiver,
   diga que confirma e já retorna, e marque "perguntar" com o que ficou pendente), e pergunte se ela quer agendar uma
   visita ou receber outras opções parecidas. Se na OLX ela já pediu visita com dia/horário, marque "visita"; se pediu
   desconto ou proposta, marque "perguntar" (a equipe responde e a conversa segue com você).
   Ex.: "Oi, Sra. Claudia! Aqui é a Nay, da Imob Easy, falamos pela OLX sobre o apartamento no Kopenhagen. A senhora quer
   agendar uma visita ou receber outras opções parecidas?"
2. OUTRAS OPÇÕES: o roteiro, UMA pergunta por vez, pulando o que ela já disse (aqui ou na OLX):
   - Até que valor?
   - Quais bairros te atendem? ("qualquer bairro" também vale)
   - Se ela quer 3 quartos (ou o anúncio é de 3 quartos): serve 2 quartos também?
   - Só na LOCAÇÃO de residencial (apartamento, casa, flat): prefere mobiliado, só com modulados e ar-condicionado, ou
     tanto faz? (Pedro, 19/10: "faltou filtrar se quer modulados e ar ou mobiliado para poder enviar correto". Se ela
     já disse aqui ou na OLX, não pergunte.)
   - Se o imóvel do anúncio é apartamento em condomínio com elevador e é de VENDA até R$ 500.000: serve apartamento com
     escada?
   - Só na VENDA: tem crédito aprovado ou gostaria de fazer uma simulação de financiamento? (uma vez só: qualquer
     resposta serve; se ela quer simular ou não tem crédito, diga que a equipe faz a simulação junto com ela)
   Respondidas as perguntas que cabem, feche como "Ok, muito grata, Sra. Claudia! Vou pegar as opções no meu sistema
   para lhe enviar." e peça a busca: acao "buscar". O sistema manda os imóveis, um por vez, logo depois. Não faça
   mais perguntas depois do fechamento.
3. DEPOIS DAS OPÇÕES: se ela gostou de algum, ofereça a visita; se quer mais, refaça o roteiro só no que mudou e peça
   "buscar" de novo.
4. VISITA: descubra QUAL imóvel (o código está nos cards e no anúncio) e o DIA e o HORÁRIO exatos (ex.: 17/10 às 11h;
   "amanhã", "sábado" você converte pela data de AGORA; "de manhã", "à tarde" não é horário: pergunte a hora). Com os
   três, marque acao "visita" com "visita": {"codigo", "data": "DD/MM", "hora": "HH:MM"} e NÃO escreva a confirmação: o
   sistema manda a mensagem de confirmação ("🏠 Só para confirmar a solicitação de visita..."); seus balões podem ficar
   vazios. Quando ela responder que os dados estão certos ("sim", "isso", "pode", "confirmo"), marque acao
   "confirmou_visita" e diga que vai confirmar com o corretor e com o proprietário e já retorna. Se ela mudar o dia ou o
   horário, marque "visita" de novo com os dados novos. Enquanto a visita está sendo confirmada (o sistema diz em que
   pé está), não prometa nada: diga que está confirmando e avisa assim que tiver a resposta.
5. FOTOS: ela pediu MAIS FOTOS de um imóvel, sem dizer de qual parte (o do anúncio ou um dos que você mandou): acao
   "fotos" com o código. O sistema manda as fotos depois dos seus balões; o que você quer dizer DEPOIS das fotos vai em
   "depois_das_fotos".
6. FOTO DE UMA PARTE (dos quartos, do roupeiro, do banheiro, da cozinha, da varanda, da vista, da fachada, da área de
   lazer...): você NÃO sabe qual foto é de qual cômodo. Não mande fotos e não prometa que manda: diga que vai separar
   essas fotos e já retorna, e marque acao "perguntar" com o pedido em "motivo" (ex.: "fotos dos quartos com roupeiros
   dos imóveis 9026, 9037 e 5724"). A equipe recebe a pergunta e manda as fotos por aqui.
Seja flexível: se ela pula etapas, acompanhe; se faz uma pergunta sobre um imóvel, responda pela ficha. Se numa mensagem
só ela pede as fotos E já diz o que procura (valor, região), faça as duas coisas: "acoes": ["fotos", "buscar"].
BAIRROS: escreva bairros de Manaus. Avenida ou região vira os bairros por onde ela passa (ex.: "da Constantino Nery até
a Ponta Negra" = Chapada, São Jorge, Dom Pedro, Planalto, Alvorada, Ponta Negra). Os bairros vizinhos o sistema já soma.
MOBÍLIA (locação): "mobiliado" = com móveis; "semi" = modulados e/ou ar-condicionado; "tanto_faz" = ela disse que
tanto faz (ou que pode ser sem nada); "" = ainda não perguntou. Quem quer "semi" também recebe mobiliado.
COMERCIAL (galpão, prédio, sala, loja, ponto, terreno): NUNCA pergunte de mobília (mobiliado ou semi) nem de quartos, e
não pergunte de escada. Pergunte só o valor e a região (e o crédito, na venda).

=== QUANDO VEIO DIRETO (ORGÂNICO) ===
Não houve OLX nem anúncio: a pessoa escreveu para este número por conta própria. NUNCA fale de anúncio, de OLX, de "falamos
antes". Se uma mensagem sua nesta conversa já falou de anúncio, foi engano: não repita (se ela estranhar, peça desculpas
pela confusão e siga).
1. ABERTURA (você ainda não falou com ela): responda o cumprimento pela hora de AGORA, apresente-se e pergunte se ela
   procura imóvel e se é para alugar ou comprar. Se ela já disse o que quer, não pergunte de novo: siga o roteiro.
   Ex.: "Boa tarde! Aqui é a Nay, da Imob Easy. Você está procurando imóvel? Seria para alugar ou para comprar?"
   Se ela citou um imóvel (pelo código ou pelo nome, ex.: "Quero saber mais sobre o imóvel Cobertura - Life Flores"), o
   sistema dá a ficha: responda pela ficha e pergunte se ela quer agendar uma visita ou receber outras opções parecidas,
   como na OLX (o tipo, os quartos e a finalidade vêm desse imóvel).
2. Se o assunto não é procurar imóvel (quer vender ou alugar o imóvel dela, é corretor, cobrança, outro assunto): diga com
   naturalidade que já passa para a equipe e marque "equipe" com o motivo.
3. Procura imóvel: o mesmo roteiro de OUTRAS OPÇÕES, uma pergunta por vez, começando pelo que o anúncio daria: o TIPO
   (apartamento, casa, casa em condomínio ou comercial; "tanto faz" vale) e, se residencial, quantos quartos (se 3,
   serve 2?); depois até que valor,
   quais bairros, a mobília (só na LOCAÇÃO residencial: mobiliado, modulados e ar, ou tanto faz), a escada (só na VENDA
   até R$ 500.000, se ela quer apartamento) e o crédito (só na VENDA). Fechamento
   e acao "buscar" como lá.

=== VENDA OU LOCAÇÃO ===
O anúncio diz qual é (no orgânico, ela diz). Na locação o campo "incluso" da ficha é o que está INCLUSO NO ALUGUEL (ex.: água, gás, condomínio).
Na locação não fale de financiamento; na venda não fale de caução nem fiador.

=== QUANDO É COM A EQUIPE (acao "equipe") ===
Documentação, contrato, reclamação, pedido para falar com uma pessoa, corretor oferecendo parceria. Diga com
naturalidade que já passa para a equipe e que vão falar com ela por aqui. (Desconto, proposta e menor valor NÃO: é
"perguntar", a equipe responde e a conversa continua com você.)

=== UMA CONFIRMAÇÃO SÓ ===
- Cada pedido é confirmado UMA vez. Quando for buscar, é UM balão só, juntando nele o que for perguntar à equipe (ex.:
  "Perfeito, Sr. Felipe! Vou confirmar com a equipe a entrada com o apartamento e já pego as opções no meu sistema para
  lhe enviar."); os imóveis chegam logo depois, pelo sistema.
- Já disse que vai confirmar algo com a equipe ou que já retorna: não diga de novo. Se ela só agradeceu, disse "ok" ou
  "aguardo", não responda (balões vazios).

=== NUNCA ===
- Repetir uma pergunta ou uma frase que você já mandou nesta conversa. Perguntou e ela ainda não respondeu: espere a
  resposta dela (balões vazios é melhor que repetir). Já disse que vai confirmar com a equipe: não diga de novo a cada
  mensagem; responda o que ela disse agora.
- Dar negativa ("não consigo", "não dá", "não é possível", "não temos"). Se a busca não achar, o sistema avisa a equipe
  e diz a ela que você está separando as opções.
- Inventar. O que não está na ficha você não sabe: diga que confirma e retorna.
- Endereço exato, número da casa ou do apartamento, bloco, torre, nome do proprietário. Bairro e condomínio pode.
- Link, telefone, e-mail, emoji.
- Falar de Nay da OLX, de robô, de ficha, de catálogo. Para ela você é só a Nay, da Imob Easy.
- Dizer que um imóvel é "de parceiro", "de parceria" ou "de outra imobiliária". Para ela todo imóvel é da Imob Easy.

=== COMO VOCÊ FALA ===
Português do Brasil, de gente: uma moça de Manaus no WhatsApp do trabalho, não um assistente traduzido do inglês. Curto:
um ou dois balões, poucas linhas. Trate pelo tratamento que o sistema dá (Sra./Sr. + primeiro nome; "a senhora", "o
senhor"); sem tratamento, pelo primeiro nome e "você". Nada de "Como posso te ajudar hoje?", "Fico à disposição".
Valor em reais assim: R$ 700.000 / R$ 2.500.

=== A SUA RESPOSTA: SÓ ESTE JSON, NADA MAIS ===
{"baloes": ["..."], "acoes": [],
 "filtros": {"finalidade": "", "tipo": "", "teto": 0, "bairros": [], "qualquer_bairro": false, "quartos": 0,
             "aceita_menos_quartos": null, "aceita_escada": null, "financiamento": "", "mobilia": ""},
 "fotos": {"codigo": 0}, "depois_das_fotos": [], "visita": {"codigo": 0, "data": "", "hora": ""}, "motivo": ""}
- acoes: [] ou, na ordem, até duas de: "fotos" | "buscar" | "visita" | "confirmou_visita" | "perguntar" (você precisa
  que a equipe responda ou mande algo, e a conversa continua com você) | "equipe" (a conversa passa para a equipe) |
  "encerrar" (ela agradeceu e não quer mais nada).
- filtros: TUDO o que ela já disse até agora (aqui e na OLX); vazio/0/null o que não disse. finalidade: "locacao" ou
  "venda" (sem ela dizer, é a do anúncio). tipo: "apartamento", "casa", "casa_condominio", "tanto_faz" ou, no
  comercial, "galpao", "predio", "sala", "loja", "terreno" ("comercial" quando ela não disser qual). teto: só o
  número em reais. quartos: o número que ela quer. financiamento: "aprovado", "simular", "a vista" ou "".
  mobilia: "mobiliado", "semi" (modulados e/ou ar), "tanto_faz" ou "" (ainda não disse).
  No orgânico, finalidade só quando ela disser.
- visita: o código do imóvel, a data (DD/MM) e a hora (HH:MM) que ela disse.
- motivo: em poucas palavras, para a equipe (com "perguntar" ou "equipe"): o que ela pediu, com os códigos.
"""


# ── a Z-API da captação: a mesma do config do vigia (só root lê); nada de segredo aqui ──
def _instancia() -> dict:
    conf = grupo._conf_do_vigia()
    inst = (conf or {}).get("instancias", {}).get("captacao")
    if not inst:
        raise ErroDeEnvio("não achei a Z-API da captação no config do vigia")
    return inst


_CONEXAO = [0.0, False]


def conectada() -> bool:
    """Desconectada, a Z-API aceita e não entrega (02/10): sem conexão, a Nay não fala. A resposta vale 30 s (a volta é
    de 5 em 5 s e várias partes perguntam)."""
    if time.monotonic() - _CONEXAO[0] < 30:
        return bool(_CONEXAO[1])
    try:
        st = grupo._zapi(_instancia(), "GET", "/status")
        ok = isinstance(st, dict) and bool(st.get("connected"))
    except ErroDeEnvio:
        ok = False
    _CONEXAO[0], _CONEXAO[1] = time.monotonic(), ok
    return ok


def _mandar(conn, lead: dict, caminho: str, corpo: dict, tipo: str, codigo: int | None = None,
            texto_no_crm: str | None = None) -> str:
    r = grupo._zapi(_instancia(), "POST", caminho, {"phone": "55" + lead["telefone"], **corpo}, timeout=40)
    mid = str((r or {}).get("messageId") or (r or {}).get("id") or "") if isinstance(r, dict) else ""
    if not mid:
        raise ErroDeEnvio((r or {}).get("_erro") if isinstance(r, dict) else "sem resposta da Z-API")
    banco.um(conn, """INSERT INTO privado.olx_cliente_enviada (message_id, lead, tipo, codigo) VALUES (%s, %s, %s, %s)
                      ON CONFLICT (message_id) DO NOTHING""", (mid, lead["id"], tipo, codigo))
    if texto_no_crm:
        # a conversa do CRM (aba Captação) é captacao_mensagens: se o eco da Z-API chegou antes, só vira 'resposta'
        banco.um(conn, """
            WITH ja AS (UPDATE captacao_mensagens SET origem = 'resposta' WHERE message_id = %(mid)s AND direcao = 'enviada'
                        RETURNING 1)
            INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status, message_id)
            SELECT %(tel)s, 'enviada', 'resposta', %(texto)s, 'Enviado', %(mid)s WHERE NOT EXISTS (SELECT 1 FROM ja)""",
                 {"mid": mid, "tel": "55" + lead["telefone"], "texto": texto_no_crm})
    return mid


def mandar_texto(conn, lead: dict, texto: str) -> str:
    """Um texto dela. O MESMO texto para a mesma pessoa nas últimas 6 h não sai de novo (Pedro, 16/10: "fez a mesma
    pergunta duas vezes para o lead ... precisa checar para ela nunca fazer isso"). Devolve '' quando segurou."""
    if any(_normal(texto) == _normal(x) for x in ja_mandou(conn, lead, horas=6)):
        log.info("lead %s: texto repetido segurado: %s", lead.get("id"), texto[:80])
        return ""
    return _mandar(conn, lead, "/send-text", {"message": texto}, "texto", texto_no_crm=texto)


# ── nunca repetir (392b) ──
def _normal(t: str | None) -> str:
    t = unicodedata.normalize("NFKD", (t or "").lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^a-z0-9]+", " ", t).split())


def parecida(a: str | None, b: str | None, limite: float = 0.85) -> bool:
    na, nb = _normal(a), _normal(b)
    if not na or not nb:
        return False
    return na == nb or SequenceMatcher(None, na, nb).ratio() >= limite


def ja_mandou(conn, lead: dict, horas: int = 24) -> list[str]:
    """Os textos que foram para esta pessoa por este número (dela ou da equipe), os mais novos primeiro."""
    return [l["texto"] for l in banco.linhas(conn, """
        SELECT texto FROM captacao_mensagens
         WHERE direcao = 'enviada' AND coalesce(btrim(texto), '') <> '' AND criada_em > now() - make_interval(hours => %s)
           AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
         ORDER BY id DESC LIMIT 80""", (horas, _so8(lead["telefone"])))]


def _frases(t: str) -> list[str]:
    return [f.strip() for f in re.split(r"(?<=[.!?])\s+", t or "") if f.strip()]


def sem_repetir(baloes: list[str], ja: list[str]) -> list[str]:
    """Tira o balão igual (ou quase) a um que já foi, e a PERGUNTA já feita de dentro de um balão novo ("Até que valor
    o senhor procura?" duas vezes): o resto do balão fica. Balão que ficou vazio sai."""
    frases_ja = [f for x in ja for f in _frases(x)]
    saida: list[str] = []
    for b in baloes:
        if any(parecida(b, x) for x in ja + saida):
            continue
        # a pergunta já feita sai (0,8); a frase de 4+ palavras já dita também ("Assim que tiver um retorno, aviso por aqui.")
        frases = [f for f in _frases(b)
                  if not any(parecida(f, p, 0.8 if f.endswith("?") else 0.85) for p in frases_ja
                             if f.endswith("?") or len(f.split()) >= 4)]
        novo = " ".join(frases).strip()
        if len(novo.split()) <= 3 and len(frases) < len(_frases(b)):
            continue                      # sobrou só o "Certo, Sr. Carlos!" de uma pergunta repetida: não vale um balão
        if novo and not any(parecida(novo, x) for x in ja + saida):
            saida.append(novo)
    return saida


def mandar_imovel(conn, lead: dict, codigo: int, com_card: bool = True) -> int:
    """O card e as fotos de UM imóvel (sem a colagem, que é só dos grupos). Devolve quantas fotos saíram.
    `com_card=False`: só as fotos ("gostaria de ver mais fotos" do imóvel que ela já conhece)."""
    # 400: o card de CLIENTE (o de parceiro sai completo); só chega aqui o que _ofertavel deixou
    card = banco.um(conn, "SELECT texto_pronto FROM nai_card_do_imovel(%s, true)", (codigo,)) if com_card else None
    if card:
        _mandar(conn, lead, "/send-text", {"message": card}, "card", codigo, texto_no_crm=card)
    fotos = [l["url"] for l in banco.linhas(conn, "SELECT url FROM nai_imagens_do_envio(%s) WHERE NOT e_colagem", (codigo,))
             if l.get("url")][:MAX_FOTOS]
    for url in fotos:
        time.sleep(ENTRE_ENVIOS_S)
        _mandar(conn, lead, "/send-image", {"image": url}, "foto", codigo)
    return len(fotos)


# ── o banco ──
def _so8(t: str | None) -> str:
    return re.sub(r"\D", "", t or "")[-8:]


def _lista(v: str | None) -> set[str]:
    return {_so8(x) for x in re.split(r"[,;\s]+", v or "") if len(re.sub(r"\D", "", x)) >= 8}


def _pode(cfg: dict, telefone: str) -> bool:
    if _so8(telefone) in _lista(cfg.get("whatsapp_nunca")):
        return False
    modo = (cfg.get("whatsapp_responde") or "nao").strip().lower()
    return modo == "sim" or (modo == "teste" and _so8(telefone) in _lista(cfg.get("whatsapp_teste")))


def _lead(conn, lid: int) -> dict:
    l = banco.linhas(conn, """SELECT l.*, nay_tratamento_por_nome(l.nome) AS trat FROM privado.olx_lead_whatsapp l
                               WHERE l.id = %s""", (lid,))
    return l[0] if l else {}


def _gente_escreveu(conn, lead: dict, desde) -> object:
    """A última mensagem de GENTE para esta pessoa por este número (texto que não foi a Nay), depois de `desde`."""
    return banco.um(conn, """
        SELECT max(m.criada_em) FROM captacao_mensagens m
         WHERE m.direcao = 'enviada' AND m.criada_em > %s AND coalesce(btrim(m.texto), '') <> ''
           AND coalesce(m.origem, '') NOT IN ('resposta', 'disparo')
           AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = %s
           AND NOT EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id)""",
                    (desde, _so8(lead["telefone"])))


def _marcar(conn, lid: int, **campos) -> None:
    if not campos:
        return
    sets, vals = [], []
    for k, v in campos.items():
        if k == "etapa":
            sets.append("etapa = %s, etapa_em = now()")
        elif k in ("filtros", "visita"):
            sets.append(f"{k} = %s::jsonb")
            v = json.dumps(v, ensure_ascii=False)
        elif k == "assumido_em_agora":
            sets.append("assumido_em = now()")
            continue
        else:
            sets.append(f"{k} = %s")
        vals.append(v)
    banco.um(conn, f"UPDATE privado.olx_lead_whatsapp SET {', '.join(sets)}, atualizado_em = now() WHERE id = %s",
             (*vals, lid))


def _conversa(conn, lead: dict) -> list[dict]:
    return list(reversed(banco.linhas(conn, """
        SELECT m.id, m.direcao, m.origem, m.texto, m.criada_em,
               EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id) AS nossa
          FROM captacao_mensagens m
         WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = %s
           AND m.criada_em > now() - interval '30 days'
           -- 394: o eco das fotos (sem texto) não ocupa o lugar da conversa
           AND (m.direcao = 'recebida' OR coalesce(btrim(m.texto), '') <> '')
         ORDER BY m.id DESC LIMIT 40""", (_so8(lead["telefone"]),))))


def _int(v) -> int | None:
    """O número que o modelo mandou ("#9026", "9026", 9026.0, "R$ 2.500") ou None."""
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return int(v) or None
    d = re.sub(r"\D", "", str(v))
    return int(d) if d else None


def _ultima_recebida(conn, lead: dict) -> int:
    return int(banco.um(conn, """SELECT coalesce(max(id), 0) FROM captacao_mensagens WHERE direcao = 'recebida'
                                  AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""",
                        (_so8(lead["telefone"]),)) or 0)


# ── o turno que vai ao modelo ──
def tratamento(lead: dict) -> tuple[str, str]:
    """('Sra. Claudia', 'a senhora') | ('Sr. Felipe', 'o senhor') | ('Ana', 'você')."""
    primeiro = ((lead.get("nome") or "").strip().split() or [""])[0].capitalize()
    t = lead.get("trat")
    if t == "Sra." and primeiro:
        return f"Sra. {primeiro}", "a senhora"
    if t == "Sr." and primeiro:
        return f"Sr. {primeiro}", "o senhor"
    return primeiro or "", "você"


def organico(lead: dict) -> bool:
    return lead.get("origem") == "organico"


def quem(lead: dict) -> str:
    """Para os avisos da equipe: 'Fulana (OLX, (92) 9...)' ou '(orgânico, ...)'."""
    return (f"{lead.get('nome') or 'sem nome'} ({'orgânico' if organico(lead) else 'OLX'}, "
            f"{nay.telefone_bonito(lead['telefone'])})")


CODIGO_CITADO = re.compile(r"(?<![\d.,$])#?(\d{4})(?![\d.,]|\s*(?:mil|reais|k\b))", re.I)


# 394: "até 2500", "uns 3000", "aluguel de 2800" são valor, não código de imóvel
VALOR_EM_REAIS = re.compile(r"(R\$|\bat[eé]\b|\b(?:uns|umas|uma|um)\b|\bpor\b|\bvalor\b|\baluguel( de)?\b|\bor[cç]amento\b|\bpag(ar|o)\b|"
                            r"\bteto\b|\bm[aá]ximo\b|\bde\b)\s*[0-9.,]+", re.I)


def codigos_citados(conversa: list[dict], ate: int = 2) -> list[int]:
    """Os códigos de imóvel que a pessoa escreveu (os últimos primeiro): "5758", "#5758", "o 5758"; "2500 reais" não."""
    vistos: list[int] = []
    for m in reversed(conversa):
        if m.get("direcao") != "recebida":
            continue
        for c in reversed(CODIGO_CITADO.findall(VALOR_EM_REAIS.sub(" ", m.get("texto") or ""))):
            if int(c) not in vistos:
                vistos.append(int(c))
    return vistos[:ate]


def _pelo_nome(conn, conversa: list[dict]) -> list[int]:
    """Sem código: o condomínio que ela escreveu ("Quero saber mais sobre o imóvel Cobertura - Life Flores", a mensagem
    pronta dos portais), disponível, o tipo que ela disse primeiro."""
    texto = " ".join((m.get("texto") or "") for m in conversa if m.get("direcao") == "recebida")[-1500:]
    if not texto.strip():
        return []
    return [int(l["codigo"]) for l in banco.linhas(conn, """
        SELECT codigo FROM imoveis
         WHERE status = 'Disponível' AND length(btrim(coalesce(condominio_nome, ''))) >= 6
           -- o "condomínio" que é só o tipo (Apartamento, Prédio, Loja/Ponto...) não é nome
           AND lower(unaccent(btrim(condominio_nome))) <> lower(unaccent(coalesce(tipo, '')))
           AND lower(unaccent(btrim(condominio_nome)))
               !~ '^(apartamento|predio|casa|cobertura|kitnet|terreno|condominio|residencial|sala|loja|galpao)([/ ].*)?$'
           AND position(lower(unaccent(btrim(condominio_nome))) IN lower(unaccent(%(t)s))) > 0
         ORDER BY position(lower(unaccent(coalesce(tipo, '-'))) IN lower(unaccent(%(t)s))) > 0 DESC, codigo DESC
         LIMIT 2""", {"t": texto})]


def _fichas_citadas(conn, conversa: list[dict], lead: dict | None = None) -> list[dict]:
    fichas = []
    for c in codigos_citados(conversa) or _pelo_nome(conn, conversa):
        i = banco.um(conn, "SELECT site_imovel_publico(%s)", (c,))
        if isinstance(i, dict) and i:
            fichas.append({"codigo": c, **nay._ficha(i)})
        elif lead and _ofertavel(conn, c, lead):
            # 400: o de parceiro não tem página pública; ela lê o card de cliente dele
            card = banco.um(conn, "SELECT texto_pronto FROM nai_card_do_imovel(%s, true)", (c,))
            if card:
                fichas.append({"codigo": c, "card": card})
    return fichas


def montar_turno(lead: dict, ctx_olx: dict | None, conversa: list[dict]) -> str:
    ctx_olx = ctx_olx or {}
    anuncio = ctx_olx.get("anuncio") or {}
    negocio = "LOCAÇÃO" if (lead.get("negocio") or anuncio.get("negocio") or "").startswith("loca") else "VENDA"
    trat, pronome = tratamento(lead)
    agora = datetime.now(MANAUS)
    periodo = "manhã: Bom dia" if agora.hour < 12 else "tarde: Boa tarde" if agora.hour < 18 else "noite: Boa noite"
    linhas = [
        f"=== AGORA === {visita.DIAS[agora.weekday()]}, {agora:%d/%m/%Y %H:%M} em Manaus ({periodo}). Cumprimente pela hora "
        f"de AGORA, não pela da OLX.",
        "",
        "=== QUEM É ===",
        f"Nome: {lead.get('nome') or 'não informado'} | trate como: {trat or 'pelo primeiro nome'} ({pronome})",
        "",
    ]
    if organico(lead):
        linhas += [
            "=== DE ONDE VEIO: ORGÂNICO ===",
            "Escreveu direto para este número: não houve OLX nem anúncio. Siga QUANDO VEIO DIRETO.",
        ]
        if not any(m.get("nossa") or m.get("origem") == "resposta" for m in conversa):
            linhas.append("Você ainda não falou com ela: esta é a sua primeira mensagem (a abertura do orgânico).")
        for f in lead.get("fichas_citadas") or []:
            linhas.append(f"Ficha do imóvel {f['codigo']} (o que ela citou): " + json.dumps(f, ensure_ascii=False))
    else:
        linhas += [
            "=== DE ONDE VEIO: O ANÚNCIO NA OLX ===",
            f"{negocio} | {anuncio.get('titulo') or '-'} | cód. {lead.get('codigo') or anuncio.get('codigo') or '-'}",
            "Ficha do imóvel do anúncio: " + json.dumps(nay._ficha(ctx_olx.get("imovel")), ensure_ascii=False),
            "O que a Nay da OLX leu dela: " + json.dumps(lead.get("perfil") or {}, ensure_ascii=False),
            f"Na OLX ela disse que quer visitar: {'sim' if lead.get('quer_visita') else 'não'}",
            "A conversa na OLX (a mais antiga primeiro):",
        ]
        for m in ctx_olx.get("mensagens") or []:
            linhas.append(f"  {nay._quem(m)}: {(m.get('texto') or '').strip()}")
    linhas += [
        "",
        "=== ONDE ESTÁ ===",
        f"Etapa: {lead.get('etapa')}",
        "Filtros já ditos: " + json.dumps(lead.get("filtros") or {}, ensure_ascii=False),
        "Imóveis já enviados (códigos): " + (", ".join(str(c) for c in lead.get("enviados") or []) or "nenhum"),
        _linha_da_visita(lead.get("visita_aberta")),
        "",
        "=== A CONVERSA NO WHATSAPP (a mais antiga primeiro) ===",
    ]
    if not conversa:
        linhas.append("Ainda não há conversa: escreva a PRIMEIRA mensagem (a abertura).")
    for m in conversa:
        texto = (m.get("texto") or "").strip()
        if m.get("direcao") == "recebida":
            linhas.append(f"CLIENTE: {texto or '[mandou ' + (m.get('origem') or 'uma mídia') + ']'}")
        elif m.get("nossa") or m.get("origem") == "resposta":
            if texto:
                linhas.append(f"NAY: {texto}")
        elif texto:
            linhas.append(f"EQUIPE: {texto}")
    linhas += ["", "Responda agora, só com o JSON."]
    return "\n".join(linhas)


PE_DA_VISITA = {
    "confirmar_cliente": "a confirmação foi para ela; espere o sim (acao confirmou_visita) ou a correção (acao visita)",
    "buscando_corretor": "ela confirmou; você está confirmando com o corretor",
    "pedindo_proprietario": "o corretor confirmou; você está confirmando com o proprietário",
    "confirmada": "CONFIRMADA: ela já recebeu a confirmação com o corretor",
    "sem_corretor": "a equipe está combinando quem acompanha; se ela perguntar, diga que está confirmando",
    "sem_proprietario": "a equipe está falando com o proprietário; se ela perguntar, diga que está confirmando",
    "proprietario_nao": "o proprietário não pode nesse horário; ela precisa escolher outro dia e horário",
}


def _linha_da_visita(v: dict | None) -> str:
    if not v:
        return "Visita em andamento: nenhuma"
    q = v["quando"].astimezone(MANAUS)
    return (f"Visita em andamento: imóvel #{v['codigo']}, {visita.dia(q)} às {visita.hora(q)} — "
            f"{PE_DA_VISITA.get(v['estado'], v['estado'])}")


def _filtros(antes: dict, novos) -> dict:
    """Junta o que ela disse agora ao que já sabíamos. Vazio, 0 e null não apagam o que já estava."""
    f = dict(antes or {})
    for k in CAMPOS_DOS_FILTROS:
        v = (novos or {}).get(k) if isinstance(novos, dict) else None
        if v in (None, "", 0, [], False) and k not in ("aceita_menos_quartos", "aceita_escada"):
            continue
        if v is None:
            continue
        if k == "teto":
            v = _int(v)
            if not v:
                continue
        f[k] = v
    if f.get("qualquer_bairro") is True and (novos or {}).get("qualquer_bairro") is True:
        f["bairros"] = []                     # 394: "pode ser qualquer bairro" apaga os bairros ditos antes
    return f


def _resumo_dos_filtros(f: dict) -> str:
    partes = [f.get("finalidade") or "", f.get("tipo") or "",
              f"até R$ {int(float(f['teto'])):,}".replace(",", ".") if f.get("teto") else "",
              ", ".join(f.get("bairros") or []) or ("qualquer bairro" if f.get("qualquer_bairro") else ""),
              f"{f['quartos']} quartos" if f.get("quartos") else "",
              # 19/10: a mobília entra no resumo, senão a Nay pergunta de novo
              {"mobiliado": "mobiliado", "semi": "modulados e ar", "tanto_faz": "mobília tanto faz"}.get(f.get("mobilia") or "", ""),
              f.get("financiamento") or ""]
    return " · ".join(p for p in partes if p)


# ── as três tarefas ──
_FALHAS: dict[int, int] = {}
_ESPERA: dict[int, float] = {}


def _em_espera(lid: int) -> bool:
    return _ESPERA.get(lid, 0.0) > time.monotonic()


def _falhou(conn, lead: dict, ate: int | None, erro: Exception) -> None:
    """394: um cliente com erro (modelo, Z-API, dado estranho) não trava os outros nem chama o modelo de 5 em 5 s:
    espera 2 min; na terceira falha seguida, a Nay larga a mensagem (marca lida) e avisa a equipe no grupo."""
    lid = lead["id"]
    _FALHAS[lid] = _FALHAS.get(lid, 0) + 1
    _ESPERA[lid] = time.monotonic() + 120
    log.warning("lead %s: falhou (%d): %s", lid, _FALHAS[lid], erro)
    if _FALHAS[lid] >= 3:
        _FALHAS.pop(lid, None)
        if ate:
            _marcar(conn, lid, ultima_lida=ate)
        _grupo(f"Cliente {quem(lead)} no WhatsApp de captação: a Nay não conseguiu responder a última mensagem "
               f"(três tentativas). Vejam por lá.")


def _deu_certo(lid: int) -> None:
    _FALHAS.pop(lid, None)
    _ESPERA.pop(lid, None)


def _baloes_do(r: dict) -> list[str]:
    """Os balões do modelo, limpos. Texto solto (não lista) vira um balão só, não um balão por letra."""
    brutos = r.get("baloes")
    if isinstance(brutos, str):
        brutos = [brutos]
    if not isinstance(brutos, list):
        return []
    return [b for b in (nay.limpar_balao(str(x)) for x in brutos[:MAX_BALOES]) if b]


def _falar(conn, lead: dict, r: dict, acoes: list[str]) -> list[str]:
    """Manda os balões do turno. 394 (Pedro: "ela só deve confirmar que vai mandar as solicitações uma vez ... e depois
    já vir com as opções pesquisadas"): com "buscar", é UM balão só (o resto vem nos cards); nada repetido sai."""
    baloes = _baloes_do(r)
    if "buscar" in acoes and len(baloes) > 1:
        baloes = [" ".join(baloes)]
    antes = len(baloes)
    baloes = sem_repetir(baloes, ja_mandou(conn, lead))
    if antes != len(baloes):
        log.info("lead %s: %d balão(ões) repetido(s) não saiu(íram)", lead["id"], antes - len(baloes))
    for n, b in enumerate(baloes):
        if n:
            time.sleep(ENTRE_ENVIOS_S)
        mandar_texto(conn, lead, b)
    r["_baloes_que_sairam"] = baloes
    return baloes


def abrir(conn, cfg: dict) -> int:
    feitos = 0
    for l in banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp
                                    WHERE etapa = 'nova' AND assumido_em IS NULL AND humano_em IS NULL
                                      AND criado_em > now() - interval '7 days' ORDER BY criado_em LIMIT 3"""):
        if _em_espera(l["id"]):
            continue
        lead = _lead(conn, l["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        try:
            # a equipe já chamou por este número (nos últimos 3 dias): a conversa é dela
            gente = _gente_escreveu(conn, lead, banco.um(conn, "SELECT now() - interval '3 days'"))
            if gente:
                _marcar(conn, lead["id"], assumido_em_agora=True, humano_em=gente, etapa="filtrar",
                        parada_motivo="a equipe já tinha chamado por este número")
                log.info("lead %s: a equipe já chamou; a Nay não abre", lead["id"])
                continue
            ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
            lead["visita_aberta"] = visita.para_o_modelo(conn, lead["id"])
            # 394: o que ela já escreveu (ou o que já conversamos, se veio de outro anúncio) entra na abertura
            conversa = _conversa(conn, lead)
            ate = max([m["id"] for m in conversa if m.get("direcao") == "recebida"] or [_ultima_recebida(conn, lead)])
            r = modelo.chamar(PROMPT, montar_turno(lead, ctx_olx, conversa))
            acoes = acoes_da(r)
            if not _baloes_do(r):
                raise ValueError("o modelo não escreveu a abertura")
            baloes = _falar(conn, lead, r, acoes)
            filtros = _filtros(lead.get("filtros"), r.get("filtros"))
            _marcar(conn, lead["id"], assumido_em_agora=True, etapa="filtrar", ultima_lida=ate, filtros=filtros)
            # 16/10: o que ela promete já na abertura (passar o desconto à equipe, confirmar a visita pedida na OLX...) tem
            # de chegar à equipe: as ações da abertura valem como as de qualquer resposta
            for acao in acoes:
                _fazer(conn, _lead(conn, lead["id"]), r, acao, filtros, cfg)
            _deu_certo(lead["id"])
            log.info("lead %s aberto (%d balão/ões)", lead["id"], len(baloes))
            feitos += 1
        except Exception as e:  # noqa: BLE001 -- um cliente não para os outros
            _falhou(conn, lead, None, e)
            if _FALHAS.get(lead["id"]) is None:       # terceira falha: não abre mais sozinha
                _marcar(conn, lead["id"], assumido_em_agora=True, humano_em=banco.um(conn, "SELECT now()"),
                        etapa="filtrar", parada_motivo="a Nay não conseguiu abrir")
    return feitos


_ULTIMA_DESCOBERTA = [0.0]


def descobrir_organicos(conn, cfg: dict, a_cada_s: float = 20.0) -> int:
    """390 (Pedro, 16/10): "quando chega lead novo a Nay deve atender normal, e perguntar se ele quer imóvel, esse vem com a
    tag orgânico". Quem escreveu pela primeira vez neste número e não é dono, corretor, equipe nem cliente da OLX
    (olx_organicos_novos) vira lead da Nay; a resposta sai pela fila de sempre, depois do silêncio."""
    if (cfg.get("organico_atende") or "nao").strip().lower() != "sim":
        return 0
    if time.monotonic() - _ULTIMA_DESCOBERTA[0] < a_cada_s:
        return 0
    _ULTIMA_DESCOBERTA[0] = time.monotonic()
    novos = 0
    for o in banco.linhas(conn, "SELECT telefone, primeira FROM olx_organicos_novos(60)"):
        if not _pode(cfg, o["telefone"]):
            continue
        lid = banco.um(conn, """
            INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, etapa, etapa_em, assumido_em, ultima_lida, perfil)
            SELECT NULL, %s, 'organico', 'filtrar', now(), now(), %s - 1, '{"procura": "escreveu direto no WhatsApp"}'::jsonb
             WHERE NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8))
            ON CONFLICT DO NOTHING RETURNING id""", (o["telefone"], int(o["primeira"]), o["telefone"]))
        if lid:
            log.info("lead %s: orgânico (%s)", lid, nay.telefone_bonito(o["telefone"]))
            novos += 1
    return novos


def _fila(conn, cfg: dict) -> list[dict]:
    """Quem escreveu e ficou `whatsapp_silencio_s` quieto. Um lead por telefone (o mais novo); o encerrado também (394:
    quem volta a escrever é atendido de novo)."""
    silencio = max(0, int(cfg.get("whatsapp_silencio_s") or 20))
    return banco.linhas(conn, """
        SELECT x.id, x.ate FROM (
          SELECT DISTINCT ON (right(l.telefone, 8)) l.id, max(m.id) AS ate, max(m.criada_em) AS ultima
            FROM privado.olx_lead_whatsapp l
            JOIN captacao_mensagens m ON m.direcao = 'recebida' AND m.id > l.ultima_lida
                                     AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
           WHERE l.assumido_em IS NOT NULL
           GROUP BY l.id, l.telefone, l.criado_em
           ORDER BY right(l.telefone, 8), l.criado_em DESC) x
         WHERE x.ultima < now() - make_interval(secs => %s)
         ORDER BY x.ultima LIMIT 5""", (silencio,))


# 394: "ok", "obrigada", "aguardo" depois de uma resposta dela não pedem outra resposta (a Michelle, 16:34: "Obrigada" e a
# Nay confirmou de novo que ia pedir à equipe)
SO_AGRADECEU = re.compile(
    r"^(ok+|okay|ok ok|blz|beleza|obrigad[oa]s?|muito obrigad[oa]|obg|brigad[oa]|valeu|vlw|aguardo|fico no aguardo|"
    r"fico aguardando|aguardando|t[aá] bom|ta|certo|combinado|perfeito|show|top|joia|ok obrigad[oa]|obrigad[oa] aguardo|"
    r"ok aguardo|tudo bem|de nada|por nada|amem|am[eé]m|grat[oa]|gratid[aã]o)$", re.I)


def so_agradeceu(textos: list[str]) -> bool:
    if not textos:
        return False
    for t in textos:
        sem_emoji = re.sub(r"[\U0001F300-\U0001FAFF☀-➿]", " ", t or "")
        n = _normal(sem_emoji)
        if not n and sem_emoji.strip() == "" and (t or "").strip():
            continue                      # só emoji (👍🙏): agradecimento
        if not n or not SO_AGRADECEU.match(n):
            return False                  # mídia sem texto, ou um pedido de verdade
    return True


def responder(conn, cfg: dict) -> int:
    feitos = 0
    for item in _fila(conn, cfg):
        if _em_espera(item["id"]):
            continue
        lead = _lead(conn, item["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        ate = int(item["ate"])
        try:
            if _responder_um(conn, cfg, lead, ate):
                feitos += 1
            _deu_certo(lead["id"])
        except Exception as e:  # noqa: BLE001 -- um cliente não para os outros
            _falhou(conn, lead, ate, e)
    return feitos


def _responder_um(conn, cfg: dict, lead: dict, ate: int) -> bool:
    # gente da equipe escreveu para ela por este número: a Nay cala (e não relê o que ficou para trás)
    gente = _gente_escreveu(conn, lead, lead.get("humano_em") or lead.get("assumido_em"))
    if gente:
        _marcar(conn, lead["id"], humano_em=gente, ultima_lida=ate, parada_motivo="a equipe respondeu")
        return False
    if lead.get("humano_em"):
        # a equipe assumiu (Pedro, 16/10, na OLX: "a nay não deve mais responder"): ela não volta sozinha
        _marcar(conn, lead["id"], ultima_lida=ate)
        return False
    conversa = _conversa(conn, lead)
    if banco.um(conn, "SELECT count(*) FROM privado.olx_cliente_enviada WHERE lead = %s AND tipo = 'texto'",
                (lead["id"],)) >= LIMITE_DE_MENSAGENS:
        _marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), ultima_lida=ate,
                parada_motivo="a conversa foi longe demais para a Nay")
        _grupo(f"Cliente {quem(lead)}: a conversa no WhatsApp de captação foi longe; precisa de alguém.")
        return False
    if lead.get("etapa") == "finalizado":
        # 394: ela tinha encerrado e a pessoa voltou a escrever: a conversa reabre
        etapa = "visita" if visita.ativa(conn, lead["id"]) else ("imoveis_enviados" if lead.get("enviados") else "filtrar")
        _marcar(conn, lead["id"], etapa=etapa)
        lead["etapa"] = etapa
    lead["visita_aberta"] = visita.para_o_modelo(conn, lead["id"])
    novas = [m.get("texto") or "" for m in conversa if m.get("direcao") == "recebida" and m.get("id", 0) > (lead.get("ultima_lida") or 0)]
    nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
    esperando_sim = (lead.get("visita_aberta") or {}).get("estado") == "confirmar_cliente"
    if (so_agradeceu(novas) and nossas and not nossas[-1]["texto"].strip().endswith("?") and not esperando_sim):
        _marcar(conn, lead["id"], ultima_lida=ate)          # "obrigada": não é pedido; ela não repete a confirmação
        log.info("lead %s: só agradeceu; a Nay não responde", lead["id"])
        return False
    ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
    if organico(lead):
        lead["fichas_citadas"] = _fichas_citadas(conn, conversa, lead)
    r = modelo.chamar(PROMPT, montar_turno(lead, ctx_olx, conversa))
    acoes = acoes_da(r)
    _falar(conn, lead, r, acoes)
    filtros = _filtros(lead.get("filtros"), r.get("filtros"))
    _marcar(conn, lead["id"], ultima_lida=ate, filtros=filtros)
    for acao in acoes:
        _fazer(conn, _lead(conn, lead["id"]), r, acao, filtros, cfg)
    return True


def acoes_da(r: dict) -> list[str]:
    """As ações da resposta, na ordem, sem repetir (até duas). Aceita o formato antigo ("acao": "buscar").
    394: "visita" e "confirmou_visita" no mesmo turno não: o sim é do turno seguinte, depois da confirmação."""
    brutas = r.get("acoes") if isinstance(r.get("acoes"), list) else [r.get("acao")]
    saida: list[str] = []
    for a in brutas:
        a = str(a or "").strip().lower()
        if a in ("fotos", "buscar", "visita", "confirmou_visita", "perguntar", "equipe", "encerrar") and a not in saida:
            saida.append(a)
    if "visita" in saida and "confirmou_visita" in saida:
        saida.remove("confirmou_visita")
    return saida[:2]


def _ofertavel(conn, codigo: int, lead: dict | None = None) -> bool:
    """O imóvel pode ir a esta pessoa: anunciável; o de PARCEIRO Disponível só a quem não é corretor (400, Pedro 17/10:
    "não enviamos para os corretores, só para os clientes finais que vêm da OLX"). Sem telefone: parceiro não sai."""
    return bool(banco.um(conn, "SELECT olx_imovel_vai_ao_cliente(%s, %s)", (codigo, (lead or {}).get("telefone"))))


def _aceita_parceiro(conn, lead: dict) -> bool:
    """400: cliente final (não é corretor dos grupos nem parceiro do site antigo) recebe imóvel de parceiro."""
    return bool(lead.get("telefone")) and bool(banco.um(conn, "SELECT olx_pode_receber_parceiro(%s)", (lead["telefone"],)))


def codigo_da_pergunta(lead: dict, motivo: str) -> int | None:
    """394: o código que está NA pergunta vence o do anúncio ("o 9026 aceita pet?" não é sobre o #3883); vários códigos,
    nenhum (a resposta não vira memória de um imóvel só)."""
    cods = list(dict.fromkeys(re.findall(r"(?<!\d)(\d{4})(?!\d)", motivo or "")))
    if len(cods) == 1:
        return int(cods[0])
    if len(cods) > 1:
        return None
    return lead.get("codigo")


def _fazer(conn, lead: dict, r: dict, acao: str, filtros: dict, cfg: dict | None = None) -> None:
    if acao == "fotos":
        f = r.get("fotos") if isinstance(r.get("fotos"), dict) else {}
        codigo = _int(f.get("codigo")) or lead.get("codigo")
        if codigo and not _ofertavel(conn, codigo, lead):
            _para_a_fila(conn, lead, codigo, f"Pediu fotos do #{codigo}, que é de parceria ou não está disponível: o que dizer?")
            codigo = None
        if codigo:
            # o imóvel do anúncio ou um que ela já recebeu: só as fotos (o card ela já viu)
            ja_viu = codigo == lead.get("codigo") or codigo in (lead.get("enviados") or [])
            mandar_imovel(conn, lead, codigo, com_card=not ja_viu)
            if not ja_viu:
                _marcar(conn, lead["id"], enviados=list(lead.get("enviados") or []) + [codigo])
            time.sleep(DEPOIS_DAS_FOTOS_S)
        depois = sem_repetir([b for b in (nay.limpar_balao(str(x)) for x in (r.get("depois_das_fotos") or [])[:MAX_BALOES]) if b],
                             ja_mandou(conn, lead))
        for b in depois:
            mandar_texto(conn, lead, b)
            time.sleep(ENTRE_ENVIOS_S)
    elif acao == "buscar":
        # ela já disse neste turno que vai pegar/separar as opções: a busca vazia não diz de novo
        ja_avisou = any(re.search(r"op[cç][oõ]es", b, re.I) and re.search(r"separ|pegar|sistema|busc|procur", b, re.I)
                        for b in (r.get("_baloes_que_sairam") or _baloes_do(r)))
        _buscar_e_mandar(conn, lead, filtros, ja_avisou=ja_avisou)
    elif acao == "visita":
        # 389 (Pedro, 16/10): a confirmação no modelo da Parceria; os contatos só depois do sim dela
        v = r.get("visita") if isinstance(r.get("visita"), dict) else {}
        codigo = _int(v.get("codigo")) or lead.get("codigo")
        if codigo and not _ofertavel(conn, codigo, lead):
            _para_a_fila(conn, lead, codigo, f"Quer visitar o #{codigo}, que é de parceria ou não está disponível: o que dizer?")
        elif visita.pedir_confirmacao(conn, lead, codigo, str(v.get("data") or ""), str(v.get("hora") or "")):
            pass                                            # a etapa vira 'visita' lá dentro
    elif acao == "confirmou_visita":
        visita.cliente_confirmou(conn, lead, cfg or {})
    elif acao == "perguntar":
        # Pedro, 16/10 (a Michelle pediu os quartos com roupeiros): "ela deve nos perguntar porque a Nay não sabe que foto
        # é de qual lugar". 391: a pergunta vai à FILA do PV do Tel (uma por vez, cobrada); a resposta dele volta por
        # entregar_respostas e a conversa continua com ela. Sem a fila, ao grupo como antes.
        motivo = str(r.get("motivo") or "algo que a Nay não sabe")[:600]
        if not _para_a_fila(conn, lead, codigo_da_pergunta(lead, motivo), motivo):
            _grupo(f"Cliente {quem(lead)} no WhatsApp de captação "
                   f"pediu: {motivo[:240]}. A Nay disse que já retorna: mandem por lá.")
    elif acao == "equipe":
        _marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), parada_motivo=str(r.get("motivo") or "")[:200])
        _grupo(f"Cliente {quem(lead)} no WhatsApp de "
               f"captação: {str(r.get('motivo') or 'precisa da equipe')[:200]}.")
    elif acao == "encerrar":
        # 394: com visita andando ou marcada, não encerra (a Josy disse "obrigada" e foi para Finalizados com a visita do
        # dia seguinte)
        if not visita.ativa(conn, lead["id"]):
            _marcar(conn, lead["id"], etapa="finalizado")


ETAPAS_DA_BUSCA = ("nova", "filtrar", "feito_busca", "imoveis_enviados", "finalizado")


def _afrouxar(f: dict) -> list[tuple[dict, bool]]:
    """394 (Pedro: "e depois já vir com as opções pesquisadas"): nada no perfil exato -> o mais perto, um passo de cada vez
    (sem mobília, com um quarto a menos, nos bairros vizinhos e em qualquer bairro, até 20% acima do valor)."""
    passos: list[tuple[dict, bool]] = [(f, False)]
    g = dict(f)
    if g.get("mobilia"):
        g = {**g, "mobilia": ""}
        passos.append((g, True))
    if g.get("quartos") and not g.get("aceita_menos_quartos"):
        g = {**g, "aceita_menos_quartos": True}
        passos.append((g, True))
    if g.get("bairros") and not g.get("qualquer_bairro"):
        g = {**g, "bairros": [], "qualquer_bairro": True}
        passos.append((g, True))
    if g.get("teto"):
        g = {**g, "teto": int(float(g["teto"]) * 1.2)}
        passos.append((g, True))
    return passos


def _buscar_e_mandar(conn, lead: dict, filtros: dict, ja_avisou: bool = False) -> None:
    excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else [])
    f = dict(filtros)
    if not f.get("finalidade"):
        f["finalidade"] = finalidade_sem_dizer(lead, f)
    if _aceita_parceiro(conn, lead):
        f["aceita_parceiro"] = "true"           # 400: o cliente final recebe também os de parceiro
    achados, proximas = [], False
    for tentativa, afrouxou in _afrouxar(f):
        achados = banco.linhas(conn, "SELECT * FROM olx_cliente_buscar(%s::jsonb, %s::int[], %s)",
                               (json.dumps(tentativa, ensure_ascii=False), excluir, MAX_IMOVEIS))
        if achados:
            proximas = afrouxou
            break
    if lead.get("etapa") in ETAPAS_DA_BUSCA:
        _marcar(conn, lead["id"], etapa="feito_busca")
    if not achados:
        # 416 (Pedro, 19/10): o catálogo não tem -> ordem de busca na OLX (olx/parceiro.py); ela "vai verificar"
        if abrir_busca_na_olx(conn, lead, f):
            if not ja_avisou:
                mandar_texto(conn, lead, "Vou verificar as opções que tenho aqui se estão disponíveis e já te retorno.")
            return
        # nunca a negativa: ela diz que está separando e a equipe recebe o perfil (se já disse neste turno, não repete)
        if not ja_avisou:
            mandar_texto(conn, lead, "Estou separando as opções com a nossa equipe e já te retorno por aqui.")
        _grupo(f"Cliente {quem(lead)} procura "
               f"{_resumo_dos_filtros(f)} e a busca não achou nada nem perto: separar opções para ela.")
        return
    enviados = list(lead.get("enviados") or [])
    for n, a in enumerate(achados):
        if n:
            time.sleep(DEPOIS_DAS_FOTOS_S)       # as fotos do anterior carregam antes do próximo card
        mandar_imovel(conn, lead, int(a["codigo"]))
        enviados.append(int(a["codigo"]))
        _marcar(conn, lead["id"], enviados=enviados)
    time.sleep(DEPOIS_DAS_FOTOS_S)
    texto = fecho(lead, len(achados), proximas=proximas)
    if any(_normal(texto) == _normal(x) for x in ja_mandou(conn, lead)):
        texto = fecho(lead, len(achados), de_novo=True)        # a segunda busca não fecha com a mesma frase
    mandar_texto(conn, lead, texto)
    if lead.get("etapa") in ETAPAS_DA_BUSCA:
        _marcar(conn, lead["id"], etapa="imoveis_enviados")
    log.info("lead %s: %d imóvel(is) enviado(s)%s", lead["id"], len(achados), " (os mais próximos)" if proximas else "")


def busca_na_olx_vale(cfg: dict, telefone: str) -> tuple[bool, bool]:
    """(abre, teste): a chave `busca_parceiro` (nao | teste | sim); em teste só para o PRIMEIRO número de `whatsapp_teste`
    (o do Pedro: o segundo da lista é a Michelle, cliente de verdade)."""
    modo = (cfg.get("busca_parceiro") or "nao").strip().lower()
    if modo == "sim":
        return True, False
    primeiro = [x for x in re.split(r"[,;\s]+", cfg.get("whatsapp_teste") or "") if x.strip()][:1]
    if modo == "teste" and primeiro and _so8(telefone) == _so8(primeiro[0]):
        return True, True
    return False, False


def abrir_busca_na_olx(conn, lead: dict, filtros: dict) -> bool:
    """Abre (ou reconhece a que já está aberta) a ordem de busca de imóvel de parceiro na OLX deste cliente."""
    abre, teste = busca_na_olx_vale(banco.chaves(conn), lead["telefone"])
    if not abre:
        return False
    # o mesmo pedido já procurado nas últimas 6 h e encerrado: a busca daria o mesmo; fica o caminho de antes (equipe)
    if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_busca_parceiro WHERE lead = %s AND filtros = %s::jsonb
                           AND estado NOT IN ('pendente', 'buscando', 'sem_navegador', 'perguntado', 'aguardando_cadastro')
                           AND criado_em > now() - interval '6 hours')""", (lead["id"], json.dumps(filtros, ensure_ascii=False))):
        return False
    try:
        nova = banco.um(conn, """INSERT INTO privado.olx_busca_parceiro (lead, filtros, teste) VALUES (%s, %s::jsonb, %s)
                                 ON CONFLICT DO NOTHING RETURNING id""", (lead["id"], json.dumps(filtros, ensure_ascii=False), teste))
    except Exception:  # noqa: BLE001
        log.exception("lead %s: a ordem de busca na OLX não abriu", lead["id"])
        return False
    log.info("lead %s: busca na OLX %s", lead["id"], f"aberta ({nova})" if nova else "já aberta")
    return True


def finalidade_sem_dizer(lead: dict, f: dict) -> str:
    """Ela não disse: na OLX é a do anúncio; no orgânico, o valor diz (até R$ 30.000 é aluguel)."""
    if lead.get("negocio"):
        return "locacao" if lead["negocio"].startswith("loca") else "venda"
    try:
        teto = float(f.get("teto") or 0)
    except (TypeError, ValueError):
        teto = 0
    return "locacao" if 0 < teto <= 30000 else "venda"


def fecho(lead: dict, quantos: int = 2, de_novo: bool = False, proximas: bool = False) -> str:
    """A mensagem depois dos imóveis (fixa: o modelo não é chamado no meio do envio). `proximas`: a busca foi afrouxada
    (o perfil exato não tinha): "as mais próximas do que procura", nunca a negativa."""
    _, pronome = tratamento(lead)
    if proximas and not de_novo:
        procura = {"a senhora": "a senhora procura", "o senhor": "o senhor procura"}.get(pronome, "você procura")
        quem = {"a senhora": "chamou a atenção da senhora", "o senhor": "chamou a atenção do senhor"}.get(pronome, "te chamou a atenção")
        if quantos == 1:
            return f"Essa é a opção mais próxima do que {procura}. Ela {quem}? Posso agendar uma visita ou procurar mais opções."
        return (f"Essas são as opções mais próximas do que {procura}. Alguma {quem}? Posso agendar uma visita ou procurar "
                f"mais opções.")
    if de_novo:
        quem = {"a senhora": "a senhora gostou", "o senhor": "o senhor gostou"}.get(pronome, "você gostou")
        return (f"{'Essa é mais uma opção' if quantos == 1 else 'Essas são mais opções'} que encontrei. Se {quem} de "
                f"alguma, já vejo a visita.")
    if quantos == 1:
        quem = {"a senhora": "agradou a senhora", "o senhor": "agradou o senhor"}.get(pronome, "te agradou")
        return f"Essa é a opção que separei. Ela {quem}? Posso agendar uma visita ou procurar mais opções."
    quem = {"a senhora": "chamou a atenção da senhora", "o senhor": "chamou a atenção do senhor"}.get(pronome, "te chamou a atenção")
    return f"Essas são as opções que separei. Alguma {quem}? Posso agendar uma visita ou procurar mais opções."


def _grupo(texto: str) -> None:
    try:
        if not grupo.mandar_ao_grupo(texto):
            log.warning("o aviso não chegou ao grupo")
    except Exception:  # noqa: BLE001
        log.exception("o aviso ao grupo falhou")


def _ha_trabalho(conn, cfg: dict) -> bool:
    silencio = max(0, int(cfg.get("whatsapp_silencio_s") or 20))
    return bool(banco.um(conn, """
        SELECT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE etapa = 'nova' AND assumido_em IS NULL
                        AND humano_em IS NULL AND criado_em > now() - interval '7 days')
            OR EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp l JOIN captacao_mensagens m
                         ON m.direcao = 'recebida' AND m.id > l.ultima_lida
                        AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
                        AND m.criada_em < now() - make_interval(secs => %s)
                        WHERE l.assumido_em IS NOT NULL)""", (silencio,)))


def _para_a_fila(conn, lead: dict, codigo: int | None, pergunta: str) -> bool:
    """391: a pergunta entra na fila do PV do Tel. False = a fila está desligada (ou falhou): vai ao grupo."""
    try:
        if banco.um(conn, "SELECT pergunta_fila_ligada()") is not True:
            return False
        # 392b: a mesma pessoa já tem pergunta aberta na fila: a parecida não entra; a nova vai junto daquela
        abertas = banco.linhas(conn, """SELECT id, pergunta, estado, linha FROM pergunta_fila WHERE estado IN ('fila', 'perguntada')
                                         AND right(chave, 8) = %s ORDER BY id""", (_so8(lead["telefone"]),))
        if any(parecida(pergunta, a["pergunta"], 0.55) or _mesmo_assunto(pergunta, a["pergunta"]) for a in abertas):
            log.info("lead %s: a pergunta já está na fila", lead.get("id"))
            return True
        na_fila = [a for a in abertas if a.get("estado") == "fila" and a.get("linha") == "captacao"]
        if na_fila:
            banco.um(conn, "UPDATE pergunta_fila SET pergunta = pergunta || %s WHERE id = %s",
                     ("\nE também: " + pergunta.strip(), na_fila[-1]["id"]))
            return True
        return bool(banco.um(conn, "SELECT pergunta_fila_entrar('captacao', %s, %s, %s, NULL, %s, 'olx_whatsapp', NULL)",
                             (lead["telefone"], lead.get("nome"), codigo, pergunta)))
    except Exception:  # noqa: BLE001
        log.exception("lead %s: a pergunta não entrou na fila", lead.get("id"))
        return False


PALAVRAS_VAZIAS = set("a o as os e de da do das dos em no na nos nas um uma para por com que se ela ele sobre confirmar "
                      "imovel imoveis apartamento casa equipe pediu quer saber".split())


def _mesmo_assunto(a: str, b: str) -> bool:
    """As palavras que importam são quase as mesmas ("menor valor ... televisão, geladeira" x "Confirmar o menor valor
    do aluguel e se televisão, geladeira ficam")."""
    pa = {p for p in _normal(a).split() if len(p) > 2 and p not in PALAVRAS_VAZIAS and not p.isdigit()}
    pb = {p for p in _normal(b).split() if len(p) > 2 and p not in PALAVRAS_VAZIAS and not p.isdigit()}
    if not pa or not pb:
        return False
    return len(pa & pb) / min(len(pa), len(pb)) >= 0.6


def texto_da_resposta(p: dict) -> str:
    """A resposta do Tel como ela chega ao cliente: "Sobre o #9026 (Turim Residencial): Fica tudo, sim."."""
    r = re.sub(r"\s+", " ", str(p.get("resposta") or "")).strip()
    r = r[:1].upper() + r[1:]
    if p.get("codigo"):
        sobre = f"o #{p['codigo']}" + (f" ({p['imovel']})" if (p.get("imovel") or "").strip() else "")
    else:
        sobre = "a sua pergunta"
    return f"Sobre {sobre}: {r}"


def entregar_respostas(conn) -> int:
    """391: o que o Tel respondeu na fila, para quem está no WhatsApp de captação, sai por aqui (é a Nay falando)."""
    feitas = 0
    for p in banco.linhas(conn, """SELECT id, chave, codigo, imovel, resposta FROM pergunta_fila
                                    WHERE linha = 'captacao' AND estado = 'respondida' AND entregue_em IS NULL
                                      AND entrega_erro IS NULL ORDER BY respondida_em LIMIT 5"""):
        achado = banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8)
                                        ORDER BY criado_em DESC LIMIT 1""", (p["chave"],))
        if not achado:
            banco.um(conn, "UPDATE pergunta_fila SET entrega_erro = 'não é cliente da Nay do WhatsApp' WHERE id = %s",
                     (p["id"],))
            continue
        lead = _lead(conn, achado[0]["id"])
        mandar_texto(conn, lead, texto_da_resposta(p))
        banco.um(conn, "UPDATE pergunta_fila SET entregue_em = now() WHERE id = %s", (p["id"],))
        log.info("lead %s: a resposta do Tel (pergunta %s) entregue", lead["id"], p["id"])
        feitas += 1
    return feitas


def _ha_resposta(conn) -> bool:
    try:
        return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM pergunta_fila WHERE linha = 'captacao'
                                        AND estado = 'respondida' AND entregue_em IS NULL AND entrega_erro IS NULL)"""))
    except Exception:  # noqa: BLE001 -- sem a 391 no banco
        return False


def enviar_pedidos(conn) -> int:
    """396 (Pedro, 16/10: "coloca esse campo [Enviar imóvel] nos cards dos leads também do de captação"): o que a equipe
    escolheu no card do CRM sai por este número (8595-6408), card + fotos, um imóvel por vez. Parceria e fora do ar não
    saem. Com a Nay na conversa, os imóveis entram nos "já enviados" dela (a busca não repete)."""
    feitos = 0
    for p in banco.linhas(conn, """UPDATE privado.captacao_envio_pedido SET estado = 'enviando'
                                    WHERE id = (SELECT id FROM privado.captacao_envio_pedido WHERE estado = 'pendente'
                                                 ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
                                  RETURNING *"""):
        fone = re.sub(r"\D", "", p["telefone"])
        if fone.startswith("55") and len(fone) in (12, 13):
            fone = fone[2:]
        achado = banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8)
                                        ORDER BY criado_em DESC LIMIT 1""", (fone,))
        lead = _lead(conn, achado[0]["id"]) if achado else {"id": 0, "telefone": fone, "enviados": []}
        enviados, fora = [], []
        try:
            for n, codigo in enumerate(p["codigos"]):
                if not _ofertavel(conn, codigo, lead):
                    fora.append(str(codigo))
                    continue
                if enviados:
                    time.sleep(DEPOIS_DAS_FOTOS_S)       # as fotos do anterior carregam antes do próximo card
                mandar_imovel(conn, lead, int(codigo))
                enviados.append(int(codigo))
                banco.um(conn, "UPDATE privado.captacao_envio_pedido SET enviados = %s WHERE id = %s", (enviados, p["id"]))
            if lead.get("id") and enviados:
                _marcar(conn, lead["id"], enviados=list(dict.fromkeys(list(lead.get("enviados") or []) + enviados)))
            resultado = (f"{len(enviados)} imóvel(is) enviado(s)" +
                         (f"; não saíram (parceria ou fora do ar): {', '.join(fora)}" if fora else ""))
            banco.um(conn, """UPDATE privado.captacao_envio_pedido SET estado = %s, resultado = %s, feito_em = now()
                               WHERE id = %s""", ("enviado" if enviados else "falhou", resultado, p["id"]))
            log.info("envio %s pela captação: %s", p["id"], resultado)
            feitos += 1
        except Exception as e:  # noqa: BLE001
            banco.um(conn, """UPDATE privado.captacao_envio_pedido SET estado = 'falhou', resultado = %s, feito_em = now()
                               WHERE id = %s""", (f"parou no meio ({len(enviados)} saíram): {e}"[:500], p["id"]))
            log.warning("envio %s pela captação falhou: %s", p["id"], e)
    return feitos


def _ha_envio(conn) -> bool:
    try:
        return bool(banco.um(conn, "SELECT EXISTS (SELECT 1 FROM privado.captacao_envio_pedido WHERE estado = 'pendente')"))
    except Exception:  # noqa: BLE001 -- sem a 396 no banco
        return False


def texto_do_seguimento(lead: dict) -> str:
    """392 (Pedro, 16/10): ~10 min de silêncio depois da última mensagem dela. Já mandou opções: se alguma agradou; só
    falou de um imóvel: "Sr. Carlos, posso estar enviando outras opções semelhantes para o Sr.?"."""
    trat, pronome = tratamento(lead)
    para = {"a senhora": "a senhora", "o senhor": "o senhor"}.get(pronome, "você")
    if lead.get("enviados"):
        t = "conseguiu ver as opções que eu mandei? Se quiser, separo outras semelhantes ou já agendo uma visita."
    else:
        t = f"posso estar enviando outras opções semelhantes para {para}?"
    return f"{trat}, {t}" if trat else t[:1].upper() + t[1:]


FECHO_DA_BUSCA = ("Essas são as opções", "Essa é a opção", "Essas são mais opções", "Essa é mais uma opção")
# "vou separar/pegar/enviar": promessa de ENTREGA, que vale como cumprida quando card ou foto saiu depois
VOU_ENTREGAR = re.compile(r"\b(vou (separar|pegar|enviar|mandar|buscar|procurar)|lhe enviar|te envio|j[aá] envio)\b", re.I)
OFERTA = "outras opções semelhantes"
# ela prometeu um retorno (a equipe confirma, ela avisa): quem espera é ela, não o cliente
PROMESSA = re.compile(r"\b(retorno|retornar|aviso por aqui|te aviso|assim que|vou (confirmar|verificar|checar|ver com)|"
                      r"estou (verificando|confirmando|separando|aguardando|vendo)|ainda (estou )?aguardando|"
                      r"j[aá] (passei|encaminhei|pedi)|passo para a equipe|reforcei|refor[cç]ar)\b", re.I)


def que_seguimento(lead: dict, conversa: list[dict], entregou_depois: bool = False) -> str | None:
    """392b (Pedro, 16/10: "fez a mesma pergunta duas vezes ... precisa checar para ela nunca fazer isso"). O
    acompanhamento só tem dois casos, e cada um sai UMA vez:
      - depois das opções (a última mensagem dela é o fecho da busca): "conseguiu ver as opções?";
      - ela só falou de um imóvel e nunca ofereceu outras: "posso estar enviando outras opções semelhantes?".
    A última mensagem dela é uma PERGUNTA ou uma PROMESSA de retorno: espera (o cliente responde, ou a equipe)."""
    nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
    if not nossas:
        return None
    ultima = nossas[-1]["texto"].strip()
    if ultima.startswith(FECHO_DA_BUSCA):
        return texto_do_seguimento({**lead, "enviados": lead.get("enviados") or [0]})
    if ultima.endswith("?") or PROMESSA.search(ultima):
        return None
    if VOU_ENTREGAR.search(ultima) and not entregou_depois:
        return None                       # 394: prometeu as opções/fotos e ainda não mandou: quem espera é ela
    if lead.get("enviados") or any(OFERTA in (m.get("texto") or "") for m in nossas):
        return None
    return texto_do_seguimento({**lead, "enviados": []})


_ULTIMO_SEGUIMENTO = [0.0]


def seguir(conn, cfg: dict, a_cada_s: float = 60.0) -> int:
    """392: o acompanhamento (que_seguimento). Os relógios: `seguimento_min` (10) depois da última mensagem DELA e da
    última do CLIENTE ("vamos aguardar, tem 1 minuto só que ele respondeu"); 60 min entre dois acompanhamentos; das 8h às
    20h; só para conversa das últimas 6 h. Visita andando, equipe na conversa e atendimento encerrado ficam de fora."""
    if time.monotonic() - _ULTIMO_SEGUIMENTO[0] < a_cada_s:
        return 0
    _ULTIMO_SEGUIMENTO[0] = time.monotonic()
    if not (8 <= datetime.now(MANAUS).hour < 20):
        return 0
    minutos = max(1, int(cfg.get("seguimento_min") or 10))
    candidatos = banco.linhas(conn, """
        SELECT l.id FROM privado.olx_lead_whatsapp l
         CROSS JOIN LATERAL (
               SELECT max(m.criada_em) FILTER (WHERE m.direcao = 'recebida') AS ela,
                      max(m.criada_em) FILTER (WHERE m.direcao = 'enviada') AS nos
                 FROM captacao_mensagens m
                WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
                  AND m.criada_em > now() - interval '3 days') x
         WHERE l.assumido_em IS NOT NULL AND l.humano_em IS NULL
           AND l.etapa IN ('filtrar', 'feito_busca', 'imoveis_enviados')
           AND x.ela IS NOT NULL AND x.nos > x.ela
           AND x.nos < now() - make_interval(mins => %(m)s) AND x.ela < now() - make_interval(mins => %(m)s)
           AND x.nos > now() - interval '6 hours'
           AND (l.seguimento_em IS NULL OR l.seguimento_em < now() - interval '60 minutes')
           AND NOT EXISTS (SELECT 1 FROM privado.olx_visita v WHERE v.lead = l.id
                              AND v.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario'))
         ORDER BY x.nos""", {"m": minutos})
    if not candidatos or not conectada():
        return 0
    feitos = 0
    for c in candidatos:
        lead = _lead(conn, c["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        if _gente_escreveu(conn, lead, lead.get("humano_em") or lead.get("assumido_em")):
            continue                                  # a equipe está na conversa: a vez é dela
        conversa = _conversa(conn, lead)
        nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
        entregou = bool(nossas) and bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_cliente_enviada
                                  WHERE lead = %s AND tipo IN ('card', 'foto') AND enviado_em > %s)""",
                                  (lead["id"], nossas[-1]["criada_em"])))
        texto = que_seguimento(lead, conversa, entregou)
        if not texto:
            continue
        if mandar_texto(conn, lead, texto):
            _marcar(conn, lead["id"], seguimento_em=banco.um(conn, "SELECT now()"))
            log.info("lead %s: acompanhamento mandado", lead["id"])
            feitos += 1
    return feitos


def atender(conn, cfg: dict) -> int:
    if (cfg.get("whatsapp_responde") or "nao").strip().lower() not in ("teste", "sim"):
        return 0
    # 394: cada parte com o seu tropeço (uma não derruba as outras); o que manda mensagem só com a Z-API conectada
    def parte(nome, f, *a):
        try:
            return f(*a) or 0
        except Exception as e:  # noqa: BLE001
            log.warning("%s não andou: %s", nome, e)
            return 0
    if visita.ha_trabalho(conn) and conectada():
        parte("a visita", visita.atender, conn, cfg)                 # 389/393: consultas, lembrete, o depois
    parte("a descoberta dos orgânicos", descobrir_organicos, conn, cfg)
    if _ha_resposta(conn) and conectada():
        parte("a resposta do Tel", entregar_respostas, conn)
    if _ha_envio(conn) and conectada():
        parte("o envio pedido no CRM", enviar_pedidos, conn)          # 396
    parte("o acompanhamento", seguir, conn, cfg)
    # a Z-API só é consultada quando há o que fazer (a volta é de 5 em 5 s)
    if not _ha_trabalho(conn, cfg) or not conectada():
        return 0
    return parte("a abertura", abrir, conn, cfg) + parte("a resposta", responder, conn, cfg)


def laco(a_cada_s: float = 5.0) -> None:
    """A linha da Nay do WhatsApp: a sua própria conexão, e um erro aqui não para o chat da OLX nem os anúncios."""
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            atender(conn, banco.chaves(conn))
        except Exception:  # noqa: BLE001
            log.exception("a volta da Nay do WhatsApp falhou; reconecto em 30 s")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(30)
        time.sleep(a_cada_s)


def iniciar() -> threading.Thread:
    t = threading.Thread(target=laco, name="nay-whatsapp", daemon=True)
    t.start()
    return t
