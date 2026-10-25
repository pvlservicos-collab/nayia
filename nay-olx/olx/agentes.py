"""OS AGENTES DA NAY LEADS (Pedro, 24/10/2026): o atendimento do WhatsApp 8595 separado por papel, e cada ativação medida.

"Separa o atendimento da Nay Lead em vários agentes: 1 agente mestre que aciona outros agentes, 1 que atende e tira
dúvidas, 1 que escolhe imóveis, 1 de busca, 1 que organiza a visita, 1 de revisão" e "de um jeito bem metrificável,
para ser escalável futuramente".

  MESTRE       perguntas fechadas ao JEV (typesafe/jev-1.13, Decisions API da OpenRouter, ~0,3 s) sobre a mensagem nova:
               quer imóvel? dúvida? visita? fotos? é com a equipe? só agradeceu? Escolhe o CAMINHO.
  ATENDIMENTO  a voz (a Luna, gpt-6-luna): o ÚNICO que escreve ao cliente. Recebe só as regras do caminho escolhido
               (o prompt de whatsapp.PROMPT cortado por seção). Na dúvida do mestre, na primeira mensagem ou se o corte
               falhar: o prompt inteiro, como era (nunca fica pior por falta de regra).
  IMÓVEIS      a busca na base (olx_cliente_buscar) e o VETO do JEV antes de cada card ("este imóvel serve?").
  BUSCA, VISITA, REVISÃO, HUMANO: os módulos que já existem (buscas.py, visita.py, a fila de perguntas, a equipe);
               aqui só se registra quando ativam. A linha do tempo do banco (489) junta o resto.

A chave `agentes` de privado.olx_config (lida de 30 em 30 s): nao (como era) | sombra (o mestre e o veto decidem e
gravam, mas nada muda no que sai) | sim. Cada ativação vira uma linha em privado.agente_evento (489): agente, ação,
decisão, confiança, ms, tokens, custo, modo. Medir nunca derruba o atendimento: conexão própria e falha calada.
"""
from __future__ import annotations

import json
import logging
import os
import re
import threading
import time
import uuid

import requests

from olx import banco

log = logging.getLogger("olx.agentes")

URL_JEV = "https://openrouter.ai/api/alpha/decisions"
MODELO_JEV = "typesafe/jev-1.13"
ENV_DO_CORE = os.environ.get("OLX_ENV_DO_CORE", "/docker/nay-core/.env")   # a chave da OpenRouter mora lá (só root lê)
ORCAMENTO_S = 6.0
CACHE_S = 30
LIMIAR_ROTA = 0.30      # o caminho entra no prompt a partir daqui (melhor sobrar regra que faltar)
LIMIAR_CORTESIA = 0.85  # "só agradeceu" com essa certeza e nada mais pedido: não responde
LIMIAR_VETO = 0.35      # o imóvel abaixo disso não sai (no modo sim)
ROTAS = ("imoveis", "duvida", "visita", "fotos", "equipe", "cortesia")

CONTEXTO = ("State: a WhatsApp chat between a client ('cliente') and Nay, the assistant of the Imob Easy real-estate "
            "agency in Manaus (Brazil). Judge ONLY the client's newest messages ('novas'), using the rest as context.")
PERGUNTAS = {
    "imoveis": ("Does the client want to RECEIVE property options now, or is she giving or changing what she is looking "
                "for (price, neighborhood, rooms, rent or buy, type, furniture, financing)?",
                "She asks for options or answers/changes a search criterion. Ex: 'até 3 mil', 'no Aleixo', 'tem casa?', "
                "'quero comprar', 'mobiliado', 'tanto faz'",
                "She asks about one property, talks about a visit, photos, thanks, or something else."),
    "duvida": ("Does the client ask a question about a specific property (price, condo fee, floor, pets, availability, "
               "what is included, size, documents of the property)?",
               "A question about a property's details. Ex: 'aceita pet?', 'qual o andar?', 'o condomínio inclui o quê?'",
               "No question about a property's details."),
    "visita": ("Does the client talk about visiting a property: wants to schedule, gives a day or time, confirms, "
               "changes or cancels a visit?",
               "Anything about a visit. Ex: 'quero visitar', 'amanhã às 10h', 'sim, confirmo', 'pode ser sábado?'",
               "Nothing about a visit."),
    "fotos": ("Does the client ask for photos or a video of a property (or of a part of it)?",
              "She asks for photos or video. Ex: 'tem mais fotos?', 'manda foto do quarto'",
              "She does not ask for photos."),
    "equipe": ("Is this for a human of the agency: documents, contract, complaint, wants to talk to a person, a broker "
               "offering partnership, the client wanting to sell or rent HER OWN property, a discount or a proposal?",
               "One of those. Ex: 'quero falar com o corretor', 'aceita proposta?', 'sou corretor', 'quero vender o meu'",
               "None of those."),
    "cortesia": ("Are the client's newest messages ONLY a thanks, ok, greeting or short acknowledgment, with nothing to "
                 "answer or do?",
                 "Only courtesy. Ex: 'obrigada', 'ok', 'certo', 'bom dia', 'aguardo'",
                 "There is a question, a request, an answer to Nay's question or new information."),
}

