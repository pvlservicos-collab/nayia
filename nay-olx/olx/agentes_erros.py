"""AS CONVERSAS COM ERRO NA NAY LEADS NOVA (Pedro, 25/10/2026: "é para testar na nova nay de leads que usa subagentes ...
se der corrige").

Entrada: o erros.md da revisão da semana (agente-claude/gemini_revisao.py): cada bloco tem os erros apontados e a conversa
inteira. Cada vez que a pessoa fala, a conversa REAL até ali vai para a Nay Leads de agora, como num turno de verdade:
  MESTRE (JEV)  escolhe o caminho (ou cala a cortesia)
  ATENDIMENTO   a Luna com o prompt da Nay Leads escreve os balões e as ações
  IMÓVEIS       se ela pedir "buscar": a busca de verdade (olx_cliente_buscar, afrouxando como no ar) e o VETO do JEV
Nada é gravado nem enviado: o registro dos agentes fica num caderno em memória, a hora do turno é a da conversa e a busca
só lê. Depois um juiz confere, erro por erro, se a Nay Leads repete o que a revisão apontou.

  python -m olx.agentes_erros erros.md                 todas
  python -m olx.agentes_erros erros.md --so 0221,4318  só as conversas desses finais
Saída: replay/erros_<carimbo>.json e um resumo (corrigido / persiste / incerto, por tipo de erro).
"""
from __future__ import annotations

import argparse
import json
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

from olx import agentes, banco, modelo, paredes, whatsapp

PASTA = Path(__file__).resolve().parent.parent / "replay"
_TL = threading.local()

JUIZ = """Você confere se a NAY LEADS (a atendente de WhatsApp de uma imobiliária de Manaus) repete erros que uma revisão
apontou numa conversa real. A pessoa do outro lado é um corretor que procura imóvel para o cliente dele (para a Nay, ele é
quem procura). Você recebe: (1) os ERROS APONTADOS na conversa original, com o que aconteceu, o que devia e o trecho;
(2) o TESTE: em cada vez que a pessoa falou, a mensagem dela, o que a Nay respondeu DE VERDADE e o que a Nay Leads responderia
AGORA (balões, ações, os filtros que ela entendeu e, quando pediu "buscar", os imóveis que a busca mandaria e os que o veto
barrou). A conversa seguinte continua a real: cada resposta nova é só daquele momento.

Como a Nay Leads trabalha (NADA disto é erro):
- O histórico que ela lê em cada turno é o da conversa REAL (inclusive as listas e cards que a Nay de verdade mandou): ela
  pode citar opções que aparecem só na resposta real.
- "buscar" manda os imóveis da busca em cards, um a um; "fotos" manda o card (se ainda não viu) e as fotos dos códigos em
  fotos.codigos; "card" manda só o card dos códigos (para a pessoa apontar qual); "visita" pede a confirmação com imóvel,
  dia e hora; "perguntar" leva a dúvida à equipe e a conversa continua; "equipe" passa a conversa para uma pessoa.
- A faixa de valor da busca é de 20% abaixo a 10% acima do teto (regra do dono): R$ 5.300 para "até 5 mil" está certo.
  "Os mais próximos" (quando o perfil exato não existe) saem avisados como próximos.
- O roteiro faz UMA pergunta por vez (valor, bairros, quartos, mobília na locação, crédito na venda) antes de buscar; a
  abertura de quem escreveu direto é "Aqui é a Nay... Você está procurando imóvel? Seria para alugar ou comprar?".
- Corretor oferecendo PARCERIA vai para a equipe (é a regra dela).
- Você não vê a ficha do imóvel que ela lê: preço, mobília, quartos ou ocupação que ela cita podem estar lá. Só chame de
  invenção o que contradiz o que está no teste.

Para CADA erro apontado, olhe o turno do trecho e diga:
- "corrigido": a Nay Leads faz o que "devia" (ou não faz mais o errado) nesse ponto;
- "persiste": a Nay Leads faz o mesmo erro, ou um equivalente, nesse ponto;
- "incerto": não dá para ver pelo teste.
Diga também o ERRO NOVO claro que a Nay Leads cometeu e a resposta real não (só se for claro), e uma nota de 0 a 100
para as respostas da Nay Leads na conversa toda.

Responda SÓ JSON: {"erros": [{"n": 1, "veredito": "corrigido|persiste|incerto", "motivo": "uma frase, citando o turno"}],
"erro_novo": "" ou "uma frase", "nota": 0-100}"""


