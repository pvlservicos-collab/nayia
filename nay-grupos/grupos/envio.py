"""O ENVIO AUTOMÁTICO. Nesta versão ele NÃO EXISTE.

Pedro, 09/10/2026: "TREINO: lê as solicitações, extrai, pontua e mostra na tela. NUNCA envia mensagem. O envio
fica bloqueado no código, não só escondido no botão." e "Não prossiga para o modo ATIVO até eu confirmar que o
modo treino está lendo certo."

Este serviço não manda mensagem nenhuma: este módulo não importa nada de rede e a única função dele levanta erro.

O que existe desde a noite de 09/10 é o envio MANUAL, pedido por ele ("põe um botão de enviar manualmente"): um
clique dele na tela, por pedido. Esse envio não passa por aqui: vai da tela para o banco
(`site_captacao_grupos_enviar`, migração 339), que põe a abertura, o card e as fotos na caixa de saída da Nay
(papel 'entrega', o mesmo caminho da aba "Enviar imóvel"), com as travas dela.
"""


class EnvioBloqueado(Exception):
    pass


def enviar(*_args, **_kwargs):
    raise EnvioBloqueado("este serviço não envia mensagem nenhuma: o envio é manual, pelo botão da tela")
