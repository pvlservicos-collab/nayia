"""A VISITA DA NAY DO WHATSAPP DOS CLIENTES DA OLX (número de captação, 92 8595-6408; migração 389).

Pedro, 16/10/2026: "primeiro fala com o corretor, e depois que ele confirmar, ou seja se não confirmar que pode no
horário chama outro, e depois só pergunta ao proprietário, e antes de chegar nisso ela deve mandar uma mensagem de
confirmação de visita igual é a mensagem da nay parceria, e só vai atrás dos contatos quando o lead dizer sim".

  1. a pessoa disse imóvel, dia e horário -> a confirmação no modelo da Parceria ("🏠 Só para confirmar a solicitação de
     visita ..."), e a visita fica em `confirmar_cliente`;
  2. ela disse sim -> `buscando_corretor`: um corretor de `visita_corretores` por vez ("Nome:telefone, ..."); "não", ou
     sem resposta em `visita_corretor_espera_min`, chama o próximo; acabou a lista -> `sem_corretor`, a equipe no grupo
     (31/10: na locação é só o Diego, e ele não tem prazo: espera até o horário da visita);
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
NAO = re.compile(r"^\s*(n[aã]o|nao|nops|negativo)\b|\b(n[aã]o\s+(posso|consigo|d[aá]|vai\s+dar|vou\s+poder|tenho\s+como|"
                 r"rola|vai\s+ser\s+poss[ií]vel)|imposs[ií]vel|outro\s+hor[aá]rio|outro\s+dia|infelizmente)\b", re.I)
NAO_SEI = re.compile(r"\bn[aã]o\s+sei\b", re.I)
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
    """'sim' | 'nao' | 'outro' para a resposta de um corretor ou do dono. 394: o "não" é o claro ("não posso", "não
    consigo", começa com "não"), e "Pode sim, não tem problema" é sim; "sim, qual o endereço?" é sim (a pergunta vai à
    equipe); "não sei" e o que não é nem um nem outro, a equipe vê."""
    t = (texto or "").strip()
    if NAO_SEI.search(t):
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


def texto_confirmacao(codigo: int, q: datetime, onde: str = "") -> str:
    """O modelo da Nay de Parceria (nai_texto_confirmar_visita), igual: "🏢 Imóvel: condomínio, bairro" acima do código
    (Pedro, 21/10: "no card de imóvel está faltando dizer qual o condomínio da visita").
    04/11 (Pedro: "ela tá falando muito robótica; melhorar sem deixar formal demais"): o bloco dos dados fica; o fecho
    "Por favor, confirme se os dados estão corretos para que eu possa entrar em contato com o proprietário." virou uma
    pergunta de gente."""
    return ("🏠 *Só para confirmar a solicitação de visita*\n\nVisita ao imóvel:\n\n"
            + (f"🏢 Imóvel: {onde}\n" if onde else "")
            + f"🔑 Código do imóvel: #{codigo}\n📅 Data: {dia(q)}\n🕐 Horário: {hora(q)}\n\n"
            "Tá certinho? Se estiver, já falo com o proprietário.")


ANTECEDENCIA_MIN = 30          # 394: o corretor e o proprietário precisam de tempo para confirmar


def primeiro_horario(agora: datetime) -> datetime:
    """O primeiro horário que dá para pedir: daqui a ANTECEDENCIA_MIN, arredondado para a próxima meia hora."""
    q = agora + timedelta(minutes=ANTECEDENCIA_MIN)
    q = q.replace(second=0, microsecond=0)
    if q.minute not in (0, 30):
        q = q + timedelta(minutes=(30 - q.minute % 30))
    return q


def por_que_nao(codigo: int | None, data: str | None, hora_dita: str | None, agora: datetime) -> str:
    """Por que a confirmação da visita NÃO sai ('' = sai): 'sem_imovel' | 'sem_dia_hora' | 'passou' | 'cedo' (a menos de
    ANTECEDENCIA_MIN). 04/11 (Pedro, o lead 60: "Posso visitar agora?" às 15:19, o modelo marcou a visita para 02/11 15:19,
    pedir_confirmacao recusou calada e ela ficou sem resposta): quem chama diz o motivo a ela."""
    if not codigo:
        return "sem_imovel"
    q = quando_de(data, hora_dita, agora)
    if not q:
        return "sem_dia_hora"
    if q < agora - timedelta(minutes=5):
        return "passou"
    if q < agora + timedelta(minutes=ANTECEDENCIA_MIN):
        return "cedo"
    return ""


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
    corretor só para venda". 31/10 (Pedro: "ele deve sempre enviar ao Diego locação, e venda sim a corretores"): a
    locação é SÓ de `visita_locacao` (o Diego); antes, sem resposta dele em 30 min, ia aos corretores (#16, #13).
    Venda: só os corretores. Sem repetir telefone."""
    lista = corretores(cfg, "visita_locacao") if locacao else corretores(cfg)
    vistos, saida = set(), []
    for nome, fone in lista:
        if fone[-8:] not in vistos:
            vistos.add(fone[-8:])
            saida.append((nome, fone))
    return saida