# ───────────────────────────── a entrada: o erros.md ─────────────────────────────
LINHA = re.compile(r"^(\d{2}):(\d{2}) (Corretor|Nay|Nay → Tel): ?(.*)$")


def conversas(md: str) -> list[dict]:
    """Os blocos do erros.md: id, nota, os erros (o que aconteceu, devia, trecho) e as falas com hora."""
    saida = []
    for bloco in re.split(r"\n(?=## \d+\. )", md)[1:]:
        cab = re.match(r"## \d+\. (\d{4}-\d{2}-\d{2}) · …(\d{4}) · nota (\d+)", bloco)
        texto = re.search(r"```text\n(.*?)\n```", bloco, re.S)
        arq = re.search(r"Arquivo: `dados/conversas/([^`]+)\.txt`", bloco)
        if not (cab and texto):
            continue
        dia, final, nota = cab.groups()
        erros = []
        for e in re.finditer(r"\d+\. \*\*\[(\w+)\] (\w+)\*\*: (.*?)\n\s+- Devia: (.*?)\n\s+- Trecho:\n(.*?)(?=\n\s+- Pista|\n\d+\. \*\*|\n\*\*A conversa)",
                             bloco, re.S):
            erros.append({"gravidade": e.group(1), "tipo": e.group(2), "o_que_aconteceu": e.group(3).strip(),
                          "o_que_devia": e.group(4).strip(),
                          "trecho": "\n".join(x.strip().lstrip("> ") for x in e.group(5).splitlines())})
        saida.append({"id": (arq.group(1) if arq else f"{dia}/{final}"), "dia": dia, "final": final, "nota": int(nota),
                      "erros": erros, "falas": falas_do_texto(texto.group(1))})
    return saida


def _texto_do_envio(bruto: str) -> str:
    """'[{"tipo": "texto", "texto": "..."}, ...]' (o enviado_antes do treino) -> os textos, um por linha."""
    try:
        itens = json.loads(bruto)
    except ValueError:
        # o envio veio cortado (a biblioteca guarda 600 caracteres): os "texto" que couberem
        achados = re.findall(r'"texto":\s*"((?:[^"\\]|\\.)*)"?', bruto)
        return "\n".join(a.encode("utf-8").decode("unicode_escape", "ignore") if "\\u" in a else a.replace("\\n", "\n")
                         for a in achados) or bruto
    return "\n".join(str(i.get("texto") or "") for i in itens if isinstance(i, dict) and i.get("texto")) if isinstance(itens, list) else bruto


def falas_do_texto(texto: str) -> list[dict]:
    """As falas com hora de uma conversa no formato do importar_nay.py ('HH:MM Corretor: ...', 'HH:MM Nay: ...') ou do
    treino da Parceria ('HH:MM Corretor: ...' e, embaixo, 'Nay (antes): [json]' e 'Nay (no treino): ...')."""
    falas: list[dict] = []
    for linha in (texto or "").splitlines():
        m = LINHA.match(linha)
        if m:
            h, mi, quem, t = m.groups()
            falas.append({"hora": f"{h}:{mi}", "quem": quem, "texto": t})
        elif falas and linha.strip().startswith("Nay (antes):"):
            falas.append({"hora": falas[-1]["hora"], "quem": "Nay", "texto": _texto_do_envio(linha.split(":", 1)[1].strip())})
        elif falas and linha.strip().startswith("Nay (no treino):"):
            continue                      # o que o código de 06/10 respondeu no treino não é a conversa real
        elif falas and linha.startswith("      "):
            falas[-1]["texto"] += "\n" + linha.strip()
    for f in falas:
        f["texto"] = re.sub(r"\s*\{[a-z_]+\}\s*$", "", f["texto"]).strip()      # o {template} do fim
    return [f for f in falas if f["texto"]]


