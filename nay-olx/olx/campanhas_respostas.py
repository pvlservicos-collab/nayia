"""AS RESPOSTAS DAS CAMPANHAS (595): ler, classificar, responder curto, anotar e avisar a equipe.

Classes: disponivel | alugado | vendido | baixa (topou baixar para X) | outras_opcoes (o corretor tem/mandou outra) |
nao_e_comigo | outra_coisa.
  - disponível nas listas dos donos: a mensagem seguinte da preparação (as métricas e o pedido de ajuste de valor);
  - o resto: o modelo escreve UMA resposta curta e humana; a "outra coisa" fica para a equipe (a Nay não responde);
  - SEMPRE: a classe na tabela, a nota interna na conversa do CRM (nay_aviso_equipe 'nota') e, quando há algo para
    conferir (alugado, vendido, baixa, outras opções, não é comigo, outra coisa), o aviso à equipe (`campanha_aviso_onde`).
  A Nay NUNCA muda situação nem valor de imóvel: anota e a equipe confere. A baixa só vira aviso aos clientes depois que a
  equipe confirma (crm_campanha_baixa_confirmar).

NÃO RESPONDER POR CIMA DE OUTRA NAY. A Nay só responde quando, na hora de responder:
  1. ninguém mais atende esse contato naquela linha (campanha_quem_atende: a Nay da Parceria com corretor, a Nay Leads,
     a Nay Corretores, a Nay de captação, uma visita, a equipe);
  2. ninguém respondeu depois da mensagem dele (nem a Nay da Parceria, nem gente pelo celular ou pelo CRM);
  3. ele ficou `campanha_silencio_s` em silêncio (a outra Nay, se for responder, responde antes e a 2 pega);
  4. ela mandou menos de 3 mensagens a ele nesta campanha (depois disso, é a equipe).
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timezone

from olx import banco, campanhas, grupo, modelo

log = logging.getLogger("olx.campanhas.respostas")
CLASSES = ("disponivel", "alugado", "vendido", "baixa", "outras_opcoes", "nao_e_comigo", "outra_coisa")
AVISAR = {"alugado", "vendido", "baixa", "outras_opcoes", "nao_e_comigo", "outra_coisa"}
MAX_NOSSAS = 3
ROTULO = {"disponivel": "DISPONÍVEL", "alugado": "ALUGADO", "vendido": "VENDIDO", "baixa": "TOPOU BAIXAR",
          "outras_opcoes": "TEM OUTRAS OPÇÕES", "nao_e_comigo": "NÃO É COM ELE", "outra_coisa": "OUTRA COISA"}

PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Você mandou uma mensagem pelo WhatsApp e a pessoa respondeu.
O sistema diz a LISTA, o que você mandou, os imóveis (código, nome, valor) e o que ela respondeu. Devolva SÓ um JSON:
{"classe": "...", "novo_valor": null, "codigos": [], "resposta": "...", "resumo": "..."}

LISTAS
- parceiros_disponivel: ela é CORRETORA PARCEIRA; você perguntou se os imóveis dela em parceria conosco ainda estão
  disponíveis e, se não, se tem outras opções parecidas.
- donos_parados / feedback_disponiveis: ela é a PROPRIETÁRIA; você perguntou se o imóvel continua disponível (depois do
  "disponível" o sistema manda as métricas e pergunta se ela topa ajustar o valor).

CLASSE (a do que ela disse agora; com vários imóveis, a mais importante para a equipe)
- disponivel: continua disponível ("sim", "está", "ainda tem", o botão "Disponível").
- alugado / vendido: já alugou / já vendeu (ou "não está mais disponível" sem dizer como: use "alugado" se o imóvel é de
  aluguel e "vendido" se é de venda).
- baixa: topou baixar o valor ou disse um valor novo menor ("pode anunciar por 2.300", "faço 450 mil"). novo_valor = o
  número em reais (2300, 450000), só se ela disse; "mil" = x1000.
- outras_opcoes: a corretora disse que tem outro imóvel, mandou outro, ou mandou ficha/fotos de outra opção.
- nao_e_comigo: número errado, não é dona, vendeu o número, "não conheço".
- outra_coisa: pergunta, reclamação, pedido para não mandar mais, áudio, "vou ver", qualquer outra coisa.
codigos: os códigos dos imóveis a que a classe se refere (dos que o sistema mostrou; vazio = todos).

RESPOSTA: o que você responde a ela, como gente no WhatsApp: UMA ou DUAS frases curtas, sem frase pronta, sem repetir a
pergunta, no máximo 1 emoji, sem link e sem telefone. Use o nome dela só se o sistema deu.
- NUNCA diga que já mudou, atualizou, tirou do ar ou baixou nada: diga que vai passar para a equipe atualizar.
- disponivel de PROPRIETÁRIA: resposta "" (o sistema manda as métricas).
- disponivel de CORRETORA: agradeça curto e diga que segue divulgando.
- alugado / vendido: agradeça o aviso; se for dona, pergunte se tem outro imóvel para alugar ou vender; se for corretora,
  se tem outra opção parecida.
- baixa: agradeça e diga que vai passar o valor novo para a equipe atualizar o anúncio.
- outras_opcoes: peça para mandar por aqui as informações e as fotos, que você passa para a equipe.
- nao_e_comigo: peça desculpas pelo engano, curto.
- outra_coisa: resposta "" (a equipe responde).
RESUMO: uma linha para a equipe, com os códigos e o valor novo se houver."""


