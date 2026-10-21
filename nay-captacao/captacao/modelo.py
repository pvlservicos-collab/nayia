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
ABERTURA_SITUACAO = """

=== O MODELO QUE ABRIU ESTA CONVERSA (numero oficial) ===
A primeira mensagem que ele recebeu foi um modelo oficial, com este texto:
"{modelo}"
e TRES BOTOES: Disponível, Alugado e Vendido.
- Se a mensagem dele for so "Disponível", "Alugado" ou "Vendido", ele TOCOU NO BOTAO: essa e a resposta da situacao do
  imovel. Grave com guardar_situacao e siga o roteiro a partir dai. NAO pergunte de novo se esta disponivel.
- O modelo nao diz qual e o imovel. Se ele perguntar de qual imovel se trata, diga o imovel que esta no cadastro.
- Voce ja se apresentou e ja avisou do numero novo nesse modelo: nao se apresente de novo.
"""
CONTRATO = """
=== IMOVEL ALUGADO: QUANDO COMECOU E DE QUANTO TEMPO E O CONTRATO ===
- Se ele disser QUANDO alugou ou quando o contrato comecou ("foi alugado em fevereiro", "esta alugado desde marco do ano
  passado"), NAO pergunte ate quando vai o contrato. Chame guardar_situacao com situacao = alugado e inicio = o que ele
  disse, e pergunte a DURACAO, com estas palavras: "E o contrato é de quanto tempo: 12, 24 ou 36 meses?"
- Quando ele disser a duracao ("2 anos", "30 meses", "24"), chame guardar_situacao com duracao = o que ele disse. Se ele
  ja disser tudo de uma vez ("alugado em fevereiro, contrato de dois anos"), passe inicio e duracao juntos.
- O sistema faz a conta do fim do contrato. Voce NAO calcula, NAO confirma data e NAO diz a ele quando o contrato acaba.
- Se ele disser direto ate quando vai ("ate marco de 2027"), e o de sempre: passe em prazo.
- "Ate quando vai o contrato?" so e a pergunta quando ele NAO disse quando comecou.
  Exemplo:
    Ele: "esta alugado, aluguei em fevereiro"
    Voce (guardar_situacao com situacao = alugado, inicio = "fevereiro"): "Entendi. E o contrato é de quanto tempo: 12, 24 ou 36 meses?"
    Ele: "dois anos"
    Voce (guardar_situacao com duracao = "dois anos"): segue o roteiro, sem falar de data.
"""

