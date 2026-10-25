"""A NAY DA OLX: atende quem escreveu no nosso anúncio da OLX, por etapas, com o modelo.

Pedro, 13/10/2026: "futuramente vou criar uma nay só para responder na olx então já deixa as funções prontas".
Tel, 14/10/2026: "ela só vai responder as duvidas dos clientes sobre o imovel que ele está perguntando e perguntar se
ele quer agendar uma visita, se sim ela vai pedir o contato dele, quero que ela funcione como funciona de captação".
Pedro, 15/10/2026: "o atendimento da nay olx é por etapas, ela responde as duvidas dos leads que chegam e convida para
uma visita, quando alguém diz que quer visitar ela pede nome e whatsapp e essa pessoa vai para o whatsapp, ela vai
mandar essa mensagem no nosso grupo ... Lead x solicitou visita pela olx, número. só para nosso controle, ela deve ser
flexível e as coisas do atendimento mudam se é venda ou locação ... muito semelhante a nay de captação".

AS ETAPAS (o modelo segue, e pula a que o cliente já adiantou):
  1. responde a dúvida sobre O IMÓVEL DAQUELE ANÚNCIO, pela ficha;
  2. convida para a visita;
  3. quis visitar -> pede nome e WhatsApp;
  4. deu -> agradece, diz que a equipe chama no WhatsApp, e a conversa vai para a equipe com o aviso no grupo:
     "Lead X solicitou visita pela OLX, número ...". Daí em diante ela cala naquela conversa.
  Proposta, desconto, documentação, contrato, outro imóvel, corretor oferecendo parceria: ela não resolve; pede o
  WhatsApp para a equipe falar e entrega do mesmo jeito. No grupo vai SÓ nome e número (15/10); o motivo fica no CRM.

16/10/2026, O OBJETIVO MUDOU (Pedro): "agora o nosso objetivo vai ser chamar a pessoa para o WhatsApp, então ela vai tirar
as dúvidas sobre o imóvel e já sugerir caso a pessoa não tenha mandado: Me manda seu WhatsApp para eu te mandar informações
e organizamos a visita por lá". Agora:
  1. responde a dúvida pela ficha;
  2. sugere o WhatsApp (se a pessoa ainda não mandou), sem repetir o pedido em toda mensagem;
  3. faz a LEITURA DE PERFIL sem interrogatório (o que ela procura, valor, bairros, quartos, financiamento, as dúvidas),
     que vai junto para a Nay do WhatsApp (número de captação) continuar de onde parou;
  4. deu o WhatsApp -> agradece, diz que chama por lá e ENCAMINHA ("whatsapp"); o perfil fica em
     privado.olx_lead_whatsapp (384). No grupo, como antes, só nome e número ("solicitou visita" se ela quis visitar).
  "visita" e "equipe" ainda são aceitos do modelo e viram a mesma entrega.

ATÉ ONDE A ANTIGA IA (14/10) E ESTA SE PARECEM: a fila, a reserva, os 20 s de silêncio e "gente respondeu, a Nay cala"
continuam no banco (364) e no chat.py. Mudou o cérebro: as regras fixas (regex de "sim", a frase exata "Quer agendar uma
visita?") viraram o modelo, como na Nay de captação. O que ficou em código são as PAREDES, que o modelo não atravessa:
sem anúncio ela não fala, sem telefone válido não há entrega, balão sem link/telefone/emoji, e conversa longa demais
vai para gente.

`decidir` continua pura: quem tem a conexão (chat.py) injeta o modelo e o catálogo. Os testes usam um modelo de mentira.
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass, field
from typing import Callable

MANAUS = timezone(timedelta(hours=-4))   # sem horário de verão


@dataclass
class Decisao:
    baloes: list[str] = field(default_factory=list)
    passar_para_gente: str | None = None
    # quando há: o aviso que vai ao grupo da equipe (visita pedida ou "a equipe precisa falar")
    aviso_grupo: str | None = None
    # 16/10: quem deu o WhatsApp, para a Nay do WhatsApp: {nome, telefone, quer_visita, perfil}
    lead: dict | None = None
    # 16/10: o recado que vai ao WhatsApp do Tel (a pessoa não quer o WhatsApp: "tal cliente não quer falar pelo WhatsApp")
    aviso_tel: str | None = None


LIMITE_DE_BALOES = 20    # nossas mensagens na conversa antes de entregar para gente
MAX_BALOES_POR_VEZ = 3
MAX_CARACTERES = 700

# telefone brasileiro: 10 ou 11 dígitos com DDD (com ou sem 55 na frente)
def telefone_valido(t: str | None) -> str | None:
    d = re.sub(r"\D", "", t or "")
    if d.startswith("55") and len(d) in (12, 13):
        d = d[2:]
    return d if len(d) in (10, 11) and d[:2] != "00" else None


def telefone_bonito(d: str) -> str:
    return f"({d[:2]}) {d[2:7]}-{d[7:]}" if len(d) == 11 else f"({d[:2]}) {d[2:6]}-{d[6:]}"


# 24/10 (Pedro): "na OLX não respondemos mais dúvidas pelo agente OLX, nosso objetivo é só trazer para o WhatsApp e lá nós
# vamos passar as informações e trazer o atendimento, tirar as dúvidas, achar mais imóveis". A mensagem é esta, fixa:
MENSAGEM_DO_WHATSAPP = ("Vou te chamar no WhatsApp para confirmar esse detalhe, enviar mais informações e caso lhe "
                        "interesse podemos organizar uma visita.")

PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Você atende, pelo chat da OLX, quem se interessou por um
anúncio NOSSO. A OLX NÃO é o lugar de tirar dúvida nem de dar informação: o SEU ÚNICO OBJETIVO é levar a pessoa para o
WhatsApp. É lá que a gente confirma os detalhes, manda as informações, outras opções parecidas e organiza a visita.

=== O QUE VOCÊ FAZ ===
1. A pessoa pergunta qualquer coisa sobre o imóvel (valor, condomínio, se aceita pet, financiamento, garantia, visita,
   outro imóvel, desconto...): você NÃO responde a dúvida. Nem "sim", nem "não", nem valor, nem detalhe.
2. Se a OLX JÁ MOSTRA um telefone dela (o sistema diz abaixo): ENCAMINHE ("whatsapp") já nesta resposta. A mensagem que
   ela recebe é fixa e o sistema coloca sozinho: você não escreve balão nenhum (baloes: []).
3. Se a OLX NÃO mostra telefone e ela ainda não mandou o WhatsApp: peça o WhatsApp e o nome, com ESTA frase e a saudação
   da hora que o sistema informa abaixo: "Olá, boa tarde, claro! Irei direcionar você para nosso time comercial, só me
   passar seu WhatsApp e nome." Se ela já disse o nome, peça só o WhatsApp. Se ela continuar perguntando sem dar o
   número, INSISTA com gentileza, com outras palavras (ex.: "Para te passar isso certinho eu preciso te chamar no
   WhatsApp. Qual é o seu número?"), sem nunca responder a dúvida. Não repita a mesma frase duas vezes seguidas.
4. Ela mandou o WhatsApp (e o nome, se disse): ENCAMINHE ("whatsapp"), sem balão.

=== A LEITURA DE PERFIL ===
Enquanto conversa, anote o que a pessoa disse do que procura (valor, bairros, quartos, financiamento, as perguntas que
fez). Não faça interrogatório: as perguntas de perfil a Nay do WhatsApp faz. Você só registra o que ela DISSE, no campo
"perfil", para a conversa continuar no WhatsApp de onde parou.

=== QUANDO A PESSOA NÃO QUER O WHATSAPP ===
Se ela diz que não quer ser chamada no WhatsApp, que prefere o chat da OLX, que não gosta de usar o WhatsApp: você NÃO
responde nada (baloes: []) e marca "sem_whatsapp": true. A equipe continua a conversa por aqui.

=== NUNCA ===
- Dar informação sobre o imóvel ou responder dúvida, mesmo que você ache que sabe.
- Dar negativa: "não consigo", "não dá", "não é possível", "só pelo WhatsApp", "por aqui não". Diga que a gente vê pelo
  WhatsApp.
- Dizer endereço, número da casa ou do apartamento, nem o nome do proprietário.
- Mandar link, telefone ou e-mail nosso, nem emoji.
- Falar de grupo, sistema, Nay nova/velha, ficha, catálogo. Para o cliente você é só a Nay, da Imob Easy.
- Prometer horário de visita ou que o Tel vai ligar.

=== COMO VOCÊ FALA ===
Português do Brasil, de gente: uma moça de Manaus respondendo no trabalho. Curto: um balão, no máximo dois. Na primeira
resposta da conversa você se apresenta ("Aqui é a Nay, da Imob Easy"). Nada de "Como posso te ajudar hoje?", "Fico à
disposição", "Estou aqui para ajudar".

=== A SUA RESPOSTA: SÓ ESTE JSON, NADA MAIS ===
{"baloes": ["..."], "encaminhar": null, "nome": "", "whatsapp": "", "quer_visita": false, "sem_whatsapp": false,
 "perfil": {"procura": "", "valor": "", "bairros": "", "quartos": "", "financiamento": "", "duvidas": ""}}
- sem_whatsapp: true quando ela disse que não quer o WhatsApp (e aí baloes vai vazio).
- baloes: o que vai para o cliente agora: o pedido do WhatsApp (passo 3). Vazio ([]) quando você encaminha.
- encaminhar: null | "whatsapp". Só quando JÁ tem o WhatsApp (o que a OLX mostra, ou o que ela disse).
- nome, whatsapp: o que ela informou (whatsapp só com dígitos e DDD).
- quer_visita: true se ela disse que quer visitar.
- perfil: só o que ela DISSE até agora; vazio o que não disse. procura = o que ela quer, em poucas palavras (ex.:
  "apartamento para alugar, 2 quartos, mobiliado"); valor = até quanto pode pagar; bairros; quartos; financiamento =
  vai financiar, à vista, crédito aprovado; duvidas = o que ela perguntou sobre o imóvel (SEM a resposta: você não
  respondeu), para a Nay do WhatsApp responder lá.
"""

