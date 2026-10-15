"""PASSO 1: a IA lê a mensagem do grupo e devolve os PEDIDOS de imóvel, em JSON.

Pedro, 09/10/2026: "Uma mensagem pode conter VÁRIOS pedidos; separe cada um como solicitação independente.
Campo não mencionado = null. NUNCA preencher por suposição. Se não tiver certeza de um campo, marcar como
'duvidoso'. Entender gírias e abreviações. Ignorar mensagens que não são pedidos."

O modelo só LÊ o que está escrito. Reconhecer o bairro e o condomínio (apelidos, nome oficial) é conta do
serviço, em lugares.py -- a tabela de apelidos é dele, editável, e não cabe num prompt.

`andar` é uma LISTA (a especificação dá um valor só): "Térreo ou 1 andar", que é um dos testes dele, só cabe
como ["terreo", "1_andar"].
"""
from __future__ import annotations

import json
import re
import time
from typing import Callable

import requests

from grupos import config

URL = "https://api.openai.com/v1/responses"
CAMPOS = ("operacao", "tipo", "bairros", "condominio", "quartos", "preco_max", "mobiliado", "andar", "suite",
          "vagas", "pet", "financiamento", "contato")

PROMPT = """Você lê mensagens de grupos de WhatsApp de corretores de imóveis de Manaus e extrai os PEDIDOS de imóvel:
um corretor procurando imóvel para um cliente dele.

É PEDIDO: alguém procurando, precisando ou buscando imóvel para alugar ou comprar ("procuro", "preciso", "busco",
"cliente quer", "alguém tem?", "tenho cliente para").
NÃO É PEDIDO (devolva "pedidos": []): oferta ou anúncio de imóvel ("alugo", "vendo", "disponível", card com valor e
código), conversa, cumprimento, propaganda, vaga de emprego, pedido de qualquer coisa que não seja imóvel.

Uma mensagem pode ter VÁRIOS pedidos (clientes diferentes, ou operação/tipo diferentes): devolva um item para cada.
Bairros alternativos do MESMO pedido ("Adrianópolis ou Vieiralves") ficam juntos em "bairros": não são dois pedidos.

CAMPOS de cada pedido:
- operacao: "aluguel" (alugar, locação, aluguel) ou "venda" (comprar, compra, venda, financiamento).
- tipo: "apartamento" (apto, ap, flat, kitnet, cobertura, studio), "casa" (casa, sobrado, casa em condomínio),
  "sala" (sala, loja, ponto comercial) ou "outro" (terreno, lote, galpão, sítio).
- bairros: os bairros ou regiões pedidos, COMO ELE ESCREVEU (sem corrigir a grafia). Lista vazia se não disse.
- condominio: o nome do condomínio, residencial ou edifício pedido, COMO ELE ESCREVEU, sem as palavras
  "condomínio", "residencial", "edifício". Nome próprio que não é bairro de Manaus é condomínio.
- quartos: número de quartos ("2q", "2 qts", "02 quartos" = 2).
- preco_max: o teto em reais, só o número ("2 mil" = 2000, "2k" = 2000, "1.800" = 1800, "4.000,00" = 4000,
  "350 mil" = 350000, "1,2 mi" = 1200000). Deu uma faixa: é o valor maior.
- mobiliado: true se pediu mobiliado ("mobiliado", "porteira fechada"); false se pediu sem mobília ("cru", "vazio",
  "sem móveis", "não mobiliado"). "Semi mobiliado" = true, com a confiança "duvidoso".
- andar: a lista do que ele aceita, entre "terreo", "1_andar" e "qualquer". "Térreo ou 1º andar" =
  ["terreo", "1_andar"]. "Andar baixo" = ["terreo", "1_andar"] com a confiança "duvidoso". "Qualquer andar" =
  ["qualquer"]. "Andar alto" não cabe aqui: deixe null e escreva em "observacao".
- suite: true se pediu suíte; false se disse que não precisa.
- vagas: número de vagas de garagem pedido.
- pet: true se o cliente tem animal ou pediu que aceite pet.
- financiamento: true se pediu imóvel que ACEITE FINANCIAMENTO (financiamento bancário, pela Caixa, FGTS, Minha Casa
  Minha Vida, "cliente vai financiar"); false se disse que é à vista e não precisa; null se não falou.
- contato: nome ou telefone que a pessoa deixou NA MENSAGEM (assinatura "Att Fulana", "falar com", um número).
- observacao: o que ele pediu e não cabe nos campos ("enviar no PV", "andar alto", "com elevador", "perto do
  trabalho"). Uma frase curta.
- trecho: o pedaço da mensagem que é este pedido, copiado.
- confianca: para CADA campo, "certo", "duvidoso" ou "nao_informado".

REGRAS:
1. Campo que ele não mencionou = null (lista vazia em "bairros") e confiança "nao_informado". NUNCA preencha por
   suposição: não deduza a operação pelo valor, nem o tipo pelo condomínio, nem o bairro pelo condomínio.
2. Na dúvida sobre um campo, ponha a melhor leitura e marque "duvidoso".
3. Entenda gíria, abreviação e emoji de corretor: "2q", "1º and", "térreo", "cru", "tx inclusa", "até 2k"."""

