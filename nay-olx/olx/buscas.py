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
# Pedro, 23/10: "o ideal não é ter um imóvel enviado e sim 3 a 5 opções; ela não deve parar na hora de achar um imóvel"
OPCOES_META = 3                # a busca só termina ('ofertado') quando a lead recebeu tantas opções
OPCOES_MAX = 5                 # e nunca passa disto (a base manda de uma vez o que couber até aqui)
# Tel, 23/10 (a Edsandra recebeu o Life Flores e dois de R$ 500 mil para teto de 750): "precisa subir a regra ... só vale
# daqueles bairros perto segundo o mapa, mais pertos ainda, aperta essa busca". Vizinho só com divisa e centros a até
# VIZINHO_ATE_KM (Flores-Parque 10 é 2,1 km); o valor na faixa firme da casa (225): 20% abaixo, 10% acima do teto.
VIZINHO_ATE_KM = 1.5
FAIXA_ABAIXO, FAIXA_ACIMA = 0.20, 0.10
# Tel, 28/10 (a lead 63 veio pelo Prime Arena, de 2019, e recebeu o Amazonas Flat, antigo): "aquele imóvel que ela veio
# tem 3 anos e o outro que a Nay enviou tem mais de 20 anos ... gente que vem por esses mais novos 80% de chance a mais de
# querer fechar em um condomínio mais novo por área de lazer e a estrutura do condomínio ser mais nova". Quem veio de um
# condomínio RECENTE (condominio_proximo: a planilha do Pedro + os lançados nos últimos 5 anos, 433/436) ou pediu
# condomínio novo ganha o critério "padrão" na nota, com este peso sobre os 100 dos outros critérios: recente vale 100,
# o resto 0 (um imóvel de nota 100 em condomínio antigo cai para 67, abaixo do corte amarelo).
PESO_PADRAO = 50
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
            "olx_por_busca": int(c.get("busca_olx_por_busca") or 3),
            # Pedro, 23/10: "não atendemos leads de imóveis abaixo de 200 mil ou abaixo de 2k de aluguel"
            "venda_min": float(c.get("busca_venda_min") or 200000), "aluguel_min": float(c.get("busca_aluguel_min") or 2000),
            "de": de, "ate": ate, "teste": teste[0] if teste else None}


def abaixo_do_minimo(f: dict, c: dict) -> bool:
    """O valor que ela quer está abaixo do que a casa atende (venda < R$ 200 mil, aluguel < R$ 2 mil): sem busca fora.
    Sem valor no perfil não se sabe: não é abaixo."""
    try:
        teto = float((f or {}).get("teto") or 0)
    except (TypeError, ValueError):
        return False
    if not teto:
        return False
    fin = finalidade(f)
    return (fin == "venda" and teto < c["venda_min"]) or (fin == "locacao" and teto < c["aluguel_min"])


def texto_do_minimo(c: dict) -> str:
    return f"abaixo do que atendemos (venda a partir de {dinheiro(c['venda_min'])}, aluguel a partir de {dinheiro(c['aluguel_min'])})"


def encerrar_abaixo_do_minimo(conn, c: dict) -> int:
    """A busca aberta cujo valor ficou abaixo do mínimo é encerrada (com o motivo na linha da tela)."""
    n = 0
    for b in banco.linhas(conn, "SELECT id, filtros FROM privado.busca_cliente WHERE estado IN ('buscando', 'perfil', 'nossa_base')"):
        if not abaixo_do_minimo(b["filtros"], c):
            continue
        banco.um(conn, "UPDATE privado.busca_cliente SET estado = 'encerrada', motivo = %s WHERE id = %s", (texto_do_minimo(c), b["id"]))
        passo(conn, b["id"], "perfil", f"Busca encerrada: {resumo(b['filtros'])}: {texto_do_minimo(c)}")
        n += 1
    conn.commit()
    return n


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
    mob = {"mobiliado": "mobiliado", "semi": "com modulados e ar", "sem": "sem mobília"}.get(str(f.get("mobilia") or ""))
    if mob and finalidade(f) == "locacao":
        partes.append(mob)
    fin = str(f.get("financiamento") or "").lower()
    if "financ" in fin or fin in ("sim", "aprovado"):
        partes.append("aceitar financiamento")
    elif "vista" in fin:
        partes.append("pagamento à vista")
    if f.get("condominio"):
        # 27/10: "só no Ponta Negra Village" (so_condominio) vai assim ao grupo, e não "de preferência"
        partes.append(f"{'só' if f.get('so_condominio') else 'de preferência'} no {f['condominio']}")
    if f.get("perto_de"):
        partes.append(f"perto do {f['perto_de']}")
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


def nota_do_anuncio(a: dict, b: dict) -> str:
    """A nota que só a equipe vê no CRM, ao lado da pergunta ao anunciante: o link do anúncio e o perfil do cliente."""
    return (f"Anúncio da OLX que a Nay perguntou: {a.get('titulo') or '-'} ({dinheiro(a.get('preco'))}, "
            f"{a.get('bairro') or '-'})\n{a.get('url') or '(sem link)'}\n\nPara a busca #{b['id']}: {resumo(b['filtros'])}")


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
                    "mobilia", "financiamento", "condominio", "so_condominio", "perto_de", "perto_km", "pet", "exigencias")


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
        # encerrada só pelo valor baixo e agora o valor serve: volta a ser uma busca como as outras
        if b["estado"] == "encerrada" and str(b.get("motivo") or "").startswith("abaixo do que atendemos") \
                and not abaixo_do_minimo(f, c):
            banco.um(conn, "UPDATE privado.busca_cliente SET estado = 'perfil', motivo = NULL WHERE id = %s", (b["id"],))
            passo(conn, b["id"], "perfil", "Busca reaberta: o valor agora está no que atendemos")
            b = {**b, "estado": "perfil"}
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
        if abaixo_do_minimo(b["filtros"], c):
            if b["estado"] not in ("encerrada",):
                banco.um(conn, "UPDATE privado.busca_cliente SET estado = 'encerrada', motivo = %s WHERE id = %s",
                         (texto_do_minimo(c), b["id"]))
                passo(conn, b["id"], "perfil", f"Busca não ativada: {texto_do_minimo(c)}")
            conn.commit()
            return False
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


