"""A VISITA DA NAY DO WHATSAPP DOS CLIENTES DA OLX (número de captação, 92 8595-6408; migração 389).

Pedro, 16/10/2026: "primeiro fala com o corretor, e depois que ele confirmar, ou seja se não confirmar que pode no
horário chama outro, e depois só pergunta ao proprietário, e antes de chegar nisso ela deve mandar uma mensagem de
confirmação de visita igual é a mensagem da nay parceria, e só vai atrás dos contatos quando o lead dizer sim".

  1. a pessoa disse imóvel, dia e horário -> a confirmação no modelo da Parceria ("🏠 Só para confirmar a solicitação de
     visita ..."), e a visita fica em `confirmar_cliente`;
  2. ela disse sim -> `buscando_corretor`: um corretor de `visita_corretores` por vez ("Nome:telefone, ..."); "não", ou
     sem resposta em `visita_corretor_espera_min`, chama o próximo; acabou a lista -> `sem_corretor`, a equipe no grupo;
  3. um corretor disse sim -> `pedindo_proprietario`: o dono do imóvel (nai_proprietario_do_imovel), pelo 8595-6408;
  4. o dono disse sim -> `confirmada`: a pessoa e o corretor recebem a visita confirmada; não -> a pessoa escolhe outro
     horário e a equipe fica sabendo.
A resposta de quem está sendo consultado entra como 'Recebido olx' (389) e é lida aqui, pelo telefone. "Sim/não" é lido
por palavra; o que não é nem um nem outro vai para a equipe no grupo, e a consulta continua esperando.
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta

from olx import banco, nay

log = logging.getLogger("olx.visita")

DIAS = ("segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo")
NAO = re.compile(r"\b(n[aã]o|nao|imposs[ií]vel|outro\s+hor[aá]rio|outro\s+dia|infelizmente)\b", re.I)
DUVIDA = re.compile(r"\bn[aã]o\s+sei\b|\?", re.I)
SIM = re.compile(r"\b(sim|s|pode|posso|consigo|confirmo|confirmado|ok|okay|beleza|blz|fechado|combinado|claro|certo|"
                 r"pode\s+ser|t[aá]\s+bom|t[aá]\s+[oó]timo|perfeito|com\s+certeza|bora)\b", re.I)


def _w():
    from olx import whatsapp   # aqui dentro: whatsapp importa este módulo
    return whatsapp


def quando_de(data: str | None, hora: str | None, agora: datetime) -> datetime | None:
    """'17/10' + '11:00' | '11h' | '11h30' -> o momento em Manaus. Ano: o desta data; já passou há mais de um dia, o
    próximo. Hora fora de 6h a 21h não vale (a pessoa não disse um horário de visita)."""
    d = re.search(r"(\d{1,2})\s*/\s*(\d{1,2})(?:\s*/\s*(\d{2,4}))?", data or "")
    h = re.search(r"(\d{1,2})\s*(?:[:h]\s*(\d{2}))?", hora or "")
    if not d or not h:
        return None
    dia, mes = int(d.group(1)), int(d.group(2))
    ano = int(d.group(3)) + (2000 if d.group(3) and len(d.group(3)) == 2 else 0) if d.group(3) else agora.year
    hh, mm = int(h.group(1)), int(h.group(2) or 0)
    if not (6 <= hh <= 21 and 0 <= mm <= 59):
        return None
    try:
        q = datetime(ano, mes, dia, hh, mm, tzinfo=agora.tzinfo)
    except ValueError:
        return None
    if not d.group(3) and q < agora - timedelta(days=1):
        q = q.replace(year=q.year + 1)
    return q


def resposta(texto: str) -> str:
    """'sim' | 'nao' | 'outro' para a resposta de um corretor ou do dono ("não" vence: "não posso" tem "posso")."""
    t = (texto or "").strip()
    if DUVIDA.search(t):              # "não sei", "qual endereço?": a equipe vê
        return "outro"
    if NAO.search(t):
        return "nao"
    if SIM.search(t):
        return "sim"
    return "outro"


def dia(q: datetime) -> str:
    return f"{q:%d/%m} ({DIAS[q.weekday()]})"


def hora(q: datetime) -> str:
    return f"{q:%H}h{q:%M}"


def texto_confirmacao(codigo: int, q: datetime) -> str:
    """O modelo da Nay de Parceria (nai_texto_confirmar_visita), igual."""
    return ("🏠 *Só para confirmar a solicitação de visita*\n\nVisita ao imóvel:\n\n"
            f"🔑 Código do imóvel: #{codigo}\n📅 Data: {dia(q)}\n🕐 Horário: {hora(q)}\n\n"
            "Por favor, confirme se os dados estão corretos para que eu possa entrar em contato com o proprietário.")


def corretores(cfg: dict, chave: str = "visita_corretores") -> list[tuple[str, str]]:
    """`visita_corretores` = "Raquel:92988285562, Neila:92...". Telefone em DDD + número (sem o 55)."""
    saida = []
    for parte in re.split(r"[,;\n]+", cfg.get(chave) or ""):
        if ":" not in parte:
            continue
        nome, fone = parte.split(":", 1)
        d = re.sub(r"\D", "", fone)
        if d.startswith("55") and len(d) in (12, 13):
            d = d[2:]
        if len(d) in (10, 11) and nome.strip():
            saida.append((nome.strip(), d))
    return saida


def quem_chamar(cfg: dict, locacao: bool) -> list[tuple[str, str]]:
    """392 (Pedro, 16/10): "quando for imóvel de locação não vai chamar corretor ... e sim o Diego direto, ela vai chamar
    corretor só para venda ... se for locação pode falar com o Diego ou com o corretor para organizar agenda".
    Locação: os de `visita_locacao` (o Diego) e depois os corretores; venda: só os corretores. Sem repetir telefone."""
    lista = (corretores(cfg, "visita_locacao") if locacao else []) + corretores(cfg)
    vistos, saida = set(), []
    for nome, fone in lista:
        if fone[-8:] not in vistos:
            vistos.add(fone[-8:])
            saida.append((nome, fone))
    return saida


def _e_locacao(conn, v: dict, lead: dict) -> bool:
    """A visita é de locação? O imóvel diz (só aluguel / só venda); se é dos dois, o que a pessoa procura."""
    l = banco.linhas(conn, "SELECT de_locacao, de_venda FROM core_imovel_busca WHERE codigo = %s", (v["codigo"],))
    if l and bool(l[0].get("de_locacao")) != bool(l[0].get("de_venda")):
        return bool(l[0].get("de_locacao"))
    neg = (lead.get("negocio") or (lead.get("filtros") or {}).get("finalidade") or "").lower()
    return neg.startswith("loca")


def _so_ddd(t: str | None) -> str:
    d = re.sub(r"\D", "", t or "")
    return d[2:] if d.startswith("55") and len(d) in (12, 13) else d


# ── o banco ──
def _visita(conn, vid: int) -> dict:
    l = banco.linhas(conn, "SELECT * FROM privado.olx_visita WHERE id = %s", (vid,))
    return l[0] if l else {}


def aberta(conn, lead_id: int) -> dict | None:
    """A visita em andamento desta pessoa (a mais nova que não acabou)."""
    l = banco.linhas(conn, """SELECT * FROM privado.olx_visita WHERE lead = %s
                               AND estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada')
                             ORDER BY id DESC LIMIT 1""", (lead_id,))
    return l[0] if l else None


def _onde(conn, codigo: int) -> str:
    l = banco.linhas(conn, "SELECT condominio_nome, bairro FROM core_imovel_busca WHERE codigo = %s", (codigo,))
    if not l:
        return ""
    c = (l[0].get("condominio_nome") or "").strip()
    if re.match(r"(?i)^(casa|apartamento|sala|loja|terreno|lote|kitnet|flat|cobertura)", c):
        c = ""
    return ", ".join(x for x in (c, (l[0].get("bairro") or "").strip()) if x)


def _endereco(conn, codigo: int) -> str:
    l = banco.linhas(conn, "SELECT condominio_nome, logradouro, numero, complemento, bairro FROM imoveis WHERE codigo = %s", (codigo,))
    if not l:
        return ""
    i = l[0]
    rua = ", ".join(x for x in ((i.get("logradouro") or "").strip(), (i.get("numero") or "").strip()) if x)
    return " · ".join(x for x in ((i.get("condominio_nome") or "").strip(), rua, (i.get("complemento") or "").strip(),
                                   (i.get("bairro") or "").strip()) if x)


def _estado(conn, vid: int, estado: str, **campos) -> None:
    sets, vals = ["estado = %s", "atualizado_em = now()"], [estado]
    for k, v in campos.items():
        if v == "now()":
            sets.append(f"{k} = now()")
        else:
            sets.append(f"{k} = %s")
            vals.append(v)
    banco.um(conn, f"UPDATE privado.olx_visita SET {', '.join(sets)} WHERE id = %s", (*vals, vid))


def _mandar_para(conn, lead_id: int, telefone: str, texto: str) -> None:
    """Uma mensagem pelo 8595-6408 a quem não é a pessoa (corretor, dono): fica na conversa do CRM e o eco não conta."""
    _w()._mandar(conn, {"id": lead_id, "telefone": telefone}, "/send-text", {"message": texto}, "texto", texto_no_crm=texto)


def _lead(conn, lead_id: int) -> dict:
    return _w()._lead(conn, lead_id)


def _quem(lead: dict) -> str:
    return _w().quem(lead)


# ── os passos ──
def pedir_confirmacao(conn, lead: dict, codigo: int | None, data: str | None, hora_dita: str | None) -> bool:
    """O passo 1: a confirmação no modelo da Parceria. Sem imóvel, dia ou hora entendidos, não manda (o modelo pergunta)."""
    w = _w()
    q = quando_de(data, hora_dita, datetime.now(w.MANAUS))
    if not codigo or not q:
        return False
    banco.um(conn, """UPDATE privado.olx_visita SET estado = 'cancelada', atualizado_em = now()
                       WHERE lead = %s AND estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario')""",
             (lead["id"],))
    banco.um(conn, """UPDATE privado.olx_visita_consulta SET estado = 'cancelada'
                       WHERE estado = 'esperando' AND visita IN (SELECT id FROM privado.olx_visita WHERE lead = %s)""",
             (lead["id"],))
    vid = banco.um(conn, "INSERT INTO privado.olx_visita (lead, codigo, quando) VALUES (%s, %s, %s) RETURNING id",
                   (lead["id"], int(codigo), q))
    w.mandar_texto(conn, lead, texto_confirmacao(int(codigo), q))
    w._marcar(conn, lead["id"], etapa="visita", visita={"id": vid, "codigo": int(codigo), "quando": q.isoformat()})
    log.info("lead %s: confirmação da visita %s mandada", lead["id"], vid)
    return True


