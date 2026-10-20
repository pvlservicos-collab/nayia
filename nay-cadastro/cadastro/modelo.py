"""O modelo só LÊ: tira os dados do texto que o Tel encaminhou e da resposta do corretor. Quem decide a próxima
pergunta, o que grava e o que diz é o código (campos.py, fluxo.py). A saída é sempre JSON no formato de ficha.py."""
from __future__ import annotations

import json
import re
import time
from typing import Callable

import requests

from cadastro import config
from cadastro.ficha import SCHEMA_LEVA, SCHEMA_RESPOSTA

URL = "https://api.openai.com/v1/responses"

REGRAS_DE_VALOR = """REGRAS DOS VALORES
- Dinheiro em reais, como número: "3.500" -> 3500; "3,5 mil" -> 3500; "750 mil" -> 750000; "1,2 milhão" -> 1200000;
  "2.5k" -> 2500. Aluguel costuma ir até 30 mil; venda, de 100 mil para cima.
- Área em m², como número: "120m²" -> 120.
- mobilia: "mobiliado" (todo mobiliado), "com modulados e ar" (semimobiliado, só armários/modulados e ar),
  "só climatizado" (só ar-condicionado), "sem nada" (vazio).
- tipo: um destes, exatamente: Apartamento, Casa, Casa de condomínio, Cobertura, Flat, Sala/Andar, Loja/Ponto, Galpão,
  Lote, Lote em Condomínio, Chácara, Prédio.
- condominio: o nome do condomínio/edifício/residencial como a pessoa escreveu (mesmo com erro de digitação).
- bairro: o bairro de Manaus como escrito.
- caracteristicas: itens curtos do próprio imóvel ("varanda", "área gourmet", "piscina privativa", "climatizado").
  Lazer e segurança do CONDOMÍNIO (piscina do condomínio, academia, portaria 24h) vão em condominio_lazer /
  condominio_seguranca.
- NUNCA invente: o que não está escrito vem null (ou lista vazia)."""

PROMPT_LEVA = """Você lê as mensagens que o Tel (dono da Imob Easy, imobiliária de Manaus) encaminhou no grupo de
cadastro de imóveis. Quase sempre são o anúncio de UM imóvel (texto e fotos) e o contato do corretor ou do
proprietário. Tire os dados do imóvel.

- e_imovel = false quando as mensagens não descrevem um imóvel (conversa, "ok", "obrigado", só um telefone solto).
- papel: "corretor" se o texto mostra que quem anuncia é corretor (CRECI, imobiliária, "corretor", "parceria");
  "proprietario" se diz que é o dono; senão null.
- contato_nome / contato_telefone: do corretor ou proprietário, se estiverem escritos ("👤 Contato: NOME — FONE" é o
  cartão de contato que o Tel encaminhou).
- descricao: o texto do anúncio, limpo (sem telefone, sem nome do corretor, sem CRECI), ou null.

""" + REGRAS_DE_VALOR

PROMPT_RESPOSTA = """Você é a Nay, da Imob Easy, completando o cadastro de um imóvel pelo WhatsApp. Você fez UMA pergunta
e a pessoa (o corretor ou o proprietário do imóvel) respondeu. Preencha o que a resposta diz; ela pode responder mais de
uma coisa de uma vez, e tudo o que disser sobre o imóvel vale.

- respondeu = true se a resposta responde à pergunta (mesmo que seja "não tem", "nenhuma", "não").
- nao_sabe = true se ela disse que não sabe, que não tem essa informação agora, ou que não se aplica
  ("não é condomínio", "é casa de rua", "não tem elevador" NÃO é nao_sabe: é a resposta).
- fora_do_assunto = true se a mensagem fala de outra coisa (outro imóvel, cliente, visita, pedido) e não responde.
- Pergunta do papel: "sou o dono", "é meu" -> papel = proprietario; "sou corretor(a)" -> papel = corretor.
- Pergunta "alugar ou vender": diga a finalidade e o valor em valor_aluguel ou valor_venda.
- Pergunta do elevador: condominio_elevador = "sim" ou "nao".
- Pergunta "quartos e suítes": quartos e suites ("3 quartos sendo 1 suíte" -> quartos 3, suites 1).
- Torre/bloco e apartamento: "bloco B, 302" -> bloco "B", unidade "302".
- ANDAR: o número do andar como texto ("7º andar" -> "7"; "térreo" -> "Térreo"; "cobertura" -> "Cobertura"). Se ela
  disser o NÚMERO DO APARTAMENTO em vez do andar, tire o andar dele: com 3 ou 4 dígitos, o andar são os dígitos antes
  dos dois últimos ("302" -> "3", "1104" -> "11"); com 2 dígitos, o primeiro ("52" -> "5"); com 1 dígito, andar null.
  Nesse caso preencha andar E unidade.
- lances_escada: quantos lances de escada até o imóvel, quando o prédio não tem elevador ("2 lances" -> 2;
  "é no térreo, sem escada" -> 0).

""" + REGRAS_DE_VALOR


class FalhaDoModelo(Exception):
    pass


def _chamar(corpo: dict) -> dict:
    ultimo = ""
    for tentativa in range(3):
        try:
            r = requests.post(URL, timeout=90, json=corpo,
                              headers={"Authorization": f"Bearer {config.OPENAI_API_KEY}",
                                       "Content-Type": "application/json"})
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


def _json(texto: str) -> dict:
    try:
        return json.loads(texto)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", texto or "", re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except json.JSONDecodeError:
                pass
    raise FalhaDoModelo("o modelo não devolveu JSON: " + (texto or "")[:200])


def pedir(prompt: str, entrada: str, schema: dict, nome: str, chamar: Callable[[dict], dict] = _chamar) -> dict:
    r = chamar({"model": config.MODELO,
                "input": [{"role": "system", "content": prompt}, {"role": "user", "content": entrada}],
                "text": {"format": {"type": "json_schema", "name": nome, "schema": schema, "strict": True}}})
    return _json(_texto_da(r))


def ler_leva(texto: str, n_fotos: int, chamar: Callable[[dict], dict] = _chamar) -> dict:
    entrada = f"MENSAGENS ENCAMINHADAS (e {n_fotos} foto(s)):\n{texto or '(sem texto)'}"
    return pedir(PROMPT_LEVA, entrada, SCHEMA_LEVA, "leva", chamar)


def ler_resposta(pergunta: str, chave: str, resposta: str, ja_sabemos: str,
                 chamar: Callable[[dict], dict] = _chamar) -> dict:
    entrada = (f"O QUE JÁ SABEMOS DO IMÓVEL: {ja_sabemos or '(pouco)'}\n"
               f"SUA PERGUNTA ({chave}): {pergunta}\n"
               f"A RESPOSTA DELA: {resposta}")
    return pedir(PROMPT_RESPOSTA, entrada, SCHEMA_RESPOSTA, "resposta", chamar)