def para_zapi(destino: str) -> str:
    """O destino como a Z-API quer. O telefone do corretor vem do webhook com 12 dígitos, sem o 9 (559293500979): o
    `[-11:]` fazia 5559293500979, que não existe, e a Z-API devolvia id mesmo assim. Tel, 28/10: "os parceiros que ela
    está fazendo as buscas ela não retorna a mensagem" (nenhum dos 20 corretores da busca tinha recebido resposta)."""
    if "-" in destino or "group" in destino:
        return destino
    d = re.sub(r"\D", "", destino)
    return d if d.startswith("55") and len(d) in (12, 13) else "55" + d[-11:]


def _enviar(destino: str, texto: str) -> str:
    """destino: o id do grupo ou o telefone. Devolve o id da mensagem."""
    r = grupo._zapi(_inst(), "POST", "/send-text", {"phone": para_zapi(destino), "message": texto}, timeout=40)
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
    # Pedro, 23/10: "quando tiver o perfil ele vai executar as 2 buscas de grupos e base da OLX juntos depois da busca na
    # base": sem a espera de `busca_lote_min` depois da ativação (a OLX já saía na hora e os grupos esperavam 10 min)
    buscas = banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE estado = 'buscando' ORDER BY ativada_em")
    # 22/10 (Tel: "o de casa faltou o valor"): sem valor a busca não vai aos grupos (a Nay pergunta o valor primeiro)
    buscas = [b for b in buscas if pronto(b["filtros"]) and b["filtros"].get("teto") and not abaixo_do_minimo(b["filtros"], c)]
    if not buscas:
        return 0
    feitas = 0
    for g in banco.linhas(conn, "SELECT * FROM privado.busca_grupo WHERE ativo ORDER BY grupo_id"):
        if c["grupos"] == "sim" and g["ultimo_envio_em"] and \
                time.time() - g["ultimo_envio_em"].timestamp() < c["intervalo_min"] * 60:
            continue
        teste = c["grupos"] == "teste"
        # o que foi em teste não conta quando o modo é sim (senão o grupo de verdade nunca receberia). 29/10: o pedido
        # que MUDOU (outro valor, outro bairro) é pedido novo e vai de novo (mesmo_pedido)
        bs = [b for b in buscas if grupo_aceita(g, b["filtros"])
              and g["grupo_id"] not in [x.get("grupo") for x in b["grupos"] or []
                                        if (teste or not x.get("teste")) and mesmo_pedido(x, mensagem_de_grupo(b["filtros"]))]]
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
            # o texto vai junto do id: o corretor que responde marcando a mensagem aparece no CRM com o pedido citado
            # (Tel, 28/10: "não conseguimos ver a mensagem que foi no grupo"; crm_mensagem_citada, 511)
            item = {"grupo": g["grupo_id"], "nome": g["nome"], "em": datetime.now(MANAUS).isoformat(timespec="minutes"),
                    "mid": mid, "teste": teste, "texto": texto}
            banco.um(conn, """UPDATE privado.busca_cliente SET grupos = grupos || %s::jsonb, grupos_em = now() WHERE id = %s""",
                     (json.dumps([item], ensure_ascii=False), b["id"]))
            passo(conn, b["id"], "grupos", f"Pedido no grupo {g['nome']}" + (" (teste: foi ao número de teste)" if teste else ""))
        conn.commit()
        feitas += 1
        log.info("grupos: %s (%d busca/s)%s", g["nome"], len(bs), " [teste]" if teste else "")
        time.sleep(3)
    return feitas


def _alguem_ofereceu(conn, b: dict) -> bool:
    """Algum corretor mandou um imóvel para esta busca (a oferta dele ficou na busca ou na tabela dos corretores)?"""
    if any(o.get("tel") for o in (b.get("ofertas") or [])):
        return True
    return bool(banco.um(conn, "SELECT EXISTS (SELECT 1 FROM privado.busca_corretor WHERE busca = %s)", (b["id"],)))


REPETICOES = 2                 # Pedro, 29/10: "em mais 2 horários, na manhã do outro dia e na tarde do outro dia"
TARDE_DESDE_H = 14             # a segunda repetição é a da tarde
ENTRE_REPETICOES_H = 3         # e nunca colada na da manhã


def _quando(x: dict) -> datetime | None:
    try:
        return datetime.fromisoformat(x["em"]).astimezone(MANAUS)
    except (KeyError, TypeError, ValueError):
        return None


def mesmo_pedido(x: dict, texto: str) -> bool:
    """O item do grupo é deste pedido? O pedido que mudou (a lead disse outro valor, outro bairro) é pedido novo
    (Pedro, 29/10: "cada mensagem do lead sobrescreve a antiga"). Item antigo, de antes de guardarmos o texto, conta."""
    return x.get("texto") in (None, texto)


