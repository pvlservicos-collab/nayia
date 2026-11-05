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
from difflib import SequenceMatcher

from olx import banco, fotos_olx, grupo, modelo, whatsapp

log = logging.getLogger("nay-olx.buscas")
MANAUS = timezone(timedelta(hours=-4))
A_CADA_S = 20
OLX_DE_NOVO_H = 6              # a mesma busca olha a base da OLX de novo depois disto (a base cresce com o scrap)
CONTATO_DE_NOVO_H = 24         # o mesmo anunciante não é chamado de novo antes disto, nem por outra busca
MEMBROS_A_CADA_S = 6 * 3600
BASE_A_CADA_MIN = 30           # a busca aberta olha a nossa base de novo depois disto (imóvel novo no perfil vai à lead)
# Pedro, 23/10: "o ideal não é ter um imóvel enviado e sim 3 a 5 opções; ela não deve parar na hora de achar um imóvel"
OPCOES_META = 5                # a busca só termina ('ofertado') quando a lead recebeu tantas opções (Pedro, 29/10: mínimo 5 para cada lead)
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
    # 04/11 (a notinha "Nay foi falar com"): uma por pedido, na primeira vez que ele vai a um grupo de verdade
    ja_nos_grupos = {b["id"] for b in buscas if any(not x.get("teste") for x in b["grupos"] or [])}
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
            if not teste and b["id"] not in ja_nos_grupos:
                ja_nos_grupos.add(b["id"])
                whatsapp.nota_nay_foi(conn, whatsapp._lead(conn, b["lead"]),
                                      f"Nay foi pedir nos grupos de corretores (começou pelo {g['nome']}): {resumo(b['filtros'])}.")
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


def abrir_com_o_anunciante(conn, tel: str, texto: str, nome: str | None, motivo: str) -> str | None:
    """Pedro, 04/11 ("já tínhamos conversa com esse número, é a Ana, e a Nay fica começando conversa pelo número de
    leads, NUNCA PARA ELA FAZER ISSO"): quem já conversa conosco na Parceria é abordado POR LÁ (a regra 492/493 do dono);
    só quem nunca falou conosco recebe a abertura pelo 8595. Devolve o id da mensagem (ou 'saida:<id>' na Parceria)."""
    # qualquer conversa na Parceria vale (recebida OU enviada, ou só o contato), não só a que ele escreveu
    if banco.um(conn, """SELECT nay_leads_linha_do_dono(%(t)s) = 'parceria'
                             OR EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = nai_chave(%(t)s))
                             OR EXISTS (SELECT 1 FROM nai_contato c WHERE c.chave = nai_chave(%(t)s))""", {"t": tel}):
        sid = banco.um(conn, "SELECT nay_leads_mandar_pela_parceria(%s, %s, %s, %s, NULL)", (tel, texto, nome or None, motivo[:200]))
        if sid:
            log.info("olx: …%s já conversa na Parceria: a abertura foi por lá (saída %s)", tel[-4:], sid)
            return f"saida:{sid}"
        log.warning("olx: …%s conversa na Parceria mas ela não aceitou; a abertura NÃO sai pelo 8595", tel[-4:])
        raise RuntimeError("a Parceria não aceitou e o contato já conversa lá: não abrir pelo 8595")
    mid = _enviar(tel, texto)
    _guardar_enviada(conn, tel, texto, mid)
    return mid


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
                               r"\bsomos (?:uma )?imobili|\btrabalho (?:com|na|no) imobili|\bcorretora? de im[oó]veis|"
                               # 04/11 (…1953734): o questionário automático de imobiliária ("antes de iniciarmos uma conversa…
                               # PROCURAS casa para IMEDIATO…") é de corretor qualificando cliente, não de cliente
                               r"\bantes de iniciarmos\b|\bprocuras\b", re.I)


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
                mid = abrir_com_o_anunciante(conn, tel, texto, a.get("anunciante"), f"busca {b['id']}: anúncio OLX {a['olx_id']}")
                banco.um(conn, """INSERT INTO privado.busca_contato (telefone8, telefone, busca, de, olx_id, nome)
                                  VALUES (%s, %s, %s, 'anunciante_olx', %s, %s)""",
                         (tel[-8:], tel, b["id"], a["olx_id"], a.get("anunciante")))
                # Tel, 28/10: "ela precisa enviar o link do imóvel para depois a gente clicar para saber se esse imóvel
                # pelo perfil vai atender o cliente"; Pedro: só no CRM (ao anunciante continua sem link, 23/10). Vira
                # nota interna na conversa do anunciante (511)
                banco.um(conn, "SELECT nay_aviso_equipe('nay-olx', 'nota', 'Anúncio da OLX', %s, %s)",
                         (nota_do_anuncio(a, b), tel))
                # 04/11: e na conversa do cliente, a notinha de com quem a Nay foi falar por ele
                whatsapp.nota_nay_foi(conn, whatsapp._lead(conn, b["lead"]),
                                      f"Nay foi falar com {a.get('anunciante') or 'o anunciante'} (anunciante da OLX, …{tel[-4:]}): "
                                      f"perguntou se \"{a.get('titulo') or 'o anúncio'}\" ({dinheiro(a.get('preco'))}, "
                                      f"{a.get('bairro') or '-'}) está disponível e se aceita parceria.")
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
# ONDE VAI CADA INFORMAÇÃO EXTRA DO CADASTRO (Pedro, 02/11/2026: "em observações deve estar negócio, se aceita pet, se aceita
# pôr mais mobília, e não informações internas; se colocar armário fica mais X ... se não tem nada ela não marca nada").
# A MESMA regra da Nay do grupo de cadastro (nay-cadastro/cadastro/modelo.py, REGRA_DOS_CAMPOS).
REGRA_DOS_CAMPOS = """ONDE VAI CADA INFORMAÇÃO EXTRA DO IMÓVEL (três campos; nada se repete em dois deles):
- observacao: SAI NO CARD, para o cliente. SÓ condição do NEGÓCIO: se aceita ou não pet; se o dono aceita pôr ou tirar
  mobília ou ar ("com os armários fica R$ 300 a mais"); a partir de quando está disponível; se aceita permuta; outra
  condição do aluguel ou da venda (duas cauções, só à vista). Frase curta. Se ele não disse nada disso, deixe VAZIO:
  nunca ponha característica do imóvel aqui, nem invente.
- descricao: NÃO sai no card; a Nay lê quando o cliente pergunta. Os detalhes do imóvel e do lugar que não têm campo
  próprio: cômodos, acabamento, vista, nascente, armários, ar-condicionado, energia solar, edícula, rua fechada, perto de
  quê, estado de conservação.
- interno: SÓ a equipe vê. O que não é para o cliente: comissão, valor líquido, saldo devedor ou financiamento do dono,
  nome do dono, situação da documentação, recado do corretor para nós, a disponibilidade que ainda vamos confirmar."""


PROMPT_CORRETOR = """Você é a Nay Corretores, da Imob Easy, imobiliária de Manaus. Você conversa pelo WhatsApp SÓ com CORRETORES.
O corretor chegou de um destes jeitos (veja "COMO CHEGOU"): respondeu um pedido que fizemos nos grupos de corretores,
respondeu a pergunta que fizemos no anúncio dele na OLX, ou escreveu pedindo parceria.
O objetivo: cadastrar na nossa base o imóvel que ele tem (como imóvel de parceiro) e, se ele servir para uma das nossas
BUSCAS ATIVAS, apresentar ao cliente. Trabalhamos em parceria (se ele perguntar a divisão: meio a meio, 50%).
Quando ELE oferece o imóvel dele, quem visita é o NOSSO cliente: se ele falar de visita ou de horário desse imóvel, diga
só que vai confirmar com o cliente e retorna (Pedro, 30/10).

PRIMEIRO ENTENDA O QUE ELE QUER AGORA (04/11, a revisão das conversas reais) e ponha em "intencao":
- "pedido": o cliente DELE procura imóvel e ele pergunta se temos ("TEM ALGUMA COISA ATÉ 300 MIL VENDA", "Vc tem algum
  apartamento no Smile Flores, andar baixo de dois quartos?"). Também quando ele CORRIGE o pedido ("É no condomínio",
  "Não é no bairro Flores", "meu cliente só quer nesse condomínio"): ponha o pedido corrigido.
- "oferta": ele tem um imóvel e está mandando (texto, fotos, link). Uma mensagem com o NOSSO pedido do grupo (na CONVERSA
  aparece como "[ele encaminhou o NOSSO pedido do grupo ...]") e o imóvel dele é OFERTA: ele está respondendo ao nosso
  pedido, NUNCA é pedido dele.
- "visita": o cliente DELE quer visitar um imóvel NOSSO (o "ANÚNCIO NOSSO" ou um imóvel nosso que ele citou): "temos
  cliente interessado em visitar amanhã às 14:30". Não é cadastro e não existe cliente nosso nessa conversa: diga, curto,
  que vai ver o horário com a equipe e já retorna. A equipe recebe o aviso e combina com ele.
- "reclamacao": ele reclama do que mandamos ("Vc não enviou nenhuma opção", "nenhum é no condomínio", "vc tá
  enganada"). Ponha em "pedido" o pedido dele de antes (o PEDIDO DELE abaixo) com a correção que ele fez; NUNCA diga
  "tenho sim" nem "te mandei" por conta própria.
- "duvida": pergunta sobre um imóvel nosso que ele citou, ou sobre a parceria.
- "outro": cumprimento, agradecimento, outro assunto.

ELE TAMBÉM PODE PEDIR IMÓVEL (Pedro, 04/11: "mandar os imóveis e responder as solicitações dele"): o corretor tem um
cliente DELE procurando e pergunta se temos ("tem alguma coisa até 300 mil venda?", "tem apartamento 2 quartos no Parque
10?", "vc teria alguma coisa?"). Aí NUNCA peça imóvel a ele nem devolva a pergunta ("Você tem algum imóvel até 300 mil?"
é o erro de 04/11): marque "pede_imovel": true e ponha em "pedido" o pedido INTEIRO de agora, juntando o que ele já disse
antes na conversa com o que mudou (finalidade, tipo, valor máximo, bairros, condomínio, quartos, mobília). A busca nos
nossos imóveis, o envio das opções e a resposta a ele são feitos pelo sistema: nesse caso deixe "baloes" vazio.
CONDOMÍNIO DITO É OBRIGATÓRIO (04/11, o ...2985 pediu o Smile Flores cinco vezes e recebeu 18 imóveis de outros lugares):
com o condomínio no pedido, ponha "condominio" e "so_condominio": true; andar e suítes vão em "exigencias" ("andar
baixo", "pelo menos 1 suíte").
- "pede_imovel" só quando o que ele escreveu DEPOIS da sua última resposta pede imóvel, muda o pedido ou aceita o que você
  ofereceu para afrouxar ("serve com 2 quartos?" -> sim: quartos 2; "num bairro vizinho, como Dom Pedro?" -> sim: ponha
  o bairro oferecido em "bairros"; "um pouco acima de R$ 300.000?" -> sim: valor 20% maior). "Ok", "obrigado", "vou
  ver" depois das opções não são pedido: "responder" false.
- Ele pede um imóvel NOSSO pelo código ("me manda o 5742", "tem foto do 2228?"): "pede_imovel" true e o código em
  "pedido.codigos".
- Pergunta sobre um imóvel NOSSO que ele citou (código ou nome; a ficha está em "IMÓVEIS NOSSOS QUE ELE CITOU"):
  responda pela ficha, curto ("oferece_imovel" false). O que não está na ficha: diga que vai confirmar e retorna.

O QUE JÁ SABEMOS (Pedro, 30/10: "ela nunca deve perguntar coisas que já tem na OLX"): o "ANÚNCIO DA OLX" (quando há) e o
"JÁ ANOTADO" já estão certos. NUNCA pergunte nada que esteja neles: nem o tipo, nem se é venda ou locação, nem o valor,
o bairro, os quartos, a área, as vagas, a taxa ou o condomínio. Pergunte só o que faltar de verdade.
O TEXTO DELE TRAZ OS DADOS (04/11, o ...1009: "Área: 142 m²", "CONDOMÍNIO VILLAGE VERT" e "R$ 660.000,00" no mesmo texto, e
a Nay perguntou o valor, a área e o condomínio): leia o texto INTEIRO, até o fim (o valor costuma vir no final), e ponha
no "imovel" tudo o que ele já disse. Suítes são quartos: "Casa com 3 suítes" = quartos 3 e suites 3. "Duplex" e
"sobrado" sem dizer apartamento são casa. Pergunta que está em "JÁ PERGUNTADO" não se repete: se ele não respondeu, siga
sem isso. Fotos mandadas como ARQUIVO (documento) contam como fotos: nunca diga que não chegaram.
UM IMÓVEL POR VEZ (04/11, o ...8020 mandou o Conquista Torquato e o Jardim Paradiso juntos e virou um cadastro só): o
"imovel" é UM imóvel. Se ele mandou mais de um, o primeiro vai em "imovel" e os outros, cada um, em "mais_imoveis". Se o
imóvel de agora NÃO é o do "JÁ ANOTADO" (outro condomínio, outro bairro, outra finalidade, outro valor), marque
"outro_imovel": true e ponha em "imovel" só o de agora.
Valor acima de R$ 100 mil é SEMPRE venda; valor até R$ 30 mil é SEMPRE aluguel (R$ 3.200 é aluguel, mesmo que ele
escreva "vendo ou alugo"). Com o valor dito, nunca pergunte se é venda ou aluguel (Pedro, 03/11).

O roteiro:
1. Ele ainda não mandou o imóvel e NÃO está pedindo imóvel: peça, curto: "Pode me mandar o imóvel que você tem?" (esta é a conversa de quem veio
   do grupo). Se ele perguntou antes se fazemos parceria (ex.: "faz parceria no Kopenhagen?"), responda em UMA frase que
   sim, trabalhamos em parceria com corretores (se "CONDOMÍNIO QUE ELE CITOU" mostrar imóveis nossos nele, pode dizer que
   temos imóveis lá, sem inventar quais), e peça o imóvel na mesma mensagem.
2. Ele mandou o imóvel (texto, áudio transcrito, fotos ou o link da OLX): anote tudo no "imovel". O que ainda falta para o
   cadastro vem em "FALTA PARA O CARD": pergunte SÓ isso, no máximo 2 coisas por vez. Fotos: peça que mande por aqui.
3. Cadastro completo: agradeça e diga que vai passar a opção para o cliente e que, se ele se interessar, você entra em
   contato para agendar uma visita. NUNCA diga ao corretor que cadastrou, que vai cadastrar ou que o imóvel está na nossa
   base (Pedro, 29/10: o cadastro é coisa nossa, o corretor só precisa saber que o cliente vai ver a opção). Se o imóvel
   serve para uma busca ativa, não diga nada do cliente além disso.

Regras:
- Português do Brasil, curto e simpático, como gente. No máximo 2 balões. Pouco emoji.
- Nunca diga o nome, o telefone ou qualquer dado do cliente.
- Diga sempre "cliente", nunca "lead": o corretor não sabe o que é lead.
- Para o cadastro (o que vai no card ao cliente) precisamos de: tipo, finalidade (aluguel ou venda), bairro, condomínio
  (se for apartamento ou casa em condomínio), quartos, área (m²), valor, mobília (na locação) e pelo menos 3 fotos; a
  taxa de condomínio e as vagas, se ele souber.
- O imóvel entra na nossa base MESMO que não sirva para nenhuma busca agora: "serve" é só sobre as buscas ativas.
- Se ele perguntar algo do cliente que você não sabe (data de mudança, renda, documentos), diga que vai confirmar.
- Se a conversa não é sobre imóvel nem parceria (outro assunto, propaganda, corrente), não responda.
- Nunca fale em imóvel "de parceria" ou "de parceiro" nosso (Tel, 28/09: "ela nunca pode falar isso").

Devolva SÓ JSON:
{"intencao": "pedido|oferta|visita|reclamacao|duvida|outro",
 "responder": true|false,
 "oferece_imovel": true|false,
 "pede_imovel": true|false,
 "pedido": {"codigos": [], "finalidade": "venda|locacao|", "tipo": "apartamento|casa|casa_condominio|cobertura|flat|comercial|terreno|",
            "teto": 0, "bairros": [], "condominio": "", "so_condominio": false, "quartos": 0, "mobilia": "mobiliado|semi|sem|",
            "exigencias": []},
 "busca_id": <id da busca que o imóvel atende, ou null>,
 "serve": "sim" | "nao" | "talvez",
 "outro_imovel": true|false,
 "imovel": {"tipo": "", "finalidade": "locacao|venda", "bairro": "", "condominio": "", "quartos": 0, "suites": 0,
            "vagas": 0, "area": 0, "valor": 0, "taxa_condominio": 0, "mobilia": "mobiliado|com modulados e ar|sem nada|",
            "andar": "", "observacao": "", "descricao": "", "interno": ""},
 "mais_imoveis": [],
 "baloes": ["..."]}
"oferece_imovel" = true quando ele falou de um imóvel que TEM (mesmo que ainda incompleto). No "imovel", ponha só o que
ele disse (o resto vazio ou 0). "pedido" (só com "pede_imovel"): o que o cliente DELE procura; "teto" é o valor máximo em
reais ("300 mil" = 300000, "3 mil de aluguel" = 3000); o que ele não disse fica vazio ou 0.

""" + REGRA_DOS_CAMPOS

