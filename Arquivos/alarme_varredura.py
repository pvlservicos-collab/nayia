"""
Avisa o Tel quando a varredura para de rodar.

POR QUE ISTO EXISTE: o cron já grita no log quando falha, mas ninguém lê
log. Foi assim que a varredura ficou de 28/08 a 31/08 sem rodar sem
ninguém notar -- e o sintoma que chegou ao Tel foi outro: a Nay dizendo
"não encontrei o imóvel pelo código 5717" de um imóvel que estava no ar.
Três dias entre a causa e o sintoma, e nada ligando os dois.

O QUE ELE OLHA: `config.varredura_rodou_em`, carimbado pela varredura ao
terminar sem abortar. NÃO `max(sincronizado_em)`, que foi o que eu pus
primeiro e deu falso alarme às 03h20 de 01/09: aquele carimbo só avança
nas linhas TOCADAS, então catálogo estável parece varredura parada. Foram
quatro varreduras seguidas, todas certas, todas silenciosas porque nada
mudou -- e o alarme acusando 3 horas de atraso. Alarme que toca à toa é
pior que alarme nenhum: ensina a ignorar.

POR QUE UM AVISO POR DIA: roda de hora em hora junto com a varredura. Se
ela ficar quebrada uma semana, o Tel não pode receber 168 mensagens
iguais. O carimbo do último aviso mora em `config`, na mesma tabela da
pausa geral.

FALHA FECHADA, como todo portão deste projeto: se não conseguir ler o
carimbo, avisa. "Não sei se está atualizado" é notícia ruim, não silêncio.

    .venv/bin/python alarme_varredura.py             # só mostra
    .venv/bin/python alarme_varredura.py --enviar    # manda se preciso
"""
import datetime
import os
import sys
from zoneinfo import ZoneInfo

import db
from enviar_zapi import enviar_texto

FUSO_MANAUS = ZoneInfo("America/Manaus")

# A varredura roda de hora em hora. Três horas de atraso é falha de
# verdade, não uma execução que demorou.
HORAS_ATE_ALARME = 3

# Um aviso por dia enquanto o problema durar.
HORAS_ENTRE_AVISOS = 24

CHAVE_ULTIMO_AVISO = "varredura_alarme_em"


def horas_desde_a_varredura(conexao, agora):
    """None quando não dá para saber -- e não saber já é motivo de alarme.

    Lê `config.varredura_rodou_em`, que a varredura carimba ao terminar --
    e NÃO `max(sincronizado_em)`, que era o que estava aqui e deu falso
    alarme às 03h20 de 01/09. Aquele carimbo só avança nas linhas tocadas,
    então quatro varreduras seguidas sem nenhuma mudança no catálogo
    pareciam quatro horas de varredura parada. O alarme que toca à toa é
    pior que alarme nenhum: ensina a ignorar.

    `max(sincronizado_em)` fica como reserva, para o caso de o carimbo
    ainda não existir (primeira vez depois deste conserto).
    """
    with conexao.cursor() as cur:
        cur.execute("SELECT valor FROM config WHERE chave = 'varredura_rodou_em'")
        linha = cur.fetchone()
    if linha and linha["valor"]:
        try:
            return (agora - datetime.datetime.fromisoformat(
                linha["valor"])).total_seconds() / 3600
        except ValueError:
            pass                      # carimbo ilegível: cai para a reserva

    with conexao.cursor() as cur:
        cur.execute("SELECT max(sincronizado_em) AS quando FROM imoveis")
        linha = cur.fetchone()
    if not linha or linha["quando"] is None:
        return None
    return (agora - linha["quando"]).total_seconds() / 3600


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


def montar_aviso(horas):
    if horas is None:
        return ("A varredura do catálogo não está respondendo: não consegui "
                "nem ler quando ela rodou pela última vez. Enquanto isso a "
                "Nay não conhece imóvel novo.")
    return (f"A varredura do catálogo não roda há {int(horas)} horas. "
            f"Imóvel cadastrado nesse período a Nay ainda não conhece — "
            f"ela vai dizer que não encontrou o código.")


def verificar(conexao, enviar=False, agora=None, destino=None):
    agora = agora or datetime.datetime.now(FUSO_MANAUS)
    horas = horas_desde_a_varredura(conexao, agora)

    if horas is not None and horas < HORAS_ATE_ALARME:
        return None                       # tudo em dia: silêncio

    aviso = montar_aviso(horas)
    if not enviar:
        return aviso
    if ja_avisou_hoje(conexao, agora):
        return None

    destino = destino or os.environ.get("TEL_WHATSAPP")
    if not destino:
        # Sem para quem mandar, não dá para avisar -- mas isso é erro de
        # configuração e precisa aparecer, não sumir.
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