def repeticao_do_grupo(itens: list[dict], agora: datetime) -> str | None:
    """Pedro, 29/10: "se não recebemos imóveis pela busca que foi mandada no grupo, ele pede de novo em mais 2 horários,
    na manhã do outro dia e na tarde do outro dia, antes de parar de mandar aquela busca". `itens` = os deste pedido neste
    grupo (no modo atual), na ordem. Devolve 'repetir', 'encerrar' ou None (nada agora). Puro: os testes chamam direto."""
    if any(x.get("encerrou") for x in itens):
        return None
    originais = [n for n, x in enumerate(itens) if not x.get("repeticao")]
    if not originais:
        return None
    primeiro = _quando(itens[originais[-1]])
    reps = [x for x in itens[originais[-1] + 1:] if x.get("repeticao")]
    if primeiro is None:
        return None
    if len(reps) >= REPETICOES:
        return "encerrar"
    if agora.date() <= primeiro.date():
        return None                              # o pedido foi hoje: a primeira repetição é amanhã de manhã
    if not reps:
        return "repetir"
    ultima = _quando(reps[-1]) or primeiro
    if agora.hour >= TARDE_DESDE_H and agora - ultima >= timedelta(hours=ENTRE_REPETICOES_H):
        return "repetir"
    return None


def grupos_repete(conn, c: dict) -> int:
    """Pedro, 24/10: "quando fizermos uma pergunta da solicitação de um cliente no grupo, mas ninguém mandou mensagem
    oferecendo, deve agendar uma cron para o começo do próximo dia para enviar novamente a mesma mensagem de busca".
    29/10: até repetia todo dia, sem parar (a busca 52 saiu 36 vezes em 9 grupos). Agora são 2 repetições por grupo, a
    da manhã e a da tarde do dia seguinte (repeticao_do_grupo); sem imóvel de corretor depois delas, aquele grupo não
    recebe mais esse pedido. Respeita o intervalo entre mensagens de cada grupo."""
    if c["grupos"] == "nao" or not no_horario(c):
        return 0
    agora = datetime.now(MANAUS)
    feitas = 0
    for b in banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE estado = 'buscando' ORDER BY ativada_em"):
        if not pronto(b["filtros"]) or not b["filtros"].get("teto") or abaixo_do_minimo(b["filtros"], c):
            continue
        itens = list(b["grupos"] or [])
        teste = c["grupos"] == "teste"
        if not itens or _alguem_ofereceu(conn, b):
            continue
        texto = mensagem_de_grupo(b["filtros"])
        # os itens deste pedido (o texto de agora) em cada grupo, no modo atual
        por_grupo: dict[str, list[dict]] = {}
        for x in itens:
            if bool(x.get("teste")) == teste and x.get("grupo") and mesmo_pedido(x, texto):
                por_grupo.setdefault(x["grupo"], []).append(x)
        mudou = False
        for gid, do_grupo in por_grupo.items():
            vez = repeticao_do_grupo(do_grupo, agora)
            if not vez:
                continue
            nome = do_grupo[-1].get("nome") or gid
            if vez == "encerrar":
                itens.append({"grupo": gid, "nome": nome, "em": agora.isoformat(timespec="minutes"), "teste": teste,
                              "encerrou": True, "texto": texto})
                mudou = True
                passo(conn, b["id"], "grupos", f"Ninguém ofereceu imóvel depois de {REPETICOES + 1} pedidos no grupo {nome}: "
                                               "esse pedido parou de ir a esse grupo")
                continue
            g = (banco.linhas(conn, "SELECT * FROM privado.busca_grupo WHERE grupo_id = %s AND ativo", (gid,)) or [None])[0]
            if not g:
                continue
            if c["grupos"] == "sim" and g["ultimo_envio_em"] and \
                    time.time() - g["ultimo_envio_em"].timestamp() < c["intervalo_min"] * 60:
                continue
            if teste:
                if not c["teste"]:
                    continue
                mid = _enviar(c["teste"], f"[teste: repetiria no grupo {g['nome']}]\n\n{texto}")
            else:
                mid = _enviar(gid, texto)
                banco.um(conn, "UPDATE privado.busca_grupo SET ultimo_envio_em = now() WHERE grupo_id = %s", (gid,))
            itens.append({"grupo": gid, "nome": g["nome"], "em": datetime.now(MANAUS).isoformat(timespec="minutes"),
                          "mid": mid, "teste": teste, "repeticao": True, "texto": texto})
            mudou = True
            passo(conn, b["id"], "grupos", f"Ninguém ofereceu: o mesmo pedido saiu de novo no grupo {g['nome']}"
                  + (" (teste: foi ao número de teste)" if teste else ""))
            log.info("grupos: repetiu a busca %s no grupo %s%s", b["id"], g["nome"], " [teste]" if teste else "")
            feitas += 1
            time.sleep(3)
        if mudou:
            banco.um(conn, "UPDATE privado.busca_cliente SET grupos = %s::jsonb, grupos_em = now() WHERE id = %s",
                     (json.dumps(itens, ensure_ascii=False), b["id"]))
            conn.commit()
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


def trecho_do_predio(titulo: str) -> str | None:
    """O pedaço do título que nomeia o prédio: o que vem depois de "Cond", "Condomínio", "Resid", "Residencial",
    "Edifício" ou "Ed" até a vírgula, o hífen ou o fim ("... Cond Resid The Club, Parque das Laranjeiras" -> "The Club")."""
    m = re.search(r"\b(?:cond(?:om[ií]nio)?|resid(?:encial)?|edif[ií]cio|ed)\b\.?\s*(?:(?:cond(?:om[ií]nio)?|resid(?:encial)?)\b\.?\s*)*"
                  r"([^,;|\n]+?)(?=\s*(?:[,;|\n]|\s-\s|$))", titulo or "", re.I)
    t = (m.group(1) if m else "").strip(" .-")
    return t if len(t) >= 3 else None


