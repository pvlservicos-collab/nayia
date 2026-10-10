"""PASSOS 2, 3 e 4: os filtros que eliminam, a nota de 0 a 100 e a faixa. Só conta, sem banco nem rede.

Pedro, 09/10/2026:
  FILTROS (um erro = imóvel descartado, sem nota): operação igual; tipo igual; local pedido ou bairro vizinho;
  quartos igual ou 1 a mais (1 a menos elimina); preço mais de 10% acima do teto elimina; imóvel disponível e
  confirmado recentemente.
  NOTA: "REGRA CENTRAL: só entram na conta os critérios que o corretor realmente pediu. Critério null sai do
  cálculo e os pesos restantes são reescalados para somar 100."

Decisões que a especificação não fecha (ditas a ele em 09/10):
  - 2 quartos ou mais ACIMA do pedido elimina (ele disse "igual ou 1 a mais").
  - pediu um CONDOMÍNIO: o condomínio vale "exato"; outro imóvel do mesmo bairro vale como vizinho
    (`local.mesmo_bairro_outro_condominio`); bairro vizinho não entra.
  - BAIRRO PRÓXIMO VALE MAIS QUE BAIRRO LONGE (Pedro, 09/10 à noite: "pontuação por bairros próximos serem maiores
    do que bairros longes ... você sabe os bairros que são próximos"). O que faz divisa vale mais que o que só
    fica perto, e os dois caem com a distância entre os centros dos bairros (`_vizinho`). Bairro que o mapa não
    lista como próximo continua eliminado.
  - o cadastro não informa o que ele pediu (andar, mobília, pet): vale 0 e a tela diz "não informado no cadastro".
  - "semi-mobiliado" vale a metade para quem pediu mobiliado e para quem pediu sem mobília.
"""
from __future__ import annotations

from grupos.texto import reais

ETAPAS = ("operacao", "tipo", "local", "quartos", "preco", "confirmado")
FALTOU = {
    "operacao": "nenhum imóvel nosso para {operacao}",
    "tipo": "nenhum imóvel nosso desse tipo para {operacao}",
    "local": "nenhum imóvel nosso nesse local",
    "quartos": "nenhum imóvel nosso com esse número de quartos nesse local",
    "preco": "os imóveis nossos nesse local passam mais de {tol}% do teto",
    "confirmado": "o que serviria não foi confirmado nos últimos {dias} dias",
}


def _preco_do(imovel: dict, operacao: str | None) -> float | None:
    v = imovel.get("valor_aluguel") if operacao == "aluguel" else imovel.get("valor_venda") if operacao == "venda" else None
    return float(v) if v else None


def _vizinho(v: dict, regras: dict) -> float:
    """Quanto rende um bairro vizinho (0-100): quem faz divisa vale mais; quanto mais longe, menos."""
    r = regras["local"]
    km = v.get("km")
    if km is None:                                  # par posto à mão na tabela dele, sem distância no mapa
        return float(r["vizinho_a_mao"])
    cai = max(0.0, 1 - km / r["km_que_zera"])
    if v.get("divisa"):
        # bairro grande faz divisa com o centro longe (Ponta Negra e Tarumã-Açu: 8,6 km): por isso o piso
        return max(float(r["divisa_piso"]), r["divisa_colado"] * cai)
    if km > r["perto_ate_km"]:                      # sem divisa e já longe: não é bairro próximo
        return 0.0
    return r["perto_sem_divisa"] * cai


def _local(pedido: dict, imovel: dict, vizinhos: dict, regras: dict):
    """(rendimento 0-100, texto) ou None = fora do local pedido. `nao_pedido` quando ele não disse lugar."""
    r = regras["local"]
    chaves = set(pedido.get("condominio_chaves") or [])
    bairros = set(pedido.get("bairro_chaves") or [])
    bairro = imovel.get("bairro_chave") or ""
    if chaves:
        palavras = set((imovel.get("condominio_chave") or "").split())
        if any(c and set(c.split()) <= palavras for c in chaves):
            return r["exato"], f"é o condomínio pedido ({imovel.get('condominio') or ''})"
        if bairro and bairro in bairros:
            return r["mesmo_bairro_outro_condominio"], f"mesmo bairro ({imovel.get('bairro')}), outro condomínio"
        return None
    if not bairros:
        return "nao_pedido"
    if pedido.get("condominio_sem_reconhecer"):
        # ele pediu um condomínio que o cadastro não conhece: o bairro serve, mas não é o que ele pediu
        if bairro and bairro in bairros:
            return r["mesmo_bairro_outro_condominio"], f"no bairro pedido ({imovel.get('bairro')}), mas não é o condomínio pedido"
        return None
    if bairro and bairro in bairros:
        return r["exato"], f"no bairro pedido ({imovel.get('bairro')})"
    # o vizinho: vale o bairro pedido de que ele está mais perto
    melhor = None
    for b in bairros:
        v = vizinhos.get(b, {}).get(bairro) if bairro else None
        if v and (melhor is None or _vizinho(v, regras) > melhor[0]):
            melhor = (_vizinho(v, regras), v)
    if not melhor or melhor[0] <= 0:
        return None
    v = melhor[1]
    km = (f"{v['km']:.1f}".replace(".", ",") + " km") if v.get("km") is not None else None
    if v.get("divisa"):
        return melhor[0], f"{imovel.get('bairro')} faz divisa com o bairro pedido" + (f" (centros a {km})" if km else "")
    return melhor[0], f"{imovel.get('bairro')} fica perto do bairro pedido, sem divisa ({km})"