_LOCAL = threading.local()
_CONN: list = [None]
_SEM_BANCO = [0.0]
_MODO: list = [0.0, "nao"]


# ───────────────────────────── a chave e o registro ─────────────────────────────
def _conn():
    if time.time() - _SEM_BANCO[0] < CACHE_S:
        return None
    c = _CONN[0]
    if c is None or c.closed:
        try:
            c = _CONN[0] = banco.conectar()
        except Exception:  # noqa: BLE001
            _SEM_BANCO[0] = time.time()
            return None
    return c


def _falhou() -> None:
    _SEM_BANCO[0] = time.time()
    try:
        if _CONN[0] is not None:
            _CONN[0].close()
    except Exception:  # noqa: BLE001
        pass
    _CONN[0] = None


_CHAVES: list = [0.0, {}]


def _chaves() -> dict:
    """As chaves 'agentes*' de privado.olx_config, relidas de 30 em 30 s."""
    if time.time() - _CHAVES[0] < CACHE_S:
        return _CHAVES[1]
    c = _conn()
    valores = _CHAVES[1]
    if c is not None:
        try:
            valores = {r["chave"]: (r["valor"] or "").strip().lower()
                       for r in banco.linhas(c, "SELECT chave, valor FROM privado.olx_config WHERE chave LIKE 'agentes%%'")}
        except Exception:  # noqa: BLE001
            _falhou()
    _CHAVES[:] = [time.time(), valores]
    return valores


def modo() -> str:
    """nao | sombra | sim (privado.olx_config 'agentes'), relida de 30 em 30 s. Um modo forçado (o replay) vence."""
    forcado = getattr(_LOCAL, "modo", None)
    if forcado:
        return forcado
    valor = _chaves().get("agentes") or "nao"
    valor = valor if valor in ("nao", "sombra", "sim") else "nao"
    if valor != _VISTO[0]:
        log.info("agentes: modo %s (era %s)", valor, _VISTO[0])   # o que o serviço enxerga, a cada troca
        _VISTO[0] = valor
    return valor


_VISTO: list = [None]


def corte_ligado() -> bool:
    """'agentes_corte' = sim: o Atendimento recebe só as regras do caminho. Desligado (padrão desde o replay de 24/10):
    o prompt vai INTEIRO, como era -- cortar economizava ~20% de tokens (centavos) e era a única coisa que mudava as
    regras; no replay ele perdeu turnos por esquecer pendências. O mestre continua escolhendo o caminho, calando a
    cortesia e medindo; o veto continua nos imóveis."""
    forcado = getattr(_LOCAL, "corte", None)
    if forcado is not None:
        return forcado
    return _chaves().get("agentes_corte") == "sim"


def forcar_modo(m: str | None, registro: str | None = None, corte: bool | None = None) -> None:
    """O replay roda como 'sim' e grava como 'replay', sem mexer na chave do banco (e pode forçar o corte)."""
    _LOCAL.modo = m
    _LOCAL.registro = registro
    _LOCAL.corte = corte


def novo_turno(lead: dict) -> str:
    _LOCAL.turno = uuid.uuid4().hex[:12]
    _LOCAL.lead = {"id": lead.get("id"), "telefone": lead.get("telefone")}
    return _LOCAL.turno


def _chave8(telefone) -> str:
    return re.sub(r"\D", "", str(telefone or ""))[-8:]