def _e_locacao(conn, v: dict, lead: dict) -> bool:
    """A visita é de locação? O imóvel diz (só aluguel / só venda); se é dos dois, o que a pessoa procura; e se é dos
    dois e não se sabe o que ela procura, locação (31/10: na dúvida o Diego, não os corretores)."""
    l = banco.linhas(conn, "SELECT de_locacao, de_venda FROM core_imovel_busca WHERE codigo = %s", (v["codigo"],))
    if l and bool(l[0].get("de_locacao")) != bool(l[0].get("de_venda")):
        return bool(l[0].get("de_locacao"))
    neg = (lead.get("negocio") or (lead.get("filtros") or {}).get("finalidade") or "").lower()
    if neg.startswith("vend") or neg.startswith("compr"):
        return False
    return neg.startswith("loca") or bool(l and l[0].get("de_locacao"))


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


def para_o_modelo(conn, lead_id: int) -> dict | None:
    """394: a visita que o modelo precisa ver, também quando ficou com a equipe (sem corretor, sem proprietário)."""
    l = banco.linhas(conn, """SELECT * FROM privado.olx_visita WHERE lead = %s AND estado NOT IN ('cancelada', 'expirada')
                                AND quando > now() - interval '1 day' ORDER BY id DESC LIMIT 1""", (lead_id,))
    return l[0] if l else None


def ativa(conn, lead_id: int) -> bool:
    """394: há visita andando ou marcada (não encerra a conversa; quem volta a escrever cai em Visita)."""
    return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_visita WHERE lead = %s
                   AND (estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'sem_corretor',
                                   'sem_proprietario') OR (estado = 'confirmada' AND quando > now())))""", (lead_id,)))


def no_horario(cfg: dict) -> bool:
    """393: Diego, corretor e proprietário só das 7h às 21h (Manaus); fora disso a visita espera e anda de manhã."""
    h = datetime.now(_w().MANAUS).hour
    return int(cfg.get("visita_hora_ini") or 7) <= h < int(cfg.get("visita_hora_fim") or 21)


def _ocupado(conn, fone: str, vid: int) -> bool:
    """394: o Diego já está respondendo sobre outra visita: um SIM dele não pode valer para duas."""
    return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_visita_consulta WHERE estado = 'esperando'
                                   AND visita <> %s AND right(telefone, 8) = right(%s, 8))""", (vid, fone)))


