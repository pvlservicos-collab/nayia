"""O FLUXO DE BUSCA DO CLIENTE (475/476, Pedro 22/10/2026). Linha própria dentro do serviço nay-olx.

"Quero que cada lead que chega na aba leads da OLX seja criado para ele um registro de busca, sabemos o que ele está
buscando baseado no anúncio, e vamos mostrar nossas opções, se não tivermos avisamos a ele que vamos continuar
verificando, e aí se ativa automaticamente o fluxo de busca de imóvel, em 2 lugares ... primeiramente nos grupos de
WhatsApp ... e também na OLX ... buscar na nossa base de dados do scrap ... mandamos mensagem para o corretor perguntando se
aceita parceria ... isso tudo pelo WhatsApp de captação (leads) ... e quando o corretor mandar no PV tenhamos uma Nay que
entenda que o cara enviou um imóvel que bate com uma das buscas ativas ... cadastre esse imóvel ... pergunte as informações
que faltar ... e completando tudo oferte ao cliente".

  1. REGISTRO   todo lead da aba Leads (privado.olx_lead_whatsapp) ganha uma busca (privado.busca_cliente): o perfil vem da
                conversa (os filtros da Nay) ou, antes dela, do anúncio que ele viu.
  2. BASE       a Nay do WhatsApp busca no nosso catálogo (whatsapp._buscar_e_mandar) e conta aqui o que achou
                (resultado_da_base). Nada no perfil exato: a busca é ATIVADA e o cliente ouve que vamos continuar verificando.
  3. GRUPOS     a busca ativa é pedida nos grupos do número de captação, pela regra de cada grupo (privado.busca_grupo:
                locação/venda e o valor mínimo do Alto Padrão), no molde do Tel ("✅ PRECISO DE AP P/ VENDA"). Uma busca
                por mensagem, só busca com valor; cada grupo no máximo uma mensagem a cada `busca_grupos_intervalo_min`.
  4. OLX        os anúncios da nossa base de scrap que servem (busca_olx_candidatos: negócio, tipo, valor de -20% a +10%,
                quartos, bairros) e têm telefone: perguntamos ao anunciante se está disponível e se aceita parceria.
  5. CORRETOR   quem responde (anunciante chamado, membro dos grupos) fala com a Nay dos corretores: ela vê se o imóvel
                serve para uma busca ativa, cadastra (pré-cadastro de parceiro), pede o que falta e, completo, oferece ao
                cliente pela Nay do WhatsApp.
Tudo pelo número de captação (8595). Cada passo vai para privado.busca_cliente_passo (a linha da tela Buscar imóvel OLX).
Chaves (privado.olx_config): busca_fluxo | busca_grupos | busca_olx | busca_corretor = nao | teste | sim. Em teste, o que
iria ao grupo, ao anunciante ou ao corretor vai ao primeiro número de `whatsapp_teste`, com "[teste: iria para ...]", e
nada é oferecido ao cliente.
"""
from __future__ import annotations

import json
import logging
import re
import threading
import time
from datetime import datetime, timedelta, timezone

from olx import banco, grupo, modelo, whatsapp

log = logging.getLogger("nay-olx.buscas")
MANAUS = timezone(timedelta(hours=-4))
A_CADA_S = 20
OLX_DE_NOVO_H = 6              # a mesma busca olha a base da OLX de novo depois disto (a base cresce com o scrap)
CONTATO_DE_NOVO_H = 24         # o mesmo anunciante não é chamado de novo antes disto, nem por outra busca
MEMBROS_A_CADA_S = 6 * 3600
BASE_A_CADA_MIN = 30           # a busca aberta olha a nossa base de novo depois disto (imóvel novo no perfil vai à lead)
FOTOS_MINIMAS = 3
ATIVAS = ("buscando",)
_ULTIMO = {"membros": 0.0}


# ── a configuração ──
def _cfg(conn) -> dict:
    c = banco.chaves(conn)

    def modo(k: str) -> str:
        v = (c.get(k) or "nao").strip().lower()
        return v if v in ("nao", "teste", "sim") else "nao"
    try:
        de, ate = [int(x) for x in (c.get("busca_horario") or "8-19").split("-")[:2]]
    except ValueError:
        de, ate = 8, 19
    teste = [re.sub(r"\D", "", x) for x in re.split(r"[,;\s]+", c.get("whatsapp_teste") or "") if len(re.sub(r"\D", "", x)) >= 10]
    return {"fluxo": modo("busca_fluxo"), "grupos": modo("busca_grupos"), "olx": modo("busca_olx"),
            "corretor": modo("busca_corretor"), "intervalo_min": int(c.get("busca_grupos_intervalo_min") or 120),
            "lote_min": int(c.get("busca_lote_min") or 10), "olx_por_busca": int(c.get("busca_olx_por_busca") or 3),
            "de": de, "ate": ate, "teste": teste[0] if teste else None}


def no_horario(c: dict, agora: datetime | None = None) -> bool:
    h = (agora or datetime.now(MANAUS)).astimezone(MANAUS).hour
    return c["de"] <= h < c["ate"]


def passo(conn, bid: int, lugar: str, texto: str, dados: dict | None = None) -> None:
    banco.um(conn, "INSERT INTO privado.busca_cliente_passo (busca, lugar, texto, dados) VALUES (%s, %s, %s, %s::jsonb)",
             (bid, lugar, texto[:900], json.dumps(dados, ensure_ascii=False) if dados else None))
    banco.um(conn, "UPDATE privado.busca_cliente SET atualizado_em = now() WHERE id = %s", (bid,))


# ── o perfil em texto ──
def finalidade(f: dict) -> str:
    v = str((f or {}).get("finalidade") or "").lower()
    return "locacao" if v.startswith(("loc", "alug")) else "venda" if v.startswith(("vend", "compr")) else ""


def tipo_rotulo(t: str | None) -> str:
    t = (t or "").lower()
    if "condom" in t and "lote" in t:
        return "LOTE EM CONDOMÍNIO"
    if "condom" in t:
        return "CASA EM CONDOMÍNIO"
    if "cobertura" in t:
        return "COBERTURA"
    if "apart" in t or t in ("ap", "apto"):
        return "APARTAMENTO"
    if "casa" in t:
        return "CASA"
    if "flat" in t or "kitnet" in t or "studio" in t:
        return t.upper()
    if any(x in t for x in ("sala", "loja", "galp", "terreno", "lote", "pr[eé]dio", "ponto")):
        return t.upper()
    return "IMÓVEL"


