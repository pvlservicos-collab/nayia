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
from datetime import datetime, timedelta, timezone

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
ela já disse lá.

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
MOBÍLIA (locação): mobiliado = com móveis; semi = modulados e/ou ar-condicionado; "" = tanto faz.

=== VENDA OU LOCAÇÃO ===
O anúncio diz qual é. Na locação o campo "incluso" da ficha é o que está INCLUSO NO ALUGUEL (ex.: água, gás, condomínio).
Na locação não fale de financiamento; na venda não fale de caução nem fiador.

=== QUANDO É COM A EQUIPE (acao "equipe") ===
Proposta, desconto, documentação, contrato, reclamação, pedido para falar com uma pessoa, corretor oferecendo parceria.
Diga com naturalidade que já passa para a equipe e que vão falar com ela por aqui.

=== NUNCA ===
- Dar negativa ("não consigo", "não dá", "não é possível", "não temos"). Se a busca não achar, o sistema avisa a equipe
  e diz a ela que você está separando as opções.
- Inventar. O que não está na ficha você não sabe: diga que confirma e retorna.
- Endereço exato, número da casa ou do apartamento, bloco, torre, nome do proprietário. Bairro e condomínio pode.
- Link, telefone, e-mail, emoji.
- Falar de Nay da OLX, de robô, de ficha, de catálogo. Para ela você é só a Nay, da Imob Easy.

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
  "venda" (sem ela dizer, é a do anúncio). tipo: "apartamento", "casa", "casa_condominio" ou "tanto_faz". teto: só o
  número em reais. quartos: o número que ela quer. financiamento: "aprovado", "simular", "a vista" ou "".
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


def conectada() -> bool:
    """Desconectada, a Z-API aceita e não entrega (02/10): sem conexão, a Nay não fala."""
    try:
        st = grupo._zapi(_instancia(), "GET", "/status")
    except ErroDeEnvio:
        return False
    return isinstance(st, dict) and bool(st.get("connected"))


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
    return _mandar(conn, lead, "/send-text", {"message": texto}, "texto", texto_no_crm=texto)


def mandar_imovel(conn, lead: dict, codigo: int, com_card: bool = True) -> int:
    """O card e as fotos de UM imóvel (sem a colagem, que é só dos grupos). Devolve quantas fotos saíram.
    `com_card=False`: só as fotos ("gostaria de ver mais fotos" do imóvel que ela já conhece)."""
    card = banco.um(conn, "SELECT texto_pronto FROM nai_card_do_imovel(%s)", (codigo,)) if com_card else None
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
        SELECT m.direcao, m.origem, m.texto, m.criada_em,
               EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id) AS nossa
          FROM captacao_mensagens m
         WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = %s
           AND m.criada_em > now() - interval '30 days'
         ORDER BY m.id DESC LIMIT 40""", (_so8(lead["telefone"]),))))


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
        f[k] = v
    return f


def _resumo_dos_filtros(f: dict) -> str:
    partes = [f.get("finalidade") or "", f.get("tipo") or "",
              f"até R$ {int(float(f['teto'])):,}".replace(",", ".") if f.get("teto") else "",
              ", ".join(f.get("bairros") or []) or ("qualquer bairro" if f.get("qualquer_bairro") else ""),
              f"{f['quartos']} quartos" if f.get("quartos") else "", f.get("financiamento") or ""]
    return " · ".join(p for p in partes if p)


# ── as três tarefas ──
def abrir(conn, cfg: dict) -> int:
    feitos = 0
    for l in banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp
                                    WHERE etapa = 'nova' AND assumido_em IS NULL AND humano_em IS NULL
                                      AND criado_em > now() - interval '7 days' ORDER BY criado_em LIMIT 3"""):
        lead = _lead(conn, l["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        # a equipe já chamou por este número (nos últimos 3 dias): a conversa é dela
        gente = _gente_escreveu(conn, lead, banco.um(conn, "SELECT now() - interval '3 days'"))
        if gente:
            _marcar(conn, lead["id"], assumido_em_agora=True, humano_em=gente, etapa="filtrar",
                    parada_motivo="a equipe já tinha chamado por este número")
            log.info("lead %s: a equipe já chamou; a Nay não abre", lead["id"])
            continue
        ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],))
        lead["visita_aberta"] = visita.aberta(conn, lead["id"])
        r = modelo.chamar(PROMPT, montar_turno(lead, ctx_olx, []))
        baloes = [b for b in (nay.limpar_balao(str(x)) for x in (r.get("baloes") or [])[:MAX_BALOES]) if b]
        if not baloes:
            log.warning("lead %s: o modelo não escreveu a abertura", lead["id"])
            continue
        ate = _ultima_recebida(conn, lead)
        for n, b in enumerate(baloes):
            if n:
                time.sleep(ENTRE_ENVIOS_S)
            mandar_texto(conn, lead, b)
        filtros = _filtros(lead.get("filtros"), r.get("filtros"))
        _marcar(conn, lead["id"], assumido_em_agora=True, etapa="filtrar", ultima_lida=ate, filtros=filtros)
        # 16/10: o que ela promete já na abertura (passar o desconto à equipe, confirmar a visita pedida na OLX...) tem de
        # chegar à equipe: as ações da abertura valem como as de qualquer resposta
        for acao in acoes_da(r):
            _fazer(conn, _lead(conn, lead["id"]), r, acao, filtros, cfg)
        log.info("lead %s aberto (%d balão/ões)", lead["id"], len(baloes))
        feitos += 1
    return feitos