def cliente_confirmou(conn, lead: dict, cfg: dict) -> None:
    """O passo 2: a pessoa disse sim -> o primeiro corretor."""
    v = aberta(conn, lead["id"])
    if not v or v["estado"] != "confirmar_cliente":
        return
    _estado(conn, v["id"], "buscando_corretor", cliente_confirmou_em="now()")
    _proximo_corretor(conn, _visita(conn, v["id"]), cfg)


def _proximo_corretor(conn, v: dict, cfg: dict) -> None:
    lead = _lead(conn, v["lead"])
    tentados = {r["telefone"][-8:] for r in banco.linhas(
        conn, "SELECT telefone FROM privado.olx_visita_consulta WHERE visita = %s AND papel = 'corretor'", (v["id"],))}
    locacao = _e_locacao(conn, v, lead)
    lista = quem_chamar(cfg, locacao)
    q = v["quando"].astimezone(_w().MANAUS)
    for nome, fone in lista:
        if fone[-8:] in tentados:
            continue
        ate = int(banco.um(conn, """SELECT coalesce(max(id), 0) FROM captacao_mensagens
                                     WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""", (fone[-8:],)) or 0)
        banco.um(conn, """INSERT INTO privado.olx_visita_consulta (visita, papel, nome, telefone, ultima_lida)
                          VALUES (%s, 'corretor', %s, %s, %s)""", (v["id"], nome, fone, ate))
        onde = _onde(conn, v["codigo"])
        _mandar_para(conn, v["lead"], fone,
                     f"Oi, {nome}! Aqui é a Nay, da Imob Easy. Tem uma visita {'de locação ' if locacao else ''}"
                     f"para o imóvel #{v['codigo']}"
                     f"{' (' + onde + ')' if onde else ''} no dia {dia(q)} às {hora(q)}, com um cliente "
                     f"{'que nos chamou no WhatsApp' if lead.get('origem') == 'organico' else 'que veio da OLX'}. "
                     f"Você consegue ir nesse horário? Me responde com SIM ou NÃO, por favor.")
        log.info("visita %s: perguntado ao corretor %s", v["id"], nome)
        return
    _estado(conn, v["id"], "sem_corretor")
    if not lista:
        motivo = "nenhum corretor cadastrado para a Nay chamar"
    elif locacao:
        motivo = "nem o Diego nem os corretores puderam no horário (ou não responderam)"
    else:
        motivo = "nenhum dos corretores pôde no horário"
    _w()._grupo(f"Visita do cliente {_quem(lead)} ao imóvel #{v['codigo']} em {dia(q)} às {hora(q)}: o cliente confirmou e "
                f"{motivo}. Combinem um corretor e o proprietário e confirmem com ele por lá.")