# ── o que chegou ──
def com_resposta_nova(conn) -> list[dict]:
    """Os contatos com mensagem dele depois da última lida (até 7 dias depois do envio), e quando foi a última."""
    return banco.linhas(conn, """
        SELECT * FROM (
          SELECT c.*, greatest(
                   (SELECT max(m.criada_em) FROM mensagens m
                     WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = c.chave
                       AND m.criada_em > coalesce(c.lida_ate, c.enviada_em)),
                   (SELECT max(m.criada_em) FROM captacao_mensagens m
                     WHERE nay_fone_chave(m.telefone) = c.chave AND m.direcao = 'recebida'
                       AND m.criada_em > coalesce(c.lida_ate, c.enviada_em))) AS ultima
            FROM privado.campanha_contato c
           WHERE c.estado IN ('enviada', 'respondida') AND c.enviada_em > now() - interval '7 days') x
         WHERE x.ultima IS NOT NULL ORDER BY x.ultima""")


def novas(conn, c: dict) -> list[dict]:
    return banco.linhas(conn, """
        SELECT criada_em, coalesce(nullif(btrim(texto), ''), '[' || origem || ']') AS texto FROM (
          SELECT m.criada_em, m.texto, m.origem FROM mensagens m
           WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = %(ch)s AND m.criada_em > %(desde)s
          UNION ALL
          SELECT m.criada_em, m.texto, m.origem FROM captacao_mensagens m
           WHERE nay_fone_chave(m.telefone) = %(ch)s AND m.direcao = 'recebida' AND m.criada_em > %(desde)s) x
         ORDER BY criada_em""", {"ch": c["chave"], "desde": c.get("lida_ate") or c["enviada_em"]})