def ha_trabalho(conn) -> bool:
    return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_visita_consulta WHERE estado = 'esperando')
        OR EXISTS (SELECT 1 FROM privado.olx_visita WHERE estado = 'buscando_corretor')
        OR EXISTS (SELECT 1 FROM privado.olx_visita WHERE estado IN ('confirmar_cliente', 'pedindo_proprietario')
                      AND quando < now())
        OR EXISTS (SELECT 1 FROM privado.olx_visita WHERE estado = 'confirmada'
                      AND ((lembrete_em IS NULL AND quando > now() AND quando < now() + interval '24 hours')
                        OR (depois_em IS NULL AND quando < now() AND quando > now() - interval '2 days')))
        OR EXISTS (SELECT 1 FROM privado.olx_visita WHERE estado = 'realizada' AND depois_em IS NULL)   -- 510
        OR EXISTS (SELECT 1 FROM privado.nay_leads_dono_pergunta WHERE estado = 'pendente')"""))   # 493


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


# 492 (Pedro, 24/10): "antes de contatar o proprietário, checar se ele tem conversa conosco em outro número e usar esse
# (ex.: Parceria); senão criar a conversa pelo número leads ... NUNCA mandar pelo número da API OFICIAL".
def linha_do_dono(conn, fone: str) -> str:
    """'parceria' se o dono já escreveu para a Parceria; senão 'captacao' (8595). O oficial nunca."""
    return "parceria" if banco.um(conn, "SELECT nay_leads_linha_do_dono(%s)", (fone,)) == "parceria" else "captacao"


def ultima_do_telefone(conn, fone: str, linha: str) -> int:
    """O id da última mensagem desse telefone na linha (a resposta é o que vier depois)."""
    if linha == "parceria":
        return int(banco.um(conn, """SELECT coalesce(max(id), 0) FROM mensagens
                                      WHERE direcao = 'recebida' AND nai_chave(telefone) = nai_chave(%s)""", (fone,)) or 0)
    return int(banco.um(conn, """SELECT coalesce(max(id), 0) FROM captacao_mensagens
                                  WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""",
                        (fone[-8:],)) or 0)


def mandar_ao_dono(conn, lead_id: int, fone: str, nome: str | None, texto: str, motivo: str, linha: str | None = None) -> str:
    """Pela Parceria (fila do núcleo, e a conversa fica roxa no CRM) quando ele já conversa lá; senão pelo 8595.
    Devolve por qual linha saiu."""
    if (linha or linha_do_dono(conn, fone)) == "parceria":
        if banco.um(conn, "SELECT nay_leads_mandar_pela_parceria(%s, %s, %s, %s, %s)",
                    (fone, texto, nome or None, motivo[:200], lead_id)):
            return "parceria"
        log.warning("dono %s: a Parceria não aceitou, vai pelo 8595", fone[-4:])
    _mandar_para(conn, lead_id, fone, texto)
    return "captacao"


def perguntas_ao_dono(conn) -> int:
    """493: a dúvida da Nay Leads que o agente não achou vai ao dono (nay_leads_perguntar_ao_dono), pela linha certa.
    O lead da conversa é o cliente da dúvida (pergunta_fila.chave): é a ele que o envio fica ligado."""
    feitas = 0
    for p in banco.linhas(conn, """
            SELECT p.*, (SELECT l.id FROM pergunta_fila f JOIN privado.olx_lead_whatsapp l
                                        ON right(l.telefone, 8) = right(regexp_replace(f.chave, '[^0-9]', '', 'g'), 8)
                          WHERE f.id = p.fila ORDER BY l.criado_em DESC LIMIT 1) AS lead
              FROM privado.nay_leads_dono_pergunta p WHERE p.estado = 'pendente' ORDER BY p.id LIMIT 5"""):
        linha = linha_do_dono(conn, p["telefone"])
        if linha == "captacao" and not (p.get("lead") and _w().conectada()):
            if not p.get("lead"):
                banco.um(conn, """UPDATE privado.nay_leads_dono_pergunta SET estado = 'erro', erro = %s WHERE id = %s""",
                         ("sem conversa na Parceria e sem o cliente da dúvida para ligar o envio pelo 8595", p["id"]))
            continue                        # 8595 desconectado: tenta na próxima volta
        try:
            saiu = mandar_ao_dono(conn, p.get("lead"), p["telefone"], p.get("nome"), p["texto"],
                                  f"dúvida da Nay Leads (fila #{p.get('fila')})", linha)
            banco.um(conn, """UPDATE privado.nay_leads_dono_pergunta SET estado = 'enviada', linha = %s, enviado_em = now()
                               WHERE id = %s""", (saiu, p["id"]))
            if p.get("lead"):
                _w().nota_nay_foi(conn, _lead(conn, p["lead"]),
                                  f"Nay foi falar com o proprietário {p.get('nome') or ''} (…{p['telefone'][-4:]}, pelo número "
                                  f"{'Parceria' if saiu == 'parceria' else 'Leads'}): {p['texto'][:300]}")
            log.info("pergunta %s ao dono ...%s: pela %s", p["id"], p["telefone"][-4:], saiu)
            feitas += 1
        except Exception as e:  # noqa: BLE001
            banco.um(conn, "UPDATE privado.nay_leads_dono_pergunta SET estado = 'erro', erro = %s WHERE id = %s",
                     (str(e)[:300], p["id"]))
    return feitas


def _lead(conn, lead_id: int) -> dict:
    return _w()._lead(conn, lead_id)


def _quem(lead: dict) -> str:
    return _w().quem(lead)


# ── os passos ──
def pedir_confirmacao(conn, lead: dict, codigo: int | None, data: str | None, hora_dita: str | None) -> bool:
    """O passo 1: a confirmação no modelo da Parceria. Sem imóvel, dia ou hora entendidos, não manda (o modelo pergunta)."""
    w = _w()
    agora = datetime.now(w.MANAUS)
    if por_que_nao(codigo, data, hora_dita, agora):
        return False                      # 394: sem dia/hora, ou um horário que já passou: o balão dela pergunta
    q = quando_de(data, hora_dita, agora)  # (04/11: whatsapp.depois_do_modelo já leva o motivo ao modelo antes)
    mesma = aberta(conn, lead["id"])
    if mesma and mesma["estado"] == "confirmar_cliente" and int(mesma["codigo"]) == int(codigo) and mesma["quando"] == q:
        return True                       # 394: a mesma visita de novo: a confirmação já está com ela
    banco.um(conn, """UPDATE privado.olx_visita SET estado = 'cancelada', atualizado_em = now()
                       WHERE lead = %s AND estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario')""",
             (lead["id"],))
    banco.um(conn, """UPDATE privado.olx_visita_consulta SET estado = 'cancelada'
                       WHERE estado = 'esperando' AND visita IN (SELECT id FROM privado.olx_visita WHERE lead = %s)""",
             (lead["id"],))
    vid = banco.um(conn, "INSERT INTO privado.olx_visita (lead, codigo, quando) VALUES (%s, %s, %s) RETURNING id",
                   (lead["id"], int(codigo), q))
    w.mandar_texto(conn, lead, texto_confirmacao(int(codigo), q, _onde(conn, int(codigo))))
    w._marcar(conn, lead["id"], etapa="visita", visita={"id": vid, "codigo": int(codigo), "quando": q.isoformat()})
    log.info("lead %s: confirmação da visita %s mandada", lead["id"], vid)
    return True


def cliente_confirmou(conn, lead: dict, cfg: dict) -> None:
    """O passo 2: a pessoa disse sim -> o primeiro corretor."""
    v = aberta(conn, lead["id"])
    if not v or v["estado"] != "confirmar_cliente":
        return
    # 27/10 (Pedro, o Sr. Eduardo): remarcou o mesmo imóvel para outro dia -> a visita confirmada de antes deixa de valer
    banco.um(conn, """UPDATE privado.olx_visita SET estado = 'cancelada', atualizado_em = now()
                       WHERE lead = %s AND codigo = %s AND id <> %s AND estado = 'confirmada'""",
             (lead["id"], int(v["codigo"]), v["id"]))
    _estado(conn, v["id"], "buscando_corretor", cliente_confirmou_em="now()")
    _proximo_corretor(conn, _visita(conn, v["id"]), cfg)


# 31/10 (Pedro, o Eduardo ...2424 desmarcou a visita do #5699 às 14:01 e ela seguiu "confirmada" para sábado, sem aviso à
# corretora nem à dona): o cliente desmarcar cancela a visita e avisa quem já tinha sido chamado. Remarcar ("amanhã",
# "outro dia", um horário) não é desmarcar: aí o modelo pergunta o dia novo, e a visita nova derruba a antiga.
DESMARCA = re.compile(r"\bdesmarc|\bcancel|imprevisto|n[aã]o (vou|vamos|irei|iremos) (mais|poder|conseguir)|"
                      r"n[aã]o vai (dar|rolar)|n[aã]o (tenho|temos) mais interesse|desisti", re.I)
