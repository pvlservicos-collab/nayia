"""Os números que falam e ouvem como o Tel.

O PEDIDO (Tel, 28/09): "todo comando que o Tel tem, você repassa também para
este número como se fosse ele 92 98595-6408 ... nestes dois números". E,
perguntado, ele escolheu que o número novo RECEBE tudo também -- a
confirmação de cada disparo da grade, os cinco alertas de visita, a cobrança
de pendência, os alarmes e a resposta de cada comando.

POR QUE UM MÓDULO, e não um `split(',')` em cada arquivo: são NOVE lugares
que mandam mensagem para ele (servidor, grade, alertas, detector, ciclo de
pendências, dois alarmes, filtro de alto padrão). Nove cópias de "quem é o
Tel" divergem na primeira edição -- é o padrão 4.3 do HISTORICO, e aqui a
divergência seria silenciosa: um alerta chegaria nos dois números e outro em
um só, e ninguém saberia qual.

A FALHA É ISOLADA POR NÚMERO. Se a Z-API recusar um, o outro recebe -- o
contrário faria o segundo número derrubar um aviso que sempre funcionou.
"""
import os


def numeros_do_tel(valor=None):
    """A lista de números, lida de `TEL_WHATSAPP` (separados por vírgula).

    Um número só continua funcionando exatamente como antes: a vírgula é
    opcional, e quem tiver a variável antiga não precisa mudar nada.
    """
    bruto = valor if valor is not None else os.environ.get("TEL_WHATSAPP", "")
    return [n for n in (p.strip() for p in str(bruto or "").split(",")) if n]


def enviar_ao_tel(destino, texto, enviar=None):
    """Manda o texto para TODOS os números do Tel. Devolve quantos receberam.

    `enviar` é injetável porque as suítes trocam o transporte por um espião --
    e é por isso que o laço mora aqui e não dentro do `enviar_texto`: aquele
    também manda para corretor e para grupo, e um fan-out escondido ali seria
    uma surpresa em todo caminho de envio do projeto.
    """
    if enviar is None:
        # O CHAMADOR NORMALMENTE PASSA O SEU `enviar_texto`, e não é detalhe:
        # as suítes trocam o nome DENTRO do módulo que envia
        # (`patch("servidor.enviar_texto")`). Importar aqui passaria por cima
        # do dublê e o teste tentaria falar com a Z-API de verdade -- que foi
        # o que aconteceu na primeira versão disto.
        from enviar_zapi import enviar_texto
        enviar = enviar_texto
    entregues = 0
    erro = None
    for numero in numeros_do_tel(destino):
        try:
            enviar(numero, texto)
            entregues += 1
        except Exception as exc:      # falha isolada: o outro número recebe
            erro = erro or exc
    if not entregues and erro is not None:
        raise erro
    return entregues


def finais_do_tel(valor=None):
    """Os 8 últimos dígitos de cada número -- a forma de comparar.

    A Z-API entrega número brasileiro ora com o 9 na frente (13 dígitos) ora
    sem (12), então igualdade crua não serve. É o mesmo critério do
    `nay_e_da_equipe`, de 29/08.
    """
    finais = []
    for numero in numeros_do_tel(valor):
        so_digitos = "".join(c for c in numero if c.isdigit())
        if len(so_digitos) >= 8:
            finais.append(so_digitos[-8:])
    return finais