def _fila(conn, cfg: dict) -> list[dict]:
    silencio = max(0, int(cfg.get("whatsapp_silencio_s") or 20))
    return banco.linhas(conn, """
        SELECT l.id, max(m.id) AS ate
          FROM privado.olx_lead_whatsapp l
          JOIN captacao_mensagens m ON m.direcao = 'recebida' AND m.id > l.ultima_lida
                                   AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
         WHERE l.assumido_em IS NOT NULL AND l.etapa <> 'finalizado'
         GROUP BY l.id
        HAVING max(m.criada_em) < now() - make_interval(secs => %s)
         ORDER BY max(m.criada_em) LIMIT 3""", (silencio,))


def responder(conn, cfg: dict) -> int:
    feitos = 0
    for item in _fila(conn, cfg):
        lead = _lead(conn, item["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        ate = int(item["ate"])
        # gente da equipe escreveu para ela por este número: a Nay cala (e não relê o que ficou para trás)
        gente = _gente_escreveu(conn, lead, lead.get("humano_em") or lead.get("assumido_em"))
        if gente:
            _marcar(conn, lead["id"], humano_em=gente, ultima_lida=ate, parada_motivo="a equipe respondeu")
            continue
        if lead.get("humano_em"):
            # a equipe assumiu (Pedro, 16/10, na OLX: "a nay não deve mais responder"): ela não volta sozinha
            _marcar(conn, lead["id"], ultima_lida=ate)
            continue
        conversa = _conversa(conn, lead)
        if sum(1 for m in conversa if m.get("nossa")) >= LIMITE_DE_MENSAGENS:
            _marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), ultima_lida=ate,
                    parada_motivo="a conversa foi longe demais para a Nay")
            _grupo(f"Cliente {lead.get('nome') or ''} (OLX, {nay.telefone_bonito(lead['telefone'])}): a conversa no "
                   f"WhatsApp de captação foi longe; precisa de alguém.")
            continue
        ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],))
        lead["visita_aberta"] = visita.aberta(conn, lead["id"])
        r = modelo.chamar(PROMPT, montar_turno(lead, ctx_olx, conversa))
        baloes = [b for b in (nay.limpar_balao(str(x)) for x in (r.get("baloes") or [])[:MAX_BALOES]) if b]
        for n, b in enumerate(baloes):
            if n:
                time.sleep(ENTRE_ENVIOS_S)
            mandar_texto(conn, lead, b)
        filtros = _filtros(lead.get("filtros"), r.get("filtros"))
        _marcar(conn, lead["id"], ultima_lida=ate, filtros=filtros)
        for acao in acoes_da(r):
            _fazer(conn, lead, r, acao, filtros, cfg)
        feitos += 1
    return feitos


def acoes_da(r: dict) -> list[str]:
    """As ações da resposta, na ordem, sem repetir (até duas). Aceita o formato antigo ("acao": "buscar")."""
    brutas = r.get("acoes") if isinstance(r.get("acoes"), list) else [r.get("acao")]
    saida: list[str] = []
    for a in brutas:
        a = str(a or "").strip().lower()
        if a in ("fotos", "buscar", "visita", "confirmou_visita", "perguntar", "equipe", "encerrar") and a not in saida:
            saida.append(a)
    return saida[:2]