# um dia ou um horário novo DITO: aí é remarcação, e o modelo pergunta/confirma (a visita nova derruba a antiga)
DIA_NOVO = re.compile(r"\bàs? \d|\d ?h\b|\d{1,2}:\d{2}|\bdia \d|\d{1,2}/\d{1,2}|segunda|ter[cç]a|quarta|quinta|sexta|"
                      r"s[aá]bado|domingo|amanh[aã] (de|à|a) (manh|tard|noit)", re.I)
QUER_REMARCAR = re.compile(r"remarc|\bmarca\w* (pra|para|outro|outra)|outro dia|outra (hora|data|semana)|pr[oó]xima semana|"
                           r"semana que vem", re.I)


def desmarcou(textos: list[str]) -> bool:
    """O Eduardo, 30/10: "tive um imprevisto, amanhã meu sogro vai precisar operar ... podemos marcar pra próxima
    semana?" desmarca (sem dia novo); "pode ser quinta às 18h?" é remarcação com dia, e fica com o modelo."""
    t = " ".join(x for x in textos if x)
    return bool(DESMARCA.search(t)) and not DIA_NOVO.search(t)


def cliente_desmarcou(conn, lead: dict, textos: list[str] | None = None) -> bool:
    """Cancela a visita aberta, avisa o corretor e o proprietário (se já tinham sido chamados), o grupo, e responde ao
    cliente (pedindo o dia novo quando ele quer remarcar). False quando não há visita aberta."""
    v = aberta(conn, lead["id"])
    if not v:
        return False
    w = _w()
    q = v["quando"].astimezone(w.MANAUS)
    quando = f"{dia(q)} às {hora(q)}"
    _estado(conn, v["id"], "cancelada")
    banco.um(conn, "UPDATE privado.olx_visita_consulta SET estado = 'cancelada' WHERE visita = %s AND estado = 'esperando'",
             (v["id"],))
    avisados = []
    if v.get("corretor_telefone") and v["estado"] in ("pedindo_proprietario", "confirmada"):
        nome = (v.get("corretor_nome") or "").split(" ")[0]
        _mandar_para(conn, v["lead"], v["corretor_telefone"],
                     f"Oi{', ' + nome if nome else ''}! O cliente desmarcou a visita do imóvel #{v['codigo']} de {quando}. "
                     f"Obrigada pela disponibilidade; se ele remarcar, te aviso.")
        avisados.append(f"corretor {v.get('corretor_nome') or ''}".strip())
    if v.get("proprietario_telefone") and v["estado"] in ("pedindo_proprietario", "confirmada"):
        nome = (v.get("proprietario_nome") or "").split(" ")[0].capitalize()
        mandar_ao_dono(conn, v["lead"], v["proprietario_telefone"], v.get("proprietario_nome"),
                       f"Olá{', ' + nome if nome else ''}! A visita ao seu imóvel #{v['codigo']} marcada para {quando} foi "
                       f"desmarcada pelo cliente. Obrigada! Se ele remarcar, eu te aviso.", f"visita #{v['codigo']} desmarcada")
        avisados.append("proprietário")
    remarcar = bool(QUER_REMARCAR.search(" ".join(textos or [])))
    w.mandar_texto(conn, lead, f"Tudo bem, desmarquei a visita do imóvel #{v['codigo']} de {quando}. " +
                   ("Me diz o dia e o horário que ficam bons que eu já vejo com o corretor." if remarcar
                    else "Se quiser remarcar ou ver outras opções, é só me dizer."))
    w._grupo(f"Visita DESMARCADA pelo cliente {_quem(lead)}: imóvel #{v['codigo']}, {quando}. "
             + (f"Avisei: {', '.join(avisados)}." if avisados else "Ninguém tinha sido chamado ainda."))
    log.info("visita %s: o cliente desmarcou (avisados: %s)", v["id"], ", ".join(avisados) or "ninguém")
    return True


def _proximo_corretor(conn, v: dict, cfg: dict) -> None:
    if not no_horario(cfg):
        return                            # 393: de noite a visita espera (_retomar chama de manhã)
    lead = _lead(conn, v["lead"])
    tentados = {r["telefone"][-8:] for r in banco.linhas(
        conn, "SELECT telefone FROM privado.olx_visita_consulta WHERE visita = %s AND papel = 'corretor'", (v["id"],))}
    locacao = _e_locacao(conn, v, lead)
    lista = quem_chamar(cfg, locacao)
    q = v["quando"].astimezone(_w().MANAUS)
    ocupados = 0
    for nome, fone in lista:
        if fone[-8:] in tentados:
            continue
        if _ocupado(conn, fone, v["id"]):
            ocupados += 1
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
                     f"{ {'organico': 'que nos chamou no WhatsApp', 'chavesnamao': 'que veio do Chaves na Mão', 'zap': 'que veio do ZAP Imóveis'}.get(lead.get('origem'), 'que veio da OLX')}. "
                     f"Você consegue ir nesse horário? Me responde com SIM ou NÃO, por favor.")
        _w().nota_nay_foi(conn, lead, f"Nay foi falar com o corretor {nome} (…{fone[-4:]}): perguntou se ele vai à visita do "
                                      f"imóvel #{v['codigo']} no dia {dia(q)} às {hora(q)}.")
        log.info("visita %s: perguntado ao corretor %s", v["id"], nome)
        return
    if ocupados:
        return                            # 394: quem falta está respondendo outra visita; _retomar tenta de novo
    _estado(conn, v["id"], "sem_corretor")
    if not lista:
        motivo = "nenhum corretor cadastrado para a Nay chamar"
    elif locacao:
        motivo = "o Diego não pôde no horário (ou não respondeu)"
    else:
        motivo = "nenhum dos corretores pôde no horário"
    _w()._grupo(f"Visita do cliente {_quem(lead)} ao imóvel #{v['codigo']} em {dia(q)} às {hora(q)}: o cliente confirmou e "
                f"{motivo}. Combinem um corretor e o proprietário e confirmem com ele por lá.")