CAMPOS_DO_PERFIL = ("procura", "valor", "bairros", "quartos", "financiamento", "duvidas")


def _perfil(p) -> dict:
    """O perfil que o modelo leu, só com os campos conhecidos e em texto curto (o resto é descartado)."""
    p = p if isinstance(p, dict) else {}
    return {k: str(p.get(k) or "").strip()[:300] for k in CAMPOS_DO_PERFIL if str(p.get(k) or "").strip()}


def resumo_do_perfil(perfil: dict) -> str:
    rotulo = {"procura": "procura", "valor": "até", "bairros": "bairros", "quartos": "quartos",
              "financiamento": "pagamento", "duvidas": "perguntou"}
    return "; ".join(f"{rotulo[k]}: {perfil[k]}" for k in CAMPOS_DO_PERFIL if perfil.get(k))[:400]


def _ficha(imovel: dict | None) -> dict:
    """A ficha que o modelo lê: a página pública do imóvel, sem fotos nem a observação interna."""
    i = dict(imovel or {})
    for k in ("fotos", "obs", "geo", "slug", "pode_enviar", "parceiro", "link"):
        i.pop(k, None)
    return i


def _quem(m: dict) -> str:
    if m.get("de") == "comprador":
        return "CLIENTE"
    if m.get("de") == "sistema":
        return "SISTEMA DA OLX"
    por = (m.get("por") or "").strip()
    return "NAY" if por.lower().startswith("nay") else "EQUIPE"