_NULO = {"type": "null"}


def _ou_nulo(esquema: dict) -> dict:
    return {"anyOf": [esquema, _NULO]}


ESQUEMA = {
    "type": "object", "additionalProperties": False, "required": ["pedidos"],
    "properties": {"pedidos": {"type": "array", "items": {
        "type": "object", "additionalProperties": False,
        "required": [*CAMPOS, "observacao", "trecho", "confianca"],
        "properties": {
            "operacao": _ou_nulo({"type": "string", "enum": ["aluguel", "venda"]}),
            "tipo": _ou_nulo({"type": "string", "enum": ["apartamento", "casa", "sala", "outro"]}),
            "bairros": {"type": "array", "items": {"type": "string"}},
            "condominio": _ou_nulo({"type": "string"}),
            "quartos": _ou_nulo({"type": "integer"}),
            "preco_max": _ou_nulo({"type": "number"}),
            "mobiliado": _ou_nulo({"type": "boolean"}),
            "andar": _ou_nulo({"type": "array", "items": {"type": "string", "enum": ["terreo", "1_andar", "qualquer"]}}),
            "suite": _ou_nulo({"type": "boolean"}),
            "vagas": _ou_nulo({"type": "integer"}),
            "pet": _ou_nulo({"type": "boolean"}),
            "financiamento": _ou_nulo({"type": "boolean"}),
            "contato": _ou_nulo({"type": "string"}),
            "observacao": _ou_nulo({"type": "string"}),
            "trecho": {"type": "string"},
            "confianca": {
                "type": "object", "additionalProperties": False, "required": list(CAMPOS),
                "properties": {c: {"type": "string", "enum": ["certo", "duvidoso", "nao_informado"]} for c in CAMPOS},
            },
        },
    }}},
}


class FalhaDoModelo(Exception):
    pass


def _chamar(corpo: dict) -> dict:
    ultimo = ""
    for tentativa in range(3):
        try:
            r = requests.post(URL, timeout=90, json=corpo,
                              headers={"Authorization": f"Bearer {config.OPENAI_API_KEY}", "Content-Type": "application/json"})
            if r.status_code == 200:
                return r.json()
            ultimo = f"HTTP {r.status_code} {r.text[:200]}"
            if r.status_code < 500 and r.status_code != 429:
                break
        except requests.RequestException as e:
            ultimo = f"rede: {e}"
        time.sleep(2 + 3 * tentativa)
    raise FalhaDoModelo(ultimo)


def _texto_da(resposta: dict) -> str:
    return "".join(c.get("text", "") for o in resposta.get("output") or [] if o.get("type") == "message"
                   for c in o.get("content") or [] if c.get("type") == "output_text")


# ── o que nem precisa ir à IA ──
_CARD_NOSSO = re.compile(r"c[óo]digo:\s*\d{3,5}", re.I)


def nao_precisa_ler(texto: str) -> str | None:
    """O motivo, quando a mensagem evidentemente não é pedido (poupa a chamada). None = a IA decide."""
    t = (texto or "").strip()
    if len(t) < 12 or not re.search(r"[A-Za-zÀ-ÿ]{3}", t):
        return "curta demais para ser um pedido"
    if _CARD_NOSSO.search(t):
        return "card de imóvel (tem Código:), é oferta"
    return None


# ── a limpeza: o que o modelo devolveu vira a ficha que o resto do serviço usa ──
def _inteiro(v, minimo: int, maximo: int) -> int | None:
    try:
        n = int(v)
    except (TypeError, ValueError):
        return None
    return n if minimo <= n <= maximo else None