CAMPOS_DO_IMOVEL = ("tipo", "finalidade", "bairro", "condominio", "quartos", "suites", "vagas", "area", "valor",
                    "taxa_condominio", "mobilia", "andar", "observacao", "descricao", "interno")
# os textos SOMAM de uma mensagem para a outra (o corretor conta aos poucos); os outros campos, o novo vale
CAMPOS_DE_TEXTO = ("observacao", "descricao", "interno")


def juntar_imovel(antes: dict, novo: dict) -> dict:
    d = dict(antes or {})
    for k in CAMPOS_DO_IMOVEL:
        v = (novo or {}).get(k)
        if v in (None, "", 0, "0"):
            continue
        if k in CAMPOS_DE_TEXTO and d.get(k) and str(v).strip() not in str(d[k]):
            v = v if str(d[k]) in str(v) else f"{d[k]} {v}"   # o novo já traz o antigo: fica o novo
        d[k] = v
    return d


def sem_marcas(im: dict | None) -> dict:
    """O imóvel sem as marcas internas ("_pedido", "_revisar"...), que moram no mesmo jsonb de privado.busca_corretor."""
    return {k: v for k, v in (im or {}).items() if not str(k).startswith("_")}


def marcas(im: dict | None) -> dict:
    return {k: v for k, v in (im or {}).items() if str(k).startswith("_")}


PALAVRAS_DE_CONDOMINIO = {"condominio", "cond", "residencial", "res", "edificio", "ed", "residence", "the", "torre"}


def chave_do_condominio(nome) -> str:
    """'Condomínio Smille Flores' -> 'smille flores' (para comparar nomes escritos de ouvido)."""
    return " ".join(p for p in whatsapp._normal(str(nome or "")).split() if p not in PALAVRAS_DE_CONDOMINIO)


def mesmo_condominio(a, b, limite: float = 0.8) -> bool:
    ca, cb = chave_do_condominio(a), chave_do_condominio(b)
    if not ca or not cb:
        return False
    return ca == cb or ca in cb or cb in ca or SequenceMatcher(None, ca, cb).ratio() >= limite


def _categoria(tipo) -> str:
    t = whatsapp._normal(str(tipo or ""))
    if not t:
        return ""
    if "casa" in t or "sobrado" in t or "duplex" in t:
        return "casa"
    if any(x in t for x in ("apart", "apto", "cobert", "flat", "kitnet", "studio")):
        return "apartamento"
    return t.split()[0]


def mesmo_imovel(a: dict | None, b: dict | None) -> bool:
    """04/11 (o ...8525: o Simon Bolívar, venda R$ 250 mil, num dia e o Smart Tarumã, aluguel R$ 1.600, no outro viraram o
    mesmo #9130; o ...8020 mandou dois de uma vez e virou o #9132): o que se sabe dos dois descreve o mesmo imóvel. Só
    compara o que os dois dizem: outro condomínio, outra finalidade, outro tipo, valor 30% diferente ou (sem condomínio
    nos dois) outro bairro = outro imóvel."""
    a, b = sem_marcas(a), sem_marcas(b)
    if a.get("condominio") and b.get("condominio") and not mesmo_condominio(a["condominio"], b["condominio"], 0.75):
        return False
    fa, fb = finalidade(a), finalidade(b)
    if fa and fb and fa != fb:
        return False
    va, vb = (whatsapp._num(x.get("valor")) or 0 for x in (a, b))
    if va > 0 and vb > 0 and max(va, vb) / min(va, vb) > 1.3:
        return False
    ta, tb = _categoria(a.get("tipo")), _categoria(b.get("tipo"))
    if ta and tb and ta != tb:
        return False
    if not (a.get("condominio") and b.get("condominio")):
        ba, bb = whatsapp._normal(str(a.get("bairro") or "")), whatsapp._normal(str(b.get("bairro") or ""))
        if ba and bb and ba != bb:
            return False
    return True


def tem_identidade(im: dict | None) -> bool:
    """O imóvel diz o bastante para se comparar com outro (condomínio, bairro, valor ou finalidade)."""
    im = sem_marcas(im)
    return any(im.get(k) for k in ("condominio", "bairro", "valor", "finalidade"))


VENDA_A_PARTIR_DE = 100_000     # Pedro, 30/10: "acima de 100k é sempre venda"
# Pedro, 03/11 (a Tahina ...3600 disse "venda ou aluguel no valor de 3.200" e a Nay perguntou se era venda ou aluguel):
# "quando já estiver o valor ela já entende que é aluguel esses valores de locação baixos"
ALUGUEL_ATE = 30_000
OLX_NO_LINK = re.compile(r"olx\.com\.br/\S*?-(\d{9,11})(?!\d)")
FOTOS_DO_ANUNCIO = 12


def venda_pelo_valor(im: dict) -> dict:
    """Valor acima de R$ 100 mil é venda e até R$ 30 mil é aluguel, diga o que disser a leitura do modelo."""
    try:
        valor = float(im.get("valor") or 0)
    except (TypeError, ValueError):
        valor = 0
    if valor > VENDA_A_PARTIR_DE:
        return {**im, "finalidade": "venda"}
    if 0 < valor <= ALUGUEL_ATE:
        return {**im, "finalidade": "locacao"}
    return im


def anuncio_da_conversa(conn, t8: str, textos: list[str]) -> dict | None:
    """O anúncio da OLX de que se fala com este corretor: o link mais recente na conversa (dele, da equipe ou da Nay) ou o
    que a Nay perguntou a ele pela busca. Lido da base de scrap. Pedro, 30/10: a Stela recebeu o link do Piazza Dell'Acqua
    e a Nay perguntou tipo, venda ou locação, valor, bairro e taxa, tudo no anúncio."""
    ids: list[int] = []
    for t in textos:
        ids += [int(x) for x in OLX_NO_LINK.findall(t or "")]
    ids.reverse()   # o mais recente primeiro
    ids += [int(r["olx_id"]) for r in banco.linhas(conn, """SELECT olx_id FROM privado.busca_contato WHERE telefone8 = %s
                                                            AND olx_id IS NOT NULL ORDER BY em DESC""", (t8,))]
    for olx_id in dict.fromkeys(ids):
        a = banco.linhas(conn, """SELECT * FROM scrap_anuncio WHERE olx_id = %s ORDER BY coletado_em DESC LIMIT 1""", (olx_id,))
        if a:
            return a[0]
    return None


def imovel_do_anuncio(conn, a: dict) -> dict:
    """O que o anúncio da OLX já diz, no formato do "imovel" da Nay Corretores."""
    cat, sub, neg = (str(a.get(k) or "").lower() for k in ("categoria", "subtipo", "tipo_negocio"))
    tipo = ("casa em condomínio" if "condom" in sub else "cobertura" if "cobertura" in sub
            else "apartamento" if cat.startswith("apart") else "casa" if "casa" in cat else "")
    fin = "venda" if neg.startswith("venda") else "locacao" if neg.startswith("aluguel") else ""
    im = {"tipo": tipo, "finalidade": fin, "bairro": a.get("bairro") or "", "quartos": a.get("quartos") or 0,
          "vagas": a.get("vagas") or 0, "area": float(a.get("area_m2") or 0), "valor": float(a.get("preco") or 0),
          "taxa_condominio": float(a.get("condominio") or 0),
          "condominio": predio_do_anuncio(conn, a) or trecho_do_predio(a.get("titulo") or "") or "",
          # 02/11: o link é coisa nossa (Observações internas), não do card
          "interno": f"Anúncio da OLX: {a.get('url')}" if a.get("url") else ""}
    return venda_pelo_valor({k: v for k, v in im.items() if v not in (None, "", 0, 0.0)})


# 04/11 (o ...7891 mandou o link da OLX de uma casa NOSSA, do Tel, com "temos cliente interessado em visitar amanhã"; a Nay
# achou que era o imóvel dele, cadastrou o #9129 em dobro do nosso #2462 e falou de "um cliente" nosso que não existia):
# o anúncio da OLX é nosso quando o anunciante é a casa (a mesma lista de busca_olx.NOSSOS) ou quando é o mesmo imóvel de
# um cadastro NOSSO (o número do anúncio, ou o mesmo condomínio, quartos e valor: o gêmeo de whatsapp.gemeos).
ANUNCIANTE_NOSSO = ("imob easy", "imobeasy", "f v sobreira", "telmario")