def _pedir_ao_dono(conn, v: dict, cfg: dict) -> None:
    if not no_horario(cfg):
        return                            # 393: de noite o proprietário espera (_retomar chama de manhã)
    lead = _lead(conn, v["lead"])
    q = v["quando"].astimezone(_w().MANAUS)
    # 400: imóvel de PARCEIRO -- o "proprietário" do cadastro é o corretor parceiro, e parceria é com o Tel: a Nay não
    # escreve para ele; a equipe combina com o parceiro e confirma com o cliente
    if banco.um(conn, "SELECT coalesce(e_parceiro, false) FROM imoveis WHERE codigo = %s", (v["codigo"],)):
        _estado(conn, v["id"], "sem_proprietario")
        _w()._grupo(f"Visita do cliente {_quem(lead)} ao imóvel #{v['codigo']} (DE PARCEIRO) em {dia(q)} às {hora(q)}: o "
                    f"corretor {v.get('corretor_nome') or ''} confirmou. Combinem com o parceiro e confirmem com o cliente por lá.")
        return
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
    linha = linha_do_dono(conn, fone)
    cid = banco.um(conn, """INSERT INTO privado.olx_visita_consulta (visita, papel, nome, telefone, ultima_lida, linha)
                            VALUES (%s, 'proprietario', %s, %s, %s, %s) RETURNING id""",
                   (v["id"], nome or None, fone, ultima_do_telefone(conn, fone, linha), linha))
    _estado(conn, v["id"], "pedindo_proprietario", proprietario_nome=nome or None, proprietario_telefone=fone)
    _w()._marcar(conn, v["lead"], etapa="proprietarios")
    onde = _onde(conn, v["codigo"])
    saiu = mandar_ao_dono(conn, v["lead"], fone, nome,
                          f"Olá{', ' + chamado if chamado else ''}! Aqui é a Nay, da Imob Easy. Temos um cliente interessado no "
                          f"seu imóvel #{v['codigo']}{' (' + onde + ')' if onde else ''} e gostaríamos de agendar uma visita no "
                          f"dia {dia(q)} às {hora(q)}, com o nosso corretor {v.get('corretor_nome') or ''}. Podemos confirmar?",
                          f"visita #{v['codigo']}", linha)
    if saiu != linha:                     # a Parceria recusou e saiu pelo 8595: a resposta vem por lá
        banco.um(conn, "UPDATE privado.olx_visita_consulta SET linha = %s, ultima_lida = %s WHERE id = %s",
                 (saiu, ultima_do_telefone(conn, fone, saiu), cid))
    _w().nota_nay_foi(conn, lead, f"Nay foi falar com o proprietário {nome or ''} (…{fone[-4:]}, pelo número "
                                  f"{'Parceria' if saiu == 'parceria' else 'Leads'}): pediu para confirmar a visita do imóvel "
                                  f"#{v['codigo']} no dia {dia(q)} às {hora(q)}.")
    log.info("visita %s: perguntado ao proprietário", v["id"])


def mandar_card_ao_corretor(conn, v: dict) -> bool:
    """27/10 (Pedro, a Neila no #3841: "me envia as informações do apartamento" e não recebeu): junto da "Visita
    confirmada" o corretor recebe o card do imóvel, só o card (sem fotos). Falhou o card, a confirmação já foi."""
    card = banco.um(conn, "SELECT texto_pronto FROM nai_card_do_imovel(%s, true)", (int(v["codigo"]),))
    if not card:
        return False
    try:
        _mandar_para(conn, v["lead"], v["corretor_telefone"], card)
    except Exception as e:  # noqa: BLE001
        log.warning("visita %s: o card não saiu para o corretor: %s", v.get("id"), e)
        return False
    return True


def _confirmar(conn, v: dict) -> None:
    w = _w()
    lead = _lead(conn, v["lead"])
    q = v["quando"].astimezone(w.MANAUS)
    _estado(conn, v["id"], "confirmada", confirmada_em="now()")
    w._marcar(conn, v["lead"], etapa="visita")
    trat, pronome = w.tratamento(lead)
    onde = _onde(conn, v["codigo"])
    if lead.get("humano_em"):
        w._grupo(f"Visita confirmada (o cliente {_quem(lead)} está com a equipe: avisem ele): imóvel #{v['codigo']}, "
                 f"{dia(q)} às {hora(q)}, com {v.get('corretor_nome') or ''}, proprietário {v.get('proprietario_nome') or ''}.")
        return
    w.mandar_texto(conn, lead, f"Visita confirmada{', ' + trat if trat else ''}! ✅\n\n🔑 Imóvel: #{v['codigo']}"
                               f"{' (' + onde + ')' if onde else ''}\n📅 Data: {dia(q)}\n🕐 Horário: {hora(q)}\n\n"
                               f"O corretor {v.get('corretor_nome') or ''} vai acompanhar {pronome}.")
    if v.get("corretor_telefone"):
        _mandar_para(conn, v["lead"], v["corretor_telefone"],
                     f"Visita confirmada ✅\n\n🔑 Imóvel: #{v['codigo']}\n📍 {_endereco(conn, v['codigo']) or onde}\n"
                     f"📅 {dia(q)} às {hora(q)}\n👤 Cliente: {lead.get('nome') or ''} — {nay.telefone_bonito(lead['telefone'])}\n"
                     f"🏠 Proprietário: {v.get('proprietario_nome') or ''} — "
                     f"{nay.telefone_bonito(v['proprietario_telefone']) if v.get('proprietario_telefone') else ''}")
        mandar_card_ao_corretor(conn, v)
    w._grupo(f"Visita confirmada: cliente {_quem(lead)}, imóvel #{v['codigo']}, {dia(q)} às {hora(q)}, corretor "
             f"{v.get('corretor_nome') or ''}, proprietário {v.get('proprietario_nome') or ''}.")