def _rendimento_do_preco(preco: float, teto: float, regras: dict) -> tuple[float, bool]:
    """(0-100, acima do teto?). Quem chama já eliminou o que passa da tolerância."""
    p = regras["preco"]
    razao = preco / teto
    if razao > 1:
        return max(0.0, (1 + p["tolerancia_acima"] - razao) / p["tolerancia_acima"]) * 100, True
    piso_cheio = 1 - p["cheio_ate_abaixo"]
    if razao >= piso_cheio:
        return 100.0, False
    # mais barato que 20% abaixo do teto: costuma ser padrão inferior ao que ele procura
    return max(0.0, (razao - p["zera_em"]) / (piso_cheio - p["zera_em"])) * 100, False


def _mobilia(pedido: bool, imovel: dict, regras: dict) -> tuple[float, str]:
    m = regras["mobiliado"]
    estado = imovel.get("mobilia")            # 'mobiliado' | 'semi' | 'vazio' | None
    if estado is None:
        return m["nao_atende"], "mobília não informada no cadastro"
    if estado == "semi":
        return m["semi"], "semi-mobiliado"
    if pedido:
        return (m["atende"], "mobiliado") if estado == "mobiliado" else (m["nao_atende"], "sem mobília")
    return (m["atende"], "sem mobília") if estado == "vazio" else (m["nao_atende"], "é mobiliado")


def _andar(aceita: list[str], imovel: dict) -> tuple[float, str]:
    andar = imovel.get("andar")                # 0 = térreo; None = não informado
    if imovel.get("tipo") == "casa":
        andar = 0
    if andar is None:
        return 0.0, "andar não informado no cadastro"
    nome = "térreo" if andar == 0 else ("andar alto" if andar >= 90 else f"{andar}º andar")
    serve = ("terreo" in aceita and andar == 0) or ("1_andar" in aceita and andar == 1)
    return (100.0 if serve else 0.0), nome


def _extras(pedido: dict, imovel: dict) -> tuple[float, str] | None:
    partes: list[tuple[bool, str]] = []
    if pedido.get("suite") is True:
        tem = imovel.get("suites")
        partes.append((bool(tem), "tem suíte" if tem else ("sem suíte" if tem == 0 else "suíte não informada no cadastro")))
    if pedido.get("vagas"):
        tem = imovel.get("vagas")
        partes.append((tem is not None and tem >= pedido["vagas"],
                       f"{tem} vaga(s)" if tem is not None else "vagas não informadas no cadastro"))
    if pedido.get("pet") is True:
        aceita = imovel.get("pet")
        partes.append((aceita is True, "aceita pet" if aceita else "pet não informado no cadastro"))
    if not partes:
        return None
    return 100.0 * sum(1 for ok, _ in partes if ok) / len(partes), "; ".join(t for _, t in partes)