def predio_do_anuncio(conn, a: dict) -> str | None:
    """O condomínio que o título do anúncio cita (só o título: na descrição o reconhecedor erra, "Smart Tarumã" virava
    "Nossa Senhora de Fátima"). Pedro, 24/10: a Suzy respondeu "não tenho nenhum imóvel no Cond Laranjeiras" a um anúncio do
    The Club, "Parque das Laranjeiras": o reconhecedor pegou o bairro do fim do título. Por isso primeiro o trecho que
    nomeia o prédio ("The Club"); só sem achar nada vale o título inteiro."""
    titulo = a.get("titulo") or ""
    try:
        for texto in [t for t in (trecho_do_predio(titulo), titulo) if t]:
            nome = banco.um(conn, "SELECT c.nome FROM condominios c WHERE c.id = nai_condominio_da_pergunta(%s)", (texto,))
            if nome:
                return nome
        return None
    except Exception:  # noqa: BLE001 -- sem o prédio, vai o título
        conn.rollback()
        log.exception("o prédio do anúncio %s não foi achado", a.get("olx_id"))
        return None


# 488 (Pedro, 24/10: "faz parceria no Kopenhagen?"): quem escreve ao 8595 pedindo parceria, ou dizendo que é corretor, não é
# cliente: vai para a Nay Corretores. "corretor" solto não vale (o cliente fala "o corretor me disse").
CORRETOR_NO_TEXTO = re.compile(r"parceria|parceir[oa]s?\b|\bcreci\b|\bsou (?:a |o )?corretor|\bsou (?:da|do) imobili|"
                               r"\bsomos (?:uma )?imobili|\btrabalho (?:com|na|no) imobili|\bcorretora? de im[oó]veis", re.I)


def parece_corretor(texto: str | None) -> bool:
    return bool(CORRETOR_NO_TEXTO.search(texto or ""))


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
    # 23/10: no modo sim, a busca que só foi perguntada em teste é refeita de verdade já (antes esperava OLX_DE_NOVO_H)
    so_teste = "" if c["olx"] == "teste" else \
        " OR (olx_em < now() - interval '10 minutes' AND NOT jsonb_path_exists(olx, '$[*] ? (@.teste == false)'))"
    for b in banco.linhas(conn, f"""SELECT * FROM privado.busca_cliente WHERE estado = 'buscando'
                                     AND (olx_em IS NULL OR olx_em < now() - interval '{OLX_DE_NOVO_H} hours'{so_teste})
                                   ORDER BY olx_em NULLS FIRST, id LIMIT 4"""):
        # sem valor no perfil a base da OLX traria de tudo (no teste de 22/10, casas de R$ 1,6 a 2 mi): espera o valor
        if not pronto(b["filtros"]) or not b["filtros"].get("teto") or abaixo_do_minimo(b["filtros"], c):
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
        if b["filtros"].get("so_condominio") and b["filtros"].get("condominio"):
            # 27/10: só no condomínio que ela disse (o Sr. Karis, "só no Ponta Negra Village"): o título tem de citá-lo
            alvo = re.sub(r"^(residencial|condominio|cond)\s+", "", whatsapp._normal(b["filtros"]["condominio"]))
            cands = [a for a in cands if alvo and alvo in whatsapp._normal(a.get("titulo"))]
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
                # Tel, 28/10: "ela precisa enviar o link do imóvel para depois a gente clicar para saber se esse imóvel
                # pelo perfil vai atender o cliente"; Pedro: só no CRM (ao anunciante continua sem link, 23/10). Vira
                # nota interna na conversa do anunciante (511)
                banco.um(conn, "SELECT nay_aviso_equipe('nay-olx', 'nota', 'Anúncio da OLX', %s, %s)",
                         (nota_do_anuncio(a, b), tel))
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
# 488 (Pedro, 24/10): a NAY CORRETORES, agente próprio do corretor que escreve no número de leads (8595).
PROMPT_CORRETOR = """Você é a Nay Corretores, da Imob Easy, imobiliária de Manaus. Você conversa pelo WhatsApp SÓ com CORRETORES.
O corretor chegou de um destes jeitos (veja "COMO CHEGOU"): respondeu um pedido que fizemos nos grupos de corretores,
respondeu a pergunta que fizemos no anúncio dele na OLX, ou escreveu pedindo parceria.
O objetivo: cadastrar na nossa base o imóvel que ele tem (como imóvel de parceiro) e, se ele servir para uma das nossas
BUSCAS ATIVAS, apresentar ao cliente. Trabalhamos em parceria (se ele perguntar a divisão: meio a meio, 50%).

O roteiro:
1. Ele ainda não mandou o imóvel: peça, curto: "Pode me mandar o imóvel que você tem?" (esta é a conversa de quem veio
   do grupo). Se ele perguntou antes se fazemos parceria (ex.: "faz parceria no Kopenhagen?"), responda em UMA frase que
   sim, trabalhamos em parceria com corretores (se "CONDOMÍNIO QUE ELE CITOU" mostrar imóveis nossos nele, pode dizer que
   temos imóveis lá, sem inventar quais), e peça o imóvel na mesma mensagem.
2. Ele mandou o imóvel (texto, áudio transcrito ou fotos): anote tudo no "imovel". Veja o que ainda falta para o cadastro
   (em "JÁ ANOTADO") e pergunte SÓ o que falta, no máximo 2 coisas por vez. Fotos: peça que mande por aqui.
3. Cadastro completo: agradeça e diga que já cadastrou e que, aparecendo cliente, a gente chama. Se o imóvel serve para
   uma busca ativa, não diga nada do cliente.

Regras:
- Português do Brasil, curto e simpático, como gente. No máximo 2 balões. Pouco emoji.
- Nunca diga o nome, o telefone ou qualquer dado do cliente.
- Para o cadastro precisamos de: tipo, finalidade (aluguel ou venda), bairro, condomínio (se for apartamento ou casa em
  condomínio), quartos, valor, taxa de condomínio (se houver), mobília (na locação) e pelo menos 3 fotos.
- O imóvel entra na nossa base MESMO que não sirva para nenhuma busca agora: "serve" é só sobre as buscas ativas.
- Se ele perguntar algo do cliente que você não sabe (data de mudança, renda, documentos), diga que vai confirmar.
- Se a conversa não é sobre imóvel nem parceria (outro assunto, propaganda, corrente), não responda.

Devolva SÓ JSON:
{"responder": true|false,
 "oferece_imovel": true|false,
 "busca_id": <id da busca que o imóvel atende, ou null>,
 "serve": "sim" | "nao" | "talvez",
 "imovel": {"tipo": "", "finalidade": "locacao|venda", "bairro": "", "condominio": "", "quartos": 0, "suites": 0,
            "vagas": 0, "area": 0, "valor": 0, "taxa_condominio": 0, "mobilia": "mobiliado|com modulados e ar|sem nada|",
            "andar": "", "observacao": ""},
 "baloes": ["..."]}
"oferece_imovel" = true quando ele falou de um imóvel que TEM (mesmo que ainda incompleto). No "imovel", ponha só o que
ele disse (o resto vazio ou 0)."""

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