def _retomar(conn, cfg: dict) -> int:
    """393/394: a visita que esperou (a noite, ou o Diego respondendo outra) anda; a que passou do horário sem fechar sai."""
    feitas = 0
    for v in banco.linhas(conn, """SELECT * FROM privado.olx_visita
                                    WHERE estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario')
                                      AND quando < now()"""):
        _estado(conn, v["id"], "expirada")
        banco.um(conn, "UPDATE privado.olx_visita_consulta SET estado = 'cancelada' WHERE visita = %s AND estado = 'esperando'",
                 (v["id"],))
        if v["estado"] != "confirmar_cliente":
            q = v["quando"].astimezone(_w().MANAUS)
            _w()._grupo(f"A visita do cliente {_quem(_lead(conn, v['lead']))} ao #{v['codigo']} ({dia(q)} às {hora(q)}) passou "
                        f"do horário sem fechar com o corretor ou o proprietário.")
        feitas += 1
    if not no_horario(cfg):
        return feitas
    for v in banco.linhas(conn, """SELECT v.* FROM privado.olx_visita v WHERE v.estado = 'buscando_corretor' AND v.quando > now()
                                      AND NOT EXISTS (SELECT 1 FROM privado.olx_visita_consulta c WHERE c.visita = v.id
                                                        AND c.estado IN ('esperando', 'duvida'))"""):
        if v.get("corretor_telefone"):
            _pedir_ao_dono(conn, v, cfg)
        else:
            _proximo_corretor(conn, v, cfg)
        feitas += 1
    return feitas


def ainda_vale(conn, vid: int) -> bool:
    """27/10 (Pedro: "ela nunca deve mandar lembrete ou feedback de visitas que não aconteceram e não constam lá em
    visitas ... deve ter um check novamente"; o Sr. Eduardo remarcou o #5699 de segunda para sábado e recebeu o lembrete
    e o "como foi?" da de segunda). Relido na hora de mandar: a visita continua confirmada e não há outra do mesmo cliente
    para o mesmo imóvel pedida depois dela (remarcada, sendo confirmada ou já confirmada)."""
    return bool(banco.um(conn, """
        SELECT EXISTS (SELECT 1 FROM privado.olx_visita v WHERE v.id = %s AND v.estado = 'confirmada'
                         AND NOT EXISTS (SELECT 1 FROM privado.olx_visita n WHERE n.lead = v.lead AND n.codigo = v.codigo
                                           AND n.id > v.id AND n.estado NOT IN ('cancelada', 'expirada')))""", (vid,)))


def _lembrar(conn, cfg: dict) -> int:
    """393: "pode sim, só me avisar antes" (o Cristian). `visita_lembrete_h` antes: o proprietário, quem acompanha e o
    cliente. Confirmada em cima da hora (menos de 30 min antes do lembrete) não ganha lembrete."""
    if not no_horario(cfg):
        return 0
    w = _w()
    feitas = 0
    for v in banco.linhas(conn, """SELECT * FROM privado.olx_visita WHERE estado = 'confirmada' AND lembrete_em IS NULL
                                     AND quando > now() AND quando - make_interval(hours => %s) <= now()""",
                          (max(1, int(cfg.get("visita_lembrete_h") or 2)),)):
        banco.um(conn, "UPDATE privado.olx_visita SET lembrete_em = now() WHERE id = %s", (v["id"],))
        if v.get("confirmada_em") and v["confirmada_em"] > datetime.now(w.MANAUS) - timedelta(minutes=30):
            continue
        if not ainda_vale(conn, v["id"]):
            log.info("visita %s: não vale mais (cancelada ou remarcada); sem lembrete", v["id"])
            continue
        lead = _lead(conn, v["lead"])
        q = v["quando"].astimezone(w.MANAUS)
        onde = _onde(conn, v["codigo"])
        quando_txt = f"hoje às {hora(q)}" if q.date() == datetime.now(w.MANAUS).date() else f"em {dia(q)} às {hora(q)}"
        if v.get("proprietario_telefone"):
            nome = (v.get("proprietario_nome") or "").strip()
            trat = banco.um(conn, "SELECT nay_tratamento_por_nome(%s)", (nome,)) if nome else None
            primeiro = (nome.split() or [""])[0].capitalize()
            chamado = f"{trat} {primeiro}" if trat and primeiro else primeiro
            mandar_ao_dono(conn, v["lead"], v["proprietario_telefone"], nome,
                           f"Olá{', ' + chamado if chamado else ''}! Passando para lembrar da visita {quando_txt} no seu imóvel "
                           f"#{v['codigo']}{' (' + onde + ')' if onde else ''}, com o nosso corretor {v.get('corretor_nome') or ''}.",
                           f"lembrete da visita #{v['codigo']}")
        if v.get("corretor_telefone"):
            _mandar_para(conn, v["lead"], v["corretor_telefone"],
                         f"Lembrete da visita {quando_txt} 🔑 #{v['codigo']}\n📍 {_endereco(conn, v['codigo']) or onde}\n"
                         f"👤 Cliente: {lead.get('nome') or ''} — {nay.telefone_bonito(lead['telefone'])}\n"
                         f"🏠 Proprietário: {v.get('proprietario_nome') or ''} — "
                         f"{nay.telefone_bonito(v['proprietario_telefone']) if v.get('proprietario_telefone') else ''}")
        if not lead.get("humano_em"):
            trat, pronome = w.tratamento(lead)
            w.mandar_texto(conn, lead, f"{trat + ', p' if trat else 'P'}assando para lembrar da visita {quando_txt}"
                                       f"{' (' + onde + ')' if onde else ''}. O corretor {v.get('corretor_nome') or ''} "
                                       f"vai acompanhar {pronome}.")
        log.info("visita %s: lembrete mandado", v["id"])
        feitas += 1
    return feitas