def alguem_respondeu(conn, c: dict, desde) -> str | None:
    """Depois da mensagem dele, saiu alguma coisa para ele que não foi a campanha? (a Nay da Parceria, a Nay Leads, a
    equipe pelo celular ou pelo CRM). Devolve quem, ou None."""
    nossos = {campanhas_normal(t) for t in campanhas.nossos_textos(conn, c["id"])}
    if c["linha"] == "parceria":
        for r in banco.linhas(conn, """SELECT texto FROM mensagens WHERE direcao = 'enviada' AND criada_em > %s
                                         AND right(regexp_replace(telefone, '\\D', '', 'g'), 8) = %s""", (desde, c["tel8"])):
            if campanhas_normal(r["texto"]) not in nossos:
                return "a Parceria (Nay ou equipe)"
        if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM core_saida WHERE chave_destino = %s AND criado_em > %s
                                AND motivo IS DISTINCT FROM 'nay_leads_dono' AND estado IN ('pendente', 'enviado'))""",
                    (c["chave"], desde)):
            return "a Nay da Parceria"
        return None
    for r in banco.linhas(conn, """SELECT texto FROM captacao_mensagens WHERE nay_fone_chave(telefone) = %s
                                     AND direcao = 'enviada' AND criada_em > %s""", (c["chave"], desde)):
        if campanhas_normal(r["texto"]) not in nossos:
            return "outra mensagem pelo número"
    if c["linha"] == "captacao":
        from olx import whatsapp
        if any(e["criada_em"] > desde for e in whatsapp.da_equipe_no_crm(c["tel8"], 5)):
            return "a equipe pelo CRM"
    return None


def campanhas_normal(t: str | None) -> str:
    return re.sub(r"\W+", " ", (t or "").lower()).strip()


# ── o modelo ──
BOTAO = {"disponivel": re.compile(r"^\s*dispon[ií]vel\s*[.!]*\s*$", re.I),
         "alugado": re.compile(r"^\s*alugado\s*[.!]*\s*$", re.I),
         "vendido": re.compile(r"^\s*vendido\s*[.!]*\s*$", re.I)}


def classe_do_botao(texto: str) -> str | None:
    """O botão do modelo oficial chega como o texto dele: sem o modelo, isso já é a classe."""
    return next((k for k, r in BOTAO.items() if r.match(texto or "")), None)


def valor_em_reais(v) -> float | None:
    """2300 | '2.300' | 'R$ 2.300,00' | '450 mil' | '1,2 milhão' -> reais."""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v) if v > 0 else None
    t = str(v).lower().replace("r$", "").strip()
    mult = 1_000_000 if re.search(r"milh", t) else 1000 if re.search(r"\bmil\b|\d\s*k\b", t) else 1
    m = re.search(r"\d[\d.,]*", t)
    if not m:
        return None
    n = m.group(0)
    if re.fullmatch(r"\d{1,3}(\.\d{3})+(,\d+)?", n):
        n = n.replace(".", "").replace(",", ".")
    elif re.fullmatch(r"\d+,\d{1,2}", n):
        n = n.replace(",", ".")
    else:
        n = n.replace(",", "").replace(".", "") if re.fullmatch(r"\d{1,3}([.,]\d{3})+", n) else n.replace(",", ".")
    try:
        x = float(n) * mult
    except ValueError:
        return None
    return x if x > 0 else None


def ler(r: dict, c: dict) -> dict:
    """O JSON do modelo, conferido: classe válida, valor em reais, códigos só os da campanha."""
    classe = str(r.get("classe") or "").strip().lower().replace("í", "i").replace(" ", "_")
    if classe not in CLASSES:
        classe = "outra_coisa"
    validos = set(c.get("codigos") or [])
    cods = [int(x) for x in (r.get("codigos") or []) if str(x).isdigit() and int(x) in validos]
    valor = valor_em_reais(r.get("novo_valor")) if classe == "baixa" else None
    return {"classe": classe, "novo_valor": valor, "codigos": cods, "resposta": str(r.get("resposta") or "").strip(),
            "resumo": str(r.get("resumo") or "").strip()[:300]}


def turno(c: dict, texto: str) -> str:
    ims = "\n".join(f"- {i.get('codigo')}: {i.get('nome')} (venda {i.get('valor_venda') or '-'}, aluguel {i.get('valor_aluguel') or '-'})"
                    for i in (c.get("imoveis") or []))
    return (f"LISTA: {c['lista']}\nNOME: {c.get('vocativo') or '(sem nome: não use nome)'}\n"
            f"O QUE VOCÊ MANDOU: {c['mensagem']}\nIMÓVEIS:\n{ims}\n"
            f"JÁ CLASSIFICADO ANTES: {c.get('classe') or 'nada'}\nO QUE ELA RESPONDEU AGORA:\n{texto}")


def classificar(c: dict, texto: str, chamar=None) -> dict:
    chamar = chamar or modelo.chamar
    try:
        return ler(chamar(PROMPT, turno(c, texto), no="olx.campanha"), c)
    except Exception as e:  # noqa: BLE001 -- sem o modelo: o botão ainda vale, o resto vai à equipe
        log.warning("campanha #%s: o modelo falhou (%s)", c.get("id"), e)
        return {"classe": classe_do_botao(texto) or "outra_coisa", "novo_valor": None, "codigos": [], "resposta": "",
                "resumo": "a Nay não conseguiu ler a resposta (modelo fora do ar)"}


# ── a resposta ──
MUDOU = re.compile(r"\b(j[aá]\s+)?(atualizei|alterei|mudei|baixei|troquei|tirei|removi|retirei|corrigi)\b", re.I)
LINK_FONE = re.compile(r"https?://|www\.|\b\d{4,5}[-\s]?\d{4}\b")
EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")


def resposta_segura(t: str | None) -> str | None:
    """A resposta do modelo só sai se for curta, sem link/telefone, sem dizer que mudou algo e com no máximo 1 emoji."""
    t = re.sub(r"\s+", " ", (t or "")).strip()
    if not t or len(t) > 320 or LINK_FONE.search(t) or MUDOU.search(t) or len(EMOJI.findall(t)) > 1:
        return None
    if len(re.findall(r"[.!?](\s|$)", t)) > 3:
        return None
    return t


def decidir(c: dict, r: dict, outro: str | None, respondeu: str | None, responde: bool) -> tuple[str, str]:
    """('seguinte' | 'resposta' | 'nada', o porquê)."""
    if not responde:
        return "nada", "campanha_responde = nao"
    if outro:
        return "nada", f"quem responde é {outro}"
    if respondeu:
        return "nada", f"já respondeu: {respondeu}"
    if int(c.get("nossas") or 0) >= MAX_NOSSAS:
        return "nada", f"a Nay já mandou {MAX_NOSSAS}; a equipe segue"
    if r["classe"] == "disponivel" and c.get("mensagem_seguinte") and not c.get("seguinte_em"):
        return "seguinte", ""
    if r["classe"] == "outra_coisa":
        return "nada", "outra coisa: a equipe responde"
    if r["classe"] == "disponivel" and c.get("seguinte_em"):
        return "nada", "as métricas já foram"
    if resposta_segura(r.get("resposta")):
        return "resposta", ""
    return "nada", "sem resposta segura"


def texto_do_aviso(c: dict, r: dict, dele: str) -> str:
    """O aviso à equipe para CONFERIR (a Nay não mudou nada)."""
    quem = f"{c.get('nome') or 'sem nome'} (…{c['tel8'][-4:]})"
    cods = ", ".join(str(x) for x in (r.get("codigos") or c.get("codigos") or []))
    t = (f"📋 Campanha ({campanhas.LISTAS.get(c['lista'], c['lista'])}): {quem} respondeu \"{dele[:300]}\". "
         f"A Nay entendeu: {ROTULO[r['classe']]} ({cods})")
    if r["classe"] == "baixa":
        t += (f", valor novo {campanhas_dinheiro(r.get('novo_valor')) or 'não dito'}. Conferir com ele e mudar o valor no "
              f"editar imóvel; depois confirmar a baixa (crm_campanha_baixa_confirmar) para a Nay avisar quem recebeu o imóvel")
    elif r["classe"] in ("alugado", "vendido"):
        t += ". Conferir e mudar a situação no editar imóvel"
    elif r["classe"] == "outras_opcoes":
        t += ". Ver o que ele mandou e cadastrar se servir"
    elif r["classe"] == "nao_e_comigo":
        t += ". Corrigir o telefone do proprietário no cadastro"
    else:
        t += ". Responder a ele"
    return t + ". A Nay não mudou nada no imóvel."


def campanhas_dinheiro(v) -> str | None:
    if not v:
        return None
    return "R$ " + f"{int(round(float(v))):,}".replace(",", ".")


def avisar_equipe(conn, c: dict, r: dict, dele: str, cfg: dict, acao: str, porque: str) -> None:
    nota = (f"Campanha ({campanhas.LISTAS.get(c['lista'], c['lista'])}): respondeu \"{dele[:500]}\". "
            f"Classe: {ROTULO[r['classe']]}"
            + (f", valor novo {campanhas_dinheiro(r['novo_valor'])}" if r.get("novo_valor") else "")
            + (f". {r['resumo']}" if r.get("resumo") else "")
            + (". A Nay respondeu." if acao != "nada" else f". A Nay não respondeu ({porque}).")
            + " Nada foi mudado no imóvel.")
    try:
        banco.um(conn, "SELECT nay_aviso_equipe('nay-olx', 'nota', 'Campanha', %s, %s)", (nota[:1500], c["telefone"]))
        campanhas.evento(conn, c["id"], "nota", nota[:1500])
    except Exception:  # noqa: BLE001
        log.exception("nota da campanha #%s", c["id"])
    onde = (cfg.get("campanha_aviso_onde") or "crm").strip().lower()
    if r["classe"] not in AVISAR or onde == "nenhum":
        return
    aviso = texto_do_aviso(c, r, dele)
    saiu = grupo.mandar_ao_grupo(aviso) if onde == "grupo" else grupo.ao_crm("outro", aviso, "Campanha: conferir", c["telefone"])
    if saiu:
        banco.um(conn, "UPDATE privado.campanha_contato SET equipe_avisada_em = now() WHERE id = %s", (c["id"],))
        campanhas.evento(conn, c["id"], "aviso", aviso, dados={"onde": onde})


def processar(conn, cfg: dict, c: dict, chamar=None) -> str:
    msgs = novas(conn, c)
    if not msgs:
        return "nada novo"
    dele = "\n".join(m["texto"] for m in msgs)
    desde, ate = msgs[0]["criada_em"], msgs[-1]["criada_em"]
    banco.um(conn, """UPDATE privado.campanha_contato SET lida_ate = %s, resposta_em = coalesce(resposta_em, now()),
                             resposta_texto = left(concat_ws(E'\\n', resposta_texto, %s), 4000), estado = 'respondida',
                             atualizado_em = now() WHERE id = %s""", (ate, dele, c["id"]))
    campanhas.evento(conn, c["id"], "recebida", dele[:2000])
    r = classificar(c, dele, chamar)
    banco.um(conn, """UPDATE privado.campanha_contato SET classe = %s, novo_valor = coalesce(%s, novo_valor),
                             classe_codigos = %s, resumo = %s, atualizado_em = now() WHERE id = %s""",
             (r["classe"], r["novo_valor"], r["codigos"] or None, r["resumo"] or None, c["id"]))
    campanhas.evento(conn, c["id"], "classificada", r["classe"], dados=r)
    outro = banco.um(conn, "SELECT campanha_quem_atende(%s)", (c["id"],))
    acao, porque = decidir(c, r, outro, alguem_respondeu(conn, c, desde), campanhas.modo(cfg, "campanha_responde", "sim") == "sim")
    texto = c["mensagem_seguinte"] if acao == "seguinte" else resposta_segura(r["resposta"]) if acao == "resposta" else None
    if texto:
        s = campanhas.mandar(conn, c, texto)
        if s["ok"]:
            banco.um(conn, f"""UPDATE privado.campanha_contato SET nossas = nossas + 1, respondeu_quem = 'nay',
                                      {'seguinte_em = now(),' if acao == 'seguinte' else ''} atualizado_em = now() WHERE id = %s""",
                     (c["id"],))
            campanhas.evento(conn, c["id"], "enviada", texto, s.get("mid"), s.get("saida"))
        else:
            acao, porque = "nada", f"não saiu: {s.get('erro')}"
            campanhas.evento(conn, c["id"], "erro", porque[:300])
    if acao == "nada":
        banco.um(conn, "UPDATE privado.campanha_contato SET respondeu_quem = %s WHERE id = %s", (porque[:200], c["id"]))
    avisar_equipe(conn, c, r, dele, cfg, acao, porque)
    log.info("campanha #%s: %s -> %s (%s)", c["id"], r["classe"], acao, porque or "ok")
    return acao


def atender(conn, cfg: dict, agora: datetime | None = None) -> int:
    if not campanhas.no_horario(cfg.get("campanha_horario_resposta") or "7-21", agora, so_dia_util=False):
        return 0
    silencio = campanhas.numero(cfg, "campanha_silencio_s", 90)
    agora_utc = datetime.now(timezone.utc)
    feitos = 0
    for c in com_resposta_nova(conn):
        if (agora_utc - c["ultima"]).total_seconds() < silencio:
            continue                        # ele ainda pode estar escrevendo
        processar(conn, cfg, c)
        feitos += 1
        if feitos >= 3:
            break                           # o resto na próxima volta
    return feitos