COMO_CHEGOU = {"grupo": "respondeu um pedido que fizemos nos grupos de corretores",
               "olx": "é o anunciante da OLX a quem perguntamos se o imóvel dele estava disponível e se aceita parceria",
               "parceria": "escreveu pedindo parceria ou disse que é corretor"}


def condominio_citado(conn, conversa: list[dict]) -> str:
    """O condomínio que o corretor citou (o nome inteiro dentro do que ele escreveu) e quantos imóveis nossos há nele."""
    texto = " ".join((m["texto"] or "") for m in conversa if m["direcao"] == "recebida")[-1500:]
    if not texto.strip():
        return ""
    r = banco.linhas(conn, """
        SELECT k.nome, (SELECT count(*) FROM imoveis i WHERE i.condominio_nome = k.nome AND i.status = 'Disponível'
                           AND NOT coalesce(i.e_parceiro, false)) AS nossos,
               (SELECT count(*) FROM imoveis i WHERE i.condominio_nome = k.nome AND i.status = 'Disponível'
                   AND coalesce(i.e_parceiro, false)) AS de_parceiro
          FROM condominios k
         WHERE length(k.nome) >= 5 AND position(lower(unaccent(k.nome)) in lower(unaccent(%s))) > 0
         ORDER BY length(k.nome) DESC LIMIT 1""", (texto,))
    if not r:
        return ""
    return f"{r[0]['nome']}: {r[0]['nossos']} imóvel(is) nosso(s) e {r[0]['de_parceiro']} de parceiro, Disponíveis"


def _turno_corretor(conn, cor: dict, conversa: list[dict], ativas: list[dict], fotos: int) -> str:
    linhas = [f"COMO CHEGOU: {COMO_CHEGOU.get(cor.get('origem') or '', 'escreveu para o nosso número')}.",
              f"CONDOMÍNIO QUE ELE CITOU: {condominio_citado(conn, conversa) or 'nenhum que a gente tenha cadastrado'}", "",
              "BUSCAS ATIVAS (id: o que o cliente procura):"]
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


def cadastrar(conn, cor: dict, b: dict | None, ativo: bool) -> int:
    """O imóvel do corretor no nosso cadastro, como imóvel de PARCEIRO. Rascunho enquanto falta dado; completo, Disponível
    (ativo=True). Devolve o código."""
    im = cor["imovel"] or {}
    loc = str(im.get("finalidade") or "").startswith("loc")
    valor = None
    try:
        valor = float(im.get("valor") or 0) or None
    except (TypeError, ValueError):
        pass
    extras = {"corretor_parceiro": cor.get("nome") or "", "corretor_telefone": cor["telefone"],
              "busca_cliente": str(b["id"]) if b else "",
              "cadastrado_pelo": "Nay Corretores" + (" (busca do cliente)" if b else f" ({cor.get('origem') or 'corretor'})"),
              "observacao_do_corretor": str(im.get("observacao") or "")}
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
        whatsapp._ao_crm(f"Busca do cliente {whatsapp.quem(lead)}: o corretor {cor.get('nome') or ''} ({grupo.telefone_bonito(cor['telefone'])}) "
                         f"ofereceu o imóvel #{codigo}, já cadastrado como parceiro. A conversa do cliente está com a equipe: "
                         f"apresentem por lá.")
        return "grupo"
    return _mandar_ao_cliente(conn, lead, [codigo])


def _mandar_ao_cliente(conn, lead: dict, codigos: list[int]) -> str:
    """Os imóveis um de cada vez (card, fotos, espera as fotos, o próximo) e uma pergunta no fim."""
    um = len(codigos) == 1
    whatsapp.mandar_texto(conn, lead, "Boa notícia! Encontrei uma opção que combina com o que você procura:" if um else
                          f"Boa notícia! Encontrei {len(codigos)} opções que combinam com o que você procura:")
    enviados = list(lead.get("enviados") or [])
    for n, codigo in enumerate(codigos):
        time.sleep(whatsapp.DEPOIS_DAS_FOTOS_S if n else whatsapp.ENTRE_ENVIOS_S)
        whatsapp.mandar_imovel(conn, lead, codigo)
        if codigo not in enviados:
            enviados.append(codigo)
            whatsapp._marcar(conn, lead["id"], enviados=enviados)
    time.sleep(whatsapp.DEPOIS_DAS_FOTOS_S)
    whatsapp.mandar_texto(conn, lead, "O que achou dessa? Se gostar, já vejo a visita para você." if um else
                          "Alguma delas te agradou? Me diz qual e já vejo a visita para você.")
    conn.commit()
    return "cliente"


def opcoes_enviadas(b: dict) -> int:
    """Quantos imóveis diferentes a busca já pôs na frente dela (o da base e o do corretor)."""
    return len({int(x["codigo"]) for x in b.get("ofertas") or [] if x.get("codigo") and x.get("estado") in ("cliente", "grupo")})