def _pedir_ao_dono(conn, v: dict, cfg: dict) -> None:
    lead = _lead(conn, v["lead"])
    q = v["quando"].astimezone(_w().MANAUS)
    d = banco.linhas(conn, "SELECT * FROM nai_proprietario_do_imovel(%s)", (v["codigo"],))
    nome = (d[0].get("nome") or "").strip() if d else ""
    fone = _so_ddd(d[0].get("telefone") if d else None)
    if len(fone) not in (10, 11):
        _estado(conn, v["id"], "sem_proprietario")
        _w()._grupo(f"Visita do cliente {_quem(lead)} ao imóvel #{v['codigo']} em {dia(q)} às {hora(q)}: o corretor "
                    f"{v.get('corretor_nome') or ''} confirmou, mas o imóvel não tem o telefone do proprietário no cadastro. "
                    f"Confirmem com o dono e avisem o cliente por lá.")
        return
    trat = banco.um(conn, "SELECT nay_tratamento_por_nome(%s)", (nome,))
    primeiro = (nome.split() or [""])[0].capitalize()
    chamado = f"{trat} {primeiro}" if trat and primeiro else (primeiro or "")
    ate = int(banco.um(conn, """SELECT coalesce(max(id), 0) FROM captacao_mensagens
                                 WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""", (fone[-8:],)) or 0)
    banco.um(conn, """INSERT INTO privado.olx_visita_consulta (visita, papel, nome, telefone, ultima_lida)
                      VALUES (%s, 'proprietario', %s, %s, %s)""", (v["id"], nome or None, fone, ate))
    _estado(conn, v["id"], "pedindo_proprietario", proprietario_nome=nome or None, proprietario_telefone=fone)
    _w()._marcar(conn, v["lead"], etapa="proprietarios")
    onde = _onde(conn, v["codigo"])
    _mandar_para(conn, v["lead"], fone,
                 f"Olá{', ' + chamado if chamado else ''}! Aqui é a Nay, da Imob Easy. Temos um cliente interessado no seu "
                 f"imóvel #{v['codigo']}{' (' + onde + ')' if onde else ''} e gostaríamos de agendar uma visita no dia "
                 f"{dia(q)} às {hora(q)}, com o nosso corretor {v.get('corretor_nome') or ''}. Podemos confirmar?")
    log.info("visita %s: perguntado ao proprietário", v["id"])