def nosso_do_anuncio(conn, a: dict | None) -> dict | None:
    """{'codigo': o nosso imóvel (ou None)} quando o anúncio da OLX é NOSSO; None quando é de outro."""
    if not a:
        return None
    quem = whatsapp._normal(str(a.get("anunciante") or ""))
    im = imovel_do_anuncio(conn, a)
    codigo = banco.um(conn, """
        SELECT i.codigo FROM imoveis i
         WHERE i.status <> 'Excluído' AND NOT coalesce(i.e_parceiro, false)
           AND (i.extras->>'olx_id' = %(o)s
                OR (%(c)s <> '' AND similarity(nay_chave_condominio(i.condominio_nome), nay_chave_condominio(%(c)s)) >= 0.7
                    AND i.quartos IS NOT DISTINCT FROM %(q)s AND %(v)s > 0
                    AND (coalesce(i.valor_aluguel, 0) = %(v)s OR coalesce(i.valor_venda, 0) = %(v)s)))
         ORDER BY (i.status = 'Disponível') DESC, i.codigo LIMIT 1""",
                      {"o": str(a.get("olx_id") or ""), "c": str(im.get("condominio") or ""),
                       "q": whatsapp._num(im.get("quartos")), "v": float(im.get("valor") or 0)})
    if codigo or any(n in quem for n in ANUNCIANTE_NOSSO):
        return {"codigo": int(codigo) if codigo else None}
    return None


# 04/11 (o ...3703: "Condomínio Bela sonata" virou bairro Turismo sem condomínio; o Bella Sonata é do Tarumã na base): o
# condomínio escrito de ouvido, achado na nossa lista de condomínios, dá o nome certo e o bairro
CONDOMINIO_NO_TEXTO = re.compile(r"\b(?:condom[ií]nio|cond\.|residencial|edif[ií]cio)\s+([^\W\d_][\w' ]{2,40})", re.I)
CONDOMINIO_DA_BASE_MIN = 0.7


def condominio_da_base(conn, nome: str | None) -> dict | None:
    """{'nome', 'bairro'} do condomínio da nossa lista (condominios) com o nome parecido (pg_trgm sobre
    nay_chave_condominio, a partir de 0,7: "Bela sonata" acha o "Bella Sonata Residencial", Tarumã), ou None."""
    n = str(nome or "").strip()
    if len(chave_do_condominio(n)) < 4:
        return None
    r = banco.linhas(conn, """
        SELECT nome, bairro FROM condominios
         WHERE similarity(nay_chave_condominio(nome), nay_chave_condominio(%(n)s)) >= %(s)s
         ORDER BY similarity(nay_chave_condominio(nome), nay_chave_condominio(%(n)s)) DESC, length(nome) LIMIT 1""",
                     {"n": n, "s": CONDOMINIO_DA_BASE_MIN})
    return r[0] if r else None


def completar_imovel(conn, im: dict, textos: list[str]) -> dict:
    """O que o código acerta sozinho no imóvel do corretor, depois do modelo: suítes são quartos ("Casa com 3 suítes");
    o condomínio dito (no "imovel" ou no texto novo dele) achado na nossa lista dá o nome e o BAIRRO do cadastro, e a casa
    em condomínio vira "casa em condomínio"."""
    im = dict(im or {})
    s, q = whatsapp._num(im.get("suites")), whatsapp._num(im.get("quartos"))
    if s and s > 0 and (not q or q < s):
        im["quartos"] = s
    if im.get("condominio"):
        base = condominio_da_base(conn, im["condominio"])
    else:
        # o mais novo que a nossa lista conhece ("Condomínio fechado, lazer completo" não é nome)
        achados = [m.strip() for t in textos or [] for m in CONDOMINIO_NO_TEXTO.findall(t or "")]
        base = next((x for x in (condominio_da_base(conn, n) for n in reversed(achados[-4:])) if x), None)
    if base:
        im["condominio"] = base["nome"]
        if base.get("bairro"):
            im["bairro"] = base["bairro"]
        if _categoria(im.get("tipo")) == "casa" and "condom" not in whatsapp._normal(str(im.get("tipo") or "")):
            im["tipo"] = "casa em condomínio"
    return im


# 04/11 (o ...5642 encaminhou o NOSSO pedido do grupo, "✅ PRECISO DE AP P/ LOCAÇÃO ... até 2.600 ... Me chama no privado",
# junto com o imóvel dele; a Nay leu como pedido DELE e mandou o nosso #5724): o bloco do nosso pedido (bloco e
# mensagem_de_grupo, no molde do Tel) sai da conversa antes do modelo e vira uma marca
NOSSO_PEDIDO = re.compile(r"✅\s*PRECISO DE\b[^\n]*(?:\n[ \t]*-[^\n]*)*(?:\s*Tem algum\?\s*Me chama no privado\.?)?", re.I)


def sem_nosso_pedido(texto: str | None) -> tuple[str, bool]:
    """(o texto com o nosso pedido do grupo trocado pela marca, se ele estava lá)."""
    achou = []

    def troca(m: re.Match) -> str:
        achou.append(m.group(0))
        linhas = [re.sub(r"^✅\s*PRECISO DE\s*", "", x.strip(" -\t")) for x in m.group(0).splitlines()
                  if x.strip() and not x.strip().lower().startswith("tem algum")]
        return f"[ele encaminhou o NOSSO pedido do grupo ({' · '.join(linhas)[:220]}): ele responde a ele, NÃO é pedido dele]"
    return NOSSO_PEDIDO.sub(troca, texto or ""), bool(achou)


def busca_do_pedido_citado(ativas: list[dict], textos: list[str]) -> dict | None:
    """A busca ativa cujo pedido do grupo ele encaminhou (o mesmo bloco)."""
    junto = whatsapp._normal(" ".join(textos or []))
    return next((b for b in ativas if b.get("filtros") and whatsapp._normal(bloco(b["filtros"])) in junto), None)


def falta_no_imovel(im: dict, fotos: int) -> list[str]:
    falta = []
    # Pedro, 30/10: "precisa ter informações mínimas, como as informações que vão no card" (o m² é a 3ª linha do card)
    for k, nome in (("tipo", "o tipo"), ("finalidade", "se é aluguel ou venda"), ("bairro", "o bairro"),
                    ("quartos", "os quartos"), ("area", "a área (m²)"), ("valor", "o valor")):
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
    daqui = list(reversed(banco.linhas(conn, """
        SELECT id, direcao, origem, texto, criada_em, to_char(criada_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS hora
          FROM captacao_mensagens
         WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
         ORDER BY id DESC LIMIT %s""", (tel8, CONVERSA_DO_CORRETOR))))
    # 30/10: o que a equipe mandou pelo CRM ou pelo celular fica só no crmdb; sem isto a Nay não via o Tel na conversa
    equipe = [{"id": 0, "direcao": "enviada", "origem": "equipe_crm", "texto": e["texto"], "criada_em": e["criada_em"],
               "hora": e["criada_em"].astimezone(MANAUS).strftime("%d/%m %H:%M")}
              for e in whatsapp.da_equipe_no_crm(tel8, 15)]
    return sorted(daqui + equipe, key=lambda m: m["criada_em"])[-CONVERSA_DO_CORRETOR:]


# 04/11 (o ...1009 mandou o texto do Village Vert e 25 fotos como documento): eram as 30 últimas mensagens, e as 25 fotos
# empurravam o texto para fora; e cada mensagem ia cortada em 600 letras (o valor, no fim do texto, sumia). Agora 80, as
# mídias sem texto em sequência viram uma linha ("[25 arquivos]") e o texto dele vai até TEXTO_DO_CORRETOR letras
CONVERSA_DO_CORRETOR = 80
TEXTO_DO_CORRETOR = 2500


def _midia_sem_texto(m: dict) -> bool:
    return m["direcao"] == "recebida" and not (m.get("texto") or "").strip() and m.get("origem") not in ("texto", None)


def docs_recebidos(conversa: list[dict], horas: int = 6) -> int:
    """Quantas fotos ele mandou como ARQUIVO (documento) nas últimas `horas`: o recebedor das fotos não guarda o documento
    (busca_corretor_foto só tem as imagens), mas a foto chegou e não se pede de novo."""
    desde = datetime.now(timezone.utc) - timedelta(hours=horas)
    return sum(1 for m in conversa if m["direcao"] == "recebida" and m.get("origem") == "documento"
               and not (m.get("texto") or "").strip() and m["criada_em"] > desde)


def ja_perguntado(conversa: list[dict], n: int = 6) -> list[str]:
    """As perguntas que a Nay já fez a ele (as mais novas), para não repetir (o ...5600 ouviu "é casa ou apartamento?"
    duas vezes)."""
    ps = [f for m in conversa if m["direcao"] == "enviada" and m.get("origem") == "resposta"
          for f in whatsapp._frases(m.get("texto") or "") if f.endswith("?")]
    return list(dict.fromkeys(ps))[-n:]


def sem_pergunta_repetida(baloes: list[str], perguntas: list[str]) -> list[str]:
    """Tira de cada balão a pergunta que já foi feita (as palavras dela estão todas numa pergunta de antes: "É casa ou
    apartamento?" depois de "Essa duplex é casa ou apartamento?"); balão que fica vazio sai."""
    antes = [set(whatsapp._normal(p).split()) for p in perguntas]
    saida = []
    for b in baloes:
        frases = [f for f in whatsapp._frases(b)
                  if not (f.endswith("?") and any(len(set(whatsapp._normal(f).split()) - {"e"}) >= 2
                                                  and set(whatsapp._normal(f).split()) - {"e"} <= p for p in antes))]
        novo = " ".join(frases).strip()
        if novo and (frases == whatsapp._frases(b) or any(f.endswith("?") for f in frases) or len(novo.split()) > 3):
            saida.append(novo)
    return saida


EQUIPE_NA_CONVERSA_H = 12   # a equipe falou com o corretor há menos disto: a Nay não fala, só anota e cadastra


def _guardar_enviada(conn, tel: str, texto: str, mid: str) -> None:
    """O que a Nay manda ao corretor/anunciante entra na conversa dela (antes ela não via as próprias perguntas e
    perguntava de novo). Origem 'resposta': para a Nay Leads não é gente escrevendo."""
    d = re.sub(r"\D", "", tel or "")
    banco.um(conn, """INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status, message_id)
                      VALUES (%s, 'enviada', 'resposta', %s, 'Enviado', %s)""",
             (d if d.startswith("55") else "55" + d, texto, mid or None))


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


def _turno_corretor(conn, cor: dict, conversa: list[dict], ativas: list[dict], fotos: int,
                    anuncio: dict | None = None, ja: dict | None = None, fichas: list[dict] | None = None,
                    nosso: dict | None = None, docs: int = 0) -> str:
    ja = sem_marcas(ja if ja is not None else (cor.get("imovel") or {}))
    linhas = [f"COMO CHEGOU: {COMO_CHEGOU.get(cor.get('origem') or '', 'escreveu para o nosso número')}.",
              f"CONDOMÍNIO QUE ELE CITOU: {condominio_citado(conn, conversa) or 'nenhum que a gente tenha cadastrado'}"]
    if fichas:
        # 04/11 (Pedro: "responder as solicitações dele"): a ficha do imóvel NOSSO que ele citou, para tirar a dúvida dele
        linhas += ["IMÓVEIS NOSSOS QUE ELE CITOU (ficha; para responder dúvida dele sobre eles; NÃO é o imóvel que ele oferece):"]
        linhas += [f"- #{f.get('codigo')}: {json.dumps({k: v for k, v in f.items() if k != 'codigo'}, ensure_ascii=False, default=str)[:1500]}"
                   for f in fichas]
    linhas += ["", "BUSCAS ATIVAS (id: o que o cliente procura):"]
    linhas += [f"- {b['id']}: {resumo(b['filtros'])}" for b in ativas] or ["- nenhuma"]
    if anuncio and nosso is not None:
        # 04/11 (o ...7891): o anúncio é NOSSO; não é o imóvel dele e não se cadastra
        linhas += ["", "ANÚNCIO NOSSO (o link da OLX que está na conversa é um imóvel NOSSO"
                       + (f", o #{nosso['codigo']}" if nosso.get("codigo") else "") + f": {anuncio.get('titulo')}). NÃO é o "
                       "imóvel dele e NÃO se cadastra; se o cliente dele quer visitar, intencao \"visita\"."]
    elif anuncio:
        linhas += ["", f"ANÚNCIO DA OLX deste imóvel (já sabemos; NUNCA pergunte): {anuncio.get('titulo')} | "
                       f"{json.dumps(imovel_do_anuncio(conn, anuncio), ensure_ascii=False)} | {len(anuncio.get('fotos') or [])} fotos"]
    falta = falta_no_imovel(ja, fotos + docs)
    ped = pedido_guardado(cor)
    perguntas = ja_perguntado(conversa)
    linhas += ["", f"JÁ ANOTADO deste imóvel: {json.dumps(ja, ensure_ascii=False)}",
               f"FALTA PARA O CARD: {', '.join(falta) if falta else 'nada, está completo'}",
               f"Fotos recebidas até agora: {fotos}"
               + (f" (e mais {docs} mandadas como ARQUIVO: contam como fotos, NÃO peça de novo)" if docs else ""),
               f"Busca escolhida antes: {cor.get('busca') or 'nenhuma'}",
               "PEDIDO DELE (o último, para o cliente dele): "
               + (f"{perfil_do_pedido(ped['f'])} (de {ped.get('em', '')[:16]}; respondemos: \"{ped.get('resposta') or '-'}\")"
                  if ped else "nenhum"),
               "JÁ PERGUNTADO (não repita): " + (" | ".join(perguntas) if perguntas else "nada"), "", "CONVERSA:"]
    midias: list[str] = []

    def solta_midias() -> None:
        if midias:
            nomes = {"imagem": ("foto", "fotos"),
                     "documento": ("arquivo (foto mandada como documento)", "arquivos (fotos mandadas como documento)")}
            n = {o: midias.count(o) for o in dict.fromkeys(midias)}
            linhas.append(f"{hora} CORRETOR: [" + ", ".join(
                f"{q} {nomes.get(o, (o, o))[q > 1]}" for o, q in n.items()) + "]")
            midias.clear()
    hora = ""
    for m in conversa:
        if _midia_sem_texto(m):
            hora = hora if midias else m["hora"]
            midias.append(m.get("origem") or "mídia")
            continue
        solta_midias()
        quem = "CORRETOR" if m["direcao"] == "recebida" else "EQUIPE" if m.get("origem") == "equipe_crm" else "NAY/EQUIPE"
        texto = (m["texto"] or "").strip() or f"[{m['origem'] or 'mídia'}]"
        if m["direcao"] == "recebida":
            texto = sem_nosso_pedido(texto)[0][:TEXTO_DO_CORRETOR]
        else:
            texto = texto[:600]
        if m["origem"] == "imagem":
            texto = "[foto] " + texto
        linhas.append(f"{m['hora']} {quem}: {texto}")
    solta_midias()
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