def saudacao_de_manaus(agora: datetime | None = None) -> str:
    """19/10: a saudação da frase de quando não há telefone ("Olá, boa tarde, claro!..."), pela hora de Manaus."""
    h = (agora or datetime.now(MANAUS)).astimezone(MANAUS).hour
    return "bom dia" if 5 <= h < 12 else "boa tarde" if 12 <= h < 18 else "boa noite"


def montar_turno(ctx: dict, sugestao: str | None) -> str:
    anuncio = ctx.get("anuncio") or {}
    cliente = ctx.get("cliente") or {}
    negocio = "LOCAÇÃO" if (anuncio.get("negocio") or "").startswith("loca") else "VENDA"
    fone = telefone_valido(cliente.get("telefone"))
    linhas = [
        f"=== ESTE ANÚNCIO: {negocio} ===",
        f"Título na OLX: {anuncio.get('titulo') or '-'}",
        "",
        f"=== O CLIENTE (cadastro da OLX) ===",
        f"Nome: {cliente.get('nome') or 'não informado'}",
        f"Telefone que a OLX mostra: {telefone_bonito(fone) if fone else 'nenhum'}",
        f"Saudação desta hora (Manaus): {saudacao_de_manaus()}",
        "",
        "=== A CONVERSA ATÉ AGORA (a mais antiga primeiro) ===",
    ]
    for m in ctx.get("mensagens") or []:
        linhas.append(f"{_quem(m)}: {(m.get('texto') or '').strip()}")
    linhas += ["", "Responda agora, só com o JSON."]
    return "\n".join(linhas)


EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿️]")
LINK = re.compile(r"(https?://|www\.|\.com\b|\.online\b|@\w+\.\w+)", re.I)


def limpar_balao(t: str) -> str | None:
    """A parede de saída: sem emoji, sem link nem e-mail, sem telefone, curto. Balão que não passa é cortado."""
    t = EMOJI.sub("", (t or "")).strip()
    if not t or LINK.search(t):
        return None
    if re.search(r"(?<!\d)\d{8,}(?!\d)|\d{4,5}-\d{4}", t):
        return None
    return t[:MAX_CARACTERES]


def numero_dito_pelo_cliente(mensagens: list[dict]) -> str | None:
    """O último telefone válido que o CLIENTE escreveu (com espaço, traço ou parênteses). 24/10: o modelo comeu um dígito de
    "92 98111-2222" e o lead iria para o número errado; o número que vale é o que está nas palavras dele."""
    for m in reversed(mensagens or []):
        if m.get("de") != "comprador":
            continue
        for trecho in reversed(re.findall(r"\+?\d[\d\s().-]{8,18}\d", m.get("texto") or "")):
            fone = telefone_valido(trecho)
            if fone:
                return fone
    return None


def _ultima_do_cliente(mensagens: list[dict]) -> str:
    for m in reversed(mensagens):
        if m.get("de") == "comprador":
            return (m.get("texto") or "").strip()
    return ""


def _aviso(ctx: dict, tipo: str, nome: str, fone: str, motivo: str) -> str:
    """O aviso no grupo: SÓ nome e número (Pedro, 15/10: "não precisa avisar nada no grupo fora nome e número")."""
    quem = nome or ((ctx.get("cliente") or {}).get("nome") or "sem nome")
    if tipo == "visita":
        return f"Lead {quem} solicitou visita pela OLX, número {telefone_bonito(fone)}."
    return f"Lead {quem} pela OLX, número {telefone_bonito(fone)}."