def _confirmar(conn, v: dict) -> None:
    w = _w()
    lead = _lead(conn, v["lead"])
    q = v["quando"].astimezone(w.MANAUS)
    _estado(conn, v["id"], "confirmada", confirmada_em="now()")
    w._marcar(conn, v["lead"], etapa="visita")
    trat, pronome = w.tratamento(lead)
    onde = _onde(conn, v["codigo"])
    w.mandar_texto(conn, lead, f"Visita confirmada{', ' + trat if trat else ''}! ✅\n\n🔑 Imóvel: #{v['codigo']}"
                               f"{' (' + onde + ')' if onde else ''}\n📅 Data: {dia(q)}\n🕐 Horário: {hora(q)}\n\n"
                               f"O corretor {v.get('corretor_nome') or ''} vai acompanhar {pronome}.")
    if v.get("corretor_telefone"):
        _mandar_para(conn, v["lead"], v["corretor_telefone"],
                     f"Visita confirmada ✅\n\n🔑 Imóvel: #{v['codigo']}\n📍 {_endereco(conn, v['codigo']) or onde}\n"
                     f"📅 {dia(q)} às {hora(q)}\n👤 Cliente: {lead.get('nome') or ''} — {nay.telefone_bonito(lead['telefone'])}\n"
                     f"🏠 Proprietário: {v.get('proprietario_nome') or ''} — "
                     f"{nay.telefone_bonito(v['proprietario_telefone']) if v.get('proprietario_telefone') else ''}")
    w._grupo(f"Visita confirmada: cliente {_quem(lead)}, imóvel #{v['codigo']}, {dia(q)} às {hora(q)}, corretor "
             f"{v.get('corretor_nome') or ''}, proprietário {v.get('proprietario_nome') or ''}.")