def limpar(p: dict) -> dict | None:
    """Tipos certos, nada inventado, e a lista do que ficou duvidoso. None = não sobrou pedido."""
    if not isinstance(p, dict):
        return None
    conf = p.get("confianca") if isinstance(p.get("confianca"), dict) else {}
    duvidosos = [c for c in CAMPOS if conf.get(c) == "duvidoso"]

    def texto(chave: str, limite: int = 120) -> str | None:
        v = p.get(chave)
        v = re.sub(r"\s+", " ", v).strip() if isinstance(v, str) else ""
        return v[:limite] or None

    def sim_nao(chave: str) -> bool | None:
        return p.get(chave) if isinstance(p.get(chave), bool) else None

    ficha = {
        "operacao": p.get("operacao") if p.get("operacao") in ("aluguel", "venda") else None,
        "tipo": p.get("tipo") if p.get("tipo") in ("apartamento", "casa", "sala", "outro") else None,
        "bairros": [re.sub(r"\s+", " ", b).strip()[:80] for b in (p.get("bairros") or [])
                    if isinstance(b, str) and b.strip()][:6],
        "condominio": texto("condominio", 80),
        "quartos": _inteiro(p.get("quartos"), 0, 12),
        "preco_max": None,
        "mobiliado": sim_nao("mobiliado"),
        "andar": None,
        "suite": sim_nao("suite"),
        "vagas": _inteiro(p.get("vagas"), 0, 12),
        "pet": sim_nao("pet"),
        "financiamento": sim_nao("financiamento"),
        "contato": texto("contato", 80),
        "observacao": texto("observacao", 200),
        "trecho": texto("trecho", 600),
    }
    try:
        teto = float(p.get("preco_max")) if p.get("preco_max") is not None else None
    except (TypeError, ValueError):
        teto = None
    if teto is not None and teto > 0:
        ficha["preco_max"] = round(teto, 2)
        # um teto que não combina com a operação é leitura suspeita ("2" no lugar de 2 mil, aluguel de 350 mil)
        if (ficha["operacao"] == "aluguel" and not 300 <= teto <= 100_000) or \
           (ficha["operacao"] == "venda" and teto < 30_000) or teto < 100:
            duvidosos.append("preco_max")
    if isinstance(p.get("andar"), list):
        andar = [a for a in ("terreo", "1_andar", "qualquer") if a in p["andar"]]
        ficha["andar"] = andar or None
    # pedido que não diz nada de imóvel não é pedido
    if not any([ficha["operacao"], ficha["tipo"], ficha["bairros"], ficha["condominio"],
                ficha["quartos"] is not None, ficha["preco_max"]]):
        return None
    ficha["confianca"] = {c: ("nao_informado" if ficha.get(c) in (None, []) else
                              ("duvidoso" if c in duvidosos else "certo")) for c in CAMPOS}
    ficha["duvidosos"] = sorted({c for c in duvidosos if ficha.get(c) not in (None, [])})
    return ficha


def extrair(texto: str, chamar: Callable[[dict], dict] = _chamar) -> list[dict]:
    """Os pedidos da mensagem (lista vazia = não é pedido). Levanta FalhaDoModelo se a IA não respondeu."""
    entrada = [{"role": "system", "content": PROMPT}, {"role": "user", "content": (texto or "")[:3000]}]
    try:
        r = chamar({"model": config.MODELO, "input": entrada,
                    "text": {"format": {"type": "json_schema", "name": "pedidos_de_imovel", "strict": True, "schema": ESQUEMA}}})
        bruto = _texto_da(r)
    except FalhaDoModelo as e:
        if "HTTP 400" not in str(e):
            raise
        # o modelo recusou o formato rígido: pede o mesmo JSON por instrução
        r = chamar({"model": config.MODELO, "input": [
            {"role": "system", "content": PROMPT + "\n\nResponda SÓ com um JSON neste esquema, sem texto em volta:\n"
                                          + json.dumps(ESQUEMA, ensure_ascii=False)}, entrada[1]]})
        bruto = _texto_da(r)
    try:
        dados = json.loads(bruto[bruto.index("{"): bruto.rindex("}") + 1])
    except ValueError as e:
        raise FalhaDoModelo(f"a resposta não é JSON: {bruto[:120]!r}") from e
    pedidos = [limpar(p) for p in (dados.get("pedidos") or []) if isinstance(dados, dict)]
    return [p for p in pedidos if p][:8]