def cadastrar(conn, cor: dict, b: dict | None, ativo: bool, fotos_do_anuncio: list[str] | None = None,
              anuncio: dict | None = None, com_fotos: bool = True) -> int:
    """O imóvel do corretor no nosso cadastro, como imóvel de PARCEIRO. Rascunho enquanto falta dado; completo, Disponível
    (ativo=True). Devolve o código.

    30/10 (revisão, o Eudes ...8856): o anúncio da OLX citado na conversa já cadastrado (pelo Tel, pelo link ou por outro
    corretor) não vira outro imóvel -- o 9090 era o mesmo apartamento do 9089, e o cliente recebeu os dois. Acha pelo
    número do anúncio (extras.olx_id) ou pelo link e devolve esse código, sem mexer nos dados dele."""
    im = cor["imovel"] or {}
    loc = str(im.get("finalidade") or "").startswith("loc")
    valor = None
    try:
        valor = float(im.get("valor") or 0) or None
    except (TypeError, ValueError):
        pass
    extras = {"corretor_parceiro": cor.get("nome") or "", "corretor_telefone": cor["telefone"],
              "busca_cliente": str(b["id"]) if b else "",
              "cadastrado_pelo": "Nay Corretores" + (" (busca do cliente)" if b else f" ({cor.get('origem') or 'corretor'})")}
    olx_id = str((anuncio or {}).get("olx_id") or "")
    olx_url = str((anuncio or {}).get("url") or "")
    if olx_id:
        extras.update({"olx_id": olx_id, "olx_url": olx_url})
    extras = {k: v for k, v in extras.items() if v}
    if not cor.get("codigo") and olx_id:
        ja = banco.um(conn, """SELECT codigo FROM imoveis WHERE status <> 'Excluído'
                                AND (extras->>'olx_id' = %s OR (%s <> '' AND extras->>'olx_url' = %s)) ORDER BY codigo LIMIT 1""",
                      (olx_id, olx_url, olx_url))
        if ja:
            log.info("corretor …%s: o anúncio %s já é o imóvel #%s; não cadastra de novo", _tel8(cor["telefone"])[-4:], olx_id, ja)
            return int(ja)
    campos = {"tipo": _tipo_do_cadastro(im.get("tipo")), "bairro": im.get("bairro") or None,
              "condominio_nome": im.get("condominio") or None, "quartos": im.get("quartos") or None,
              "suites": im.get("suites") or None, "vagas": im.get("vagas") or None, "area_util": im.get("area") or None,
              "valor_aluguel": valor if loc else None, "valor_venda": None if loc else valor,
              "taxa_condominio": im.get("taxa_condominio") or None, "mobilia": im.get("mobilia") or None,
              "andar": im.get("andar") or None,
              # 02/11 (REGRA_DOS_CAMPOS): o negócio no card, os detalhes na descrição; o interno vai abaixo
              "observacao": str(im.get("observacao") or "").strip() or None,
              "descricao": str(im.get("descricao") or "").strip() or None}
    if not cor.get("codigo"):
        codigo = banco.um(conn, """
            INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, criado_em, captado_em, e_parceiro,
                                 tipo, bairro, condominio_nome, quartos, suites, vagas, area_util, valor_aluguel, valor_venda,
                                 taxa_condominio, mobilia, andar, observacao, descricao, extras)
            VALUES (nextval('imoveis_crm_codigo_seq'), 'busca', 'Rascunho', false, false, now(), to_char(now(), 'DD/MM/YYYY'), true,
                    %(tipo)s, %(bairro)s, %(condominio_nome)s, %(quartos)s, %(suites)s, %(vagas)s, %(area_util)s, %(valor_aluguel)s,
                    %(valor_venda)s, %(taxa_condominio)s, %(mobilia)s, %(andar)s, %(observacao)s, %(descricao)s, %(extras)s::jsonb)
            RETURNING codigo""", {**campos, "extras": json.dumps(extras, ensure_ascii=False)})
    else:
        codigo = cor["codigo"]
        sets = ", ".join(f"{k} = coalesce(%({k})s, {k})" for k in campos)
        banco.um(conn, f"UPDATE imoveis SET {sets}, extras = coalesce(extras, '{{}}'::jsonb) || %(extras)s::jsonb WHERE codigo = %(codigo)s",
                 {**campos, "extras": json.dumps(extras, ensure_ascii=False), "codigo": codigo})
    if str(im.get("interno") or "").strip():
        # Uso interno › Observações (privado.imovel_ficha); a função não repete o que já está lá
        banco.um(conn, "SELECT privado.uso_interno_somar(%s, %s)", (codigo, str(im["interno"]).strip()[:2000]))
    ordem = int(banco.um(conn, "SELECT coalesce(max(ordem), 0) FROM imovel_fotos WHERE codigo = %s", (codigo,)) or 0)
    # 04/11: o segundo imóvel da mesma mensagem não leva as fotos (elas ficam no primeiro, e a equipe separa)
    for f in (_fotos_novas(conn, _tel8(cor["telefone"])) if com_fotos else []):
        ordem += 1
        banco.um(conn, "INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (%s, %s, %s, %s)", (codigo, ordem, f["url"], ordem == 1))
        banco.um(conn, "UPDATE privado.busca_corretor_foto SET usada_em = now() WHERE id = %s", (f["id"],))
    if fotos_do_anuncio and ordem < FOTOS_MINIMAS:
        # as fotos do anúncio da OLX, como no pré-cadastro da OLX (parceiro.precadastrar)
        # 02/11 (o 9115): baixadas para o nosso site; o link da OLX dava foto quebrada no site e no CRM
        for url in fotos_do_anuncio:
            ordem += 1
            banco.um(conn, "INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (%s, %s, %s, %s)",
                     (codigo, ordem, fotos_olx.guardar(codigo, ordem, url), ordem == 1))
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
    # 30/10 (revisão, o Eudes ...8856): a oferta do corretor também espera quando a equipe acabou de escrever ou o filtro
    # não está pronto (a mesma regra da revisita da base); fica em "cadastrando" e a revisita manda depois
    if whatsapp.oferta_sozinha_espera(conn, lead, b.get("filtros")):
        return "espera"
    return _mandar_ao_cliente(conn, lead, [codigo], b.get("filtros"))


def _mandar_ao_cliente(conn, lead: dict, codigos: list[int], filtros: dict | None = None) -> str:
    """Os imóveis um de cada vez (card, fotos, espera as fotos, o próximo) e uma pergunta no fim. 'nao_serve' = nenhum
    passou na régua (nada foi a ela)."""
    # 03/11 (Pedro: "enviando 2 vezes o mesmo imóvel"): o que já foi para ela nas últimas 24 h, por qualquer caminho, não vai
    codigos = [c for c in codigos if not whatsapp.card_ja_foi(conn, lead, c)]
    if not codigos:
        return "cliente"
    # 04/11 (Pedro: "ela não pode errar ... nem mandar imóvel errado"): a régua única (whatsapp.so_o_que_serve) também na
    # oferta que chega sozinha: a revisita da base e o imóvel do corretor
    f = dict(filtros or lead.get("filtros") or {})
    if not f.get("finalidade"):
        f["finalidade"] = whatsapp.finalidade_sem_dizer(lead, f)
    codigos = whatsapp.so_o_que_serve(conn, lead, f, codigos, onde="oferta da busca")
    if not codigos:
        return "nao_serve"
    # 04/11 (Pedro: "ela tá falando muito robótica"): eram "Boa notícia! Encontrei uma opção que combina com o que você
    # procura:" e "O que achou dessa? Se gostar, já vejo a visita para você.", sempre iguais; agora variam (whatsapp)
    ja = whatsapp.ja_mandou(conn, lead)
    whatsapp.mandar_texto(conn, lead, whatsapp.abre_oferta(lead, len(codigos), ja))
    enviados = list(lead.get("enviados") or [])
    for n, codigo in enumerate(codigos):
        time.sleep(whatsapp.DEPOIS_DAS_FOTOS_S if n else whatsapp.ENTRE_ENVIOS_S)
        whatsapp.mandar_imovel(conn, lead, codigo)
        if codigo not in enviados:
            enviados.append(codigo)
            whatsapp._marcar(conn, lead["id"], enviados=enviados)
    time.sleep(whatsapp.DEPOIS_DAS_FOTOS_S)
    whatsapp.mandar_texto(conn, lead, whatsapp.fecho(lead, len(codigos), de_novo=True, evitar=ja))
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
    # 01/11 (lead 39: o Piazza que ela já visitou voltou duas vezes, cadastrado como 9089 e 9090): o cadastro em dobro de
    # um imóvel que ela já recebeu não sai
    fora_gemeos = whatsapp.gemeos(conn, [int(p["codigo"]) for p in r["pares"]], list(excluir))
    for p in r["pares"]:
        if int(p["codigo"]) in fora_gemeos:
            continue
        if p["nota"] < regras["cortes"]["amarelo"] or len(saida) >= quantas:
            break
        if f.get("perto_de") and p["imovel"].get("bairro") not in perto:
            continue
        if whatsapp._ofertavel(conn, int(p["codigo"]), lead):
            saida.append({"codigo": int(p["codigo"]), "nota": p["nota"]})
    # 04/11 (Pedro: "o foco da Nay Leads é ser um bom filtro"): a nota da Captação ativa junta o que "parece" com o pedido
    # (a faixa de valor, o vizinho colado); a régua única corta o que não serve de fato (mobília, suítes, andar, o "sem")
    if saida:
        g = dict(f)
        if not g.get("finalidade"):
            g["finalidade"] = whatsapp.finalidade_sem_dizer(lead, g)
        servem = set(whatsapp.so_o_que_serve(conn, lead, g, [s["codigo"] for s in saida], onde="revisita da base"))
        saida = [s for s in saida if s["codigo"] in servem]
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
        # 30/10 (revisão, o Eudes ...8856 e o #9084): só o que FOI ao cliente (ou ao grupo) sai da revisita; o que ficou em
        # "cadastrando" (o cadastro do corretor no modo teste, ou que não terminou) é imóvel nosso e volta a servir
        oferecidos = [int(x["codigo"]) for x in ofertas if x.get("codigo") and x.get("estado") in ("cliente", "grupo")]
        excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else []) + oferecidos
        achados = opcoes_da_base(conn, lead, f, excluir, OPCOES_MAX - opcoes_enviadas(b))
        if not achados:
            continue
        codigos = [a["codigo"] for a in achados]
        onde = _mandar_ao_cliente(conn, lead, codigos, f)
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


