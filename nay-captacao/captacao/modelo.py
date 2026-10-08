"""O agente: o modelo, o prompt e o laço das ferramentas.

É o nó "AI Agent" do fluxo, pela API de Responses da OpenAI (a mesma do nó "GPT (captação)"): manda o prompt, a
conversa até aqui e o turno; enquanto o modelo pedir ferramenta, roda e devolve o resultado; a última resposta em
texto é o que ela quer dizer ao proprietário.

O ACRÉSCIMO ao prompt vivo (nai_prompt 'captacao') é o que só vale para a conversa pelo número oficial: o modelo
da Meta que abriu a conversa, e a pergunta da indicação antes de encerrar (Pedro, 08/10/2026).
"""
from __future__ import annotations

import json
import time
from typing import Callable

import requests

from captacao import config

URL = "https://api.openai.com/v1/responses"
RODADAS = 8
ACRESCIMO = """

=== O MODELO QUE ABRIU ESTA CONVERSA (numero oficial) ===
A primeira mensagem que ele recebeu foi um modelo oficial, com este texto:
"{modelo}"
e TRES BOTOES: Disponível, Alugado e Vendido.
- Se a mensagem dele for so "Disponível", "Alugado" ou "Vendido", ele TOCOU NO BOTAO: essa e a resposta da situacao do
  imovel. Grave com guardar_situacao e siga o roteiro a partir dai. NAO pergunte de novo se esta disponivel.
- O modelo nao diz qual e o imovel. Se ele perguntar de qual imovel se trata, diga o imovel que esta no cadastro.
- Voce ja se apresentou e ja avisou do numero novo nesse modelo: nao se apresente de novo.

=== ANTES DE ENCERRAR: A INDICACAO ===
Depois da pergunta dos outros imoveis, e antes de encerrar, faca UMA vez esta pergunta, com EXATAMENTE estas palavras
(nao troque, nao resuma, nao junte outra pergunta; antes dela cabe no maximo um "Certo, obrigada." curto):
"{indicacao}"
- Se ele disser que nao conhece ninguem: agradeca em uma linha e encerre.
- Se indicar alguem: peca o nome e o telefone da pessoa (o que ele ainda nao deu), chame guardar_indicacao e siga a
  instrucao que ela devolver.
- Mensagem dele no formato "👤 Contato: NOME — TELEFONE" e um CARTAO DE CONTATO que ele compartilhou: ali estao o nome e
  o telefone da pessoa. Chame guardar_indicacao com esse nome e esse telefone e NAO peca o telefone de novo.
- A ferramenta encerrar_conversa NAO encerra enquanto essa pergunta nao tiver saido: ela devolve a frase para voce dizer.
- Quem pediu para parar de receber, e numero errado, encerram na hora, sem essa pergunta.
"""


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


def responder(prompt: str, historico: list[dict], turno: str, ferramentas: list[dict],
              executar: Callable[[str, dict], str], chamar: Callable[[dict], dict] = _chamar) -> tuple[str, list[dict]]:
    """Devolve o texto final e o que as ferramentas fizeram (para o registro)."""
    feito: list[dict] = []
    r = chamar({"model": config.MODELO, "tools": ferramentas,
                "input": [{"role": "system", "content": prompt}, *historico, {"role": "user", "content": turno}]})
    for _ in range(RODADAS):
        chamadas = [o for o in r.get("output") or [] if o.get("type") == "function_call"]
        if not chamadas:
            return _texto_da(r), feito
        saidas = []
        for c in chamadas:
            try:
                args = json.loads(c.get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            saida = executar(c["name"], args)
            feito.append({"ferramenta": c["name"], "args": {k: v for k, v in args.items() if v not in ("", None)},
                          "saida": saida[:400]})
            saidas.append({"type": "function_call_output", "call_id": c["call_id"], "output": saida})
        r = chamar({"model": config.MODELO, "tools": ferramentas, "previous_response_id": r["id"], "input": saidas})
    raise FalhaDoModelo("passou de 8 rodadas de ferramenta sem responder")