def avaliar(pedido: dict, imovel: dict, regras: dict, vizinhos: dict, hoje_menos_dias=None) -> tuple[str | None, dict | None]:
    """Devolve (etapa em que caiu, None) ou (None, {nota, detalhe, acima_do_teto})."""
    operacao = pedido.get("operacao")
    preco = _preco_do(imovel, operacao)
    if not operacao or not preco:
        return "operacao", None
    if pedido.get("tipo") and imovel.get("tipo") != pedido["tipo"]:
        return "tipo", None
    local = _local(pedido, imovel, vizinhos, regras)
    if local is None:
        return "local", None
    quartos_rend = None
    if pedido.get("quartos") is not None:
        tem = imovel.get("quartos")
        if tem is None or tem < pedido["quartos"] or tem > pedido["quartos"] + 1:
            return "quartos", None
        quartos_rend = regras["quartos"]["igual"] if tem == pedido["quartos"] else regras["quartos"]["um_a_mais"]
    teto = pedido.get("preco_max")
    if teto and preco > teto * (1 + regras["preco"]["tolerancia_acima"]):
        return "preco", None
    if hoje_menos_dias is not None and (imovel.get("confirmado_em") is None or imovel["confirmado_em"] < hoje_menos_dias):
        return "confirmado", None

    # ── a nota: só o que ele pediu ──
    itens: list[dict] = []
    acima = False
    if teto:
        rend, acima = _rendimento_do_preco(preco, teto, regras)
        pct = round(preco / teto * 100)
        itens.append({"criterio": "preco", "rendimento": rend,
                      "texto": f"{reais(preco)} é {pct}% do teto de {reais(teto)}" + (" (acima do teto, negociável)" if acima else "")})
    if local != "nao_pedido":
        itens.append({"criterio": "local", "rendimento": float(local[0]), "texto": local[1]})
    if quartos_rend is not None:
        itens.append({"criterio": "quartos", "rendimento": float(quartos_rend),
                      "texto": f"{imovel['quartos']} quarto(s), pediu {pedido['quartos']}"})
    if pedido.get("mobiliado") is not None:
        rend, texto = _mobilia(pedido["mobiliado"], imovel, regras)
        itens.append({"criterio": "mobiliado", "rendimento": float(rend), "texto": texto})
    aceita = pedido.get("andar") or []
    if aceita and "qualquer" not in aceita:
        rend, texto = _andar(aceita, imovel)
        itens.append({"criterio": "andar", "rendimento": rend, "texto": texto})
    extras = _extras(pedido, imovel)
    if extras:
        itens.append({"criterio": "extras", "rendimento": extras[0], "texto": extras[1]})
    if not itens:
        return None, {"nota": None, "detalhe": [], "acima_do_teto": False}

    brutos = [regras["pesos"].get(i["criterio"], 0) for i in itens]
    if sum(brutos) <= 0:                            # só pediu critério de peso zero: todos valem igual
        brutos = [1] * len(itens)
    soma = sum(brutos)
    # a nota sai dos pesos inteiros; o que a tela mostra (peso e pontos) é o arredondamento dela
    nota = round(min(100.0, sum(b * i["rendimento"] for b, i in zip(brutos, itens)) / soma), 1)
    for b, i in zip(brutos, itens):
        i["peso"] = round(b * 100 / soma, 1)        # reescalado para somar 100
        i["pontos"] = round(b * i["rendimento"] / soma, 1)
        i["rendimento"] = round(i["rendimento"], 1)
    return None, {"nota": nota, "detalhe": itens, "acima_do_teto": acima}


def faixa_da(nota: float, regras: dict) -> str:
    c = regras["cortes"]
    return "verde" if nota >= c["verde"] else "amarelo" if nota >= c["amarelo"] else "registro"


def melhores(pedido: dict, catalogo: list[dict], regras: dict, vizinhos: dict, hoje_menos_dias=None) -> dict:
    """O melhor imóvel, as alternativas e o funil (quantos sobraram depois de cada filtro)."""
    if not pedido.get("operacao"):
        return {"pares": [], "funil": {}, "motivo": "ele não disse se é aluguel ou venda"}
    if pedido.get("local_nao_reconhecido"):
        return {"pares": [], "funil": {}, "motivo": "não reconheci o lugar pedido: " + ", ".join(pedido["local_nao_reconhecido"])}
    caiu = {e: 0 for e in ETAPAS}
    passaram: list[tuple[dict, dict]] = []
    sem_criterio = False
    for imovel in catalogo:
        etapa, resultado = avaliar(pedido, imovel, regras, vizinhos, hoje_menos_dias)
        if etapa:
            caiu[etapa] += 1
        elif resultado["nota"] is None:
            sem_criterio = True
        else:
            passaram.append((imovel, resultado))
    funil, resto = {}, len(catalogo)
    for e in ETAPAS:
        resto -= caiu[e]
        funil[e] = resto
    if sem_criterio and not passaram:
        return {"pares": [], "funil": funil, "motivo": "pedido sem lugar, quartos nem valor: não há o que pontuar"}
    if not passaram:
        primeira = next((e for e in ETAPAS if funil[e] == 0), "confirmado")
        motivo = FALTOU[primeira].format(operacao=pedido["operacao"], dias=regras["confirmado_dias"],
                                         tol=round(regras["preco"]["tolerancia_acima"] * 100))
        return {"pares": [], "funil": funil, "motivo": motivo}
    # o melhor primeiro; no empate, o que não passa do teto e depois o mais barato
    passaram.sort(key=lambda x: (-x[1]["nota"], x[1]["acima_do_teto"], _preco_do(x[0], pedido["operacao"]) or 0, x[0]["codigo"]))
    pares = [{"codigo": im["codigo"], "posicao": n + 1, **res, "imovel": im}
             for n, (im, res) in enumerate(passaram[: 1 + regras["alternativas"]])]
    return {"pares": pares, "funil": funil, "motivo": None, "passaram": len(passaram)}