def dinheiro(v) -> str:
    try:
        return "R$ " + f"{int(round(float(v))):,}".replace(",", ".")
    except (TypeError, ValueError):
        return ""


_MINUSCULAS = {"de", "da", "do", "das", "dos", "e"}


def _nome_de_lugar(b: str) -> str:
    ps = [p for p in re.split(r"\s+", (b or "").strip()) if p]
    return " ".join(p.lower() if i and p.lower() in _MINUSCULAS else (p[:1].upper() + p[1:]) for i, p in enumerate(ps))


def bairros_texto(f: dict) -> str:
    bs = [_nome_de_lugar(b) for b in (f.get("bairros") or []) if str(b).strip()]
    if not bs or f.get("qualquer_bairro") is True:
        return "qualquer bairro"
    return bs[0] if len(bs) == 1 else ", ".join(bs[:-1]) + " e " + bs[-1]


def quartos_texto(f: dict) -> str:
    try:
        q = int(f.get("quartos") or 0)
    except (TypeError, ValueError):
        q = 0
    if not q:
        return ""
    if f.get("aceita_menos_quartos") is True and q > 1:
        return f"{q - 1} ou {q} quartos"
    return "1 quarto" if q == 1 else f"{q} quartos"


def obs_texto(f: dict) -> str:
    partes = []
    mob = {"mobiliado": "mobiliado", "semi": "com modulados e ar"}.get(str(f.get("mobilia") or ""))
    if mob and finalidade(f) == "locacao":
        partes.append(mob)
    fin = str(f.get("financiamento") or "").lower()
    if "financ" in fin or fin in ("sim", "aprovado"):
        partes.append("aceitar financiamento")
    elif "vista" in fin:
        partes.append("pagamento à vista")
    if f.get("condominio"):
        partes.append(f"de preferência no {f['condominio']}")
    return "; ".join(partes)


TIPO_DO_PEDIDO = (("lote", "LOTE EM CONDOMÍNIO"), ("condom", "CS EM CONDOMÍNIO"), ("cobertura", "COBERTURA"),
                  ("apart", "AP"), ("flat", "FLAT"), ("kitnet", "KITNET"), ("casa", "CASA"), ("sala", "SALA"),
                  ("terreno", "TERRENO"))


def tipo_do_pedido(t: str | None) -> str:
    t = (t or "").lower()
    return next((v for k, v in TIPO_DO_PEDIDO if k in t), "IMÓVEL")


def valor_curto(v) -> str:
    try:
        return f"{int(round(float(v))):,}".replace(",", ".")
    except (TypeError, ValueError):
        return ""


def bloco(f: dict) -> str:
    """Um pedido no molde do Tel (22/10: "use essa headline mesmo, algo assim nessa estrutura"):
    ✅ PRECISO DE AP P/ VENDA / - bairros: parque dez, flores, Aleixo / - 3 quartos / - até 700.000 / - OBS: (se tiver)."""
    fin = finalidade(f)
    bairros = [str(b).strip() for b in (f.get("bairros") or []) if str(b).strip()]
    linhas = [f"✅ PRECISO DE {tipo_do_pedido(f.get('tipo'))} P/ {'LOCAÇÃO' if fin == 'locacao' else 'VENDA'}",
              "- bairros: " + (", ".join(bairros) if bairros and f.get("qualquer_bairro") is not True else "qualquer bairro")]
    if quartos_texto(f):
        linhas.append(f"- {quartos_texto(f)}")
    if f.get("teto"):
        linhas.append(f"- até {valor_curto(f['teto'])}")
    if obs_texto(f):
        linhas.append(f"- OBS: {obs_texto(f)}")
    return "\n".join(linhas)


def mensagem_de_grupo(f: dict) -> str:
    """Uma busca por mensagem (Tel, 22/10: "tem que ser sempre separado as buscas por mensagem individual")."""
    return bloco(f) + "\n\nTem algum? Me chama no privado."


def resumo(f: dict) -> str:
    fin = finalidade(f)
    partes = [tipo_rotulo(f.get("tipo")).lower(), "para locação" if fin == "locacao" else "para venda" if fin else "",
              f"em {bairros_texto(f)}", quartos_texto(f), f"até {dinheiro(f['teto'])}" if f.get("teto") else "", obs_texto(f)]
    return ", ".join(p for p in partes if p)


def pronto(f: dict) -> bool:
    """Dá para pedir: sabemos o negócio e pelo menos o tipo, o valor ou o lugar."""
    f = f or {}
    return bool(finalidade(f) and (f.get("tipo") or f.get("teto") or f.get("bairros")))


def grupo_aceita(g: dict, f: dict) -> bool:
    """A regra do Pedro (22/10): o grupo de Locação nunca recebe venda; o Alto Padrão só locação de R$ 7 mil e venda de
    R$ 800 mil para cima. Sem valor, o grupo com mínimo não recebe (na dúvida, nunca o grupo errado)."""
    fin = finalidade(f)
    try:
        teto = float(f.get("teto") or 0)
    except (TypeError, ValueError):
        teto = 0.0
    if fin == "locacao":
        return bool(g.get("locacao")) and (g.get("locacao_min") is None or teto >= float(g["locacao_min"]))
    if fin == "venda":
        return bool(g.get("venda")) and (g.get("venda_min") is None or teto >= float(g["venda_min"]))
    return False


# ── 1. o registro ──
CHAVES_DO_PERFIL = ("finalidade", "tipo", "teto", "bairros", "qualquer_bairro", "quartos", "aceita_menos_quartos",
                    "mobilia", "financiamento", "condominio")


def limpo(f: dict) -> dict:
    return {k: v for k, v in (f or {}).items() if k in CHAVES_DO_PERFIL and v not in (None, "", [])}


def do_anuncio(conn, lead: dict) -> dict:
    """Antes de a Nay conversar: o que ele viu no anúncio (o nosso imóvel do anúncio da OLX)."""
    if not lead.get("codigo"):
        return {}
    i = banco.linhas(conn, "SELECT tipo, bairro, quartos, valor_aluguel, valor_venda, condominio_nome FROM imoveis WHERE codigo = %s",
                     (lead["codigo"],))
    if not i:
        return {}
    i = i[0]
    neg = str(lead.get("negocio") or "").lower()
    fin = "locacao" if neg.startswith("loc") or (not neg and i["valor_aluguel"]) else "venda"
    teto = i["valor_aluguel"] if fin == "locacao" else i["valor_venda"]
    return limpo({"finalidade": fin, "tipo": (i["tipo"] or "").lower(), "bairros": [i["bairro"]] if i["bairro"] else [],
                  "quartos": i["quartos"], "teto": int(teto) if teto else None})


