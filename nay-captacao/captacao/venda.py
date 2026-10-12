"""O imóvel da campanha que está no nosso cadastro para VENDA (12/10/2026).

O roteiro da captação nasceu para imóvel de LOCAÇÃO: quando o dono diz "Disponível", o fluxo manda pedir "o valor do
imóvel para locação". Em 12/10 o disparo foi para a lista dos donos com imóvel disponível, e quase todos são de venda
(108 de 111). Das 6 respostas da primeira hora, 5 ouviram "para locação" de um imóvel que anunciamos à venda:
    "Não é para locação, é para venda"                                   (casa de R$ 310 mil)
    "D novo?" / "Procura aí no banco d dados d vcs" / "Coisa chata"      (casa de R$ 580 mil; o Tel repassou a queixa)
O valor de venda já está no cadastro. Aqui a pergunta da locação é trocada por UMA confirmação com o valor que temos;
a resposta dele vai por `guardar_venda`, que já existia no roteiro ("quer vender").

Só vale para imóvel que está no cadastro com valor de venda e SEM valor de aluguel. Imóvel de locação segue o roteiro
de sempre.

E QUEM NÃO TEM IMÓVEL LIGADO (o lead sem código: a lista dos donos da planilha antiga, que nunca viraram imóvel)? Aí
não sabemos se é venda ou locação, e presumir locação é o mesmo erro. Pedro, 12/10: "a Nay que roda lá tem que saber
isso, se o imóvel é venda ou locação". Ela pergunta: "o imóvel é para venda ou para locação?", e segue pelo que ele
disser (venda: guardar_venda; locação: a pergunta do valor da locação, a de sempre).
"""
from __future__ import annotations

from captacao.turno import primeiro_nome

DO_CADASTRO = """
SELECT i.valor_venda, l.tratamento, l.nome
  FROM captacao_leads l JOIN imoveis i ON i.codigo::text = l.codigo
 WHERE l.telefone_chave = nay_fone_chave(%s)
   AND coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0
"""
# o lead sem imóvel ligado: não sabemos o negócio
SEM_IMOVEL = """
SELECT l.tratamento, l.nome FROM captacao_leads l
 WHERE l.telefone_chave = nay_fone_chave(%s) AND coalesce(btrim(l.codigo), '') = ''
   AND NOT coalesce(l.quer_vender, false) AND l.valor_locacao_pedido IS NULL
"""
# o pedaço da instrução do fluxo (guardar_situacao) que manda pedir o valor da locação
PEDIDO_DA_LOCACAO = ". agora peca o valor atualizado da locacao"

SECAO_SEM_IMOVEL = """

=== NAO SABEMOS SE O IMOVEL DELE E DE VENDA OU DE LOCACAO ===
Este proprietario nao tem imovel ligado no nosso cadastro: nao sabemos se o imovel dele e para vender ou para alugar.
- NAO presuma locacao. Quando ele disser que esta DISPONIVEL: chame guardar_situacao com disponivel e, ANTES de pedir
  qualquer valor, faca UMA pergunta, com exatamente estas palavras: "{frase}"
- Se ele disser VENDA: chame guardar_venda (sem valor) e obedeca a instrucao que ela devolver.
- Se ele disser LOCACAO (alugar): ai sim faca a pergunta do valor da locacao (ETAPA 1B) e siga o roteiro.
- Se disser os dois: pergunte os dois valores; o da venda vai em guardar_venda e o da locacao em guardar_situacao (valor).
- Se ele ja disse por conta propria se e venda ou locacao, NAO pergunte de novo: siga direto pelo caminho certo.
"""

SECAO = """

=== ESTE IMOVEL ESTA NO NOSSO CADASTRO PARA VENDA ===
O imovel desta conversa esta anunciado por nos para VENDA, por {valor}. Ele NAO e de locacao.
- NAO faca a pergunta do valor da locacao (ETAPA 1B) e NUNCA diga "para locacao" sobre este imovel.
- Quando ele disser que esta DISPONIVEL: chame guardar_situacao com disponivel e, no lugar do valor da locacao, faca UMA
  pergunta, com exatamente estas palavras: "{frase}"
- Se ele confirmar ("sim", "continua", "isso mesmo"): chame guardar_venda com valor = "{valor}". Se ele disser outro
  valor: chame guardar_venda com o valor do jeito que ele disse. Depois obedeca a instrucao que a ferramenta devolver.
- Se voce ja pediu o valor "para locacao" mais acima nesta conversa, foi engano: NAO repita a pergunta. Se ele responder
  com um valor, e o valor de VENDA (guardar_venda). Se ele reclamar ou disser que e venda, peca desculpa em uma linha e
  confirme o valor do cadastro com a frase acima.
- Se ele perguntar que valor esta no nosso cadastro, diga {valor}.
- So fale de locacao se ELE disser que tambem quer alugar.
"""


