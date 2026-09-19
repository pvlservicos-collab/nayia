"""
Doc 28: fecha a decisão pendente do passo 8 e implementa o passo 9.

Passo 8 (decisão confirmada pelo Tel): quando VENDEU/ALUGOU acerta uma
vaga com mais de 1 código, remove só o código vendido/alugado do array,
mantendo os outros ativos.

Passo 9 (aviso de vaga livre): se a remoção deixar o array vazio, a
vaga vira vaga livre -- não é um estado novo, é só codigos = [] (o
default do schema). Quando isso acontece, monta o aviso pro Tel dizendo
qual vaga (dia + horário) ficou livre. A Nay não escolhe o próximo
imóvel sozinha -- só avisa e espera (doc 28).

Funções puras: recebem a lista de vagas e devolvem o que deveria
mudar, não escrevem no banco -- mesmo padrão dos passos anteriores.
"""

NUMERO_PARA_DIA = {
    0: "domingo", 1: "segunda", 2: "terça", 3: "quarta",
    4: "quinta", 5: "sexta", 6: "sábado",
}


def _fmt_hora(horario):
    if horario.minute == 0:
        return f"{horario.hour}h"
    return f"{horario.hour}h{horario.minute:02d}"


def _lista_de_dias(dias):
    """"terça, quinta e sábado" -- não "terça e quinta e sábado".

    O Tel lê esta frase toda vez que cria ou remove vaga."""
    nomes = [NUMERO_PARA_DIA[d] for d in dias]
    if len(nomes) <= 1:
        return "".join(nomes)
    return ", ".join(nomes[:-1]) + " e " + nomes[-1]


def descrever_vaga(vaga):
    hora = _fmt_hora(vaga["horario"])
    tipo = vaga["tipo_recorrencia"]
    if tipo == "diaria":
        return f"todo dia às {hora}"
    if tipo == "semanal":
        return f"{_lista_de_dias(vaga['dias_semana'])} às {hora}"
    if tipo == "unica":
        return f"dia {vaga['data_unica'].strftime('%d/%m')} às {hora}"
    return f"às {hora}"


def montar_aviso_vaga_livre(vaga):
    return f"A vaga de {descrever_vaga(vaga)} ficou livre. Qual imóvel entra?"


def liberar_codigo(vagas, codigo):
    """Remove `codigo` do array de codigos de toda vaga que o contém.

    Devolve uma lista de mudanças (uma por vaga afetada), cada uma com
    o array antes/depois e, se a vaga ficou vazia, o aviso pronto pro
    Tel. Não aplica nada no banco -- só decide o que deveria acontecer.
    """
    mudancas = []
    for vaga in vagas:
        if codigo not in vaga["codigos"]:
            continue
        codigos_depois = [c for c in vaga["codigos"] if c != codigo]
        ficou_livre = len(codigos_depois) == 0
        mudancas.append({
            "vaga_id": vaga["id"],
            "codigos_antes": list(vaga["codigos"]),
            "codigos_depois": codigos_depois,
            "ficou_livre": ficou_livre,
            "aviso": montar_aviso_vaga_livre(vaga) if ficou_livre else None,
        })
    return mudancas