def garantir(conn, lead: dict, filtros: dict | None = None, c: dict | None = None) -> dict:
    """A busca do lead (cria ou atualiza o perfil). Devolve a linha."""
    c = c or _cfg(conn)
    f = limpo(filtros if filtros is not None else lead.get("filtros"))
    origem = "da conversa"
    if not pronto(f):
        f2 = do_anuncio(conn, lead)
        if pronto(f2):
            f, origem = {**f2, **f}, "do anúncio"
    b = banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE lead = %s", (lead["id"],))
    if not b:
        bid = banco.um(conn, """INSERT INTO privado.busca_cliente (lead, filtros, teste) VALUES (%s, %s::jsonb, %s)
                                ON CONFLICT (lead) DO NOTHING RETURNING id""",
                       (lead["id"], json.dumps(f, ensure_ascii=False), c["fluxo"] == "teste"))
        if bid:
            passo(conn, bid, "perfil", f"Busca criada ({origem}): {resumo(f) or 'perfil ainda sem dados'}", f)
        conn.commit()
        return banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE lead = %s", (lead["id"],))[0]
    b = b[0]
    if pronto(f) and f != (b["filtros"] or {}):
        banco.um(conn, "UPDATE privado.busca_cliente SET filtros = %s::jsonb, atualizado_em = now() WHERE id = %s",
                 (json.dumps(f, ensure_ascii=False), b["id"]))
        passo(conn, b["id"], "perfil", f"Perfil atualizado ({origem}): {resumo(f)}", f)
        conn.commit()
        b = {**b, "filtros": f}
    return b


def sincronizar(conn, c: dict) -> int:
    """Todo lead dos últimos 7 dias tem a sua busca, com o perfil em dia."""
    n = 0
    for l in banco.linhas(conn, """
            SELECT l.* FROM privado.olx_lead_whatsapp l
              LEFT JOIN privado.busca_cliente b ON b.lead = l.id
             WHERE l.criado_em > now() - interval '7 days'
               AND (b.id IS NULL OR (l.filtros - 'olx' - 'aceita_parceiro') IS DISTINCT FROM b.filtros)
             ORDER BY l.id LIMIT 20"""):
        antes = banco.um(conn, "SELECT filtros FROM privado.busca_cliente WHERE lead = %s", (l["id"],))
        b = garantir(conn, l, None, c)
        n += int(antes is None or antes != b["filtros"])
    return n


# ── 2. a nossa base (chamada pela Nay do WhatsApp) ──
def resultado_da_base(conn, lead: dict, filtros: dict, quantos: int, exato: bool) -> bool:
    """A Nay buscou no catálogo. Devolve True quando a busca externa foi ATIVADA agora (ela avisa o cliente)."""
    try:
        c = _cfg(conn)
        b = garantir(conn, lead, filtros, c)
        banco.um(conn, "UPDATE privado.busca_cliente SET base_em = now(), base_qtd = %s WHERE id = %s", (quantos, b["id"]))
        if quantos and exato:
            if b["estado"] == "perfil":
                banco.um(conn, "UPDATE privado.busca_cliente SET estado = 'nossa_base' WHERE id = %s", (b["id"],))
            passo(conn, b["id"], "base", f"Nossa base: {quantos} opção(ões) no perfil, enviada(s) ao cliente")
            conn.commit()
            return False
        passo(conn, b["id"], "base", f"Nossa base: nada no perfil exato; foram {quantos} mais próxima(s)" if quantos
              else "Nossa base: nada para esse perfil")
        if c["fluxo"] == "nao" or b["estado"] in ("buscando", "pausada", "encerrada", "ofertado") or not pronto(b["filtros"]):
            conn.commit()
            return False
        banco.um(conn, """UPDATE privado.busca_cliente SET estado = 'buscando', ativada_em = now(),
                                 motivo = 'a nossa base não tinha o perfil exato' WHERE id = %s""", (b["id"],))
        passo(conn, b["id"], "base", "Busca ativada: grupos de WhatsApp e OLX")
        conn.commit()
        return True
    except Exception:  # noqa: BLE001 -- o registro nunca para o atendimento
        conn.rollback()
        log.exception("lead %s: o resultado da base não foi registrado", lead.get("id"))
        return False


def cliente_avisado(conn, lead: dict, texto: str) -> None:
    try:
        bid = banco.um(conn, "SELECT id FROM privado.busca_cliente WHERE lead = %s", (lead["id"],))
        if bid:
            banco.um(conn, "UPDATE privado.busca_cliente SET cliente_avisado_em = now() WHERE id = %s", (bid,))
            passo(conn, bid, "cliente", f"Cliente avisado: \"{texto}\"")
            conn.commit()
    except Exception:  # noqa: BLE001
        conn.rollback()
        log.exception("lead %s: o aviso ao cliente não foi registrado", lead.get("id"))


# ── o envio pelo número de captação ──
def _inst() -> dict:
    conf = grupo._conf_do_vigia() or {}
    inst = (conf.get("instancias") or {}).get("captacao")
    if not inst:
        raise RuntimeError("sem a instância de captação no config do vigia")
    return inst


def _enviar(destino: str, texto: str) -> str:
    """destino: o id do grupo ou o telefone. Devolve o id da mensagem."""
    phone = destino if ("-" in destino or "group" in destino) else "55" + re.sub(r"\D", "", destino)[-11:]
    r = grupo._zapi(_inst(), "POST", "/send-text", {"phone": phone, "message": texto}, timeout=40)
    mid = str((r or {}).get("messageId") or (r or {}).get("id") or (r or {}).get("zaapId") or "") if isinstance(r, dict) else ""
    if not mid:
        raise RuntimeError((r or {}).get("_erro") if isinstance(r, dict) else "sem resposta da Z-API")
    return mid


def _tel8(t: str | None) -> str:
    return re.sub(r"\D", "", t or "")[-8:]