# ── 5b. o corretor PEDE imóvel, e quem a Nay Corretores atende (Pedro, 04/11/2026) ──
# "todos que estão marcados como corretores, mesmo no número Leads, é para a Nay Parceria atender e não a Nay Leads; esses
# que eu passei para a Rayssa, pode pôr a Nay para atender todos eles"; como: "mandar os imóveis e responder as
# solicitações dele". O caso: o vasconcelosizaias (…8585) escreveu "TEM ALGUMA COISA ATÉ 300 MIL VENDA" às 09:28 e a Nay
# Corretores, que só sabia cadastrar o imóvel do corretor, devolveu "Você tem algum imóvel à venda até R$ 300 mil? Pode me
# mandar?"; ele: "NÃO ESTOU EM BUSCA VC TERIA ALGUMA COISA", e o Pedro mandou as opções à mão (2228, 4262, 5699...).
# Agora ela lê o pedido, procura nos NOSSOS imóveis (a busca da Nay Leads: olx_cliente_buscar com a faixa firme -20%/+10%
# e a régua serve_ao_pedido; nunca imóvel de parceiro) e manda até PEDIDO_MAX opções pelo número da Parceria, como o
# "Enviar imóvel" do CRM (nai_disparo_enfileirar: card e fotos); a Nay da Parceria segue com ele por lá.
PARCERIA_NUMERO = "92 9445-3618"
PEDIDO_MAX = 5
# com "automático" o turno do disparo não conta como "feito à mão" (nai_turno_feito_a_mao): a parede de 24 h de
# nai_enviar_imoveis_para vale (o mesmo imóvel não vai duas vezes ao corretor; só o envio da equipe passa por cima, 467)
QUEM_DISPARA = "Nay Corretores (automático)"
REPETIDO_H = 24
MARCADOS_A_CADA_S = 600        # a lista dos corretores marcados é relida a cada 10 min (crm_leads_corretores leva ~6 s)
MARCADO_JANELA_H = 12          # o marcado que a Nay Corretores pega agora: só o que ele escreveu nestas horas (não responde
                               # mensagem de dois dias atrás de quem a equipe ou a Nay Leads já atendia)


def _tipo_pedido(t) -> str:
    """O tipo que o corretor pediu, no vocabulário da busca (olx_cliente_buscar). '' = residencial, qualquer um."""
    n = whatsapp._normal(str(t or "")).replace("_", " ")
    if not n or "tanto" in n or n == "imovel":
        return ""
    if "casa" in n and "condom" in n:
        return "casa_condominio"
    for prefixo, tipo in (("cobert", "cobertura"), ("apart", "apartamento"), ("apto", "apartamento"), ("ap ", "apartamento"),
                          ("ape", "apartamento"), ("flat", "flat"), ("kit", "flat"), ("studio", "flat"), ("casa", "casa"),
                          ("sobrado", "casa"), ("sala", "comercial"), ("loja", "comercial"), ("ponto", "comercial"),
                          ("comerc", "comercial"), ("galp", "comercial"), ("predio", "comercial"), ("terreno", "terreno"),
                          ("lote", "terreno")):
        if (n + " ").startswith(prefixo):
            return tipo
    return ""


def pedido_do_corretor(p: dict | None) -> dict:
    """O "pedido" do modelo nos filtros da busca da Nay Leads. O valor manda na finalidade, como no cadastro (Pedro, 30/10 e
    03/11): acima de R$ 100 mil é venda; até R$ 30 mil é aluguel."""
    p = p or {}
    f: dict = {}
    teto = whatsapp._num(p.get("teto"))
    if teto and teto > 0:
        f["teto"] = teto
    fin = whatsapp._normal(str(p.get("finalidade") or ""))
    if fin.startswith(("vend", "compr")):
        f["finalidade"] = "venda"
    elif fin.startswith(("loc", "alug")):
        f["finalidade"] = "locacao"
    if teto and teto > VENDA_A_PARTIR_DE:
        f["finalidade"] = "venda"
    elif teto and 0 < teto <= ALUGUEL_ATE:
        f["finalidade"] = "locacao"
    tipo = _tipo_pedido(p.get("tipo"))
    if tipo:
        f["tipo"] = tipo
    bairros = [str(b).strip() for b in (p.get("bairros") or []) if str(b).strip()]
    if bairros:
        f["bairros"] = bairros
    if str(p.get("condominio") or "").strip():
        # 04/11 (o ...2985: "apartamento no Smille Flores", e saíram 18 imóveis de outros lugares): o condomínio que o
        # corretor diz é o pedido; nada fora dele
        f["condominio"] = str(p["condominio"]).strip()
        f["so_condominio"] = True
    exigencias = [str(x).strip()[:120] for x in (p.get("exigencias") or []) if str(x).strip()]
    if exigencias:
        f["exigencias"] = exigencias          # "andar baixo", "pelo menos 1 suíte": a régua (serve_ao_pedido) cumpre
    q = whatsapp._num(p.get("quartos"))
    if q and 0 < q < 10:
        f["quartos"] = q
    mob = whatsapp._normal(str(p.get("mobilia") or ""))
    if f.get("finalidade") == "locacao" and mob:
        f["mobilia"] = ("semi" if ("semi" in mob or "modulad" in mob) else "sem" if mob.startswith(("sem", "vazi", "nao"))
                        else "mobiliado" if mob.startswith("mobil") else "")
        if not f["mobilia"]:
            f.pop("mobilia")
    return f


# 04/11 (o ...2985 repetiu o pedido cinco vezes e cada reclamação virou um pedido novo): o pedido do corretor fica guardado
# (o jsonb de privado.busca_corretor, na marca "_pedido") com o que respondemos e o que mandamos, e vale entre os turnos
PEDIDO_VALE_H = 24
CAMPOS_DO_PEDIDO = ("finalidade", "tipo", "teto", "bairros", "condominio", "so_condominio", "quartos", "mobilia", "exigencias")


def pedido_guardado(cor: dict) -> dict | None:
    """{'f', 'em', 'resposta', 'mandados'} do último pedido dele, se for das últimas PEDIDO_VALE_H horas."""
    p = (cor.get("imovel") or {}).get("_pedido") if isinstance(cor.get("imovel"), dict) else None
    if not isinstance(p, dict) or not isinstance(p.get("f"), dict):
        return None
    try:
        em = datetime.fromisoformat(str(p.get("em")))
    except ValueError:
        return None
    if em.tzinfo is None:
        em = em.replace(tzinfo=MANAUS)
    return p if datetime.now(MANAUS) - em <= timedelta(hours=PEDIDO_VALE_H) else None


def herdar_pedido(antes: dict | None, novo: dict) -> dict:
    """O pedido de agora com o de antes: quando o de agora não diz o lugar, o valor nem o tipo ("Venda", "Vc não enviou
    nenhuma opção"), ele é a continuação do de antes e só soma o que trouxe. Quando diz, é ele que vale (o modelo já junta
    a conversa)."""
    if not antes:
        return novo
    if novo.get("condominio") or novo.get("bairros") or novo.get("teto") or novo.get("tipo"):
        return novo
    return {**antes, **novo}


def mesmo_pedido_do_corretor(a: dict | None, b: dict | None) -> bool:
    def chave(f):
        f = f or {}
        return json.dumps({k: (sorted(whatsapp._normal(str(x)) for x in f[k]) if isinstance(f.get(k), list)
                               else chave_do_condominio(f[k]) if k == "condominio" else f[k])
                           for k in CAMPOS_DO_PEDIDO if f.get(k) not in (None, "", [], 0, False)}, sort_keys=True, default=str)
    return chave(a) == chave(b)


def guardar_pedido(conn, t8: str, cor: dict, feito: dict) -> None:
    """Grava o pedido de agora (a marca "_pedido" do jsonb do corretor), sem mexer no imóvel que ele oferece."""
    p = {**feito, "em": datetime.now(MANAUS).isoformat(timespec="minutes")}
    banco.um(conn, """UPDATE privado.busca_corretor SET imovel = coalesce(imovel, '{}'::jsonb) || jsonb_build_object('_pedido', %s::jsonb)
                       WHERE telefone8 = %s""", (json.dumps(p, ensure_ascii=False, default=str), t8))
    cor["imovel"] = {**(cor.get("imovel") or {}), "_pedido": p}


def nome_do_condominio(conn, nome: str) -> str:
    """O nome do condomínio pedido como está no NOSSO cadastro ("Smille Flores" -> "Smile Flores"), ou o que ele escreveu."""
    r = banco.um(conn, """
        SELECT condominio_nome FROM imoveis WHERE coalesce(btrim(condominio_nome), '') <> ''
           AND similarity(nay_chave_condominio(condominio_nome), nay_chave_condominio(%(n)s)) >= 0.6
         ORDER BY similarity(nay_chave_condominio(condominio_nome), nay_chave_condominio(%(n)s)) DESC, (status = 'Disponível') DESC
         LIMIT 1""", {"n": nome})
    return str(r) if r else nome


def _no_condominio(conn, f: dict) -> list[dict]:
    """Os imóveis do condomínio pedido, direto do cadastro: a busca da base (olx_cliente_buscar) só conhece o condomínio
    da planilha dos próximos e, sem ele, traz 10 de qualquer lugar (o 99 Adrianópolis de R$ 3 mi para o Smile Flores).
    Parceiro e fora do mercado saem depois (_nossos_no_mercado); a régua confere o resto."""
    venda = f.get("finalidade") == "venda"
    return [{"codigo": int(r["codigo"]), "perto": False} for r in banco.linhas(conn, f"""
        SELECT codigo, condominio_nome FROM imoveis
         WHERE status = 'Disponível' AND coalesce(btrim(condominio_nome), '') <> ''
           AND coalesce({'valor_venda' if venda else 'valor_aluguel'}, 0) > 0
           AND similarity(nay_chave_condominio(condominio_nome), nay_chave_condominio(%s)) >= 0.6
         ORDER BY codigo DESC LIMIT 20""", (f["condominio"],))
            if whatsapp.so_no_condominio([{"condominio": r["condominio_nome"]}], {**f, "so_condominio": True})]


def codigos_do_pedido(p: dict | None) -> list[int]:
    return [c for c in dict.fromkeys(whatsapp._int(x) for x in (p or {}).get("codigos") or []) if c and 100 <= c <= 99999]


def falta_no_pedido(f: dict) -> str:
    """'' = dá para buscar; senão UMA pergunta curta. Sem valor e sem lugar não se busca (o catálogo inteiro não é
    resposta); com o lugar e sem valor, falta saber se é venda ou locação."""
    lugar = bool(f.get("bairros") or f.get("condominio"))
    if not f.get("teto") and not lugar:
        return "Até quanto o seu cliente quer pagar?" if f.get("finalidade") else \
            "É para venda ou locação, e até quanto o seu cliente quer pagar?"
    if not f.get("finalidade"):
        return "É para venda ou locação?"
    return ""


ROTULO_DO_TIPO = {"apartamento": "apartamento", "casa": "casa", "casa_condominio": "casa em condomínio",
                  "cobertura": "cobertura", "flat": "flat", "comercial": "imóvel comercial", "terreno": "terreno"}


def perfil_do_pedido(f: dict) -> str:
    """"Apartamento para venda em Flores com 2 quartos até R$ 300.000" (a frase do "não tenho")."""
    partes = [ROTULO_DO_TIPO.get(f.get("tipo") or "", "imóvel")]
    if f.get("finalidade"):
        partes.append("para venda" if f["finalidade"] == "venda" else "para locação")
    if f.get("condominio"):
        partes.append(f"no {f['condominio']}")
    elif f.get("bairros"):
        partes.append("em " + " ou ".join(f["bairros"][:2]))
    if f.get("quartos") and f.get("tipo") not in ("comercial", "terreno"):
        partes.append(f"com {f['quartos']} {'quarto' if f['quartos'] == 1 else 'quartos'}")
    if f.get("teto"):
        partes.append(f"até {whatsapp._dinheiro(f['teto'])}")
    t = " ".join(partes)
    return t[:1].upper() + t[1:]


def pergunta_de_afrouxar(f: dict, achou: list[tuple[str, str]]) -> str:
    """A UMA pergunta do "não tenho" (Pedro, 04/11): só o primeiro afrouxar que a base TEM (o_que_existe_afrouxando)."""
    if not achou:
        return ""
    o_que, d = achou[0]
    if o_que == "quartos":
        return f"serve com {d} {'quarto' if str(d) == '1' else 'quartos'}?"
    if o_que == "bairro":
        return f"serve num bairro vizinho, como {d}?" if d else "serve num bairro vizinho?"
    return f"serve um pouco acima de {whatsapp._dinheiro(f['teto'])}?" if f.get("teto") else ""


def opcoes_text(n: int) -> str:
    return "1 opção" if n == 1 else f"{n} opções"