def decidir(contexto: dict, responder_duvida: Callable[[int, str], str | None] | None = None,
            chamar_modelo: Callable[[str, str], dict] | None = None) -> Decisao | None:
    """Lê a conversa e decide o que dizer. `None` = não responde (segue esperando gente)."""
    ctx = contexto or {}
    mensagens = ctx.get("mensagens") or []
    anuncio = ctx.get("anuncio") or {}
    codigo = anuncio.get("codigo")
    pergunta = _ultima_do_cliente(mensagens)

    if not pergunta:
        return None                                   # nada do cliente para responder

    # SEM SABER DE QUAL IMÓVEL É, ELA NÃO FALA: anúncio feito à mão no site da OLX chega sem `anuncio`.
    if not codigo:
        return Decisao(passar_para_gente="anúncio que não subiu por aqui: não sei de qual imóvel é a conversa")

    if sum(1 for m in mensagens if m.get("de") == "nos") >= LIMITE_DE_BALOES:
        return Decisao(passar_para_gente="a conversa já foi longe demais para a Nay")

    if chamar_modelo is None:
        return None

    # 24/10: a OLX não responde mais dúvida: o catálogo (`responder_duvida`) nem é consultado
    r = chamar_modelo(PROMPT, montar_turno(ctx, None))

    # 16/10 (Pedro, o caso da Camila): "nunca deve dar uma negativa; se a pessoa disser que não quer ser chamada pelo
    # WhatsApp a Nay não responde nada e avisa o Tel: tal cliente não quer falar pelo WhatsApp". A conversa fica com a
    # equipe, no chat da OLX, e nenhum balão sai (mesmo que o modelo tenha escrito algum).
    if r.get("sem_whatsapp") is True:
        quem = (ctx.get("cliente") or {}).get("nome") or "sem nome"
        titulo = anuncio.get("titulo") or f"imóvel {codigo}"
        return Decisao(passar_para_gente="não quer falar pelo WhatsApp: responder pelo chat da OLX",
                       aviso_tel=f"Cliente {quem}, da OLX ({titulo}, cód. {codigo}), não quer falar pelo WhatsApp. "
                                 f"A Nay parou; a conversa está no CRM › Chat OLX para responder por lá.")

    baloes = [b for b in (limpar_balao(str(x)) for x in (r.get("baloes") or [])[:MAX_BALOES_POR_VEZ]) if b]

    encaminhar = (r.get("encaminhar") or "").strip().lower() or None
    if encaminhar:
        # 16/10 (Pedro: "pode já chamar quem tem o número lá na OLX"): sem número na resposta, vale o que a OLX mostra
        # o número do modelo só vale se bate com o que o cliente escreveu; senão vale o que está nas palavras dele
        dito = numero_dito_pelo_cliente(mensagens)
        do_modelo = telefone_valido(r.get("whatsapp"))
        fone = (dito if dito and (not do_modelo or do_modelo[-8:] != dito[-8:]) else do_modelo)             or telefone_valido((ctx.get("cliente") or {}).get("telefone"))
        if not fone:
            # disse que encaminha sem ter o número: a parede segura, e ela continua a conversa
            encaminhar = None
        else:
            # 16/10: tudo vai para o WhatsApp; "visita" e "equipe" (o formato de antes) também valem
            nome = (r.get("nome") or "").strip()[:80]
            quer_visita = r.get("quer_visita") is True or encaminhar == "visita"
            perfil = _perfil(r.get("perfil"))
            motivo = (r.get("motivo") or "").strip()[:200]
            resumo = "; ".join(x for x in (resumo_do_perfil(perfil), motivo) if x)
            rotulo = "mandou o WhatsApp e quer visitar" if quer_visita else "mandou o WhatsApp"
            return Decisao(
                baloes=[MENSAGEM_DO_WHATSAPP],       # 24/10: fixa, escrita pelo Pedro; o modelo não escreve esta
                passar_para_gente=f"{rotulo}: {nome or 'sem nome'}, {telefone_bonito(fone)}" + (f" ({resumo})" if resumo else ""),
                aviso_grupo=_aviso(ctx, "visita" if quer_visita else "whatsapp", nome, fone, motivo),
                lead={"nome": nome or ((ctx.get("cliente") or {}).get("nome") or ""), "telefone": fone,
                      "quer_visita": quer_visita, "perfil": perfil})

    return Decisao(baloes=baloes) if baloes else None