# ── 3. os grupos ──
def grupos_volta(conn, c: dict) -> int:
    if c["grupos"] == "nao" or not no_horario(c):
        return 0
    buscas = banco.linhas(conn, """SELECT * FROM privado.busca_cliente WHERE estado = 'buscando'
                                    AND ativada_em < now() - make_interval(mins => %s) ORDER BY ativada_em""", (c["lote_min"],))
    # 22/10 (Tel: "o de casa faltou o valor"): sem valor a busca não vai aos grupos (a Nay pergunta o valor primeiro)
    buscas = [b for b in buscas if pronto(b["filtros"]) and b["filtros"].get("teto")]
    if not buscas:
        return 0
    feitas = 0
    for g in banco.linhas(conn, "SELECT * FROM privado.busca_grupo WHERE ativo ORDER BY grupo_id"):
        if c["grupos"] == "sim" and g["ultimo_envio_em"] and \
                time.time() - g["ultimo_envio_em"].timestamp() < c["intervalo_min"] * 60:
            continue
        teste = c["grupos"] == "teste"
        # o que foi em teste não conta quando o modo é sim (senão o grupo de verdade nunca receberia)
        bs = [b for b in buscas if grupo_aceita(g, b["filtros"])
              and g["grupo_id"] not in [x.get("grupo") for x in b["grupos"] or [] if teste or not x.get("teste")]]
        # Tel, 22/10: "tem que ser sempre separado as buscas por mensagem individual": uma busca por mensagem; a próxima
        # do mesmo grupo espera `busca_grupos_intervalo_min`
        bs = bs[:1]
        if not bs:
            continue
        texto = mensagem_de_grupo(bs[0]["filtros"])
        if teste:
            if not c["teste"]:
                continue
            mid = _enviar(c["teste"], f"[teste: iria para o grupo {g['nome']}]\n\n{texto}")
        else:
            mid = _enviar(g["grupo_id"], texto)
            banco.um(conn, "UPDATE privado.busca_grupo SET ultimo_envio_em = now() WHERE grupo_id = %s", (g["grupo_id"],))
        for b in bs:
            item = {"grupo": g["grupo_id"], "nome": g["nome"], "em": datetime.now(MANAUS).isoformat(timespec="minutes"),
                    "mid": mid, "teste": teste}
            banco.um(conn, """UPDATE privado.busca_cliente SET grupos = grupos || %s::jsonb, grupos_em = now() WHERE id = %s""",
                     (json.dumps([item], ensure_ascii=False), b["id"]))
            passo(conn, b["id"], "grupos", f"Pedido no grupo {g['nome']}" + (" (teste: foi ao número de teste)" if teste else ""))
        conn.commit()
        feitas += 1
        log.info("grupos: %s (%d busca/s)%s", g["nome"], len(bs), " [teste]" if teste else "")
        time.sleep(3)
    return feitas


def atualizar_membros(conn) -> int:
    """Os participantes dos grupos (Z-API group-metadata): quem deles escrever no PV é corretor, nunca cliente orgânico."""
    if time.time() - _ULTIMO["membros"] < MEMBROS_A_CADA_S:
        return 0
    _ULTIMO["membros"] = time.time()
    inst, n = _inst(), 0
    for g in banco.linhas(conn, "SELECT grupo_id, nome FROM privado.busca_grupo WHERE ativo"):
        r = grupo._zapi(inst, "GET", f"/group-metadata/{g['grupo_id']}", timeout=30)
        for p in (r or {}).get("participants") or [] if isinstance(r, dict) else []:
            tel = re.sub(r"\D", "", str(p.get("phone") or ""))
            if not (10 <= len(tel) <= 13):
                continue
            banco.um(conn, """INSERT INTO privado.busca_grupo_membro (telefone8, telefone, grupos) VALUES (%s, %s, ARRAY[%s])
                              ON CONFLICT (telefone8) DO UPDATE SET grupos = (SELECT array_agg(DISTINCT x)
                                     FROM unnest(privado.busca_grupo_membro.grupos || EXCLUDED.grupos) x), atualizado_em = now()""",
                     (tel[-8:], tel, g["grupo_id"]))
            n += 1
        conn.commit()
    log.info("grupos: %d participação(ões) conferida(s)", n)
    return n


# ── 4. a OLX (a nossa base de scrap) ──
def pergunta_ao_anunciante(a: dict, predio: str | None = None) -> str:
    """Pedro, 23/10: sem o link do anúncio, "só falar o nome do prédio". O prédio vem do título (o reconhecedor de
    condomínios da Nay); sem prédio reconhecido, o título do anúncio."""
    onde = " · ".join(x for x in (a.get("preco_texto") or dinheiro(a.get("preco")), a.get("bairro")) if x)
    qual = f"do *{predio}*" if predio else f"*{a.get('titulo')}*"
    return (f"Olá! Tudo bem? Aqui é a Nay, da Imob Easy. Vi o seu anúncio na OLX {qual}"
            f"{' (' + onde + ')' if onde else ''}.\nTenho um cliente com esse perfil. Ele ainda está disponível? "
            f"Você trabalha com parceria?")


def predio_do_anuncio(conn, a: dict) -> str | None:
    """O condomínio que o título do anúncio cita (só o título: na descrição o reconhecedor erra, "Smart Tarumã" virava
    "Nossa Senhora de Fátima")."""
    try:
        return banco.um(conn, "SELECT c.nome FROM condominios c WHERE c.id = nai_condominio_da_pergunta(%s)",
                        (a.get("titulo") or "",))
    except Exception:  # noqa: BLE001 -- sem o prédio, vai o título
        conn.rollback()
        log.exception("o prédio do anúncio %s não foi achado", a.get("olx_id"))
        return None


def _telefone_bom(t: str) -> str | None:
    d = re.sub(r"\D", "", t or "")
    if d.startswith("55") and len(d) in (12, 13):
        d = d[2:]
    return d if len(d) in (10, 11) else None


