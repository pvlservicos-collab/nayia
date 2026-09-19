"""
Manda os lembretes de retorno que vencem agora.

O QUE É UM LEMBRETE: o corretor diz que o cliente dele responde "amanhã de
manhã", e a Nay cobra na hora certa em vez de esquecer. As regras e os 205
jeitos de dizer "amanhã" estão no doc 31; as tabelas e funções em
`lembrete.sql`. Este script é só o braço que executa.

DECISÕES DO TEL QUE ESTE SCRIPT OBEDECE (31/08):
  * no máximo 1 mensagem por corretor por dia iniciada pela Nay -- três
    lembretes vencendo juntos viram UMA mensagem com lista. O teto vive na
    `nay_pode_falar`, não aqui, para valer para qualquer emissor futuro;
  * sem janela por dia da semana: domingo e sábado valem;
  * mas nada antes das 08:00 nem depois das 20:00, porque todos os
    horários que ele descreveu vivem lá dentro;
  * três toques e depois escala.

POR QUE RESERVA ATÔMICA: o cron roda de minuto em minuto. `postar_agora` já
provou neste projeto que, sem reserva, o mesmo item sai duas vezes -- e
mensagem de WhatsApp não tem desfazer. `nay_reservar_lembretes` só devolve
linha para quem estava mesmo em 'agendado'.

POR QUE A PAUSA É LIDA AQUI: quando o Tel pausa a Nay, ninguém pode receber
nada -- e o cron é um caminho de saída que não passa pelo n8n, então o
porteiro de lá não o alcança.

SILÊNCIO QUANDO NÃO HÁ NADA: como o `disparar_grade.py`, não escreve nem
manda nada quando não há lembrete devido. Vai rodar 1.440 vezes por dia.

Rodar à mão para observar antes do cron:
    .venv/bin/python disparar_lembretes.py            # só mostra
    .venv/bin/python disparar_lembretes.py --enviar   # manda de verdade
"""
import datetime
import sys
from zoneinfo import ZoneInfo

import db
from enviar_zapi import enviar_texto

FUSO_MANAUS = ZoneInfo("America/Manaus")

# Fora desta faixa nada sai. Não é a "janela de silêncio" que o Tel
# recusou (aquela bloqueava domingo e sábado); é só o piso e o teto do
# dia, e todo horário que ele descreveu cabe aqui dentro.
HORA_MINIMA = 8
HORA_MAXIMA = 20


def dentro_do_horario(agora=None):
    agora = agora or datetime.datetime.now(FUSO_MANAUS)
    return HORA_MINIMA <= agora.hour < HORA_MAXIMA


def atendimento_pausado(conexao):
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT valor = 'sim' AS pausado FROM config "
            "WHERE chave = 'atendimento_pausado'"
        )
        linha = cur.fetchone()
    # Sem a linha, considera PAUSADO: mesmo princípio do porteiro do n8n --
    # quem não sabe se pode falar, não fala.
    return True if linha is None else bool(linha["pausado"])


def lembretes_devidos(conexao):
    with conexao.cursor() as cur:
        cur.execute("SELECT telefone, ids, mensagem FROM nay_lembretes_devidos()")
        return cur.fetchall()


def reservar(conexao, ids):
    """Devolve quantos foram efetivamente reservados. Zero significa que
    outra execução pegou primeiro -- não envia."""
    with conexao.cursor() as cur:
        cur.execute("SELECT nay_reservar_lembretes(%s) AS n", (ids,))
        return cur.fetchone()["n"]


def marcar_proximo_toque(conexao, ids):
    with conexao.cursor() as cur:
        cur.execute("SELECT nay_proximo_toque(%s) AS n", (ids,))
        return cur.fetchone()["n"]


def disparar(conexao, enviar=False, agora=None):
    agora = agora or datetime.datetime.now(FUSO_MANAUS)

    if not dentro_do_horario(agora):
        return []
    if atendimento_pausado(conexao):
        return []

    resultados = []
    for linha in lembretes_devidos(conexao):
        telefone = linha["telefone"]
        ids = linha["ids"]
        mensagem = linha["mensagem"]

        if not enviar:
            resultados.append((telefone, ids, mensagem, "simulado"))
            continue

        # Reserva ANTES de enviar. Se outra execução já pegou, sai fora.
        if reservar(conexao, ids) == 0:
            continue

        try:
            enviar_texto(telefone, mensagem)
        except Exception as erro:
            # O envio falhou depois da reserva: devolve para 'agendado'
            # para a próxima execução tentar, em vez de perder o lembrete.
            with conexao.cursor() as cur:
                cur.execute(
                    "UPDATE lembrete SET estado = 'agendado', "
                    "tentativa = greatest(tentativa - 1, 0), "
                    "atualizado_em = now() WHERE id = ANY(%s)",
                    (ids,),
                )
            conexao.commit()
            resultados.append((telefone, ids, mensagem, f"erro: {erro}"))
            continue

        marcar_proximo_toque(conexao, ids)
        conexao.commit()
        resultados.append((telefone, ids, mensagem, "enviado"))

    return resultados


def main():
    enviar = "--enviar" in sys.argv
    conexao = db.conectar()
    try:
        resultados = disparar(conexao, enviar=enviar)
    finally:
        conexao.close()

    # Silêncio total quando não há nada: este script roda 1.440x por dia.
    if not resultados:
        return 0

    for telefone, ids, mensagem, estado in resultados:
        print(f"[{estado}] {telefone} lembretes={ids}")
        print(f"    {mensagem}")
    if not enviar:
        print("\n(simulação -- rode com --enviar para mandar de verdade)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