def da_biblioteca(caminho: str) -> list[dict]:
    """As conversas com erro da biblioteca (498), exportadas em JSON: [{ref, nay, dia, tel4, nota, marcas, texto}].
    Os erros são os de todas as marcas que disseram erro (o Pedro, o agente, o Gemini, a nota automática...)."""
    saida = []
    for x in json.loads(Path(caminho).read_text(encoding="utf-8")):
        erros = []
        for m in x.get("marcas") or []:
            if m.get("resultado") != "erro":
                continue
            for e in m.get("erros") or []:
                if e.get("o_que_aconteceu") or e.get("o_que_devia"):
                    erros.append({"gravidade": e.get("gravidade") or "media", "tipo": e.get("tipo") or "outro",
                                  "o_que_aconteceu": e.get("o_que_aconteceu") or "", "o_que_devia": e.get("o_que_devia") or "",
                                  "trecho": e.get("trecho") or "", "fonte": m.get("fonte")})
        falas = falas_do_texto(x.get("texto") or "")
        if not erros or not any(f["quem"] == "Corretor" for f in falas):
            continue
        saida.append({"id": x["ref"], "dia": str(x.get("dia") or "")[:10], "final": x.get("tel4") or "0000",
                      "nota": x.get("nota") or 0, "erros": erros[:10], "falas": falas, "nay": x.get("nay")})
    return saida


# ───────────────────────────── a Nay Leads num turno ─────────────────────────────
class _Hora(datetime):
    """A hora do turno no lugar do relógio (o 'AGORA' do prompt e o 'amanhã' da visita)."""
    @classmethod
    def now(cls, tz=None):
        t = getattr(_TL, "agora", None)
        return t.astimezone(tz) if (t and tz) else (t or datetime.now(tz))


whatsapp.datetime = _Hora
_CADERNO = threading.local()


def _anotar(lead, agente, acao, decisao=None, confianca=None, ms=None, uso=None, modelo=None, erro=None):  # noqa: ARG001
    """No lugar de agentes.registrar: o que os agentes decidiram fica no caderno do turno, nada vai ao banco."""
    getattr(_CADERNO, "ev", []).append({"agente": agente, "acao": acao, "decisao": decisao, "erro": erro})


agentes.registrar = _anotar
COD = re.compile(r"(?:#|C[óo]digo:?\s*)(\d{4})\b")


def _conversa(falas: list[dict], dia: str) -> list[dict]:
    saida = []
    for i, f in enumerate(falas):
        if f["quem"] == "Nay → Tel":
            continue                     # o aviso ao Tel não é fala da conversa
        quando = datetime.fromisoformat(f"{dia} {f['hora']}").replace(tzinfo=whatsapp.MANAUS)
        saida.append({"id": i + 1, "direcao": "recebida" if f["quem"] == "Corretor" else "enviada",
                      "origem": None if f["quem"] == "Corretor" else "resposta", "nossa": f["quem"] != "Corretor",
                      "texto": f["texto"], "criada_em": quando})
    return saida