def olx_volta(conn, c: dict) -> int:
    if c["olx"] == "nao" or not no_horario(c):
        return 0
    feitos = 0
    # 476c: os nossos números nunca são perguntados; o mesmo anunciante uma vez por volta (também em teste)
    nossos = set(banco.um(conn, "SELECT busca_nossos_numeros()") or [])
    nesta_volta: set[str] = set()
    for b in banco.linhas(conn, f"""SELECT * FROM privado.busca_cliente WHERE estado = 'buscando'
                                     AND (olx_em IS NULL OR olx_em < now() - interval '{OLX_DE_NOVO_H} hours')
                                   ORDER BY olx_em NULLS FIRST, id LIMIT 4"""):
        # sem valor no perfil a base da OLX traria de tudo (no teste de 22/10, casas de R$ 1,6 a 2 mi): espera o valor
        if not pronto(b["filtros"]) or not b["filtros"].get("teto"):
            continue
        teste = c["olx"] == "teste"
        tentados = [int(x["olx_id"]) for x in b["olx"] or [] if x.get("olx_id") and (teste or not x.get("teste"))]
        falta = c["olx_por_busca"] - len(tentados)
        banco.um(conn, "UPDATE privado.busca_cliente SET olx_em = now() WHERE id = %s", (b["id"],))
        conn.commit()
        if falta <= 0:
            continue
        cands = banco.linhas(conn, "SELECT * FROM busca_olx_candidatos(%s::jsonb, %s::bigint[], %s)",
                             (json.dumps(b["filtros"], ensure_ascii=False), tentados, falta * 4))
        if not cands:
            if not tentados and b["olx_em"] is None:
                passo(conn, b["id"], "olx", "OLX (nossa base de scrap): nenhum anúncio com telefone nesse perfil, por enquanto")
                conn.commit()
            continue
        n = 0
        for a in cands:
            tel = next((t for t in (_telefone_bom(x) for x in a["telefones"] or []) if t), None)
            if not tel or tel[-8:] in nossos or tel[-8:] in nesta_volta:
                continue
            nesta_volta.add(tel[-8:])
            if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.busca_contato WHERE telefone8 = %s
                                    AND em > now() - make_interval(hours => %s))""", (tel[-8:], CONTATO_DE_NOVO_H)):
                continue
            texto = pergunta_ao_anunciante(a, predio_do_anuncio(conn, a))
            if teste:
                if not c["teste"]:
                    break
                mid = _enviar(c["teste"], f"[teste: iria para {a.get('anunciante') or 'o anunciante'} {tel}]\n{texto}")
            else:
                mid = _enviar(tel, texto)
                banco.um(conn, """INSERT INTO privado.busca_contato (telefone8, telefone, busca, de, olx_id, nome)
                                  VALUES (%s, %s, %s, 'anunciante_olx', %s, %s)""",
                         (tel[-8:], tel, b["id"], a["olx_id"], a.get("anunciante")))
            item = {"olx_id": a["olx_id"], "titulo": a["titulo"], "url": a["url"], "preco": float(a["preco"] or 0),
                    "bairro": a["bairro"], "tel": tel, "anunciante": a.get("anunciante"), "nota": a.get("nota"),
                    "em": datetime.now(MANAUS).isoformat(timespec="minutes"), "mid": mid, "teste": teste}
            banco.um(conn, "UPDATE privado.busca_cliente SET olx = olx || %s::jsonb WHERE id = %s",
                     (json.dumps([item], ensure_ascii=False), b["id"]))
            passo(conn, b["id"], "olx", f"OLX: perguntei a {a.get('anunciante') or 'anunciante'} (…{tel[-4:]}) se \"{a['titulo']}\" "
                                       f"({dinheiro(a['preco'])}, {a['bairro']}) está disponível e se aceita parceria"
                                       + (" (teste: foi ao número de teste)" if teste else ""), {"url": a["url"]})
            conn.commit()
            n += 1
            feitos += 1
            time.sleep(4)
            if n >= falta:
                break
    return feitos


# ── 5. a Nay dos corretores ──
PROMPT_CORRETOR = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Você conversa pelo WhatsApp com um CORRETOR que
respondeu um pedido nosso: o que pedimos nos grupos de corretores, ou a pergunta que fizemos no anúncio dele na OLX.
O objetivo: ver se ele tem um imóvel que serve para uma das nossas BUSCAS ATIVAS, anotar os dados desse imóvel para o
cadastro e, completo, apresentar ao cliente. Trabalhamos em parceria (se ele perguntar a divisão: meio a meio, 50%).

Regras:
- Português do Brasil, curto e simpático, como gente. No máximo 2 balões. Pouco emoji.
- Nunca diga o nome, o telefone ou qualquer dado do cliente.
- Para o cadastro precisamos de: tipo, finalidade (aluguel ou venda), bairro, condomínio (se for apartamento ou casa em
  condomínio), quartos, valor, taxa de condomínio (se houver), mobília (na locação) e pelo menos 3 fotos. Pergunte SÓ o
  que ainda falta (veja "JÁ ANOTADO"), no máximo 2 coisas por vez. Fotos: peça que mande por aqui.
- Se o imóvel claramente não serve para nenhuma busca (negócio, tipo, bairro ou valor muito fora), agradeça e diga que
  no momento não bate com o que o cliente procura, mas que guardou o contato.
- Se ele perguntar algo do cliente que você não sabe (data de mudança, renda, documentos), diga que vai confirmar.
- Se a conversa não é sobre imóvel para as nossas buscas (outro assunto, propaganda, corrente), não responda.

Devolva SÓ JSON:
{"responder": true|false,
 "oferece_imovel": true|false,
 "busca_id": <id da busca que o imóvel atende, ou null>,
 "serve": "sim" | "nao" | "talvez",
 "imovel": {"tipo": "", "finalidade": "locacao|venda", "bairro": "", "condominio": "", "quartos": 0, "suites": 0,
            "vagas": 0, "area": 0, "valor": 0, "taxa_condominio": 0, "mobilia": "mobiliado|com modulados e ar|sem nada|",
            "andar": "", "observacao": ""},
 "baloes": ["..."]}
No "imovel", ponha só o que ele disse (o resto vazio ou 0)."""

CAMPOS_DO_IMOVEL = ("tipo", "finalidade", "bairro", "condominio", "quartos", "suites", "vagas", "area", "valor",
                    "taxa_condominio", "mobilia", "andar", "observacao")


def juntar_imovel(antes: dict, novo: dict) -> dict:
    d = dict(antes or {})
    for k in CAMPOS_DO_IMOVEL:
        v = (novo or {}).get(k)
        if v in (None, "", 0, "0"):
            continue
        d[k] = v
    return d