def resposta_do_pedido(f: dict, mandados: list[int], repetidos: list[int], afrouxar: str = "") -> str:
    """A resposta no 8595, curta e de gente. Mandou: "Tenho sim! ..." e o número da Parceria (é por lá que as fotos
    chegam e que a Nay da Parceria segue com ele)."""
    if mandados:
        return f"Tenho sim! Te mandei {opcoes_text(len(mandados))} pelo nosso número de parcerias, o {PARCERIA_NUMERO}."
    if repetidos:
        return (f"As que tenho nesse perfil já te mandei pelo nosso número de parcerias, o {PARCERIA_NUMERO}."
                + (f" Para mais opções, {afrouxar}" if afrouxar else ""))
    perfil = perfil_do_pedido(f)
    return f"{perfil} não tenho agora" + (f"; {afrouxar}" if afrouxar else ".")


def _recentes_do_corretor(conn, tel: str) -> list[int]:
    """O que já foi para ele (qualquer caminho: a Nay velha, a Nay da Parceria, a equipe) nas últimas REPETIDO_H horas."""
    return [int(r["codigo"]) for r in banco.linhas(conn, f"""
        SELECT codigo FROM crm_imoveis_enviados(%s) WHERE ultimo_em > now() - interval '{REPETIDO_H} hours'""", (tel,))]


def _nossos_no_mercado(conn, codigos: list[int]) -> list[int]:
    """Dos códigos, na mesma ordem, só os NOSSOS Disponíveis (parceria nunca sai ao corretor, 60/299/400)."""
    if not codigos:
        return []
    ok = {int(r["codigo"]) for r in banco.linhas(conn, """
        SELECT codigo FROM imoveis WHERE codigo = ANY(%s::int[]) AND status = 'Disponível' AND NOT coalesce(e_parceiro, false)
           AND coalesce(nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site), false)""", (list(codigos),))}
    return [c for c in codigos if c in ok]


def opcoes_para_o_corretor(conn, tel: str, f: dict) -> dict:
    """A busca da Nay Leads para o pedido do corretor: olx_cliente_buscar (sem aceita_parceiro: só o que é nosso), os
    cortes de sempre (perto de, condomínio, gêmeos), a régua serve_ao_pedido, o exato antes do "mais próximo" (este no
    máximo whatsapp.MAX_PROXIMOS), até PEDIDO_MAX. {'novos': [...], 'repetidos': [...], 'afrouxar': 'pergunta' | ''}:
    `repetidos` = os que serviriam mas já foram para ele nas últimas REPETIDO_H h."""
    lead = {"id": None, "telefone": tel}
    g = {k: v for k, v in f.items() if k != "aceita_parceiro"}
    # 04/11: com o condomínio dito, só os do condomínio (direto do cadastro); sem ele, a busca da Nay Leads
    achados = _no_condominio(conn, g) if g.get("condominio") else whatsapp._consultar(conn, g, [], [], limite=10)
    servem = set(whatsapp.so_o_que_serve(conn, lead, g, [a["codigo"] for a in achados], bairro_conferido=True,
                                         onde="pedido do corretor"))
    achados = [a for a in achados if int(a["codigo"]) in servem]
    nossos = set(_nossos_no_mercado(conn, [int(a["codigo"]) for a in achados]))
    achados = [a for a in achados if int(a["codigo"]) in nossos]
    recentes = set(_recentes_do_corretor(conn, tel))
    repetidos = [int(a["codigo"]) for a in achados if int(a["codigo"]) in recentes]
    novos = [a for a in achados if int(a["codigo"]) not in recentes]
    exatos = [int(a["codigo"]) for a in novos if not a.get("perto")]
    perto = [int(a["codigo"]) for a in novos if a.get("perto")][:whatsapp.MAX_PROXIMOS]
    escolhidos = (exatos + perto)[:PEDIDO_MAX]
    afrouxar = ""
    if not escolhidos:
        try:
            achou = whatsapp.o_que_existe_afrouxando(conn, lead, {"f": g, "excluir": list(recentes), "nomes_recusados": []})
            # a sondagem é a mesma busca sem aceita_parceiro: só pergunta o que é nosso e ainda não foi para ele
            afrouxar = pergunta_de_afrouxar(g, achou)
        except Exception:  # noqa: BLE001 -- a pergunta para afrouxar não derruba a resposta
            log.exception("corretor …%s: a sondagem do afrouxar falhou", tel[-4:])
    return {"novos": escolhidos, "repetidos": repetidos, "afrouxar": afrouxar}


MANDOU_CODIGO = re.compile(r"(\d{3,5}) \(card e")


def mandar_pela_parceria(conn, tel: str, codigos: list[int], c: dict) -> tuple[list[int], str]:
    """Card e fotos de cada imóvel pela Nay da Parceria (o "Enviar imóvel" do CRM). Devolve (os que saíram, o texto da
    função). Em teste, nada sai: o número de teste recebe o aviso e conta como enviado."""
    if not codigos:
        return [], ""
    if c.get("corretor") == "teste":
        if c.get("teste"):
            _enviar(c["teste"], f"[teste: iria pela Parceria ao corretor …{tel[-4:]}: "
                                + ", ".join(f"#{x}" for x in codigos) + "]")
        return list(codigos), "teste"
    msg = banco.um(conn, "SELECT nai_disparo_enfileirar(%s, %s::int[], %s)", (tel, list(codigos), QUEM_DISPARA)) or ""
    conn.commit()
    if not msg.startswith("Mandei"):
        return [], msg
    feitos = msg.split(".\n", 1)[0]
    return [int(x) for x in MANDOU_CODIGO.findall(feitos) if int(x) in codigos], msg


def atender_pedido(conn, cor: dict, r: dict, c: dict) -> list[str]:
    """O corretor pediu imóvel (pede_imovel): os balões da resposta no 8595 ([] = não responde). Pergunta UMA coisa se
    falta o essencial; senão busca, manda pela Parceria e diz o que fez."""
    tel = re.sub(r"\D", "", cor["telefone"])
    p = r.get("pedido") or {}
    codigos = codigos_do_pedido(p)
    guardado = pedido_guardado(cor)
    if codigos:
        # ele pediu um imóvel NOSSO pelo código: vai esse (o de parceiro e o fora do mercado não; nem se fala em parceria)
        nossos = _nossos_no_mercado(conn, codigos)
        recentes = set(_recentes_do_corretor(conn, tel))
        novos = [x for x in nossos if x not in recentes][:PEDIDO_MAX]
        mandados, msg = mandar_pela_parceria(conn, tel, novos, c)
        log.info("corretor …%s pediu %s: %s", tel[-4:], codigos, msg or "nada a mandar")
        if mandados:
            return [f"Te mandei pelo nosso número de parcerias, o {PARCERIA_NUMERO}."]
        if nossos:
            return [f"Esse eu já te mandei pelo nosso número de parcerias, o {PARCERIA_NUMERO}."]
        return ["Esse não está disponível no momento."]
    # 04/11 (o ...2985): o pedido de antes vale ("Venda" responde à pergunta; a reclamação não é pedido novo)
    f = herdar_pedido((guardado or {}).get("f"), pedido_do_corretor(p))
    if f.get("condominio"):
        f["condominio"] = nome_do_condominio(conn, f["condominio"])
    r["_pedido_feito"] = {"f": f}
    pergunta = falta_no_pedido(f)
    if pergunta:
        r["_pedido_feito"]["resposta"] = pergunta
        return [pergunta]
    o = opcoes_para_o_corretor(conn, tel, f)
    mandados, msg = mandar_pela_parceria(conn, tel, o["novos"], c)
    log.info("corretor …%s pediu %s: achou %s, já tinha %s; %s", tel[-4:], perfil_do_pedido(f), o["novos"], o["repetidos"],
             msg or "nada a mandar")
    if o["novos"] and not mandados:
        if "já foi" in msg:
            resposta = resposta_do_pedido(f, [], o["novos"], o["afrouxar"])
            r["_pedido_feito"].update(resposta=resposta, mandados=[])
            return [resposta]
        # a fila da Parceria recusou por outro motivo (card, número): não se promete o que não saiu; a equipe fica sabendo
        whatsapp._ao_crm(f"Corretor {cor.get('nome') or ''} ({grupo.telefone_bonito(tel)}) pediu {perfil_do_pedido(f)}: a Nay "
                         f"achou {', '.join('#' + str(x) for x in o['novos'])}, mas o envio pela Parceria não saiu ({msg[:200]}).")
        return []
    resposta = resposta_do_pedido(f, mandados, o["repetidos"], o["afrouxar"])
    if not mandados and guardado and mesmo_pedido_do_corretor(guardado.get("f"), f) and not guardado.get("mandados"):
        # o mesmo pedido, já respondido, e nada novo: diz uma vez que conferiu, sem "tenho sim" (e sem repetir a frase)
        resposta = f"Conferi de novo: {perfil_do_pedido(f)[:1].lower()}{perfil_do_pedido(f)[1:]} não tenho agora. " \
                   "Se entrar algum, te chamo por aqui."
    r["_pedido_feito"].update(resposta=resposta, mandados=mandados)
    return [resposta]


_MARCADOS: dict = {"em": 0.0, "fins": None}
_MARCADOS_TRAVA = threading.Lock()


def _marcados_no_crm() -> tuple[set[str], set[str], set[str]]:
    """(corretor, não corretor, mandado para a Rayssa) pelo que o CRM diz da conversa do Leads (a linha Z-API da
    captação): o tipo escolhido à mão (tipo_contato) vence; sem ele, "corretor/CRECI/imobiliária" no título conta como
    corretor (a mesma leitura de /api/captacao/corretores). Mandado para a Rayssa: o "Enviar para Rayssa" (mudou_para
    'parceria') ou a aba Rayssa da Parceria (etapa_parceria 'rayssa'), em qualquer linha. Falhou = nada."""
    from olx import config
    if not config.CRM_DATABASE_URL:
        return set(), set(), set()
    import psycopg2
    sim, nao, rayssa = set(), set(), set()
    c = None
    try:
        c = psycopg2.connect(config.CRM_DATABASE_URL, connect_timeout=5, application_name="nay-olx-corretores",
                             options="-c statement_timeout=15000 -c default_transaction_read_only=on")
        with c.cursor() as cur:
            cur.execute("""
                SELECT right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8),
                       l.custom_attributes->>'tipo_contato', coalesce(l.title, '') ~* '(corretor|creci|imobili)'
                  FROM leads l JOIN integrations i ON i.id = l.integration_id
                 WHERE l.deleted_at IS NULL AND i.type = 'whatsapp_zapi_captacao'
                   AND (coalesce(l.custom_attributes->>'tipo_contato', '') <> '' OR coalesce(l.title, '') ~* '(corretor|creci|imobili)')""")
            for fim8, tipo, no_nome in cur.fetchall():
                if len(fim8 or "") != 8:
                    continue
                if tipo:
                    (sim if tipo == "corretor" else nao).add(fim8)
                elif no_nome:
                    sim.add(fim8)
            cur.execute("""
                SELECT DISTINCT right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8)
                  FROM leads l
                 WHERE l.deleted_at IS NULL
                   AND (l.custom_attributes->>'mudou_para' = 'parceria' OR l.custom_attributes->>'etapa_parceria' = 'rayssa')""")
            rayssa = {f for (f,) in cur.fetchall() if len(f or "") == 8}
    except Exception:  # noqa: BLE001
        log.exception("não li os tipos de contato no crmdb")
        return set(), set(), set()
    finally:
        if c is not None:
            c.close()
    return sim, nao, rayssa


def corretores_marcados(conn) -> frozenset:
    """Os 8 últimos dígitos de quem está marcado como corretor no Leads (8595), o mesmo "Corretor · Nay atende" do CRM:
    crm_leads_corretores (541: disse que é corretor/CRECI/imobiliária, a lista de corretores, os grupos, a Nay Corretores,
    o contato de imóvel de parceiro...) + o CRM (_marcados_no_crm). Fora: a equipe, os nossos números e os corretores que
    a Nay chama para as visitas (visita_corretores / visita_locacao), que trabalham com a gente. E SÓ os mandados para a
    Rayssa (Pedro, 04/11: "atende os que foram mandados para a Rayssa"; os com o Lucas que não foram ficam com ele).
    Relida a cada
    MARCADOS_A_CADA_S; enquanto uma linha relê, as outras usam a de antes. Falhou sem nenhuma lida: vazia (fica a regra
    de antes, busca_corretor_e)."""
    if _MARCADOS["fins"] is not None and time.monotonic() - _MARCADOS["em"] < MARCADOS_A_CADA_S:
        return _MARCADOS["fins"]
    if not _MARCADOS_TRAVA.acquire(blocking=_MARCADOS["fins"] is None):
        return _MARCADOS["fins"]
    try:
        if _MARCADOS["fins"] is not None and time.monotonic() - _MARCADOS["em"] < MARCADOS_A_CADA_S:
            return _MARCADOS["fins"]
        try:
            linhas = banco.linhas(conn, "SELECT fone8, motivo FROM crm_leads_corretores()")
            fins = {l["fone8"] for l in linhas if "da equipe" not in (l.get("motivo") or "")}
            sim, nao, rayssa = _marcados_no_crm()
            fins = ((fins | sim) - nao) & rayssa
            from olx import visita
            cfg = banco.chaves(conn)
            fins -= {f[-8:] for _n, f in visita.corretores(cfg) + visita.corretores(cfg, "visita_locacao")}
            fins -= set(banco.um(conn, "SELECT coalesce(busca_nossos_numeros(), '{}')") or [])
            _MARCADOS.update(em=time.monotonic(), fins=frozenset(x for x in fins if len(x or "") == 8))
        except Exception:  # noqa: BLE001
            conn.rollback()
            log.exception("não li os corretores marcados; fica a lista de antes")
            # tenta de novo em 2 min
            _MARCADOS.update(em=time.monotonic() - MARCADOS_A_CADA_S + 120, fins=_MARCADOS["fins"] or frozenset())
        return _MARCADOS["fins"]
    finally:
        _MARCADOS_TRAVA.release()


