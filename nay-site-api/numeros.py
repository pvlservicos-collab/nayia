"""O número que vem de um formulário de cadastro, lido de um jeito só.

POR QUE EXISTE (03/10/2026). O cadastro de imóvel tinha duas leituras de número, e as duas erravam:

  * a tela de editar do site mandava o que estava num campo type="number", onde o navegador lê o
    ponto como vírgula decimal: "750.000" chegava como 750. Foi assim que o 9013 ficou à venda por
    R$ 690, o 9010 por R$ 590 e o 9008 por R$ 900 ("eu salvei a casa com valor de 850.000 e quando
    eu salvo ela volta para o valor de 750");

  * o popup do CRM (olx_api._valor_do_popup) tirava TODO ponto antes de converter: certo para
    "750.000", mas a área 88.5 que o próprio popup mostrava virava 885 a cada salvar.

A REGRA, uma só: ponto seguido de exatamente três dígitos é milhar ("750.000", "1.200.000"); com
vírgula no texto, a vírgula é o decimal e os pontos são milhar ("1.089,50"); o resto é número
comum ("88.5", "750000"). Funções puras, sem Flask: dá para testar sem subir nada.
"""
import re

MILHARES = re.compile(r"\d{1,3}(\.\d{3})+(,\d+)?")


def numero_br(valor):
    """float do que veio do formulário. Levanta ValueError/TypeError para o que não é número."""
    if isinstance(valor, bool):
        raise ValueError("booleano não é número")
    if isinstance(valor, (int, float)):
        return float(valor)
    s = str(valor).strip().replace("R$", "").replace(" ", "")
    if MILHARES.fullmatch(s) or "," in s:
        s = s.replace(".", "").replace(",", ".")
    return float(s)


# Abaixo disto o valor só pode ser erro de digitação: em 03/10 a venda mais barata do catálogo era
# R$ 80.000 e o aluguel mais barato R$ 1.100.
PISO_DO_VALOR = {"valor_venda": 10000, "valor_aluguel": 100}


def valor_que_nao_existe(campo, numero):
    """A frase do erro quando o valor é pequeno demais para ser verdade; None quando está certo.
    Zero e vazio passam: é "sem valor", não valor errado."""
    piso = PISO_DO_VALOR.get(campo)
    if piso is None or numero is None or numero <= 0 or numero >= piso:
        return None
    nome = "venda" if campo == "valor_venda" else "aluguel"
    escrito = f"{numero:,.0f}".replace(",", ".")
    return (f"{campo}: {nome} de R$ {escrito}? Parece faltar os milhares. "
            f"Escreva o valor inteiro, com os pontos (por exemplo 750.000).")