def falta_no_imovel(im: dict, fotos: int) -> list[str]:
    falta = []
    for k, nome in (("tipo", "o tipo"), ("finalidade", "se é aluguel ou venda"), ("bairro", "o bairro"),
                    ("quartos", "os quartos"), ("valor", "o valor")):
        if not im.get(k):
            falta.append(nome)
    t = str(im.get("tipo") or "").lower()
    if ("apart" in t or "condom" in t) and not im.get("condominio"):
        falta.append("o condomínio")
    if str(im.get("finalidade") or "").startswith("loc") and not im.get("mobilia"):
        falta.append("a mobília")
    if fotos < FOTOS_MINIMAS:
        falta.append("as fotos")
    return falta


def _conversa_corretor(conn, tel8: str) -> list[dict]:
    return list(reversed(banco.linhas(conn, """
        SELECT id, direcao, origem, texto, to_char(criada_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS hora
          FROM captacao_mensagens
         WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
         ORDER BY id DESC LIMIT 30""", (tel8,))))


def _turno_corretor(conn, cor: dict, conversa: list[dict], ativas: list[dict], fotos: int) -> str:
    linhas = ["BUSCAS ATIVAS (id: o que o cliente procura):"]
    linhas += [f"- {b['id']}: {resumo(b['filtros'])}" for b in ativas] or ["- nenhuma"]
    linhas += ["", f"JÁ ANOTADO deste imóvel: {json.dumps(cor.get('imovel') or {}, ensure_ascii=False)}",
               f"Fotos recebidas até agora: {fotos}", f"Busca escolhida antes: {cor.get('busca') or 'nenhuma'}", "", "CONVERSA:"]
    for m in conversa:
        quem = "CORRETOR" if m["direcao"] == "recebida" else "NAY/EQUIPE"
        texto = (m["texto"] or "").strip() or f"[{m['origem'] or 'mídia'}]"
        if m["origem"] == "imagem":
            texto = "[foto] " + texto
        linhas.append(f"{m['hora']} {quem}: {texto[:600]}")
    return "\n".join(linhas)


def _fotos_novas(conn, tel8: str) -> list[dict]:
    return banco.linhas(conn, "SELECT id, url FROM privado.busca_corretor_foto WHERE telefone8 = %s AND usada_em IS NULL ORDER BY id", (tel8,))


def _qtd_fotos(conn, tel8: str, codigo: int | None) -> int:
    soltas = banco.um(conn, "SELECT count(*) FROM privado.busca_corretor_foto WHERE telefone8 = %s AND usada_em IS NULL", (tel8,)) or 0
    no_cadastro = banco.um(conn, "SELECT count(*) FROM imovel_fotos WHERE codigo = %s", (codigo,)) if codigo else 0
    return int(soltas) + int(no_cadastro or 0)


TIPO_DO_CADASTRO = (("lote", "Lote em Condomínio"), ("condom", "Casa de condomínio"), ("cobertura", "Cobertura"),
                    ("apart", "Apartamento"), ("flat", "Flat"), ("casa", "Casa"), ("sala", "Sala/Andar"))


def _tipo_do_cadastro(t: str | None) -> str | None:
    t = (t or "").lower()
    return next((v for k, v in TIPO_DO_CADASTRO if k in t), None)


def cadastrar(conn, cor: dict, b: dict, ativo: bool) -> int:
    """O imóvel do corretor no nosso cadastro, como imóvel de PARCEIRO. Rascunho enquanto falta dado; completo, Disponível
    (ativo=True). Devolve o código."""
    im = cor["imovel"] or {}
    loc = str(im.get("finalidade") or "").startswith("loc")
    valor = None
    try:
        valor = float(im.get("valor") or 0) or None
    except (TypeError, ValueError):
        pass
    extras = {"corretor_parceiro": cor.get("nome") or "", "corretor_telefone": cor["telefone"], "busca_cliente": str(b["id"]),
              "cadastrado_pelo": "Nay dos corretores (busca do cliente)", "observacao_do_corretor": str(im.get("observacao") or "")}
    extras = {k: v for k, v in extras.items() if v}
    campos = {"tipo": _tipo_do_cadastro(im.get("tipo")), "bairro": im.get("bairro") or None,
              "condominio_nome": im.get("condominio") or None, "quartos": im.get("quartos") or None,
              "suites": im.get("suites") or None, "vagas": im.get("vagas") or None, "area_util": im.get("area") or None,
              "valor_aluguel": valor if loc else None, "valor_venda": None if loc else valor,
              "taxa_condominio": im.get("taxa_condominio") or None, "mobilia": im.get("mobilia") or None,
              "andar": im.get("andar") or None}
    if not cor.get("codigo"):
        codigo = banco.um(conn, """
            INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, criado_em, captado_em, e_parceiro,
                                 tipo, bairro, condominio_nome, quartos, suites, vagas, area_util, valor_aluguel, valor_venda,
                                 taxa_condominio, mobilia, andar, extras)
            VALUES (nextval('imoveis_crm_codigo_seq'), 'busca', 'Rascunho', false, false, now(), to_char(now(), 'DD/MM/YYYY'), true,
                    %(tipo)s, %(bairro)s, %(condominio_nome)s, %(quartos)s, %(suites)s, %(vagas)s, %(area_util)s, %(valor_aluguel)s,
                    %(valor_venda)s, %(taxa_condominio)s, %(mobilia)s, %(andar)s, %(extras)s::jsonb)
            RETURNING codigo""", {**campos, "extras": json.dumps(extras, ensure_ascii=False)})
    else:
        codigo = cor["codigo"]
        sets = ", ".join(f"{k} = coalesce(%({k})s, {k})" for k in campos)
        banco.um(conn, f"UPDATE imoveis SET {sets}, extras = coalesce(extras, '{{}}'::jsonb) || %(extras)s::jsonb WHERE codigo = %(codigo)s",
                 {**campos, "extras": json.dumps(extras, ensure_ascii=False), "codigo": codigo})
    ordem = int(banco.um(conn, "SELECT coalesce(max(ordem), 0) FROM imovel_fotos WHERE codigo = %s", (codigo,)) or 0)
    for f in _fotos_novas(conn, _tel8(cor["telefone"])):
        ordem += 1
        banco.um(conn, "INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (%s, %s, %s, %s)", (codigo, ordem, f["url"], ordem == 1))
        banco.um(conn, "UPDATE privado.busca_corretor_foto SET usada_em = now() WHERE id = %s", (f["id"],))
    if ativo:
        banco.um(conn, "UPDATE imoveis SET status = 'Disponível', disponivel = true, publicado_no_site = true WHERE codigo = %s", (codigo,))
    conn.commit()
    return int(codigo)