def _fechar_se_completa(conn, b: dict, ofertas: list[dict]) -> bool:
    """A busca termina quando ela recebeu OPCOES_META opções; antes disso grupos, OLX e base continuam."""
    if opcoes_enviadas({"ofertas": ofertas}) < OPCOES_META:
        return False
    banco.um(conn, "UPDATE privado.busca_cliente SET estado = 'ofertado', ofertado_em = now() WHERE id = %s", (b["id"],))
    passo(conn, b["id"], "oferta", f"Busca concluída: {opcoes_enviadas({'ofertas': ofertas})} opções enviadas ao cliente")
    return True


def recentes(conn, codigos) -> dict[int, dict]:
    """codigo -> {recente, ano, nome}: o condomínio do imóvel na lista de condomínios (condominio_proximo, pelo condo_id).
    Fora da lista = não recente."""
    cods = [int(c) for c in codigos if c]
    if not cods:
        return {}
    return {int(r["codigo"]): r for r in banco.linhas(conn, """
        SELECT i.codigo, coalesce(bool_or(p.recente), false) AS recente, max(p.ano) AS ano, max(i.condominio_nome) AS nome
          FROM imoveis i LEFT JOIN condominio_proximo p ON p.condo_id = i.condo_id
         WHERE i.codigo = ANY(%s) GROUP BY i.codigo""", (cods,))}


def quer_recente(conn, lead: dict, f: dict) -> str | None:
    """Por que esta pessoa quer condomínio novo, ou None (o padrão não entra na nota): pediu condomínio novo, veio pelo
    anúncio de um condomínio recente (o da conversa da OLX, o link da OLX ou do site que colou) ou citou um recente."""
    if str(f.get("condominio_novo")).lower() == "true":
        return "pediu condomínio novo"
    conversa = banco.linhas(conn, """SELECT direcao, texto FROM captacao_mensagens
                                      WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = right(%s, 8)
                                      ORDER BY criada_em""", (lead.get("telefone") or "",)) if lead.get("telefone") else []
    refs = [lead.get("codigo")] + whatsapp.codigos_dos_links(conn, conversa, ate=10)
    for m in conversa:
        if m["direcao"] == "recebida":
            refs += [int(c) for c in re.findall(r"imobeasy\.com/imoveis/(\d{3,5})", m["texto"] or "")]
    for c in refs:
        x = recentes(conn, [c]).get(int(c)) if c else None
        if x and x["recente"]:
            return f"veio pelo {x['nome']}" + (f" ({x['ano']})" if x.get("ano") else "")
    citados = [whatsapp._normal(n) for n in [f.get("condominio")] + list(f.get("referencias") or []) if n]
    if citados:
        for r in banco.linhas(conn, "SELECT nome, ano FROM condominio_proximo WHERE recente"):
            nome = whatsapp._normal(r["nome"])
            if any(c and (c in nome or nome in c) for c in citados):
                return f"citou o {r['nome']}" + (f" ({r['ano']})" if r.get("ano") else "")
    return None


def com_padrao(pares: list[dict], classe: dict[int, dict], motivo: str) -> list[dict]:
    """Junta o critério "padrão do condomínio" à nota de cada par (peso PESO_PADRAO sobre os 100 dos outros) e reordena:
    recente vale 100, o resto 0. Os pesos e pontos dos outros itens são reescalados para a soma continuar 100."""
    total = 100 + PESO_PADRAO
    saida = []
    for p in pares:
        x = classe.get(int(p["codigo"])) or {}
        rend = 100.0 if x.get("recente") else 0.0
        nome = x.get("nome") or "condomínio"
        texto = (f"{nome} é recente" + (f" ({x['ano']})" if x.get("ano") else "") if rend
                 else f"{nome} não é condomínio recente") + f"; ele {motivo}"
        detalhe = [{**d, "peso": round((d.get("peso") or 0) * 100 / total, 1),
                    "pontos": round((d.get("pontos") or 0) * 100 / total, 1)} for d in p.get("detalhe") or []]
        detalhe.append({"criterio": "padrao", "rendimento": rend, "texto": texto,
                        "peso": round(PESO_PADRAO * 100 / total, 1), "pontos": round(PESO_PADRAO * rend / total, 1)})
        saida.append({**p, "nota": round((p["nota"] * 100 + PESO_PADRAO * rend) / total, 1), "detalhe": detalhe})
    saida.sort(key=lambda p: -p["nota"])
    return saida