def e_corretor_marcado(conn, telefone: str | None) -> bool:
    """Para a Nay Leads (whatsapp.py): esta pessoa é da Nay Corretores, não dela."""
    t8 = re.sub(r"\D", "", telefone or "")[-8:]
    return len(t8) == 8 and t8 in corretores_marcados(conn)


def _pendentes_corretores(conn) -> list[dict]:
    """Quem é corretor da busca e escreveu (e parou de escrever há 30 s) depois da última mensagem lida.
    04/11 (Pedro: "todos que estão marcados como corretores, mesmo no número Leads ... esses que eu passei para a Rayssa,
    pode pôr a Nay para atender todos eles"): além do corretor da busca (busca_corretor_e), o corretor MARCADO
    (corretores_marcados), mesmo que já tenha sido cliente da Nay Leads (olx_lead_whatsapp; ela não atende mais) e mesmo
    com o "Enviar para Rayssa" (etapa 'rayssa', que cala só a Nay Leads). Fica de fora quando a Nay da captação (campanha)
    está com ele (captacao_leads sem humano) ou ele está respondendo a consulta de uma visita (olx_visita_consulta)."""
    return banco.linhas(conn, """
        SELECT right(regexp_replace(m.telefone, '\\D', '', 'g'), 8) AS t8, max(m.telefone) AS telefone, max(m.id) AS ate,
               max(m.criada_em) AS ultima
          FROM captacao_mensagens m
          LEFT JOIN privado.busca_corretor bc ON bc.telefone8 = right(regexp_replace(m.telefone, '\\D', '', 'g'), 8)
         WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '2 days'
           AND m.id > coalesce(bc.ultima_lida, 0)
           AND coalesce(bc.estado, '') NOT IN ('humano')
           AND (busca_corretor_e(m.telefone)
                OR (right(regexp_replace(m.telefone, '\\D', '', 'g'), 8) = ANY(%(marcados)s::text[])
                    AND m.criada_em > now() - make_interval(hours => %(janela)s)
                    AND NOT EXISTS (SELECT 1 FROM captacao_leads l
                                     WHERE right(regexp_replace(coalesce(l.telefone, ''), '\\D', '', 'g'), 8)
                                           = right(regexp_replace(m.telefone, '\\D', '', 'g'), 8)
                                       AND l.humano_assumiu_em IS NULL)
                    AND NOT EXISTS (SELECT 1 FROM privado.olx_visita_consulta v
                                     WHERE right(regexp_replace(coalesce(v.telefone, ''), '\\D', '', 'g'), 8)
                                           = right(regexp_replace(m.telefone, '\\D', '', 'g'), 8)
                                       AND v.estado = 'esperando')))
         GROUP BY 1
        HAVING max(m.criada_em) < now() - interval '30 seconds'
         ORDER BY max(m.criada_em) LIMIT 4""", {"marcados": sorted(corretores_marcados(conn)), "janela": MARCADO_JANELA_H})


# ── 5c. O QUE O CORRETOR QUER (04/11/2026, a revisão das conversas reais da Nay Corretores) ──
# Os erros de 04/11 tinham a mesma raiz: a Nay agia antes de entender. "TEM ALGUMA COISA ATÉ 300 MIL VENDA" virou pedido
# de cadastro; o NOSSO pedido do grupo encaminhado virou pedido dele; o link de uma casa NOSSA com "temos cliente
# interessado em visitar" virou cadastro (o #9129, em dobro do #2462); cada "vc não enviou nenhuma" virou um pedido novo.
# Agora um entendimento só, antes de agir: pedido | oferta | visita | reclamacao | duvida | outro -- o do modelo, com as
# travas que o código sabe sozinho.
INTENCOES = ("pedido", "oferta", "visita", "reclamacao", "duvida", "outro")
VISITA_NO_TEXTO = re.compile(r"\b(visit\w*|agend\w*|conhecer o im[oó]vel|levar (?:o |meu |minha |a )?client\w*|"
                             r"client\w* interessad\w*)", re.I)


def entender_corretor(r: dict, novas: list[str], nosso: dict | None, im_anuncio: dict | None, citou_nosso_pedido: bool,
                      tem_pedido: bool = False) -> str:
    """A intenção do turno: a do modelo ("intencao"; o formato antigo pede_imovel/oferece_imovel também vale), corrigida
    pelo que o código sabe: o anúncio NOSSO não é oferta dele (com visita no texto é visita); o nosso pedido do grupo
    encaminhado não é pedido dele; a reclamação sem pedido nenhum (nem agora nem antes) fica com o balão do modelo."""
    i = whatsapp._normal(str(r.get("intencao") or "")).replace(" ", "")
    if i not in INTENCOES:
        i = "pedido" if r.get("pede_imovel") else "oferta" if r.get("oferece_imovel") else "outro"
    texto = " ".join(novas or [])
    im = sem_marcas(r.get("imovel") if isinstance(r.get("imovel"), dict) else {})
    if nosso is not None and i in ("oferta", "outro", "duvida"):
        if VISITA_NO_TEXTO.search(texto):
            i = "visita"
        elif i == "oferta" and (not tem_identidade(im) or mesmo_imovel(im_anuncio, im)):
            i = "duvida"                  # o imóvel "oferecido" é o do nosso anúncio
    if citou_nosso_pedido and i in ("pedido", "reclamacao") and not codigos_do_pedido(r.get("pedido")):
        i = "oferta" if (r.get("oferece_imovel") or tem_identidade(im)) else "outro"
    if i == "reclamacao" and not tem_pedido and not pedido_do_corretor(r.get("pedido")):
        i = "duvida"                      # reclama de outra coisa: o modelo responde
    return i


def _avisar_revisao(conn, cor: dict, codigos: list[int], motivo: str) -> None:
    """Dados que não fecham num imóvel só ficam em Rascunho e a equipe confere (Pedro: dados conflitantes não viram
    Disponível)."""
    whatsapp._ao_crm(f"Corretor {cor.get('nome') or ''} ({grupo.telefone_bonito(cor['telefone'])}): {motivo} "
                     f"Pré-cadastro{'s' if len(codigos) > 1 else ''} {', '.join('#' + str(x) for x in codigos)} em Rascunho: "
                     "confiram os dados e as fotos antes de publicar.")


def _atender_oferta(conn, cor: dict, r: dict, b: dict | None, c: dict, *, ja: dict, anuncio: dict | None, do_anuncio: dict,
                    fotos: int, docs: int, fotos_anuncio: list[str], novas: list[str], baloes: list[str]) -> list[str]:
    """O imóvel que ele oferece: anota, cadastra (pré-cadastro de parceiro) e, completo, oferece ao cliente da busca.
    04/11: imóvel diferente do anotado abre um pré-cadastro NOVO (o #9130 juntou o Simon Bolívar e o Smart Tarumã);
    vários de uma vez, um Rascunho para cada e nenhum Disponível sozinho (as fotos vieram misturadas: o #9132); o
    condomínio da nossa lista dá o bairro; e o imóvel é anotado mesmo quando não serve à busca (o ...1009 tinha o Village
    Vert esquecido a cada turno porque "serve" era "nao", e a Nay perguntava de novo o que ele tinha escrito)."""
    t8 = _tel8(cor["telefone"])
    novo = sem_marcas(r.get("imovel") if isinstance(r.get("imovel"), dict) else {})
    if b and r.get("serve") == "nao":
        b = None                          # não serve a essa busca: entra na base e a revisita olha as outras
    antes = sem_marcas(cor.get("imovel"))
    outro = bool(cor.get("codigo")) and tem_identidade(novo) and (
        r.get("outro_imovel") is True or (tem_identidade(antes) and not mesmo_imovel(antes, novo)))
    revisar = bool((cor.get("imovel") or {}).get("_revisar"))
    if outro:
        # outro imóvel: começa do zero (o anúncio só vale se for dele); o pré-cadastro de antes fica como estava
        log.info("corretor …%s: outro imóvel (o #%s era outro): pré-cadastro novo", t8[-4:], cor.get("codigo"))
        base = do_anuncio if anuncio and mesmo_imovel(do_anuncio, novo) else {}
        if not base:
            anuncio, fotos_anuncio = None, []
        ja, revisar = base, False
        cor = {**cor, "codigo": None}
        fotos = _qtd_fotos(conn, t8, None) + len(fotos_anuncio)
    mais = [sem_marcas(x) for x in (r.get("mais_imoveis") or []) if isinstance(x, dict) and tem_identidade(x)]
    im = venda_pelo_valor(completar_imovel(conn, juntar_imovel(ja, novo), novas))
    if mais:
        revisar = True                    # as fotos de mais de um imóvel vieram juntas: ninguém vira Disponível sozinho
    guardadas = {k: v for k, v in marcas(cor.get("imovel")).items() if not outro or k == "_pedido"}
    im = {**guardadas, **im, **({"_revisar": True} if revisar else {})}
    if not revisar:
        im.pop("_revisar", None)
    banco.um(conn, """UPDATE privado.busca_corretor SET imovel = %s::jsonb, busca = %s, estado = 'cadastrando',
                       codigo = CASE WHEN %s THEN NULL ELSE codigo END WHERE telefone8 = %s""",
             (json.dumps(im, ensure_ascii=False, default=str), b["id"] if b else None, outro, t8))
    cor = {**cor, "imovel": im, "busca": b["id"] if b else None}
    primeira = not cor.get("codigo")
    # pronto de verdade: as fotos guardadas (o documento não fica no cadastro) e nada a conferir
    falta = falta_no_imovel(sem_marcas(im), fotos)
    pronto = not falta and not revisar
    completo = pronto and c["corretor"] == "sim"
    codigo = cadastrar(conn, {**cor, "imovel": sem_marcas(im)}, b, ativo=completo, fotos_do_anuncio=fotos_anuncio, anuncio=anuncio)
    banco.um(conn, "UPDATE privado.busca_corretor SET codigo = %s WHERE telefone8 = %s", (codigo, t8))
    if mais:
        extras = [cadastrar(conn, {**cor, "codigo": None, "imovel": venda_pelo_valor(completar_imovel(conn, x, []))}, None,
                            ativo=False, com_fotos=False) for x in mais]
        _avisar_revisao(conn, cor, [codigo, *extras], f"mandou {1 + len(extras)} imóveis na mesma conversa; as fotos vieram "
                                                      f"juntas e ficaram no #{codigo}.")
    if docs and fotos < FOTOS_MINIMAS and (cor.get("imovel") or {}).get("_aviso_docs") != docs:
        # o documento não é guardado pelo recebedor das fotos: a equipe baixa do WhatsApp
        _avisar_revisao(conn, cor, [codigo], f"mandou {docs} foto(s) como ARQUIVO (documento), que não entram no cadastro "
                                             "sozinhas: baixem do WhatsApp do Leads.")
        banco.um(conn, """UPDATE privado.busca_corretor SET imovel = imovel || jsonb_build_object('_aviso_docs', %s::int)
                           WHERE telefone8 = %s""", (docs, t8))
    if primeira and b:
        banco.um(conn, "UPDATE privado.busca_cliente SET ofertas = ofertas || %s::jsonb WHERE id = %s",
                 (json.dumps([{"tel": cor["telefone"], "nome": cor.get("nome"), "codigo": codigo,
                               "em": datetime.now(MANAUS).isoformat(timespec="minutes"), "estado": "cadastrando"}], ensure_ascii=False), b["id"]))
        passo(conn, b["id"], "corretor", f"Corretor {cor.get('nome') or ''} (…{t8[-4:]}) ofereceu um imóvel: pré-cadastro #{codigo}")
    if pronto and not b:
        # 488: cadastro completo e nenhuma busca em vista: a Nay dos leads recebe a opção nova (a nossa base é
        # olhada de novo agora por todas as buscas abertas) e o corretor sabe que ficou cadastrado
        banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'ofertado' WHERE telefone8 = %s", (t8,))
        banco.um(conn, "UPDATE privado.busca_cliente SET base_em = NULL WHERE estado = 'buscando'")
        log.info("corretor …%s: imóvel #%s cadastrado; as buscas abertas olham a base de novo", t8[-4:], codigo)
        if not baloes:
            baloes = ["Perfeito, obrigado! Vou passar a opção para o cliente e, se ele se interessar, entro em contato para agendar uma visita."]
    elif pronto:
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
                                        "teste": f"Imóvel #{codigo} completo (teste: não foi ao cliente)",
                                        # 04/11: a régua única barrou (o motivo fica no registro dos agentes)
                                        "nao_serve": f"Imóvel #{codigo} completo, mas não serve ao pedido do cliente: não foi",
                                        "espera": f"Imóvel #{codigo} completo; vai ao cliente na revisita da base "
                                                  f"({whatsapp.oferta_sozinha_espera(conn, whatsapp._lead(conn, b['lead']), b.get('filtros')) or 'agora pode ir'})"}[onde])
        if not baloes and onde == "nao_serve":
            # 04/11: a régua barrou; ao corretor não se diz que foi ao cliente
            baloes = ["Obrigado! Esse não fecha com tudo o que o cliente pediu, mas ficou cadastrado aqui e, se servir "
                      "para outro cliente, te chamo."]
        if not baloes:
            baloes = ["Perfeito, obrigado! Já passei a opção para o cliente e, se ele se interessar, entro em contato para agendar uma visita."
                      if onde != "espera" else
                      "Perfeito, obrigado! Vou passar a opção para o cliente e, se ele se interessar, entro em contato para agendar uma visita."]
    elif b:
        passo(conn, b["id"], "corretor", f"#{codigo}: falta {', '.join(falta) or 'conferir (dados de mais de um imóvel)'}")
    conn.commit()
    return baloes


