"""O ENVIO. Nesta versão ele NÃO EXISTE.

Pedro, 09/10/2026: "TREINO: lê as solicitações, extrai, pontua e mostra na tela. NUNCA envia mensagem. O envio
fica bloqueado no código, não só escondido no botão." e "Não prossiga para o modo ATIVO até eu confirmar que o
modo treino está lendo certo."

Este módulo é o único lugar por onde uma mensagem sairia. Ele não importa nada de rede, não conhece a Z-API
nem a caixa da Nay, e a única função dele levanta erro. O modo ativo entra aqui, depois do sim dele.
"""


class EnvioBloqueado(Exception):
    pass


def enviar(*_args, **_kwargs):
    raise EnvioBloqueado("modo treino: esta versão não envia mensagem nenhuma")