def buscar_sem_mandar(conn, lead: dict, filtros: dict) -> dict:
    """A busca de _buscar_e_mandar, só lendo: o que sairia (com o afrouxar e o veto) e nada mais."""
    cods_recusados, nomes_recusados = whatsapp.recusados(filtros)
    excluir = list(lead.get("enviados") or []) + cods_recusados
    f = dict(filtros)
    if not f.get("finalidade"):
        f["finalidade"] = whatsapp.finalidade_sem_dizer(lead, f)
    achados, proximas = [], False
    for tentativa, afrouxou in whatsapp._afrouxar(f):
        achados = banco.linhas(conn, "SELECT * FROM olx_cliente_buscar(%s::jsonb, %s::int[], %s)",
                               (json.dumps(tentativa, ensure_ascii=False), excluir,
                                whatsapp.MAX_IMOVEIS * 4 if (f.get("perto_de") or nomes_recusados or f.get("so_condominio")) else whatsapp.MAX_IMOVEIS))
        achados = whatsapp.so_no_condominio(whatsapp.fora_os_recusados(whatsapp.so_perto(conn, achados, tentativa), nomes_recusados),
                                            f)[:whatsapp.MAX_IMOVEIS]
        if achados:
            proximas = afrouxou
            break
    antes = [int(a["codigo"]) for a in achados]
    if achados and not proximas:
        achados = agentes.filtrar_imoveis(lead, f, achados)

    def curto(a):
        valor = a.get("valor_aluguel") or a.get("valor_venda") or a.get("preco") or ""
        return " · ".join(str(x) for x in (f"#{a['codigo']}", a.get("tipo"), a.get("condominio") or a.get("bairro"),
                                            a.get("bairro") if a.get("condominio") else "", f"R$ {valor}" if valor else "",
                                            f"{a['quartos']} qts" if a.get("quartos") else "", a.get("mobilia") or "") if x)
    return {"filtros": f, "mais_proximas": proximas, "mandaria": [curto(a) for a in achados],
            "veto_barrou": [c for c in antes if c not in {int(a["codigo"]) for a in achados}]}


ECONOMIA = [True]            # 25/10 (Pedro: "dá uma filtrada nos testes para não gastar meus créditos"); --tudo desliga
CUMPRIMENTO = re.compile(r"^\s*(bom dia|boa tarde|boa noite|oi+|ol[áa]|opa|e a[ií])[\s,!.]*(nay|nai|amiga|querida)?[\s,!.]*$", re.I)
HORA = re.compile(r"\b([01]\d|2[0-3]):([0-5]\d)\b")


def _minutos(h: str) -> int:
    a, b = h.split(":")
    return int(a) * 60 + int(b)


def _pular(c: dict, hora: str, novas: list[str], anteriores: list[dict]) -> str | None:
    """O motivo de não chamar o modelo neste turno (None = roda): mídia sem texto, só cortesia ou cumprimento, a mesma
    mensagem de novo, ou longe do erro (quando os erros apontados dizem a hora, só roda a 10 min deles)."""
    textos = [t.strip() for t in novas if (t or "").strip()]
    if not textos:
        return "mídia sem texto"
    if whatsapp.so_agradeceu(textos) or all(CUMPRIMENTO.match(t) for t in textos):
        return "só cortesia ou cumprimento"
    if anteriores and [t.strip() for t in anteriores[-1]["ele"] if (t or "").strip()] == textos:
        return "a mesma mensagem de novo"
    return None


def _normal(t: str) -> str:
    return re.sub(r"\s+", " ", whatsapp._normal(t or "")).strip()


def turnos_alvo(c: dict, conv: list[dict]) -> set[int] | None:
    """Os turnos (o índice da 1ª fala da pessoa) que valem rodar: os da hora que o erro aponta (10 min para cada lado) e
    os em que aparece um trecho citado no erro, com o turno de antes (o contexto do erro). None = rodar todos (o erro não
    diz onde foi)."""
    grupos, k = [], 0
    while k < len(conv):
        if conv[k]["direcao"] != "recebida":
            k += 1
            continue
        fim = k
        while fim + 1 < len(conv) and conv[fim + 1]["direcao"] == "recebida":
            fim += 1
        j = fim + 1
        while j < len(conv) and conv[j]["direcao"] != "recebida":
            j += 1
        grupos.append((k, conv[fim]["criada_em"].strftime("%H:%M"), _normal(" ".join(m["texto"] for m in conv[k:j]))))
        k = fim + 1
    texto_erros = " ".join(str(e.get(x) or "") for e in c.get("erros") or [] for x in ("trecho", "o_que_aconteceu", "o_que_devia"))
    horas = {_minutos(f"{a}:{b}") for a, b in HORA.findall(texto_erros)}
    citados = [_normal(s)[:40] for s in re.findall(r"[“\"']([^”\"']{10,})[”\"']", texto_erros)]
    citados += [_normal(re.sub(r"^\s*>?\s*\d{2}:\d{2}\s+[^:]{1,20}:\s*", "", l))[:40]
                for e in c.get("erros") or [] for l in str(e.get("trecho") or "").splitlines() if len(l.strip()) > 14]
    citados = [s for s in citados if len(s) >= 10]
    if not horas and not citados:
        return None
    alvo = set()
    for i, (k, hora, texto) in enumerate(grupos):
        perto = horas and min(abs(_minutos(hora) - h) for h in horas) <= 10
        if perto or any(s in texto for s in citados):
            alvo.add(k)
            if i:
                alvo.add(grupos[i - 1][0])        # o turno de antes: o contexto em que o erro aconteceu
    return alvo or None