def oferecer_ao_cliente(conn, b: dict, codigo: int, cor: dict, c: dict) -> str:
    """O imóvel completo vai ao cliente pela Nay do WhatsApp; se a equipe está com o cliente, vai ao grupo."""
    lead = whatsapp._lead(conn, b["lead"])
    if c["corretor"] == "teste" or b["teste"]:
        if c["teste"]:
            _enviar(c["teste"], f"[teste: iria ao cliente {whatsapp.quem(lead)} o imóvel #{codigo} do corretor {cor.get('nome') or cor['telefone']}]")
        return "teste"
    if lead.get("humano_em"):
        whatsapp._grupo(f"Busca do cliente {whatsapp.quem(lead)}: o corretor {cor.get('nome') or ''} ({grupo.telefone_bonito(cor['telefone'])}) "
                        f"ofereceu o imóvel #{codigo}, já cadastrado como parceiro. A conversa do cliente está com a equipe: "
                        f"apresentem por lá.")
        return "grupo"
    return _mandar_ao_cliente(conn, lead, codigo)


def _mandar_ao_cliente(conn, lead: dict, codigo: int) -> str:
    whatsapp.mandar_texto(conn, lead, "Boa notícia! Encontrei uma opção que combina com o que você procura:")
    time.sleep(whatsapp.ENTRE_ENVIOS_S)
    whatsapp.mandar_imovel(conn, lead, codigo)
    time.sleep(whatsapp.DEPOIS_DAS_FOTOS_S)
    whatsapp.mandar_texto(conn, lead, "O que achou dessa? Se gostar, já vejo a visita para você.")
    enviados = list(lead.get("enviados") or [])
    if codigo not in enviados:
        whatsapp._marcar(conn, lead["id"], enviados=enviados + [codigo])
    conn.commit()
    return "cliente"


def base_volta(conn, c: dict) -> int:
    """O imóvel que entrou na nossa base DEPOIS da busca (Pedro, 23/10: "esse novo imóvel cadastrado no grupo de
    cadastro não está aparecendo para a lead"). A base só era olhada quando a lead escrevia; a busca criada da conversa
    (a Edsandra, lead 45) nunca olhou, e tinha o 3841 e o 4020 no perfil. A cada BASE_A_CADA_MIN, a busca ATIVA (só
    'buscando': as 'perfil' são dezenas de leads antigas) contra o catálogo, no perfil exato (sem afrouxar), fora o que
    ela já recebeu ou já foi oferecido; um imóvel por vez, um por dia."""
    if not no_horario(c):
        return 0
    feitos = 0
    for b in banco.linhas(conn, f"""SELECT * FROM privado.busca_cliente WHERE estado = 'buscando'
                                     AND (base_em IS NULL OR base_em < now() - interval '{BASE_A_CADA_MIN} minutes')
                                   ORDER BY base_em NULLS FIRST, id LIMIT 6"""):
        if not pronto(b["filtros"]):
            continue
        lead = whatsapp._lead(conn, b["lead"])
        f = dict(b["filtros"])
        if whatsapp._aceita_parceiro(conn, lead):
            f["aceita_parceiro"] = "true"
        # um da base por dia: o próximo espera ela ver o de antes
        if any(x.get("de") == "base" and x.get("em", "") > (datetime.now(MANAUS) - timedelta(hours=24)).isoformat()
               for x in b["ofertas"] or []):
            continue
        oferecidos = [int(x["codigo"]) for x in b["ofertas"] or [] if x.get("codigo")]
        excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else []) + oferecidos
        achados = banco.linhas(conn, "SELECT * FROM olx_cliente_buscar(%s::jsonb, %s::int[], 1)",
                               (json.dumps(f, ensure_ascii=False), excluir))
        banco.um(conn, "UPDATE privado.busca_cliente SET base_em = now() WHERE id = %s", (b["id"],))
        conn.commit()
        if not achados:
            continue
        codigo = int(achados[0]["codigo"])
        # sem o modo teste: o imóvel da nossa base é o que a Nay do WhatsApp manda quando ela escreve
        teste = False
        if lead.get("humano_em"):
            whatsapp._grupo(f"Busca do cliente {whatsapp.quem(lead)}: o imóvel #{codigo} da nossa base serve no perfil dela. "
                            f"A conversa do cliente está com a equipe: apresentem por lá.")
            onde = "grupo"
        else:
            onde = _mandar_ao_cliente(conn, lead, codigo)
        banco.um(conn, "UPDATE privado.busca_cliente SET ofertas = ofertas || %s::jsonb WHERE id = %s",
                 (json.dumps([{"codigo": codigo, "de": "base", "em": datetime.now(MANAUS).isoformat(timespec="minutes"),
                               "estado": onde, "teste": teste}], ensure_ascii=False), b["id"]))
        passo(conn, b["id"], "oferta", {"cliente": f"Nossa base: o imóvel #{codigo} serve no perfil e foi oferecido ao cliente",
                                        "grupo": f"Nossa base: o imóvel #{codigo} serve no perfil; o cliente está com a equipe: avisado no grupo",
                                        "teste": f"Nossa base: o imóvel #{codigo} serve no perfil (teste: não foi ao cliente)"}[onde])
        conn.commit()
        feitos += 1
    return feitos


def _pendentes_corretores(conn) -> list[dict]:
    """Quem é corretor da busca e escreveu (e parou de escrever há 30 s) depois da última mensagem lida."""
    return banco.linhas(conn, """
        SELECT right(regexp_replace(m.telefone, '\\D', '', 'g'), 8) AS t8, max(m.telefone) AS telefone, max(m.id) AS ate,
               max(m.criada_em) AS ultima
          FROM captacao_mensagens m
          LEFT JOIN privado.busca_corretor bc ON bc.telefone8 = right(regexp_replace(m.telefone, '\\D', '', 'g'), 8)
         WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '2 days'
           AND m.id > coalesce(bc.ultima_lida, 0)
           AND coalesce(bc.estado, '') NOT IN ('humano')
           AND busca_corretor_e(m.telefone)
         GROUP BY 1
        HAVING max(m.criada_em) < now() - interval '30 seconds'
         ORDER BY max(m.criada_em) LIMIT 4""")