def _atender_visita(conn, cor: dict, nosso: dict | None, fichas: list[dict], novas: list[str], baloes: list[str]) -> list[str]:
    """04/11 (o ...7891: "Temos cliente interessado em visitar amanhã... 14:30" sobre uma casa NOSSA; ficou "Estou no
    aguardo" sem resposta): o cliente DELE quer visitar um imóvel NOSSO. Não é cadastro e a Nay Corretores não marca
    visita: a equipe recebe o aviso com o imóvel e o que ele escreveu, e combina com ele (a conversa passa à equipe)."""
    t8 = _tel8(cor["telefone"])
    cods = [c for c in [(nosso or {}).get("codigo"), *[whatsapp._int(f.get("codigo")) for f in fichas or []]] if c]
    qual = f"o nosso #{cods[0]}" if cods else "um imóvel nosso"
    whatsapp._ao_crm(f"Corretor {cor.get('nome') or ''} ({grupo.telefone_bonito(cor['telefone'])}) quer visitar {qual} com o "
                     f"cliente dele: \"{' / '.join(t.strip() for t in novas if t.strip())[:300]}\". Combinem a visita com ele "
                     "pelo WhatsApp Leads; a Nay Corretores parou nessa conversa.")
    banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'humano', humano_em = now() WHERE telefone8 = %s", (t8,))
    conn.commit()
    log.info("corretor …%s quer visitar %s: a equipe foi avisada", t8[-4:], qual)
    # o balão do modelo, se não fala de cliente nosso nem promete o que é da equipe; senão uma frase curta
    ok = [x for x in baloes if not re.search(r"\b(com o|com a|ao|o nosso|meu|nosso) client", x, re.I)]
    return ok[:1] or ["Show! Vou ver o horário com a equipe e já te retorno por aqui."]


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
        # 04/11: o corretor marcado que a Nay Corretores pega agora (veio da Nay Leads, ou a Rayssa estava com ele) começa a
        # leitura depois da última fala nossa para ele: a fala antiga da equipe não o põe em 'humano' na hora (Pedro: "esses
        # que eu passei para a Rayssa, pode pôr a Nay para atender todos eles")
        desde = 0
        if t8 in corretores_marcados(conn) and not banco.um(conn, "SELECT busca_corretor_e(%s)", (p["telefone"],)):
            desde = banco.um(conn, """SELECT coalesce(max(id), 0) FROM captacao_mensagens WHERE direcao = 'enviada' AND id < %s
                                         AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""",
                             (p["ate"], t8)) or 0
        banco.um(conn, """INSERT INTO privado.busca_corretor (telefone8, telefone, nome, origem, classificado_em, ultima_lida)
                          VALUES (%s, %s, (SELECT nome FROM corretores WHERE right(regexp_replace(telefone, '\\D', '', 'g'), 8) = %s LIMIT 1),
                                  %s, now(), %s)
                          ON CONFLICT (telefone8) DO UPDATE SET origem = coalesce(busca_corretor.origem, EXCLUDED.origem),
                              classificado_em = coalesce(busca_corretor.classificado_em, now())""",
                 (t8, re.sub(r"\D", "", p["telefone"]), t8, origem, int(desde)))
        cor = banco.linhas(conn, "SELECT * FROM privado.busca_corretor WHERE telefone8 = %s", (t8,))[0]
        conversa = _conversa_corretor(conn, t8)
        # a equipe escreveu para ele pelo 8595 depois que a Nay começou: a conversa é dela
        if any(m["direcao"] == "enviada" and m["origem"] == "humano" and m["id"] > (cor["ultima_lida"] or 0) for m in conversa):
            banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'humano', humano_em = now(), ultima_lida = %s WHERE telefone8 = %s",
                     (p["ate"], t8))
            conn.commit()
            continue
        novas = [m["texto"] or "" for m in conversa if m["direcao"] == "recebida" and m["id"] > (cor["ultima_lida"] or 0)]
        fotos = _qtd_fotos(conn, t8, cor.get("codigo"))
        docs = docs_recebidos(conversa)
        anuncio = anuncio_da_conversa(conn, t8, [m["texto"] or "" for m in conversa])
        # 04/11 (o ...7891): o anúncio NOSSO não é o imóvel dele: não entra no "já anotado" nem no cadastro
        nosso = nosso_do_anuncio(conn, anuncio) if anuncio else None
        do_anuncio = imovel_do_anuncio(conn, anuncio) if anuncio and nosso is None else {}
        fotos_anuncio = [u for u in (anuncio or {}).get("fotos") or [] if u][:FOTOS_DO_ANUNCIO] if nosso is None else []
        if fotos < FOTOS_MINIMAS:
            fotos += len(fotos_anuncio)
        ja = venda_pelo_valor(juntar_imovel(do_anuncio, sem_marcas(cor.get("imovel"))))
        equipe_por_perto = any(m["origem"] == "equipe_crm" and m["criada_em"] > datetime.now(timezone.utc) - timedelta(hours=EQUIPE_NA_CONVERSA_H)
                               for m in conversa)
        # 04/11: a ficha do imóvel NOSSO que ele citou (código, link ou nome), para a dúvida dele; só o que está no site
        try:
            fichas = whatsapp._fichas_citadas(conn, conversa[-10:])
        except Exception:  # noqa: BLE001 -- a ficha não derruba a conversa
            log.exception("corretor …%s: a ficha citada falhou", t8[-4:])
            fichas = []
        try:
            r = modelo.chamar(PROMPT_CORRETOR, _turno_corretor(conn, cor, conversa, ativas, fotos, anuncio, ja, fichas,
                                                               nosso=nosso, docs=docs),
                              no="olx.corretor")
        except Exception:  # noqa: BLE001
            log.exception("corretor …%s: o modelo falhou", t8[-4:])
            continue
        banco.um(conn, "UPDATE privado.busca_corretor SET ultima_lida = %s, atualizado_em = now() WHERE telefone8 = %s", (p["ate"], t8))
        conn.commit()
        # 04/11: O QUE ELE QUER, antes de agir (pedido, oferta, visita, reclamação, dúvida), com as travas do código
        citou = any(sem_nosso_pedido(t)[1] for t in novas)
        intencao = entender_corretor(r, novas, nosso, do_anuncio or imovel_do_anuncio(conn, anuncio) if anuncio else {}, citou,
                                     bool(pedido_guardado(cor)))
        ids = {b["id"]: b for b in ativas}
        bid = r.get("busca_id") if r.get("busca_id") in ids else cor.get("busca")
        citada = busca_do_pedido_citado(ativas, novas) if citou else None
        if citada:
            bid = citada["id"]                    # ele respondeu ao NOSSO pedido do grupo: é dessa busca
        if not bid:
            # 30/10 (revisão, o Augusto ...8279 e a busca 85 da Karoline): a busca que o chamou pela OLX está em
            # busca_contato; sem ela o imóvel entrava solto e ele ouvia "vou passar ao cliente" de um imóvel que não servia
            bid = banco.um(conn, """SELECT c.busca FROM privado.busca_contato c JOIN privado.busca_cliente b ON b.id = c.busca
                                     WHERE c.telefone8 = %s AND b.estado = 'buscando' ORDER BY c.em DESC LIMIT 1""", (t8,))
        b = ids.get(bid) or (banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE id = %s", (bid,)) or [None])[0] if bid else None
        baloes = [str(x).strip() for x in (r.get("baloes") or []) if str(x).strip()][:2]
        if equipe_por_perto and baloes:
            # Pedro, 30/10: a equipe está falando com ele (a Stela, com o link da OLX); a Nay não fala por cima, só anota
            log.info("corretor …%s: a equipe está na conversa; a Nay não responde", t8[-4:])
            baloes = []
        pede = intencao in ("pedido", "reclamacao")
        if intencao == "oferta" or (anuncio and nosso is None and intencao not in ("pedido", "reclamacao", "visita")):
            # 488: o imóvel do corretor entra na base mesmo sem busca que sirva ("serve" é só das buscas ativas)
            baloes = _atender_oferta(conn, cor, r, b, c, ja=ja, anuncio=anuncio if nosso is None else None,
                                     do_anuncio=do_anuncio, fotos=fotos, docs=docs, fotos_anuncio=fotos_anuncio,
                                     novas=novas, baloes=baloes)
        elif intencao == "visita" and not equipe_por_perto:
            baloes = _atender_visita(conn, cor, nosso, fichas, novas, baloes)
            r["responder"] = True
        if pede and equipe_por_perto:
            log.info("corretor …%s pediu imóvel, mas a equipe está na conversa: a Nay não manda nem responde", t8[-4:])
        elif pede:
            # 04/11 (Pedro: "mandar os imóveis e responder as solicitações dele"): o pedido do cliente DELE
            try:
                resposta = atender_pedido(conn, cor, r, c)
                if r.get("_pedido_feito"):
                    guardar_pedido(conn, t8, cor, r["_pedido_feito"])
                    conn.commit()
            except Exception:  # noqa: BLE001 -- um corretor não para os outros
                conn.rollback()
                log.exception("corretor …%s: o pedido falhou", t8[-4:])
                resposta = []
            baloes, r["responder"] = resposta, bool(resposta)
        # 04/11 (o ...5600 ouviu "é casa ou apartamento?" duas vezes; o ...2985 ouviu a mesma frase cinco vezes): nada que a
        # Nay já disse ou perguntou a ele sai de novo
        nossas = [m["texto"] for m in conversa if m["direcao"] == "enviada" and (m["texto"] or "").strip()][-30:]
        baloes = whatsapp.sem_repetir(sem_pergunta_repetida(baloes, ja_perguntado(conversa, 30)), nossas)
        if r.get("responder") and baloes:
            for n, t in enumerate(baloes):
                if n:
                    time.sleep(2)
                if c["corretor"] == "teste":
                    if c["teste"]:
                        _enviar(c["teste"], f"[teste: iria para o corretor …{t8[-4:]}]\n{t}")
                else:
                    _guardar_enviada(conn, cor["telefone"], t, _enviar(cor["telefone"], t))
                    conn.commit()
        feitos += 1
    return feitos


# ── o laço ──
def _card_do_lead(conn) -> int:
    from olx import busca_do_lead              # aqui dentro: ele importa este módulo
    return busca_do_lead.atualizar(conn)


def uma_volta(conn) -> dict:
    c = _cfg(conn)
    if c["fluxo"] == "nao":
        return {}
    r = {"registro": sincronizar(conn, c)}
    # a ordem de cada volta: o que está abaixo do mínimo sai; depois a nossa base e, juntos, grupos e OLX; os corretores
    for nome, f in (("minimo", lambda: encerrar_abaixo_do_minimo(conn, c)),
                    ("membros", lambda: atualizar_membros(conn)), ("base", lambda: base_volta(conn, c)),
                    ("grupos", lambda: grupos_volta(conn, c)), ("grupos_repete", lambda: grupos_repete(conn, c)),
                    ("olx", lambda: olx_volta(conn, c)), ("corretores", lambda: corretores_volta(conn, c)),
                    # 29/10: o card da busca no CRM acompanha o pedido de agora (de 15 em 15 min)
                    ("card", lambda: _card_do_lead(conn))):
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