def rodar_conversa(c: dict) -> dict:
    conn = banco.conectar()
    agentes.forcar_modo("sim", "replay")
    conv = _conversa(c["falas"], c["dia"])
    lead = {"id": -int(c["final"]), "telefone": "559200" + c["final"].rjust(6, "0"), "origem": "organico",
            "etapa": "nova", "filtros": {}, "enviados": [], "chat": None, "nome": None, "perfil": {}}
    turnos, k = [], 0
    alvo = turnos_alvo(c, conv) if ECONOMIA[0] else None
    try:
        while k < len(conv):
            if conv[k]["direcao"] != "recebida":
                k += 1
                continue
            fim = k
            while fim + 1 < len(conv) and conv[fim + 1]["direcao"] == "recebida":
                fim += 1
            ctx = conv[:fim + 1]
            real = []
            j = fim + 1
            while j < len(conv) and conv[j]["direcao"] != "recebida":
                real.append(conv[j]["texto"])
                j += 1
            _TL.agora = ctx[-1]["criada_em"]
            _CADERNO.ev = []
            nay_ate_aqui = [m for m in ctx if m["direcao"] == "enviada"]
            lead["enviados"] = list(dict.fromkeys(int(x) for m in nay_ate_aqui for x in COD.findall(m["texto"])))
            lead["etapa"] = "imoveis_enviados" if lead["enviados"] else ("filtrar" if nay_ate_aqui else "nova")
            lead["fichas_citadas"] = whatsapp._fichas_citadas(conn, ctx, lead)
            lead["imoveis_conhecidos"] = whatsapp.imoveis_da_conversa(conn, lead)
            lead["visita_aberta"] = None
            novas = [m["texto"] for m in conv[k:fim + 1]]
            pode_calar = bool(nay_ate_aqui) and not nay_ate_aqui[-1]["texto"].strip().endswith("?")
            item = {"hora": ctx[-1]["criada_em"].strftime("%H:%M"), "ele": novas, "real": real}
            pular = (_pular(c, item["hora"], novas, turnos) or
                     ("longe do erro apontado" if alvo is not None and k not in alvo else None)) if ECONOMIA[0] else None
            if pular:                     # o histórico seguinte é o real: pular este turno não muda os outros
                item["pulado"] = pular
                turnos.append(item)
                k = fim + 1
                continue
            try:
                agentes.novo_turno(lead)
                plano = agentes.planejar(whatsapp.PROMPT, lead, ctx, novas, True, pode_calar)
                item["mestre"] = {"rotas": plano.get("rotas"), "calar": plano.get("calar")}
                if plano["calar"]:
                    r = {"baloes": [], "acoes": []}
                else:
                    turno = whatsapp.montar_turno(lead, None, ctx)
                    r = modelo.chamar(plano["prompt"], turno, no="olx.replay")
                    # a segunda chamada avisada, como no _responder_um (perguntou o que já se sabe; equipe só por interesse)
                    aviso = " ".join(x for x in (whatsapp.pergunta_a_toa(r, ctx), whatsapp.equipe_a_toa(r, novas)) if x)
                    if aviso:
                        item["chamou_de_novo"] = aviso[:160]
                        r = modelo.chamar(plano["prompt"], turno + "\n\n" + aviso, no="olx.replay")
                    # as paredes de saída, como no _responder_um (olx/paredes.py)
                    furos = paredes.conferir(whatsapp._baloes_do(r), turno, True)
                    if furos:
                        item["paredes"] = [f"{p}: {x}" for _i, p, x in furos]
                        r = modelo.chamar(plano["prompt"], turno + "\n\n" + paredes.aviso(furos), no="olx.replay")
                        sobra, ainda = paredes.cortar(whatsapp._baloes_do(r), turno, True)
                        if ainda:
                            item["paredes_cortou"] = [f"{p}: {x}" for _i, p, x in ainda]
                            r["baloes"] = sobra
                # as camadas sem modelo, a MESMA função do _responder_um
                acoes, passos = whatsapp.depois_do_modelo(conn, lead, r, novas, nay_ate_aqui[-1]["texto"] if nay_ate_aqui else "")
                if passos:
                    item["atalho"] = "; ".join(f"{n}: {d}" for n, d in passos)
                lead["filtros"] = whatsapp._filtros(lead["filtros"], r.get("filtros"))
                item.update({"baloes": [str(b).strip() for b in (r.get("baloes") or []) if str(b).strip()],
                             "acoes": acoes, "filtros": lead["filtros"]})
                if "visita" in acoes:
                    item["visita"] = r.get("visita")
                if "fotos" in acoes:
                    item["fotos"] = r.get("fotos")
                if "card" in acoes:
                    item["card"] = r.get("card")
                if "perguntar" in acoes or "equipe" in acoes:
                    item["motivo"] = r.get("motivo")
                if "buscar" in acoes:
                    item["busca"] = buscar_sem_mandar(conn, lead, lead["filtros"])
            except Exception as e:  # noqa: BLE001 -- um turno não para a conversa
                item["falha"] = f"{type(e).__name__}: {e}"[:200]
            turnos.append(item)
            k = fim + 1
    finally:
        agentes.forcar_modo(None, None)
        conn.close()
    return {**{x: c[x] for x in ("id", "dia", "final", "nota", "erros")}, "turnos": turnos}