def corretores_volta(conn, c: dict) -> int:
    if c["corretor"] == "nao":
        return 0
    ativas = banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE estado = 'buscando' ORDER BY id")
    feitos = 0
    for p in _pendentes_corretores(conn):
        t8 = p["t8"]
        banco.um(conn, """INSERT INTO privado.busca_corretor (telefone8, telefone, nome) VALUES (%s, %s,
                            (SELECT nome FROM corretores WHERE right(regexp_replace(telefone, '\\D', '', 'g'), 8) = %s LIMIT 1))
                          ON CONFLICT (telefone8) DO NOTHING""", (t8, re.sub(r"\D", "", p["telefone"]), t8))
        cor = banco.linhas(conn, "SELECT * FROM privado.busca_corretor WHERE telefone8 = %s", (t8,))[0]
        conversa = _conversa_corretor(conn, t8)
        # a equipe escreveu para ele pelo 8595 depois que a Nay começou: a conversa é dela
        if any(m["direcao"] == "enviada" and m["origem"] == "humano" and m["id"] > (cor["ultima_lida"] or 0) for m in conversa):
            banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'humano', humano_em = now(), ultima_lida = %s WHERE telefone8 = %s",
                     (p["ate"], t8))
            conn.commit()
            continue
        if not ativas:
            banco.um(conn, "UPDATE privado.busca_corretor SET ultima_lida = %s WHERE telefone8 = %s", (p["ate"], t8))
            conn.commit()
            continue
        fotos = _qtd_fotos(conn, t8, cor.get("codigo"))
        try:
            r = modelo.chamar(PROMPT_CORRETOR, _turno_corretor(conn, cor, conversa, ativas, fotos), no="olx.corretor")
        except Exception:  # noqa: BLE001
            log.exception("corretor …%s: o modelo falhou", t8[-4:])
            continue
        banco.um(conn, "UPDATE privado.busca_corretor SET ultima_lida = %s, atualizado_em = now() WHERE telefone8 = %s", (p["ate"], t8))
        conn.commit()
        ids = {b["id"]: b for b in ativas}
        bid = r.get("busca_id") if r.get("busca_id") in ids else cor.get("busca")
        b = ids.get(bid) or (banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE id = %s", (bid,)) or [None])[0] if bid else None
        baloes = [str(x).strip() for x in (r.get("baloes") or []) if str(x).strip()][:2]
        if r.get("oferece_imovel") and b and r.get("serve") != "nao":
            im = juntar_imovel(cor.get("imovel") or {}, r.get("imovel") or {})
            banco.um(conn, """UPDATE privado.busca_corretor SET imovel = %s::jsonb, busca = %s, estado = 'cadastrando'
                               WHERE telefone8 = %s""", (json.dumps(im, ensure_ascii=False), b["id"], t8))
            cor = {**cor, "imovel": im, "busca": b["id"]}
            primeira = not cor.get("codigo")
            falta = falta_no_imovel(im, fotos)
            completo = not falta and c["corretor"] == "sim"
            codigo = cadastrar(conn, cor, b, ativo=completo)
            banco.um(conn, "UPDATE privado.busca_corretor SET codigo = %s WHERE telefone8 = %s", (codigo, t8))
            if primeira:
                banco.um(conn, "UPDATE privado.busca_cliente SET ofertas = ofertas || %s::jsonb WHERE id = %s",
                         (json.dumps([{"tel": cor["telefone"], "nome": cor.get("nome"), "codigo": codigo,
                                       "em": datetime.now(MANAUS).isoformat(timespec="minutes"), "estado": "cadastrando"}], ensure_ascii=False), b["id"]))
                passo(conn, b["id"], "corretor", f"Corretor {cor.get('nome') or ''} (…{t8[-4:]}) ofereceu um imóvel: pré-cadastro #{codigo}")
            if not falta:
                onde = oferecer_ao_cliente(conn, b, codigo, cor, c)
                if onde in ("cliente", "grupo"):
                    banco.um(conn, """UPDATE privado.busca_cliente SET estado = 'ofertado', ofertado_em = now() WHERE id = %s""", (b["id"],))
                    banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'ofertado' WHERE telefone8 = %s", (t8,))
                passo(conn, b["id"], "oferta", {"cliente": f"Imóvel #{codigo} completo e oferecido ao cliente",
                                                "grupo": f"Imóvel #{codigo} completo; o cliente está com a equipe: avisado no grupo",
                                                "teste": f"Imóvel #{codigo} completo (teste: não foi ao cliente)"}[onde])
                if not baloes:
                    baloes = ["Perfeito, cadastrei aqui e já apresentei ao meu cliente. Assim que ele der retorno eu te chamo!"]
            else:
                passo(conn, b["id"], "corretor", f"#{codigo}: falta {', '.join(falta)}")
            conn.commit()
        elif r.get("oferece_imovel") and r.get("serve") == "nao":
            banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'sem_match' WHERE telefone8 = %s", (t8,))
            conn.commit()
        if r.get("responder") and baloes:
            for n, t in enumerate(baloes):
                if n:
                    time.sleep(2)
                if c["corretor"] == "teste":
                    if c["teste"]:
                        _enviar(c["teste"], f"[teste: iria para o corretor …{t8[-4:]}]\n{t}")
                else:
                    _enviar(cor["telefone"], t)
        feitos += 1
    return feitos


# ── o laço ──
def uma_volta(conn) -> dict:
    c = _cfg(conn)
    if c["fluxo"] == "nao":
        return {}
    r = {"registro": sincronizar(conn, c)}
    for nome, f in (("membros", lambda: atualizar_membros(conn)), ("base", lambda: base_volta(conn, c)),
                    ("grupos", lambda: grupos_volta(conn, c)),
                    ("olx", lambda: olx_volta(conn, c)), ("corretores", lambda: corretores_volta(conn, c))):
        try:
            r[nome] = f()
        except Exception:  # noqa: BLE001 -- uma parte não para as outras
            conn.rollback()
            log.exception("buscas: a parte %s falhou", nome)
    return r


def laco() -> None:
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            r = uma_volta(conn)
            if any(v for v in r.values()):
                log.info("buscas: %s", r)
            conn.rollback()
        except Exception:  # noqa: BLE001
            log.exception("a volta das buscas falhou")
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(30)
        time.sleep(A_CADA_S)


def iniciar() -> threading.Thread:
    t = threading.Thread(target=laco, name="nay-buscas", daemon=True)
    t.start()
    return t