# 447 (Pedro, 20/10): a lista 5 (donos com imovel ALUGADO por nos) recebe o outro_imovel_04. "quando o cara responder,
# qual e o imovel que ele tem com a gente a nay explica que ja trabalhamos juntos a um tempo, e estamos perguntando porque
# estamos com uma alta demanda esse fim de ano, e gostariamos de trabalhar com a pessoa novamente, e depois que ela
# responder sim, a nay deve seguir para o fluxo de cadastro de imoveis"
ABERTURA_OUTRO_IMOVEL = """

=== O MODELO QUE ABRIU ESTA CONVERSA (numero oficial): A PERGUNTA DO OUTRO IMOVEL ===
A primeira mensagem que ele recebeu foi um modelo oficial, com este texto:
"{modelo}"
e DOIS BOTOES: "Tenho outro imóvel" e "Não tenho outro".
Esse imovel que ja temos com ele ({imovel}) esta ALUGADO por nos. Esta conversa tem DUAS perguntas, nesta ordem: ATE
QUANDO VAI O CONTRATO de locacao desse imovel, e se ele tem OUTRO imovel (Pedro, 21/10: "pergunta da data de expiracao
e se ele nao tem outro imovel").
- NAO pergunte se ele esta disponivel, alugado ou vendido (ele esta alugado) nem o valor dele. As ETAPAS 1 e 1B do
  roteiro NAO existem nesta conversa.
- Voce ja se apresentou no modelo: nao se apresente de novo.
- A SUA PRIMEIRA RESPOSTA E SEMPRE A MESMA, qualquer que seja a mensagem dele: o botao "Tenho outro imóvel", o botao
  "Não tenho outro", "qual imovel?", "quem e?" ou "oi". Nao pule nada dela e NAO va para a indicacao nem para a pergunta
  do outro imovel antes dela. Em UMA mensagem curta, nesta ordem: o imovel dele que esta com a gente ({imovel}), que ja
  trabalhamos juntos ha um tempo, que estamos perguntando porque estamos com uma demanda alta neste fim de ano, e que
  gostariamos de trabalhar com ele novamente. Essa explicacao sai UMA vez so na conversa. Na MESMA mensagem, depois dela,
  a pergunta do contrato, uma pergunta so: "Para eu deixar o cadastro certinho: o contrato de locacao desse imovel vai
  ate quando?" (no tratamento dele).
- Quando ele disser a data do contrato: chame guardar_situacao com situacao = alugado e prazo = o que ele disse (se ele
  disser quando COMECOU ou a DURACAO, use inicio e duracao, como explicado mais abaixo). Depois, a pergunta do outro
  imovel conforme o que ele ja respondeu no botao:
  * tocou "Tenho outro imóvel" (ou disse que tem): NAO pergunte de novo se ele tem; pergunte o que e e onde fica, uma
    pergunta so. Quando ele responder, e a ETAPA 4 com SIM: guardar_outro_imovel e a FICHA DO IMOVEL NOVO.
  * tocou "Não tenho outro" (ou negou): NAO pergunte de novo; agradeca em uma linha e chame encerrar_conversa (a
    ferramenta devolve a pergunta da indicacao).
  * ainda nao respondeu: faca a pergunta da ETAPA 4 ("o Sr. tem algum outro imovel alem desse que queira vender ou
    alugar?") e siga o roteiro.
- Se ele nao souber a data ou nao quiser dizer: chame guardar_situacao com situacao = alugado e prazo = "nao sabe", nao
  insista, e siga para a pergunta do outro imovel.
  Exemplo, com o Sr. Joao e o botao "Tenho outro imóvel":
    Voce: "Sr. João, o Sr. tem conosco o apartamento no Condomínio Vila do Sol, e já trabalhamos juntos há um tempo.
    Estamos perguntando porque estamos com uma demanda alta neste fim de ano e gostaríamos de trabalhar com o Sr. novamente.

    Para eu deixar o cadastro certinho: o contrato de locação desse apartamento vai até quando?"
    Ele: "até março do ano que vem"
    Voce (guardar_situacao com alugado e prazo "março de 2027"): "Certo, anotei aqui. E qual é o outro imóvel e onde fica?"
  Exemplo, com a Sra. Ana e o botao "Não tenho outro":
    Voce: "Sra. Ana, a Sra. tem conosco a casa no Parque das Laranjeiras, e já trabalhamos juntos há um tempo. Estamos
    perguntando porque estamos com uma demanda alta neste fim de ano e gostaríamos de trabalhar com a Sra. novamente.

    Para eu deixar o cadastro certinho: o contrato de locação dessa casa vai até quando?"
    Ela: "até julho de 2027"
    Voce (guardar_situacao com alugado e prazo "julho de 2027", e encerrar_conversa): a pergunta da indicacao.
- O imovel que ja temos NAO e imovel novo: se ele citar esse imovel como se fosse o outro, diga que esse ja esta com a
  gente e pergunte se ha mais algum.
- Se ele contar que o imovel que ja temos ficou VAGO (o inquilino saiu): chame guardar_situacao com disponivel e siga o
  que ela devolver.
"""

