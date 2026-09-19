"""Prova que o alarme de crons acusa quando um cron para -- e cala quando não.

O CASO (02/09): `disparar_grade.sh` perdeu o bit de execução e o cron
falhou com "Permission denied" a cada minuto. A grade ficou **18 horas**
sem postar, com 754 linhas de erro num log que ninguém lê. O sintoma que
chegou ao Tel foi outro, no dia seguinte: "coloquei para postar no grupo e
ela não postou".

Não toca banco nem WhatsApp: mexe só nos arquivos de batimento, numa pasta
temporária.

    .venv/bin/python teste_alarme_crons.py
"""
import datetime
import os
import sys
import tempfile
from zoneinfo import ZoneInfo

import alarme_crons

FUSO = ZoneInfo("America/Manaus")


def preparar(pasta, batendo, agora, atraso_min=0):
    """Cria o batimento de cada cron em `batendo`, com o atraso pedido."""
    alarme_crons.PASTA = pasta
    for nome in batendo:
        caminho = os.path.join(pasta, f".batimento_{nome}")
        with open(caminho, "w") as f:
            f.write("")
        quando = (agora - datetime.timedelta(minutes=atraso_min)).timestamp()
        os.utime(caminho, (quando, quando))


def teste_todos_batendo_fica_em_silencio():
    print("--- os quatro batendo agora: silêncio ---")
    agora = datetime.datetime.now(FUSO)
    with tempfile.TemporaryDirectory() as pasta:
        preparar(pasta, alarme_crons.CRONS.keys(), agora, atraso_min=0)
        assert alarme_crons.parados(agora) == [], "não devia acusar nada"
    print("OK\n")


def teste_atraso_pequeno_nao_alarma():
    print("--- 10 min de atraso: ainda dentro da folga ---")
    agora = datetime.datetime.now(FUSO)
    with tempfile.TemporaryDirectory() as pasta:
        preparar(pasta, alarme_crons.CRONS.keys(), agora, atraso_min=10)
        assert alarme_crons.parados(agora) == [], \
            "10 min é menos que a folga de 15 -- alarme que toca à toa ensina a ignorar"
    print("OK\n")


def teste_cron_parado_e_acusado():
    print("--- a grade parada há 18 horas (o caso real) ---")
    agora = datetime.datetime.now(FUSO)
    with tempfile.TemporaryDirectory() as pasta:
        preparar(pasta, alarme_crons.CRONS.keys(), agora, atraso_min=0)
        # só a grade fica para trás, como aconteceu
        caminho = os.path.join(pasta, ".batimento_disparar_grade")
        quando = (agora - datetime.timedelta(hours=18)).timestamp()
        os.utime(caminho, (quando, quando))

        fora = alarme_crons.parados(agora)
        assert len(fora) == 1, fora
        assert fora[0][0] == "disparar_grade", fora
        aviso = alarme_crons.montar_aviso(fora)
        print(aviso)
        assert "grade de postagem" in aviso
        assert "1080 min" in aviso or "parado há" in aviso
    print("OK\n")


def teste_sem_batimento_conta_como_parado():
    print("--- batimento que nunca existiu: falha FECHADA ---")
    agora = datetime.datetime.now(FUSO)
    with tempfile.TemporaryDirectory() as pasta:
        # pasta vazia: nenhum cron jamais bateu
        alarme_crons.PASTA = pasta
        fora = alarme_crons.parados(agora)
        assert len(fora) == len(alarme_crons.CRONS), fora
        aviso = alarme_crons.montar_aviso(fora)
        assert "nunca rodou" in aviso, aviso
        # "não sei se está rodando" é notícia ruim, não silêncio
    print("OK\n")


def teste_aviso_nomeia_o_que_parou():
    print("--- o aviso diz QUAL cron parou, não só que algo parou ---")
    agora = datetime.datetime.now(FUSO)
    with tempfile.TemporaryDirectory() as pasta:
        preparar(pasta, ["disparar_grade"], agora, atraso_min=0)
        fora = alarme_crons.parados(agora)
        aviso = alarme_crons.montar_aviso(fora)
        print(aviso)
        assert "lembretes" in aviso and "pendências" in aviso
        assert "grade de postagem" not in aviso, "a grade está batendo, não pode entrar"
    print("OK\n")


if __name__ == "__main__":
    teste_todos_batendo_fica_em_silencio()
    teste_atraso_pequeno_nao_alarma()
    teste_cron_parado_e_acusado()
    teste_sem_batimento_conta_como_parado()
    teste_aviso_nomeia_o_que_parou()
    print("TODOS OS TESTES PASSARAM")
    sys.exit(0)
