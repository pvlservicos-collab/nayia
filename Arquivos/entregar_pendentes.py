"""
Entrega o imóvel que a Nay ficou de mandar e não mandou.

O CASO: o Gustavo pediu três imóveis em 30/08 e esperou dois dias. O Ênio
deu o perfil em 31/08 e também ficou sem. Nas duas vezes quem mandou fui
eu, rodando comando no servidor. O Tel foi direto: "preciso que a Nay
reconheça isso e envie ela mesma".

É irmão do `disparar_lembretes.py` e divide as mesmas paredes -- a pausa
geral, o teto de um contato por dia, a reserva atômica, a janela de horário
-- mas o sentido é oposto: lá a Nay cobra resposta do corretor, aqui ela
paga o que deve.

A JANELA VEM IMPORTADA de lá, de propósito: uma única definição de "de
quando até quando a Nay pode iniciar conversa". Escrita duas vezes, uma das
duas seria esquecida na primeira mudança -- e a versão esquecida acordaria
corretor às 3 da manhã com card de imóvel.

O QUE ELE NÃO FAZ: não decide o que oferecer. Só entrega o que já foi
pedido e registrado como dívida por `nay_ficou_devendo`. Empurrar imóvel
que ninguém pediu seria outra coisa, e não é isto.

Rodar à mão para observar antes do cron:
    .venv/bin/python entregar_pendentes.py            # só mostra
    .venv/bin/python entregar_pendentes.py --enviar   # manda de verdade
"""
import datetime
import sys

import db
from buscar_imovel import buscar_imovel
from disparar_lembretes import (FUSO_MANAUS, atendimento_pausado,
                                dentro_do_horario)
from enviar_zapi import enviar_imovel, enviar_texto
from montar_mensagem import montar_mensagem

TODOS_OS_NEGOCIOS = {"aceita_venda": True, "aceita_locacao": True}


def devidas(conexao):
    with conexao.cursor() as cur:
        cur.execute("SELECT telefone, ids, codigos, abertura FROM nay_entregas_devidas()")
        return cur.fetchall()


def _um(conexao, sql, params):
    with conexao.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def entregar(conexao, enviar=False, agora=None):
    agora = agora or datetime.datetime.now(FUSO_MANAUS)

    # Antes de qualquer consulta: fora da janela nada sai. A pausa geral já
    # é checada dentro de `nay_entregas_devidas`.
    if not dentro_do_horario(agora):
        return []
    # A PAUSA VALE AQUI TAMBÉM (02/09). O CLAUDE.md dizia que pausada
    # "nenhum corretor recebe nada", e não era verdade: três dos quatro
    # crons que falam com corretor ignoravam a chave. O Tel pausou porque
    # ela estava respondendo mal, e continuou saindo mensagem.
    if atendimento_pausado(conexao):
        return []

    resultados = []
    for linha in devidas(conexao):
        telefone = linha["telefone"]
        ids = linha["ids"]
        codigos = [c for c in (linha["codigos"] or "").split(",") if c]

        if not enviar:
            resultados.append((telefone, codigos, "simulado"))
            continue

        # Reserva ANTES de enviar: o cron roda de minuto em minuto.
        if _um(conexao, "SELECT nay_reservar_entregas(%s) AS n", (ids,))["n"] == 0:
            continue

        # DEVOLVE SÓ O QUE NÃO SAIU. A versão anterior devolvia `ids`
        # inteiro no primeiro erro, e como o cron roda de minuto em minuto
        # o corretor recebia a frase de abertura e os cards já entregues
        # DE NOVO, a cada minuto -- até 720 vezes por dia se a falha fosse
        # persistente. Achado na auditoria de 01/09, no código que eu tinha
        # escrito horas antes.
        entregues = []
        falhou = None
        try:
            enviar_texto(telefone, linha["abertura"])
        except Exception as erro:
            # A abertura nem saiu: devolve tudo, nada foi entregue.
            _um(conexao, "SELECT nay_devolver_entregas(%s) AS n", (ids,))
            conexao.commit()
            resultados.append((telefone, codigos, f"erro: {erro}"))
            continue

        for codigo in codigos:
            try:
                imovel = buscar_imovel(codigo)
                if not imovel:
                    continue
                fotos = [f for f in (imovel.get("fotos") or []) if f]
                enviar_imovel(telefone, montar_mensagem(imovel, TODOS_OS_NEGOCIOS), fotos)
            except Exception as erro:
                # Este imóvel não saiu. Para aqui: insistir nos seguintes
                # com a Z-API caída só empilha falha.
                falhou = erro
                break
            entregues.append(codigo)
            with conexao.cursor() as cur:
                cur.execute(
                    "INSERT INTO envios (codigo, telefone, destino) "
                    "VALUES (%s,%s,'corretor')", (str(codigo), str(telefone)))
            conexao.commit()

        if falhou is not None:
            # Só os que não saíram voltam a dever. Os entregues já estão em
            # `envios`, e a abertura não se repete porque a dívida devolvida
            # é menor -- na próxima execução ela cobre só o que faltou.
            faltando = [i for i, c in zip(ids, codigos) if c not in entregues]
            if faltando:
                _um(conexao, "SELECT nay_devolver_entregas(%s) AS n", (faltando,))
                conexao.commit()
            resultados.append((telefone, entregues, f"parcial, erro: {falhou}"))
            continue

        with conexao.cursor() as cur:
            cur.execute(
                "INSERT INTO contato_corretor (telefone, motivo) VALUES (%s,'entrega')",
                (telefone,))
        conexao.commit()
        resultados.append((telefone, codigos, "entregue"))

    return resultados


def main():
    enviar = "--enviar" in sys.argv
    conexao = db.conectar()
    try:
        resultados = entregar(conexao, enviar=enviar)
    finally:
        conexao.close()

    # Silêncio quando não há nada: roda 1.440x por dia.
    if not resultados:
        return 0
    for telefone, codigos, estado in resultados:
        print(f"[{estado}] {telefone} -> {', '.join(codigos)}")
    if not enviar:
        print("\n(simulação -- rode com --enviar para mandar de verdade)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