def _fazer(conn, lead: dict, r: dict, acao: str, filtros: dict, cfg: dict | None = None) -> None:
    if acao == "fotos":
        f = r.get("fotos") if isinstance(r.get("fotos"), dict) else {}
        codigo = int(f.get("codigo") or lead.get("codigo") or 0) or None
        if codigo:
            # o imóvel do anúncio ou um que ela já recebeu: só as fotos (o card ela já viu)
            ja_viu = codigo == lead.get("codigo") or codigo in (lead.get("enviados") or [])
            mandar_imovel(conn, lead, codigo, com_card=not ja_viu)
            time.sleep(DEPOIS_DAS_FOTOS_S)
        for b in [b for b in (nay.limpar_balao(str(x)) for x in (r.get("depois_das_fotos") or [])[:MAX_BALOES]) if b]:
            mandar_texto(conn, lead, b)
            time.sleep(ENTRE_ENVIOS_S)
    elif acao == "buscar":
        _buscar_e_mandar(conn, lead, filtros)
    elif acao == "visita":
        # 389 (Pedro, 16/10): a confirmação no modelo da Parceria; os contatos só depois do sim dela
        v = r.get("visita") if isinstance(r.get("visita"), dict) else {}
        codigo = int(v.get("codigo") or lead.get("codigo") or 0) or None
        if not visita.pedir_confirmacao(conn, lead, codigo, str(v.get("data") or ""), str(v.get("hora") or "")):
            _marcar(conn, lead["id"], etapa="visita")      # faltou dia ou hora: o balão dela já perguntou
    elif acao == "confirmou_visita":
        visita.cliente_confirmou(conn, lead, cfg or {})
    elif acao == "perguntar":
        # Pedro, 16/10 (a Michelle pediu os quartos com roupeiros): "ela deve nos perguntar porque a Nay não sabe que foto
        # é de qual lugar". A pergunta vai ao grupo e a conversa continua com ela; quem mandar por aqui tira a Nay.
        _grupo(f"Cliente {lead.get('nome') or ''} (OLX, {nay.telefone_bonito(lead['telefone'])}) no WhatsApp de captação "
               f"pediu: {str(r.get('motivo') or 'algo que a Nay não sabe')[:240]}. A Nay disse que já retorna: mandem por lá.")
    elif acao == "equipe":
        _marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), parada_motivo=str(r.get("motivo") or "")[:200])
        _grupo(f"Cliente {lead.get('nome') or ''} (OLX, {nay.telefone_bonito(lead['telefone'])}) no WhatsApp de "
               f"captação: {str(r.get('motivo') or 'precisa da equipe')[:200]}.")
    elif acao == "encerrar":
        _marcar(conn, lead["id"], etapa="finalizado")


def _buscar_e_mandar(conn, lead: dict, filtros: dict) -> None:
    excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else [])
    f = dict(filtros)
    if not f.get("finalidade"):
        f["finalidade"] = "locacao" if (lead.get("negocio") or "").startswith("loca") else "venda"
    achados = banco.linhas(conn, "SELECT * FROM olx_cliente_buscar(%s::jsonb, %s::int[], %s)",
                           (json.dumps(f, ensure_ascii=False), excluir, MAX_IMOVEIS))
    _marcar(conn, lead["id"], etapa="feito_busca")
    if not achados:
        # nunca a negativa: ela diz que está separando e a equipe recebe o perfil
        mandar_texto(conn, lead, "Estou separando as opções com a nossa equipe e já te retorno por aqui.")
        _grupo(f"Cliente {lead.get('nome') or ''} (OLX, {nay.telefone_bonito(lead['telefone'])}) procura "
               f"{_resumo_dos_filtros(f)} e a busca não achou nada: separar opções para ela.")
        return
    enviados = list(lead.get("enviados") or [])
    for n, a in enumerate(achados):
        if n:
            time.sleep(DEPOIS_DAS_FOTOS_S)       # as fotos do anterior carregam antes do próximo card
        mandar_imovel(conn, lead, int(a["codigo"]))
        enviados.append(int(a["codigo"]))
        _marcar(conn, lead["id"], enviados=enviados)
    time.sleep(DEPOIS_DAS_FOTOS_S)
    mandar_texto(conn, lead, fecho(lead, len(achados)))
    _marcar(conn, lead["id"], etapa="imoveis_enviados")
    log.info("lead %s: %d imóvel(is) enviado(s)", lead["id"], len(achados))


def fecho(lead: dict, quantos: int = 2) -> str:
    """A mensagem depois dos imóveis (fixa: o modelo não é chamado no meio do envio)."""
    _, pronome = tratamento(lead)
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
                        WHERE l.assumido_em IS NOT NULL AND l.etapa <> 'finalizado')""", (silencio,)))


def atender(conn, cfg: dict) -> int:
    if (cfg.get("whatsapp_responde") or "nao").strip().lower() not in ("teste", "sim"):
        return 0
    # 389: as respostas (e o silêncio) do corretor e do proprietário consultados sobre uma visita
    try:
        visita.atender(conn, cfg)
    except (ErroDeEnvio, modelo.FalhaDoModelo) as e:
        log.warning("a visita não andou: %s", e)
    # a Z-API só é consultada quando há o que fazer (a volta é de 5 em 5 s)
    if not _ha_trabalho(conn, cfg) or not conectada():
        return 0
    try:
        return abrir(conn, cfg) + responder(conn, cfg)
    except (ErroDeEnvio, modelo.FalhaDoModelo) as e:
        log.warning("a Nay do WhatsApp não conseguiu falar: %s", e)
        return 0


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