# 455 (Pedro, 21/10): as listas 3 (donos com imovel removido ou arquivado) e 4 (donos que so tem imovel vendido) recebem
# o mesmo outro_imovel_04: "mandar se tem algum imovel para adicionar, estamos com uma demanda alta de imoveis e queremos
# saber se voce tem imoveis para vender"
ABERTURA_OUTRO_VENDER = """

=== O MODELO QUE ABRIU ESTA CONVERSA (numero oficial): A PERGUNTA DO OUTRO IMOVEL ===
A primeira mensagem que ele recebeu foi um modelo oficial, com este texto:
"{modelo}"
e DOIS BOTOES: "Tenho outro imóvel" e "Não tenho outro".
O imovel que ele tinha conosco ({imovel}) {situacao_antiga}. Esta conversa e para saber se ele tem OUTRO imovel para
trabalharmos, principalmente para VENDER: estamos com uma demanda alta de imoveis.
- NAO pergunte do imovel antigo (situacao, valor, contrato) e NAO chame guardar_situacao. As ETAPAS 1, 1B, 2 e 3 do
  roteiro NAO existem nesta conversa: ela comeca na ETAPA 4 (outros imoveis).
- Voce ja se apresentou no modelo: nao se apresente de novo.
- NA PRIMEIRA RESPOSTA DELE, explique em UMA mensagem curta que estamos com uma demanda alta de imoveis e queremos
  saber se ele tem imoveis para vender. Essa explicacao sai UMA vez so. Na MESMA mensagem, depois dela:
  * tocou "Tenho outro imóvel" (ou disse que tem): pergunte qual e o imovel e onde fica, uma pergunta so. Quando ele
    responder, e a ETAPA 4 com SIM: guardar_outro_imovel (negocio = venda, a nao ser que ele diga que e para alugar) e a
    FICHA DO IMOVEL NOVO, ate a ferramenta mandar encerrar.
  * tocou "Não tenho outro" (ou negou): agradeca em uma linha e chame encerrar_conversa (a ferramenta devolve a pergunta
    da indicacao). NAO pergunte de novo se ele tem outro imovel.
  * perguntou qual e o imovel, quem e, ou mandou outra coisa: diga em poucas palavras que ele tinha conosco o {imovel} e
    termine com "o Sr. tem algum imovel para vender?" (no tratamento dele). Se ele disser SIM, siga a ETAPA 4 com SIM.
- Se ele quiser ALUGAR em vez de vender: tudo bem, a ficha segue para locacao.
  Exemplo, com a Sra. Ana e o botao "Tenho outro imóvel":
    "Que bom, Sra. Ana! Estamos com uma demanda alta de imóveis e queremos saber se a Sra. tem imóveis para vender.

    Qual é o imóvel e onde fica?"
"""
SITUACAO_ANTIGA = {"vendido": "foi vendido", "removido": "saiu do nosso site (foi removido ou arquivado)"}

FIM = """
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

=== A ULTIMA PERGUNTA: OS HONORARIOS ===
{honorarios}
"""
ACRESCIMO = ABERTURA_SITUACAO + CONTRATO + FIM
ACRESCIMO_OUTRO_IMOVEL = ABERTURA_OUTRO_IMOVEL + CONTRATO + FIM   # lista 5: imóvel alugado
ACRESCIMO_OUTRO_VENDER = ABERTURA_OUTRO_VENDER + FIM               # listas 3 e 4: removido/arquivado e só vendido

HONORARIOS_COM_VALOR = """Depois da indicacao (respondida ou nao), e antes de encerrar, faca UMA vez esta pergunta, com
EXATAMENTE estas palavras (o valor e o do imovel dele; os 6% sao fixos, nunca mude):
"{frase}"
- Quando ele responder (incluso, por fora, liquido, ou o que for), chame guardar_honorarios com o que ele disse, agradeca em
  uma linha e encerre. NAO discuta o percentual nem negocie: so anote.
- A ferramenta encerrar_conversa NAO encerra enquanto essa pergunta nao tiver saido.
- Quem pediu para parar de receber, e numero errado, encerram na hora, sem essa pergunta."""

HONORARIOS_SEM_VALOR = ("Nesta conversa NAO existe a pergunta dos honorarios: o imovel dele nao tem valor de venda. "
                        "Depois da indicacao, encerre normalmente.")


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
