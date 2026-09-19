"""Avisa o Tel quando um cron para de rodar.

POR QUE ISTO EXISTE (02/09): `disparar_grade.sh` perdeu o bit de execução
-- estava `100644` no git, enquanto todos os outros wrappers estavam
`100755` -- e um `git reset --hard` impôs o modo errado no servidor. O
cron passou a falhar com "Permission denied" **a cada minuto**, e ninguém
soube: a grade ficou **18 horas** sem postar. O sintoma que chegou ao Tel
foi outro, no dia seguinte: "coloquei para postar no grupo e ela não
postou".

754 linhas de erro no log, e log ninguém lê. É exatamente o mesmo enredo
da varredura que ficou três dias parada (28 a 31/08) -- e a lição que ficou
de lá, `alarme_varredura.py`, cobria só a varredura.

O QUE ELE OLHA: um arquivo de batimento por cron, que o wrapper toca ao
terminar bem. Arquivo e não tabela de propósito: `touch` é uma syscall e
roda a cada minuto, quatro vezes; abrir conexão de banco para dizer
"estou vivo" custaria mais que o trabalho.

FALHA FECHADA: batimento que não existe conta como parado. "Não sei se
está rodando" é notícia ruim, não silêncio.

UM AVISO POR DIA por cron, pelo mesmo motivo do outro alarme: se ficar
quebrado uma semana, o Tel não pode receber uma mensagem por hora.

    .venv/bin/python alarme_crons.py             # só mostra
    .venv/bin/python alarme_crons.py --enviar    # manda se preciso
"""
import datetime
import os
import sys
from zoneinfo import ZoneInfo

import db
from enviar_zapi import enviar_texto

FUSO_MANAUS = ZoneInfo("America/Manaus")
PASTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

# Minutos de atraso que já são falha, por cron. Os de minuto em minuto
# têm folga de 15: o `flock` pode segurar uma execução longa, e alarme que
# toca à toa ensina a ignorar.
CRONS = {
    "disparar_grade": ("a grade de postagem", 15),
    "disparar_lembretes": ("os lembretes de retorno", 15),
    "entregar_pendentes": ("a entrega do que ficou de mandar", 15),
    "ciclo_pendencias": ("o ciclo de pendências", 15),
}

HORAS_ENTRE_AVISOS = 24
CHAVE_ULTIMO_AVISO = "crons_alarme_em"


def caminho(nome):
    return os.path.join(PASTA, f".batimento_{nome}")


def minutos_desde(nome, agora):
    """None quando não há batimento -- e não haver já é motivo de alarme."""
    try:
        m = os.path.getmtime(caminho(nome))
    except OSError:
        return None
    quando = datetime.datetime.fromtimestamp(m, FUSO_MANAUS)
    return (agora - quando).total_seconds() / 60


def parados(agora):
    fora = []
    for nome, (descricao, limite) in CRONS.items():
        mins = minutos_desde(nome, agora)
        if mins is None or mins > limite:
            fora.append((nome, descricao, mins))
    return fora


def ja_avisou_hoje(conexao, agora):
    with conexao.cursor() as cur:
        cur.execute("SELECT valor FROM config WHERE chave = %s",
                    (CHAVE_ULTIMO_AVISO,))
        linha = cur.fetchone()
    if not linha or not linha["valor"]:
        return False
    try:
        ultimo = datetime.datetime.fromisoformat(linha["valor"])
    except ValueError:
        return False
    return (agora - ultimo).total_seconds() / 3600 < HORAS_ENTRE_AVISOS


def marcar_aviso(conexao, agora):
    with conexao.cursor() as cur:
        cur.execute(
            "INSERT INTO config (chave, valor) VALUES (%s, %s) "
            "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor",
            (CHAVE_ULTIMO_AVISO, agora.isoformat()))
    conexao.commit()


def montar_aviso(fora):
    linhas = ["Tem cron parado no servidor da Nay:"]
    for _, descricao, mins in fora:
        quando = "nunca rodou" if mins is None else f"parado há {int(mins)} min"
        linhas.append(f"• {descricao} — {quando}")
    linhas.append("")
    linhas.append("Enquanto isso nada é postado nem entregue no horário.")
    return "\n".join(linhas)


def verificar(conexao, enviar=False, agora=None, destino=None):
    agora = agora or datetime.datetime.now(FUSO_MANAUS)
    fora = parados(agora)
    if not fora:
        return None                       # tudo em dia: silêncio

    aviso = montar_aviso(fora)
    if not enviar:
        return aviso
    if ja_avisou_hoje(conexao, agora):
        return None

    destino = destino or os.environ.get("TEL_WHATSAPP")
    if not destino:
        raise RuntimeError("TEL_WHATSAPP não configurada no ambiente.")

    enviar_texto(destino, aviso)
    marcar_aviso(conexao, agora)
    return aviso


def main():
    enviar = "--enviar" in sys.argv
    conexao = db.conectar()
    try:
        aviso = verificar(conexao, enviar=enviar)
    finally:
        conexao.close()
    if aviso:
        print(aviso)
    return 0


if __name__ == "__main__":
    sys.exit(main())