def _depois(conn, cfg: dict) -> int:
    """393: `visita_depois_h` depois da visita, das 8h às 20h, a Nay pergunta ao cliente como foi."""
    w = _w()
    if not (8 <= datetime.now(w.MANAUS).hour < 20):
        return 0
    feitas = 0
    for v in banco.linhas(conn, """SELECT * FROM privado.olx_visita WHERE estado = 'confirmada' AND depois_em IS NULL
                                     AND quando + make_interval(hours => %s) <= now() AND quando > now() - interval '2 days'""",
                          (max(1, int(cfg.get("visita_depois_h") or 2)),)):
        banco.um(conn, "UPDATE privado.olx_visita SET depois_em = now() WHERE id = %s", (v["id"],))
        if not ainda_vale(conn, v["id"]):
            log.info("visita %s: não vale mais (cancelada ou remarcada); sem o \"como foi?\"", v["id"])
            continue
        lead = _lead(conn, v["lead"])
        if lead.get("humano_em"):
            continue
        trat, pronome = w.tratamento(lead)
        onde = _onde(conn, v["codigo"])
        gostou = {"a senhora": "A senhora gostou?", "o senhor": "O senhor gostou?"}.get(pronome, "Gostou?")
        w.mandar_texto(conn, lead, f"{trat + ', c' if trat else 'C'}omo foi a visita ao imóvel #{v['codigo']}"
                                   f"{' (' + onde + ')' if onde else ''}? {gostou}")
        log.info("visita %s: perguntado como foi", v["id"])
        feitas += 1
    return feitas


_TEM_O_PEDIDO: list[bool] = []