def reais(valor) -> str:
    """580000 -> 'R$ 580.000'; 1250000.5 -> 'R$ 1.250.000,50'."""
    v = round(float(valor), 2)
    inteiro, centavos = int(v), int(round((v - int(v)) * 100))
    return "R$ " + f"{inteiro:,}".replace(",", ".") + (f",{centavos:02d}" if centavos else "")


def pergunta(tratamento: str | None, nome: str | None, valor) -> str:
    """A confirmação do valor de venda, no tratamento dele. Sem nome, sai sem vocativo."""
    quem = " ".join(x for x in ((tratamento or "").strip(), primeiro_nome(nome)) if x)
    return (f"{quem}, aqui" if quem else "Aqui") + f" no nosso cadastro o imóvel está à venda por {reais(valor)}. Esse valor continua?"


def do_cadastro(conn, banco, telefone: str) -> dict | None:
    """{'valor': 'R$ 580.000', 'frase': '...'} quando o imóvel da campanha está no cadastro só para venda; senão None."""
    r = banco.linhas(conn, DO_CADASTRO, (telefone,))
    if not r:
        return None
    return {"valor": reais(r[0]["valor_venda"]), "frase": pergunta(r[0]["tratamento"], r[0]["nome"], r[0]["valor_venda"])}


def pergunta_do_negocio(tratamento: str | None, nome: str | None) -> str:
    """Para quem não tem imóvel ligado: venda ou locação?"""
    quem = " ".join(x for x in ((tratamento or "").strip(), primeiro_nome(nome)) if x)
    return (f"{quem}, o" if quem else "O") + " imóvel é para venda ou para locação?"


def sem_imovel(conn, banco, telefone: str) -> dict | None:
    """{'frase': 'Sr. X, o imóvel é para venda ou para locação?'} quando o lead não tem imóvel ligado e ainda não disse
    o negócio; senão None."""
    r = banco.linhas(conn, SEM_IMOVEL, (telefone,))
    return {"frase": pergunta_do_negocio(r[0]["tratamento"], r[0]["nome"])} if r else None


def secao(v: dict | None, s: dict | None = None) -> str:
    """O que entra no prompt: imóvel de venda, ou lead sem imóvel ligado; vazio quando não é nenhum dos dois."""
    if v:
        return SECAO.replace("{valor}", v["valor"]).replace("{frase}", v["frase"])
    return SECAO_SEM_IMOVEL.replace("{frase}", s["frase"]) if s else ""


def instrucao(v: dict) -> str:
    return (f'. o imovel dele esta no nosso cadastro para VENDA, por {v["valor"]} (nao e locacao): NAO peca valor de '
            f'locacao. faca UMA pergunta, com exatamente estas palavras: "{v["frase"]}". se ele confirmar, chame '
            f'guardar_venda com valor = "{v["valor"]}"; se disser outro valor, chame guardar_venda com o valor que ele '
            "disse. NAO comente se o valor esta bom, alto ou baixo.")


def instrucao_sem_imovel(s: dict, pedido_do_fluxo: str) -> str:
    return (f'. NAO sabemos se o imovel dele e de venda ou de locacao: NAO peca valor ainda. faca UMA pergunta, com '
            f'exatamente estas palavras: "{s["frase"]}". se ele disser VENDA, chame guardar_venda (sem valor) e obedeca; '
            "se disser LOCACAO, siga assim" + pedido_do_fluxo)


def no_lugar_da_locacao(linhas: list[dict], v: dict | None, s: dict | None = None) -> list[dict]:
    """Troca, na resposta do guardar_situacao do fluxo, o pedido do valor da locação: pela confirmação do valor de venda
    (imóvel de venda no cadastro) ou pela pergunta "venda ou locação?" (lead sem imóvel ligado)."""
    if not (v or s):
        return linhas
    for linha in linhas:
        texto = linha.get("instrucao_para_voce")
        if isinstance(texto, str) and PEDIDO_DA_LOCACAO in texto:
            antes, depois = texto.split(PEDIDO_DA_LOCACAO, 1)
            linha["instrucao_para_voce"] = antes + (instrucao(v) if v else instrucao_sem_imovel(s, ": peca o valor atualizado da locacao" + depois))
    return linhas