def registrar(lead: dict | None, agente: str, acao: str, decisao: dict | None = None, confianca=None, ms=None,
              uso: dict | None = None, modelo: str | None = None, erro: str | None = None) -> None:
    """Uma ativação em privado.agente_evento. Modo: 'replay' no replay; 'sombra' quando a chave está em sombra e quem
    registra é o mestre ou o veto (o que realmente aconteceu continua 'real')."""
    if modo() == "nao" and not getattr(_LOCAL, "registro", None):
        return
    lead = lead or getattr(_LOCAL, "lead", None) or {}
    forcado = getattr(_LOCAL, "registro", None)
    if forcado:
        registro = forcado
    elif modo() == "sombra" and (agente == "mestre" or acao.startswith("veto")):
        registro = "sombra"                       # decidiu sem valer
    else:
        registro = "real"
    if registro == "replay" and agente != "mestre" and acao not in ("replay_resumo", "replay_turno"):
        return                                    # no replay só o mestre e o resultado ficam gravados
    c = _conn()
    if c is None:
        return
    u = uso or {}
    try:
        banco.linhas(c, """INSERT INTO privado.agente_evento (lead_id, chave8, agente, acao, turno, decisao, confianca, ms,
                             tokens_entrada, tokens_cache, tokens_saida, custo_usd, modelo, modo, erro)
                           VALUES (%s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                     (lead.get("id"), _chave8(lead.get("telefone")), agente, acao[:60], getattr(_LOCAL, "turno", None),
                      json.dumps(decisao or {}, ensure_ascii=False, default=str), confianca, ms,
                      u.get("tokens_entrada"), u.get("tokens_cache"), u.get("tokens_saida"), u.get("custo_usd"),
                      modelo, registro, (erro or None) and str(erro)[:300]))
    except Exception:  # noqa: BLE001
        log.warning("não registrei o evento %s/%s", agente, acao)
        _falhou()


# ───────────────────────────── o JEV ─────────────────────────────
def _chave_openrouter() -> str:
    k = os.environ.get("OPENROUTER_API_KEY", "")
    if k:
        return k
    try:
        with open(ENV_DO_CORE, encoding="utf-8") as f:
            for linha in f:
                if linha.startswith("OPENROUTER_API_KEY="):
                    return linha.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


def _noul(pergunta: str, sim: str, nao: str) -> dict:
    return {"type": "noul", "instructions": {"question": pergunta, "context": CONTEXTO},
            "criteria": {"true": sim, "false": nao}}


def jev(estado: dict, perguntas: dict, orcamento_s: float = ORCAMENTO_S) -> tuple[dict, dict]:
    """Uma chamada ao JEV com várias perguntas fechadas. Devolve ({chave: probabilidade do sim}, {ms, custo, tokens})."""
    chave = _chave_openrouter()
    if not chave:
        raise RuntimeError("sem OPENROUTER_API_KEY")
    corpo = {"model": MODELO_JEV, "state": estado, "questions": perguntas}
    inicio = time.monotonic()
    erro = "sem tempo"
    for _ in range(2):
        resta = orcamento_s - (time.monotonic() - inicio)
        if resta < 0.5:
            break
        try:
            r = requests.post(URL_JEV, json=corpo, timeout=resta,
                              headers={"Authorization": f"Bearer {chave}", "Content-Type": "application/json"})
        except requests.RequestException as e:
            erro = f"rede: {type(e).__name__}"
            continue
        if r.status_code == 200:
            d = r.json()
            ans = d.get("answers") or {}
            probs = {k: float(v.get("noul")) for k, v in ans.items() if isinstance(v, dict) and v.get("noul") is not None}
            uso = d.get("usage") or {}
            return probs, {"ms": int((time.monotonic() - inicio) * 1000), "custo_usd": uso.get("cost"),
                           "tokens_entrada": uso.get("input_tokens"), "tokens_saida": uso.get("output_tokens"),
                           "modelo": d.get("model") or MODELO_JEV}
        erro = f"HTTP {r.status_code}: {r.text[:160]}"
        if r.status_code not in (408, 429, 500, 502, 503, 524, 529):
            break
    raise RuntimeError(f"jev: {erro}")


# ───────────────────────────── o prompt cortado por caminho ─────────────────────────────
def partes_do_prompt(prompt: str) -> dict[str, str] | None:
    """Corta whatsapp.PROMPT nas seções (=== X ===) e o CAMINHO nos itens 1-6. None se o formato mudou (aí vai inteiro)."""
    try:
        blocos = re.split(r"\n(?==== [^=]+ ===\n)", prompt)
        intro, secoes = blocos[0], {}
        for b in blocos[1:]:
            m = re.match(r"=== ([^=]+) ===\n", b)
            secoes[m.group(1).strip()] = b
        caminho = secoes["O CAMINHO"]
        itens = re.split(r"\n(?=\d\. [A-ZÁÉÍÓÚÇÃÕ ]+[:(])", caminho)
        cab, numerados = itens[0], itens[1:]
        if len(numerados) != 6:
            return None
        ultimo, sep, cauda = numerados[5].partition("\nSeja flexível")
        numerados[5] = ultimo
        p = {"intro": intro, "caminho_cab": cab, "cauda_do_roteiro": "Seja flexível" + cauda if sep else ""}
        for i, nome in enumerate(("abertura", "roteiro", "depois", "visita", "fotos", "foto_parte")):
            p[nome] = numerados[i]
        mapa = {"ORGÂNICO": "organico", "VENDA OU LOCAÇÃO": "venda_locacao", "A EQUIPE NA CONVERSA": "equipe_conversa",
                "QUANDO É COM A EQUIPE": "quando_equipe", "UMA CONFIRMAÇÃO SÓ": "confirmacao", "NUNCA": "nunca",
                "COMO VOCÊ FALA": "fala", "A SUA RESPOSTA": "json"}
        for titulo, b in secoes.items():
            for k, nome in mapa.items():
                if titulo.startswith(k) or k in titulo:
                    p[nome] = b
        precisa = ("intro", "organico", "venda_locacao", "equipe_conversa", "quando_equipe", "confirmacao", "nunca",
                   "fala", "json")
        return p if all(p.get(k) for k in precisa) else None
    except Exception:  # noqa: BLE001
        return None


def prompt_para(prompt: str, rotas: list[str], organico: bool) -> tuple[str, list[str]]:
    """O prompt do Atendimento só com as regras do caminho. Devolve (prompt, seções usadas)."""
    p = partes_do_prompt(prompt)
    if p is None:
        return prompt, ["inteiro (formato mudou)"]
    # O NÚCLEO vai sempre (replay de 24/10: cortar o roteiro e a abertura fez a Nay esquecer o que ficou PENDENTE -- o pet
    # perguntado na OLX, o CRECI -- e pedir a busca antes dos quartos e da mobília; 15 de 45 turnos piores). Só sai o que
    # não tem nada a ver com a mensagem: a visita, as fotos e o orgânico.
    usar = ["intro", "caminho_cab", "abertura", "roteiro", "depois"]
    if "visita" in rotas:
        usar += ["visita"]
    if "fotos" in rotas or "duvida" in rotas:
        usar += ["fotos", "foto_parte"]
    usar += ["cauda_do_roteiro"]
    if organico:
        usar += ["organico"]
    usar += ["venda_locacao", "equipe_conversa", "quando_equipe", "confirmacao", "nunca", "fala", "json"]
    vistos: list[str] = []
    for u in usar:
        if u not in vistos and p.get(u):
            vistos.append(u)
    texto = p["intro"]
    for u in vistos[1:]:
        texto += ("\n" if not texto.endswith("\n") else "") + p[u]
    return texto, vistos


# ───────────────────────────── o mestre ─────────────────────────────
def planejar(prompt: str, lead: dict, conversa: list[dict], novas: list[str], organico: bool,
             pode_calar: bool) -> dict:
    """O mestre: lê as mensagens novas e devolve o plano do turno.
    {"prompt": o prompt do Atendimento, "rotas": [...], "calar": bool, "geral": bool}. No modo 'nao' e no 'sombra' o
    prompt é o inteiro e nada se cala (no sombra o mestre roda e grava, para comparar). `pode_calar`: as mesmas travas
    de hoje (a última fala dela não é pergunta e não espera o sim da visita)."""
    m = modo()
    plano = {"prompt": prompt, "rotas": [], "calar": False, "geral": True}
    if m == "nao":
        return plano
    nay = [x for x in conversa if x.get("direcao") == "enviada" and (x.get("nossa") or x.get("origem") == "resposta")]
    primeira = not nay
    recentes = []
    for x in conversa[-10:]:
        quem = "cliente" if x.get("direcao") == "recebida" else ("nay" if (x.get("nossa") or x.get("origem") == "resposta") else "equipe")
        t = (x.get("texto") or "").strip()
        if t:
            recentes.append(f"{quem}: {t[:300]}")
    estado = {"novas": "\n".join(n for n in novas if n)[:1200] or "(mídia)",
              "ultima_da_nay": ((nay[-1].get("texto") or "")[:400] if nay else ""),
              "conversa_recente": "\n".join(recentes)[-2500:], "etapa": lead.get("etapa") or ""}
    perguntas = {k: _noul(*v) for k, v in PERGUNTAS.items()}
    try:
        probs, uso = jev(estado, perguntas)
        erro = None
    except Exception as e:  # noqa: BLE001
        probs, uso, erro = {}, {"ms": None}, str(e)
    rotas = [k for k in ROTAS if k != "cortesia" and probs.get(k, 0) >= LIMIAR_ROTA]
    calar = (not primeira and pode_calar and probs.get("cortesia", 0) >= LIMIAR_CORTESIA and not rotas)
    geral = primeira or bool(erro) or (not rotas and not calar)
    if geral or not corte_ligado():
        texto, secoes = prompt, ["inteiro"]
    else:
        texto, secoes = prompt_para(prompt, rotas, organico)
    resumo = "calar" if calar else ("geral" if geral else ", ".join(rotas))
    registrar(lead, "mestre", "rotear", {"rotas": (["calar"] if calar else (["geral"] if geral else rotas)),
                                         "probs": {k: round(v, 3) for k, v in probs.items()}, "secoes": secoes,
                                         "primeira": primeira, "resumo": resumo,
                                         "prompt_chars": len(texto), "prompt_inteiro_chars": len(prompt)},
              confianca=max(probs.values()) if probs else None, ms=uso.get("ms"), uso=uso, modelo=uso.get("modelo"),
              erro=erro)
    log.info("lead %s: mestre (%s) -> %s em %s ms%s", lead.get("id"), m, resumo, uso.get("ms"),
             f" [erro: {erro[:120]}]" if erro else "")
    if m == "sombra":
        return plano
    return {"prompt": texto, "rotas": rotas, "calar": calar, "geral": geral, "secoes": secoes}


# ───────────────────────────── imóveis: o veto ─────────────────────────────
def _pedido(filtros: dict) -> str:
    f = filtros or {}
    partes = [f.get("finalidade") or "", f.get("tipo") or ""]
    if f.get("quartos"):
        partes.append(f"{f['quartos']} quartos" + (" (aceita menos)" if f.get("aceita_menos_quartos") else ""))
    if f.get("teto"):
        partes.append(f"até R$ {int(float(f['teto'])):,}".replace(",", "."))
    if f.get("bairros"):
        partes.append("bairros: " + ", ".join(f["bairros"]))
    elif f.get("qualquer_bairro"):
        partes.append("qualquer bairro")
    if f.get("condominio"):
        partes.append("condomínio: " + str(f["condominio"]))
    if f.get("mobilia"):
        partes.append("mobília: " + str(f["mobilia"]))
    if f.get("aceita_escada") is False:
        partes.append("sem escada")
    return "; ".join(p for p in partes if p)


def filtrar_imoveis(lead: dict, filtros: dict, achados: list[dict]) -> list[dict]:
    """O veto do JEV, um imóvel por pergunta numa chamada só. No sim, o que fica abaixo do limiar não sai; no sombra só
    registra. Sem resposta do JEV: sai tudo, como antes."""
    m = modo()
    if m == "nao" or not achados:
        return achados
    perguntas, por_chave = {}, {}
    for a in achados[:8]:
        k = f"i{a['codigo']}"
        ficha = (f"{a.get('tipo') or 'imóvel'}, {a.get('quartos') or '?'} quartos, {a.get('bairro') or ''}"
                 f"{', ' + a['condominio'] if a.get('condominio') else ''}, R$ {int(float(a.get('preco') or 0)):,}").replace(",", ".")
        perguntas[k] = {"type": "noul",
                        "instructions": {"question": f"Does this property fit what the client is looking for? Property: {ficha}",
                                         "context": "A real-estate agency in Manaus sends properties to a client by "
                                                    "WhatsApp. 'pedido' is what the client asked."},
                        "criteria": {"true": "It fits the request (type, rent or buy, price within about 10% above the "
                                             "limit, rooms, area). Small differences are fine.",
                                     "false": "Clearly does not fit (wrong type, wrong purpose, much more expensive, "
                                              "fewer rooms than asked, far from the asked area)."}}
        por_chave[k] = (a, ficha)
    try:
        probs, uso = jev({"pedido": _pedido(filtros)}, perguntas, orcamento_s=5.0)
    except Exception as e:  # noqa: BLE001
        registrar(lead, "imoveis", "veto_erro", {"resumo": "o JEV não respondeu; sai tudo"}, erro=str(e))
        return achados
    saem = []
    for k, (a, ficha) in por_chave.items():
        p = probs.get(k)
        passou = p is None or p >= LIMIAR_VETO
        registrar(lead, "imoveis", "veto_passou" if passou else "veto_barrou",
                  {"codigo": a["codigo"], "resumo": f"#{a['codigo']} {ficha} (p={p if p is None else round(p, 2)})",
                   "pedido": _pedido(filtros)}, confianca=p, ms=uso.get("ms"),
                  uso={**uso, "custo_usd": (uso.get("custo_usd") or 0) / max(1, len(por_chave))}, modelo=uso.get("modelo"))
        if passou:
            saem.append(a)
    sobra = [a for a in achados if f"i{a['codigo']}" not in por_chave]
    return (saem + sobra) if m == "sim" else achados


# ───────────────────────────── as ações viram eventos ─────────────────────────────
DONO_DA_ACAO = {"buscar": "busca", "card": "imoveis", "fotos": "imoveis", "visita": "visita",
                "confirmou_visita": "visita", "perguntar": "revisao", "equipe": "humano", "encerrar": "atendimento"}


def acao(lead: dict, nome: str, r: dict) -> None:
    dono = DONO_DA_ACAO.get(nome)
    if dono:
        detalhe = {"motivo": str(r.get("motivo") or "")[:200]} if nome in ("perguntar", "equipe") else {}
        if nome == "visita":
            v = r.get("visita") if isinstance(r.get("visita"), dict) else {}
            detalhe = {"resumo": f"imóvel {v.get('codigo')}, {v.get('data')} {v.get('hora')}"}
        registrar(lead, dono, nome, detalhe)


def humano(lead: dict, quando) -> None:
    """A equipe escreveu (celular ou CRM): uma marca por mensagem de gente, sem repetir a mesma."""
    if modo() == "nao" or quando is None:
        return
    c = _conn()
    if c is None:
        return
    try:
        ja = banco.um(c, """SELECT 1 FROM privado.agente_evento WHERE agente = 'humano' AND chave8 = %s
                              AND decisao->>'quando' = %s LIMIT 1""", (_chave8(lead.get("telefone")), str(quando)))
    except Exception:  # noqa: BLE001
        _falhou()
        return
    if not ja:
        registrar(lead, "humano", "equipe_na_conversa", {"quando": str(quando), "resumo": "a equipe escreveu; a Nay espera"})


# o preço da Luna por milhão de tokens (o mesmo de config/modelos.yaml do nay-core, conferido em 30/09): só para medir
PRECO_LUNA = {"entrada": 0.10, "cache": 0.01, "saida": 0.50}


def custo_luna(uso: dict) -> float:
    ent, cache, sai = (uso.get("tokens_entrada") or 0), (uso.get("tokens_cache") or 0), (uso.get("tokens_saida") or 0)
    return ((ent - cache) * PRECO_LUNA["entrada"] + cache * PRECO_LUNA["cache"] + sai * PRECO_LUNA["saida"]) / 1e6


def atendimento(lead: dict, plano: dict, r: dict, uso: dict, ms: int, acoes: list[str]) -> None:
    uso = {**(uso or {}), "custo_usd": custo_luna(uso or {})}
    baloes = [b for b in (r.get("baloes") or []) if str(b).strip()]
    registrar(lead, "atendimento", "respondeu" if baloes else "calou",
              {"resumo": (baloes[0][:140] if baloes else "sem balão"), "acoes": acoes,
               "rotas": plano.get("rotas") or [], "geral": plano.get("geral", True)},
              ms=ms, uso=uso, modelo=uso.get("modelo"))