def _feedback_pedido(conn) -> int:
    """510 (Pedro, 28/10): o "como foi?" agora é MANUAL. A Rayssa abre a visita na agenda do CRM, clica em VISITA
    REALIZADA e escolhe a quem perguntar (crm_visita_leads_realizada grava feedback_para); aqui ele sai, uma vez só."""
    if not _TEM_O_PEDIDO:
        _TEM_O_PEDIDO.append(bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM information_schema.columns
                                  WHERE table_schema = 'privado' AND table_name = 'olx_visita' AND column_name = 'feedback_para')""")))
    if not _TEM_O_PEDIDO[0]:
        return 0                                   # antes da 510 no banco: nada a fazer
    feitas = 0
    for v in banco.linhas(conn, """SELECT * FROM privado.olx_visita WHERE estado = 'realizada' AND feedback_para IS NOT NULL
                                     AND depois_em IS NULL ORDER BY id"""):
        banco.um(conn, "UPDATE privado.olx_visita SET depois_em = now() WHERE id = %s", (v["id"],))
        lead = _lead(conn, v["lead"])
        onde = _onde(conn, v["codigo"])
        imovel = f"#{v['codigo']}{' (' + onde + ')' if onde else ''}"
        if v["feedback_para"] == "corretor" and v.get("corretor_telefone"):
            nome = ((v.get("corretor_nome") or "").split() or [""])[0].capitalize()
            cliente = ((lead.get("nome") or "").split() or [""])[0].capitalize()
            _mandar_para(conn, v["lead"], v["corretor_telefone"],
                         f"Oi{', ' + nome if nome else ''}! Como foi a visita ao imóvel {imovel}"
                         f"{' com o cliente ' + cliente if cliente else ''}? Ele gostou?")
        else:
            trat, pronome = _w().tratamento(lead)
            gostou = {"a senhora": "A senhora gostou?", "o senhor": "O senhor gostou?"}.get(pronome, "Gostou?")
            _w().mandar_texto(conn, lead, f"{trat + ', c' if trat else 'C'}omo foi a visita ao imóvel {imovel}? {gostou}")
        log.info("visita %s: \"como foi?\" pedido no CRM, mandado ao %s", v["id"], v["feedback_para"])
        feitas += 1
    return feitas


def atender(conn, cfg: dict) -> int:
    """As respostas (e o silêncio) de quem está sendo consultado, a visita que esperou, o lembrete e o depois.
    28/10 (Pedro: "desativa esses pedidos automáticos ... e desativa o lembrete para todos no automático, agora vai ser
    manual em todos os números"): o lembrete e o "como foi?" automáticos só voltam com olx_config visita_lembrete_auto /
    visita_depois_auto = sim. O "como foi?" sai pelo botão VISITA REALIZADA da agenda (_feedback_pedido)."""
    lembrar = _lembrar(conn, cfg) if str(cfg.get("visita_lembrete_auto") or "nao") == "sim" else 0
    depois = _depois(conn, cfg) if str(cfg.get("visita_depois_auto") or "nao") == "sim" else 0
    feitas = _retomar(conn, cfg) + lembrar + depois + _feedback_pedido(conn) + perguntas_ao_dono(conn)   # 493
    espera_c = max(1, int(cfg.get("visita_corretor_espera_min") or 30))
    espera_p = max(1, int(cfg.get("visita_proprietario_espera_min") or 180))
    # 31/10 (Pedro: "tira isso de 30 min"): o Diego (locação) não tem prazo; espera a resposta dele até o horário da
    # visita (_retomar a dá como expirada). Os 30 min ficam só para a venda, onde passam de uma corretora para outra.
    sem_prazo = {f[-8:] for _, f in corretores(cfg, "visita_locacao")}
    for c in banco.linhas(conn, """
            SELECT c.*, r.ate, r.textos,
                   now() - c.perguntado_em > make_interval(mins => CASE WHEN c.papel = 'corretor' THEN %s ELSE %s END) AS venceu
              FROM privado.olx_visita_consulta c
              CROSS JOIN LATERAL (
                SELECT max(m.id) AS ate, string_agg(coalesce(m.texto, ''), ' / ' ORDER BY m.id) AS textos
                  FROM (SELECT id, texto FROM captacao_mensagens m
                         WHERE c.linha = 'captacao' AND m.direcao = 'recebida' AND m.id > c.ultima_lida
                           AND m.criada_em > c.perguntado_em
                           AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(c.telefone, 8)
                        UNION ALL
                        SELECT id, texto FROM mensagens m      -- 492: o dono que respondeu pela Parceria
                         WHERE c.linha = 'parceria' AND m.direcao = 'recebida' AND m.id > c.ultima_lida
                           AND m.criada_em > c.perguntado_em AND nai_chave(m.telefone) = nai_chave(c.telefone)) m) r
             WHERE c.estado = 'esperando' ORDER BY c.id""", (espera_c, espera_p)):
        v = _visita(conn, c["visita"])
        if not v or v["estado"] in ("cancelada", "confirmada"):
            banco.um(conn, "UPDATE privado.olx_visita_consulta SET estado = 'cancelada' WHERE id = %s", (c["id"],))
            continue
        lead = _lead(conn, v["lead"])
        q = v["quando"].astimezone(_w().MANAUS)
        if c.get("ate"):
            r = resposta(c.get("textos") or "")
            if r == "outro":
                banco.um(conn, """UPDATE privado.olx_visita_consulta SET ultima_lida = %s, estado = 'duvida', resposta = %s,
                                         respondido_em = now() WHERE id = %s""", (c["ate"], (c.get("textos") or "")[:500], c["id"]))
                _w()._grupo(f"Sobre a visita do cliente {_quem(lead)} ao #{v['codigo']} ({dia(q)} às {hora(q)}), o "
                            f"{'corretor' if c['papel'] == 'corretor' else 'proprietário'} {c.get('nome') or ''} respondeu: "
                            f"\"{(c.get('textos') or '')[:200]}\". A Nay não entendeu se é sim ou não: vejam por lá.")
                feitas += 1
                continue
            banco.um(conn, """UPDATE privado.olx_visita_consulta SET estado = %s, resposta = %s, respondido_em = now(),
                                     ultima_lida = %s WHERE id = %s""", (r, (c.get("textos") or "")[:500], c["ate"], c["id"]))
            if c["papel"] == "corretor":
                if r == "sim" and "?" in (c.get("textos") or ""):
                    _w()._grupo(f"Visita do #{v['codigo']} ({dia(q)} às {hora(q)}): {c.get('nome') or 'o corretor'} disse sim e "
                                f"perguntou: \"{(c.get('textos') or '')[:200]}\". Respondam a ele por lá.")
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
                if not lead.get("humano_em"):
                    _w().mandar_texto(conn, lead, f"{trat + ', o' if trat else 'O'} proprietário não consegue em {dia(q)} às "
                                                  f"{hora(q)}. Que outro dia e horário ficam bons para {pronome}?")
                _w()._marcar(conn, lead["id"], etapa="visita")
                _w()._grupo(f"Visita do cliente {_quem(lead)} ao #{v['codigo']}: o proprietário não pode em {dia(q)} às "
                            f"{hora(q)} (\"{(c.get('textos') or '')[:120]}\"). A Nay pediu outro horário ao cliente.")
            feitas += 1
        elif c.get("venceu") and not (c["papel"] == "corretor" and c["telefone"][-8:] in sem_prazo):
            banco.um(conn, "UPDATE privado.olx_visita_consulta SET estado = 'sem_resposta' WHERE id = %s", (c["id"],))
            if c["papel"] == "corretor":
                _proximo_corretor(conn, v, cfg)
            else:
                _estado(conn, v["id"], "sem_proprietario")
                _w()._grupo(f"Visita do cliente {_quem(lead)} ao #{v['codigo']} em {dia(q)} às {hora(q)}: o proprietário "
                            f"{c.get('nome') or ''} não respondeu. Liguem para ele e confirmem com o cliente por lá.")
            feitas += 1
    return feitas
