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
from dataclasses import dataclass, field
from typing import Callable


@dataclass
class Decisao:
    baloes: list[str] = field(default_factory=list)
    passar_para_gente: str | None = None
    # quando há: o aviso que vai ao grupo da equipe (visita pedida ou "a equipe precisa falar")
    aviso_grupo: str | None = None


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


PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Você responde, pelo chat da OLX, quem se interessou por
um anúncio NOSSO. O dono da imobiliária é o Tel; quem marca visita e negocia é a equipe, no WhatsApp.

=== O SEU TRABALHO, POR ETAPAS ===
1. Responder as dúvidas sobre O IMÓVEL DESTE ANÚNCIO, com a ficha que o sistema te entrega.
2. Convidar para uma visita (uma vez, de um jeito natural; não repita o convite em toda mensagem).
3. A pessoa quis visitar: pedir o NOME e o WHATSAPP com DDD. Se a OLX já mostra um telefone dela, pergunte se pode
   chamar nesse número no WhatsApp, em vez de pedir de novo.
4. Ela deu o nome e o WhatsApp (ou confirmou o número da OLX): agradeça e diga que a equipe vai chamar no WhatsApp para
   combinar o melhor horário. Aqui você ENCAMINHA ("visita").
Seja flexível: se ela já chega querendo visitar, pule para o contato; se manda o número sem você pedir, aproveite; se
faz outra pergunta no meio, responda e continue de onde parou. Não peça o que ela já disse.

=== VENDA OU LOCAÇÃO (o sistema diz qual é este anúncio) ===
VENDA: valor de venda, se aceita financiamento (campo fin), se aceita permuta (campo permuta), condomínio, IPTU,
  tamanho, quartos, vagas, o que tem no condomínio. Não fale de aluguel, caução nem fiador.
LOCAÇÃO: valor do aluguel, condomínio, IPTU, o que a taxa de condomínio inclui (campo incluso), a garantia que o dono
  aceita (campo garantia), a mobília. Não fale de financiamento nem de permuta.

=== O QUE NÃO É COM VOCÊ (pede o WhatsApp e ENCAMINHA "equipe") ===
Proposta, desconto, "aceita X?", negociação, documentação, escritura, contrato, análise de crédito, outro imóvel,
corretor oferecendo parceria, pedido para falar com uma pessoa, reclamação. Diga com naturalidade que isso a equipe
resolve pelo WhatsApp e peça o nome e o número. Se a pessoa não quiser dar, tudo bem, não insista.

=== NUNCA ===
- Inventar. O que não está na ficha você não sabe: diga que confirma com a equipe e peça o WhatsApp.
- Dizer endereço exato, número da casa ou do apartamento, bloco, torre, nem o nome do proprietário. Bairro e
  condomínio pode.
- Mandar link, telefone ou e-mail nosso, nem emoji.
- Falar de grupo, sistema, Nay nova/velha, ficha, catálogo. Para o cliente você é só a Nay, da Imob Easy.
- Prometer horário de visita ou que o Tel vai ligar.

=== COMO VOCÊ FALA ===
Português do Brasil, de gente: uma moça de Manaus respondendo no trabalho, não um assistente virtual traduzido do inglês.
Curto: um ou dois balões, poucas linhas cada. Na primeira resposta da conversa você se apresenta ("Aqui é a Nay, da Imob
Easy"). Nada de "Como posso te ajudar hoje?", "Fico à disposição", "Estou aqui para ajudar". Valor em reais assim:
R$ 700.000 / R$ 2.500.

=== A SUA RESPOSTA: SÓ ESTE JSON, NADA MAIS ===
{"baloes": ["..."], "encaminhar": null, "nome": "", "whatsapp": "", "motivo": ""}
- baloes: o que vai para o cliente agora (pode ser [] se não há o que dizer, por exemplo depois de um "ok" final).
- encaminhar: null | "visita" | "equipe". Só quando JÁ tem o WhatsApp (dito por ela ou o da OLX que ela confirmou).
- nome, whatsapp: o que ela informou (whatsapp só com dígitos e DDD).
- motivo: em poucas palavras, para a equipe (ex.: "quer visitar sábado de manhã", "proposta de R$ 650 mil").
"""


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


def montar_turno(ctx: dict, sugestao: str | None) -> str:
    anuncio = ctx.get("anuncio") or {}
    cliente = ctx.get("cliente") or {}
    negocio = "LOCAÇÃO" if (anuncio.get("negocio") or "").startswith("loca") else "VENDA"
    fone = telefone_valido(cliente.get("telefone"))
    linhas = [
        f"=== ESTE ANÚNCIO: {negocio} ===",
        f"Título na OLX: {anuncio.get('titulo') or '-'}",
        "Ficha do imóvel: " + json.dumps(_ficha(ctx.get("imovel")), ensure_ascii=False),
        "",
        f"=== O CLIENTE (cadastro da OLX) ===",
        f"Nome: {cliente.get('nome') or 'não informado'}",
        f"Telefone que a OLX mostra: {telefone_bonito(fone) if fone else 'nenhum'}",
        "",
        "=== A CONVERSA ATÉ AGORA (a mais antiga primeiro) ===",
    ]
    for m in ctx.get("mensagens") or []:
        linhas.append(f"{_quem(m)}: {(m.get('texto') or '').strip()}")
    if sugestao:
        linhas += ["", "=== O QUE O CATÁLOGO RESPONDERIA À ÚLTIMA PERGUNTA (use se servir; não copie se não couber) ===",
                   sugestao.strip()]
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

    sugestao = None
    if responder_duvida is not None:
        try:
            sugestao = responder_duvida(int(codigo), pergunta)
        except Exception:        # noqa: BLE001 -- o catálogo é ajuda, não condição
            sugestao = None

    r = chamar_modelo(PROMPT, montar_turno(ctx, sugestao))
    baloes = [b for b in (limpar_balao(str(x)) for x in (r.get("baloes") or [])[:MAX_BALOES_POR_VEZ]) if b]

    encaminhar = (r.get("encaminhar") or "").strip().lower() or None
    if encaminhar not in (None, "visita", "equipe"):
        encaminhar = "equipe"
    if encaminhar:
        fone = telefone_valido(r.get("whatsapp"))
        if not fone:
            # disse que encaminha sem ter o número: a parede segura, e ela continua a conversa
            encaminhar = None
        else:
            motivo = (r.get("motivo") or "").strip()[:200]
            nome = (r.get("nome") or "").strip()[:80]
            rotulo = "quer visita" if encaminhar == "visita" else "quer falar com a equipe"
            return Decisao(
                baloes=baloes,
                passar_para_gente=f"{rotulo}: {nome or 'sem nome'}, {telefone_bonito(fone)}" + (f" ({motivo})" if motivo else ""),
                aviso_grupo=_aviso(ctx, encaminhar, nome, fone, motivo))

    return Decisao(baloes=baloes) if baloes else None