def atender(conn, cfg: dict) -> int:
    """As respostas (e o silêncio) de quem está sendo consultado. Devolve quantas consultas andaram."""
    feitas = 0
    espera_c = max(1, int(cfg.get("visita_corretor_espera_min") or 30))
    espera_p = max(1, int(cfg.get("visita_proprietario_espera_min") or 180))
    for c in banco.linhas(conn, """
            SELECT c.*, (SELECT max(m.id) FROM captacao_mensagens m
                          WHERE m.direcao = 'recebida' AND m.id > c.ultima_lida AND m.criada_em > c.perguntado_em
                            AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(c.telefone, 8)) AS ate,
                   (SELECT string_agg(coalesce(m.texto, ''), ' / ' ORDER BY m.id) FROM captacao_mensagens m
                     WHERE m.direcao = 'recebida' AND m.id > c.ultima_lida AND m.criada_em > c.perguntado_em
                       AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(c.telefone, 8)) AS textos,
                   now() - c.perguntado_em > make_interval(mins => CASE WHEN c.papel = 'corretor' THEN %s ELSE %s END) AS venceu
              FROM privado.olx_visita_consulta c WHERE c.estado = 'esperando' ORDER BY c.id""", (espera_c, espera_p)):
        v = _visita(conn, c["visita"])
        if not v or v["estado"] in ("cancelada", "confirmada"):
            banco.um(conn, "UPDATE privado.olx_visita_consulta SET estado = 'cancelada' WHERE id = %s", (c["id"],))
            continue
        lead = _lead(conn, v["lead"])
        q = v["quando"].astimezone(_w().MANAUS)
        if c.get("ate"):
            r = resposta(c.get("textos") or "")
            if r == "outro":
                banco.um(conn, "UPDATE privado.olx_visita_consulta SET ultima_lida = %s WHERE id = %s", (c["ate"], c["id"]))
                _w()._grupo(f"Sobre a visita do cliente {_quem(lead)} ao #{v['codigo']} ({dia(q)} às {hora(q)}), o "
                            f"{'corretor' if c['papel'] == 'corretor' else 'proprietário'} {c.get('nome') or ''} respondeu: "
                            f"\"{(c.get('textos') or '')[:200]}\". A Nay não entendeu se é sim ou não: vejam por lá.")
                feitas += 1
                continue
            banco.um(conn, """UPDATE privado.olx_visita_consulta SET estado = %s, resposta = %s, respondido_em = now(),
                                     ultima_lida = %s WHERE id = %s""", (r, (c.get("textos") or "")[:500], c["ate"], c["id"]))
            if c["papel"] == "corretor":
                if r == "sim":
                    _estado(conn, v["id"], "buscando_corretor", corretor_nome=c.get("nome"), corretor_telefone=c["telefone"])
                    _pedir_ao_dono(conn, _visita(conn, v["id"]), cfg)
                else:
                    _proximo_corretor(conn, v, cfg)
            elif r == "sim":
                _confirmar(conn, _visita(conn, v["id"]))
            else:
                _estado(conn, v["id"], "proprietario_nao")
                trat, pronome = _w().tratamento(lead)
                _w().mandar_texto(conn, lead, f"{trat + ', o' if trat else 'O'} proprietário não consegue em {dia(q)} às "
                                              f"{hora(q)}. Que outro dia e horário ficam bons para {pronome}?")
                _w()._marcar(conn, lead["id"], etapa="visita")
                _w()._grupo(f"Visita do cliente {_quem(lead)} ao #{v['codigo']}: o proprietário não pode em {dia(q)} às "
                            f"{hora(q)} (\"{(c.get('textos') or '')[:120]}\"). A Nay pediu outro horário ao cliente.")
            feitas += 1
        elif c.get("venceu"):
            banco.um(conn, "UPDATE privado.olx_visita_consulta SET estado = 'sem_resposta' WHERE id = %s", (c["id"],))
            if c["papel"] == "corretor":
                _proximo_corretor(conn, v, cfg)
            else:
                _estado(conn, v["id"], "sem_proprietario")
                _w()._grupo(f"Visita do cliente {_quem(lead)} ao #{v['codigo']} em {dia(q)} às {hora(q)}: o proprietário "
                            f"{c.get('nome') or ''} não respondeu. Liguem para ele e confirmem com o cliente por lá.")
            feitas += 1
    return feitas