def opcoes_da_base(conn, lead: dict, f: dict, excluir: list[int], quantas: int) -> list[dict]:
    """As melhores opções da nossa base pela NOTA da Captação ativa (Pedro, 23/10: "deve usar aquele mesmo algoritmo
    de julgamento de imóvel da aba captação ativa que dá notas, para achar mais opções"): o código de /root/nay-grupos
    (catálogo, resolvedor de lugares, pontuar e o config.json de lá), o mesmo que a busca na OLX já usa. Entra o bairro
    pedido e o vizinho colado (divisa, até VIZINHO_ATE_KM), na faixa de valor firme, nota a partir do corte amarelo (70);
    o melhor primeiro. Depois, a regra de quem
    pode receber cada imóvel (olx_imovel_vai_ao_cliente: o parceiro só ao cliente final)."""
    from olx import busca_olx as bo
    regras, _ = bo.gregras.carregar(bo.REGRAS_DOS_GRUPOS)
    imoveis, vizinhos = bo.gcatalogo.carregar(conn, com_parceiro=f.get("aceita_parceiro") == "true")
    pedido = bo.pedido_dos_filtros(f, bo.glugares.Lugares(conn), da_base=True)
    if not pedido.get("tipo"):
        imoveis = [i for i in imoveis if i["tipo"] in ("apartamento", "casa")]   # sem tipo dito: só residencial (como a busca da Nay)
    if "condom" in str(f.get("tipo") or "").lower():
        # a nota junta casa e casa de condomínio em "casa"; quem pediu condomínio não recebe casa de rua (o Luiz Paulo, 23/10)
        imoveis = [i for i in imoveis if "condom" in bo.normal(i.get("tipo_cadastro"))]
    fora = set(excluir)
    imoveis = [i for i in imoveis if int(i["codigo"]) not in fora]
    teto = pedido.get("preco_max")
    if teto:
        valor = "valor_venda" if pedido.get("operacao") == "venda" else "valor_aluguel"
        imoveis = [i for i in imoveis if i.get(valor) and teto * (1 - FAIXA_ABAIXO) <= i[valor] <= teto * (1 + FAIXA_ACIMA)]
    # o mapa apertado: o par posto à mão na tabela de vizinhos (sem km) continua valendo
    vizinhos = {a: {b: v for b, v in vs.items() if v.get("km") is None or (v.get("divisa") and v["km"] <= VIZINHO_ATE_KM)}
                for a, vs in vizinhos.items()}
    padrao = quer_recente(conn, lead, f)
    # com o padrão a ordem muda depois da nota: pede a lista inteira para o recente de nota menor não ficar de fora
    regras = {**regras, "alternativas": 200 if padrao else max(0, quantas * 3 - 1)}   # sobra para os que não podem ir a ela
    limite = datetime.now(timezone.utc) - timedelta(days=regras["confirmado_dias"])
    r = bo.gpontuar.melhores(pedido, imoveis, regras, vizinhos, limite)
    if padrao:
        r["pares"] = com_padrao(r["pares"], recentes(conn, [p["codigo"] for p in r["pares"]]), padrao)
    saida = []
    # 24/10: "perto de X" é do banco (distância do centro dos bairros), nunca da Nay
    perto = {x["bairro"] for x in whatsapp.so_perto(conn, [{"bairro": p["imovel"].get("bairro")} for p in r["pares"]], f)}
    for p in r["pares"]:
        if p["nota"] < regras["cortes"]["amarelo"] or len(saida) >= quantas:
            break
        if f.get("perto_de") and p["imovel"].get("bairro") not in perto:
            continue
        if whatsapp._ofertavel(conn, int(p["codigo"]), lead):
            saida.append({"codigo": int(p["codigo"]), "nota": p["nota"]})
    return saida