# ───────────────────────────── o juiz ─────────────────────────────
def _teste_em_texto(r: dict) -> str:
    linhas = []
    for t in r["turnos"]:
        linhas.append(f"\n{t['hora']} PESSOA: " + " / ".join(x.replace("\n", " ") for x in t["ele"])[:700])
        linhas.append("   NAY DE VERDADE: " + (" / ".join(x.replace("\n", " ") for x in t["real"])[:500] or "(nada)"))
        if t.get("pulado"):
            linhas.append(f"   NAY LEADS: (não rodado no teste: {t['pulado']})")
            continue
        if t.get("falha"):
            linhas.append(f"   NAY LEADS: (falhou: {t['falha']})")
            continue
        nova = {k: t.get(k) for k in ("baloes", "acoes", "visita", "fotos", "card", "motivo") if t.get(k)}
        if t.get("mestre", {}).get("calar"):
            nova["calou"] = "o mestre leu só cortesia: não responde"
        linhas.append("   NAY LEADS: " + json.dumps(nova, ensure_ascii=False)[:900])
        linhas.append("   filtros entendidos: " + json.dumps(t.get("filtros") or {}, ensure_ascii=False)[:300])
        if t.get("busca"):
            b = t["busca"]
            linhas.append("   a busca mandaria: " + ("; ".join(b["mandaria"]) or "nada") +
                          (" (as mais próximas)" if b["mais_proximas"] else "") +
                          (f" | o veto barrou {b['veto_barrou']}" if b["veto_barrou"] else ""))
    return "\n".join(linhas)


def julgar(r: dict) -> dict:
    erros = "\n\n".join(
        f"{i}. [{e['gravidade']}] {e['tipo']}: {e['o_que_aconteceu']}\n   Devia: {e['o_que_devia']}\n   Trecho:\n{e['trecho']}"
        for i, e in enumerate(r["erros"], 1))
    caso = f"=== ERROS APONTADOS ({r['id']}) ===\n{erros}\n\n=== O TESTE NA NAY LEADS ===\n{_teste_em_texto(r)[-16000:]}"
    try:
        return modelo.chamar(JUIZ, caso, no="olx.replay")
    except Exception as e:  # noqa: BLE001
        return {"erros": [], "falha": str(e)[:200]}


def resumo(res: list[dict]) -> dict:
    cont = {"corrigido": 0, "persiste": 0, "incerto": 0}
    conv = {"tudo_corrigido": 0, "algum_persiste": 0, "so_incerto": 0}
    por_tipo: dict = {}
    for r in res:
        vs = []
        for e, j in zip(r["erros"], (r.get("julgamento") or {}).get("erros") or []):
            v = j.get("veredito") if j.get("veredito") in cont else "incerto"
            cont[v] += 1
            vs.append(v)
            por_tipo.setdefault(e["tipo"], dict.fromkeys(cont, 0))[v] += 1
        conv["algum_persiste" if "persiste" in vs else "tudo_corrigido" if "corrigido" in vs else "so_incerto"] += 1
    notas = [r["julgamento"].get("nota") for r in res if isinstance((r.get("julgamento") or {}).get("nota"), (int, float))]
    return {"conversas": len(res), "erros": cont, "por_conversa": conv, "por_tipo": por_tipo,
            "erro_novo": sum(1 for r in res if (r.get("julgamento") or {}).get("erro_novo")),
            "nota_media": round(sum(notas) / len(notas), 1) if notas else None,
            "turnos": sum(len(r["turnos"]) for r in res),
            "turnos_com_falha": sum(1 for r in res for t in r["turnos"] if t.get("falha")),
            "turnos_pulados": sum(1 for r in res for t in r["turnos"] if t.get("pulado")),
            "julgamento_falhou": sum(1 for r in res if (r.get("julgamento") or {}).get("falha"))}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("arquivo")
    ap.add_argument("--so", default="", help="os 4 finais das conversas, separados por vírgula")
    ap.add_argument("--paralelo", type=int, default=6)
    ap.add_argument("--tudo", action="store_true", help="roda todos os turnos (sem a economia)")
    a = ap.parse_args()
    ECONOMIA[0] = not a.tudo
    if a.arquivo.endswith(".json"):    # a exportação da biblioteca de conversas (498)
        lista = da_biblioteca(a.arquivo)
    else:
        lista = conversas(Path(a.arquivo).read_text(encoding="utf-8"))
    ao_lado = Path(a.arquivo).with_name("erros.json")
    if ao_lado.exists() and not a.arquivo.endswith(".json"):   # os erros do json (o mesmo id) valem mais que os do texto
        por_id = {c["id"]: c["erros"] for c in json.loads(ao_lado.read_text(encoding="utf-8"))}
        for c in lista:
            c["erros"] = por_id.get(c["id"]) or c["erros"]
    so = {x.strip() for x in a.so.split(",") if x.strip()}
    if so:
        lista = [c for c in lista if c["final"] in so or c["id"] in so]
    with ThreadPoolExecutor(a.paralelo) as ex:
        res = list(ex.map(rodar_conversa, lista))
        juizes = list(ex.map(julgar, res))
    for r, j in zip(res, juizes):
        r["julgamento"] = j
    PASTA.mkdir(exist_ok=True)
    arq = PASTA / f"erros_{datetime.now(whatsapp.MANAUS):%Y-%m-%d_%H%M}{'_so' if so else ''}.json"
    s = resumo(res)
    arq.write_text(json.dumps({"resumo": s, "conversas": res}, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(json.dumps(s, ensure_ascii=False, indent=1))
    print(f"arquivo: {arq}")


if __name__ == "__main__":
    main()