def base_volta(conn, c: dict) -> int:
    """O imóvel que entrou na nossa base DEPOIS da busca (Pedro, 23/10: "esse novo imóvel cadastrado no grupo de
    cadastro não está aparecendo para a lead"). A base só era olhada quando a lead escrevia; a busca criada da conversa
    (a Edsandra, lead 45) nunca olhou, e tinha o 3841 e o 4020 no perfil. A cada BASE_A_CADA_MIN, a busca ATIVA (só
    'buscando': as 'perfil' são dezenas de leads antigas) contra o catálogo pela nota da Captação ativa (opcoes_da_base),
    fora o que ela já recebeu ou já foi oferecido; de uma vez o que couber até OPCOES_MAX (a espera de um por dia saiu:
    com ela, as opções que já estavam na base só chegavam nos dias seguintes).
    A conversa com a equipe: nada sai (Pedro, 23/10: o aviso "apresentem por lá" no grupo "não precisa"); a busca
    espera a conversa voltar para a Nay."""
    if not no_horario(c):
        return 0
    feitos = 0
    for b in banco.linhas(conn, f"""SELECT * FROM privado.busca_cliente WHERE estado = 'buscando'
                                     AND (base_em IS NULL OR base_em < now() - interval '{BASE_A_CADA_MIN} minutes')
                                   ORDER BY base_em NULLS FIRST, id LIMIT 6"""):
        banco.um(conn, "UPDATE privado.busca_cliente SET base_em = now() WHERE id = %s", (b["id"],))
        conn.commit()
        if not pronto(b["filtros"]):
            continue
        lead = whatsapp._lead(conn, b["lead"])
        if not lead or lead.get("humano_em") or whatsapp.oferta_sozinha_espera(conn, lead, b["filtros"]):
            continue
        ofertas = list(b["ofertas"] or [])
        if _fechar_se_completa(conn, b, ofertas):
            conn.commit()
            continue
        f = dict(b["filtros"])
        if whatsapp._aceita_parceiro(conn, lead):
            f["aceita_parceiro"] = "true"
        oferecidos = [int(x["codigo"]) for x in ofertas if x.get("codigo")]
        excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else []) + oferecidos
        achados = opcoes_da_base(conn, lead, f, excluir, OPCOES_MAX - opcoes_enviadas(b))
        if not achados:
            continue
        codigos = [a["codigo"] for a in achados]
        onde = _mandar_ao_cliente(conn, lead, codigos)
        em = datetime.now(MANAUS).isoformat(timespec="minutes")
        novas = [{"codigo": a["codigo"], "de": "base", "nota": a["nota"], "em": em, "estado": onde, "teste": False}
                 for a in achados]
        banco.um(conn, "UPDATE privado.busca_cliente SET ofertas = ofertas || %s::jsonb WHERE id = %s",
                 (json.dumps(novas, ensure_ascii=False), b["id"]))
        passo(conn, b["id"], "oferta", "Nossa base: " + ", ".join(f"#{a['codigo']} (nota {a['nota']:g})" for a in achados)
              + f" pela nota da Captação ativa; {'enviado' if len(achados) == 1 else 'enviados'} ao cliente")
        _fechar_se_completa(conn, b, ofertas + novas)
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
        origem = banco.um(conn, """SELECT CASE WHEN EXISTS (SELECT 1 FROM privado.busca_contato c WHERE c.telefone8 = %s) THEN 'olx'
                                      WHEN EXISTS (SELECT 1 FROM privado.busca_grupo_membro g WHERE g.telefone8 = %s) THEN 'grupo'
                                      ELSE 'parceria' END""", (t8, t8))
        banco.um(conn, """INSERT INTO privado.busca_corretor (telefone8, telefone, nome, origem, classificado_em) VALUES (%s, %s,
                            (SELECT nome FROM corretores WHERE right(regexp_replace(telefone, '\\D', '', 'g'), 8) = %s LIMIT 1), %s, now())
                          ON CONFLICT (telefone8) DO UPDATE SET origem = coalesce(busca_corretor.origem, EXCLUDED.origem),
                              classificado_em = coalesce(busca_corretor.classificado_em, now())""",
                 (t8, re.sub(r"\D", "", p["telefone"]), t8, origem))
        cor = banco.linhas(conn, "SELECT * FROM privado.busca_corretor WHERE telefone8 = %s", (t8,))[0]
        conversa = _conversa_corretor(conn, t8)
        # a equipe escreveu para ele pelo 8595 depois que a Nay começou: a conversa é dela
        if any(m["direcao"] == "enviada" and m["origem"] == "humano" and m["id"] > (cor["ultima_lida"] or 0) for m in conversa):
            banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'humano', humano_em = now(), ultima_lida = %s WHERE telefone8 = %s",
                     (p["ate"], t8))
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
        if r.get("oferece_imovel") and (not b or r.get("serve") != "nao"):
            # 488: o imóvel do corretor entra na base mesmo sem busca que sirva ("serve" é só das buscas ativas)
            im = juntar_imovel(cor.get("imovel") or {}, r.get("imovel") or {})
            banco.um(conn, """UPDATE privado.busca_corretor SET imovel = %s::jsonb, busca = %s, estado = 'cadastrando'
                               WHERE telefone8 = %s""", (json.dumps(im, ensure_ascii=False), b["id"] if b else None, t8))
            cor = {**cor, "imovel": im, "busca": b["id"] if b else None}
            primeira = not cor.get("codigo")
            falta = falta_no_imovel(im, fotos)
            completo = not falta and c["corretor"] == "sim"
            codigo = cadastrar(conn, cor, b, ativo=completo)
            banco.um(conn, "UPDATE privado.busca_corretor SET codigo = %s WHERE telefone8 = %s", (codigo, t8))
            if primeira and b:
                banco.um(conn, "UPDATE privado.busca_cliente SET ofertas = ofertas || %s::jsonb WHERE id = %s",
                         (json.dumps([{"tel": cor["telefone"], "nome": cor.get("nome"), "codigo": codigo,
                                       "em": datetime.now(MANAUS).isoformat(timespec="minutes"), "estado": "cadastrando"}], ensure_ascii=False), b["id"]))
                passo(conn, b["id"], "corretor", f"Corretor {cor.get('nome') or ''} (…{t8[-4:]}) ofereceu um imóvel: pré-cadastro #{codigo}")
            if not falta and not b:
                # 488: cadastro completo e nenhuma busca em vista: a Nay dos leads recebe a opção nova (a nossa base é
                # olhada de novo agora por todas as buscas abertas) e o corretor sabe que ficou cadastrado
                banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'ofertado' WHERE telefone8 = %s", (t8,))
                banco.um(conn, "UPDATE privado.busca_cliente SET base_em = NULL WHERE estado = 'buscando'")
                log.info("corretor …%s: imóvel #%s cadastrado; as buscas abertas olham a base de novo", t8[-4:], codigo)
                if not baloes:
                    baloes = ["Perfeito, já cadastrei aqui. Quando aparecer um cliente para ele eu te chamo!"]
            elif not falta:
                onde = oferecer_ao_cliente(conn, b, codigo, cor, c)
                if onde in ("cliente", "grupo"):
                    # 23/10: um imóvel não fecha a busca; ela segue até OPCOES_META opções (_fechar_se_completa)
                    ofertas = banco.um(conn, """
                        UPDATE privado.busca_cliente SET ofertas = (
                               SELECT coalesce(jsonb_agg(CASE WHEN o->>'codigo' = %s::text THEN o || jsonb_build_object('estado', %s::text)
                                                              ELSE o END ORDER BY n), '[]'::jsonb)
                                 FROM jsonb_array_elements(ofertas) WITH ORDINALITY AS x(o, n))
                         WHERE id = %s RETURNING ofertas""", (codigo, onde, b["id"]))
                    _fechar_se_completa(conn, b, ofertas or [])
                    banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'ofertado' WHERE telefone8 = %s", (t8,))
                    banco.um(conn, "UPDATE privado.busca_cliente SET base_em = NULL WHERE estado = 'buscando' AND id <> %s", (b["id"],))
                passo(conn, b["id"], "oferta", {"cliente": f"Imóvel #{codigo} completo e oferecido ao cliente",
                                                "grupo": f"Imóvel #{codigo} completo; o cliente está com a equipe: avisado no grupo",
                                                "teste": f"Imóvel #{codigo} completo (teste: não foi ao cliente)"}[onde])
                if not baloes:
                    baloes = ["Perfeito, cadastrei aqui e já apresentei ao meu cliente. Assim que ele der retorno eu te chamo!"]
            elif b:
                passo(conn, b["id"], "corretor", f"#{codigo}: falta {', '.join(falta)}")
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
    # a ordem de cada volta: o que está abaixo do mínimo sai; depois a nossa base e, juntos, grupos e OLX; os corretores
    for nome, f in (("minimo", lambda: encerrar_abaixo_do_minimo(conn, c)),
                    ("membros", lambda: atualizar_membros(conn)), ("base", lambda: base_volta(conn, c)),
                    ("grupos", lambda: grupos_volta(conn, c)), ("grupos_repete", lambda: grupos_repete(conn, c)),
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
