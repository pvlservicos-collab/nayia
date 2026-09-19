"""
Fecha o ciclo da pendência: entrega a resposta a quem ficou esperando, e
cobra o Tel do que ele esqueceu.

OS DOIS BURACOS QUE ISTO FECHA (auditoria de 31/08):

  * `pendencias.avisar` guarda UM telefone. O segundo corretor que
    perguntava a mesma coisa ouvia "ainda estou verificando" e não ficava
    ligado a pendência nenhuma -- quando o Tel respondia, só o primeiro
    recebia. Agora `nay_escalar` registra todos em `pendencia_interessado`,
    e `nay_responder_pendencia` enfileira os outros aqui.
  * Nada tinha relógio. Pendência aberta ficava aberta para sempre e
    ninguém cobrava o Tel. O Leonan esperou dois dias por uma resposta que
    estava na descrição do site.

AS MESMAS PAREDES DOS IRMÃOS, e pelas mesmas razões: pausa geral (dentro
da função SQL), janela de 08h-20h (importada do lembrete, uma definição
só), teto de um contato por dia, e reserva atômica antes de enviar --
`postar_agora` já provou neste projeto que sem reserva o mesmo item sai
duas vezes, e mensagem de WhatsApp não tem desfazer.

A COBRANÇA AO TEL NÃO PASSA PELA JANELA nem pelo teto: ele não é corretor,
é o dono, e já recebe alarme de erro a qualquer hora. Mas passa por um
teto próprio de um lembrete a cada N horas, senão vira 24 mensagens por
dia com a mesma lista.

    .venv/bin/python ciclo_pendencias.py            # só mostra
    .venv/bin/python ciclo_pendencias.py --enviar   # manda de verdade
"""
import datetime
import os
import sys

import db
from disparar_lembretes import atendimento_pausado, FUSO_MANAUS, dentro_do_horario
from enviar_zapi import enviar_texto

# Um lembrete de pendência atrasada por vez. O Tel não pode receber a
# mesma lista de hora em hora -- ele para de ler, que é o mesmo que não
# avisar.
HORAS_ENTRE_COBRANCAS = 6
CHAVE_ULTIMA_COBRANCA = "pendencia_ultima_cobranca"


def _um(conexao, sql, params=None):
    with conexao.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def _todos(conexao, sql, params=None):
    with conexao.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


# ---------------------------------------------------------------- entrega
def entregar_respostas(conexao, enviar=False, agora=None):
    """Manda a resposta do Tel a quem perguntou depois do primeiro."""
    # A PAUSA VALE AQUI (02/09): entregar resposta é a Nay falando com
    # corretor. O que vai para o TEL -- a cobrança e o aviso de mensagem
    # órfã -- NÃO para: pausar não pode deixar ele cego.
    if atendimento_pausado(conexao):
        return []
    agora = agora or datetime.datetime.now(FUSO_MANAUS)
    if not dentro_do_horario(agora):
        return []

    resultados = []
    for linha in _todos(conexao,
                        "SELECT telefone, ids, texto FROM nay_respostas_a_entregar()"):
        telefone, ids, texto = linha["telefone"], linha["ids"], linha["texto"]

        if not enviar:
            resultados.append((telefone, ids, "simulado"))
            continue

        # Reserva ANTES de enviar. Zero significa que outra execução pegou.
        if _um(conexao, "SELECT nay_reservar_respostas(%s) AS n", (ids,))["n"] == 0:
            continue

        try:
            enviar_texto(telefone, texto)
        except Exception as erro:
            # Devolve para 'devendo': a próxima execução tenta de novo, em
            # vez de a resposta sumir por uma queda de rede.
            _um(conexao, "SELECT nay_devolver_respostas(%s) AS n", (ids,))
            conexao.commit()
            resultados.append((telefone, ids, f"erro: {erro}"))
            continue

        with conexao.cursor() as cur:
            cur.execute("INSERT INTO contato_corretor (telefone, motivo) "
                        "VALUES (%s,'resposta')", (telefone,))
        conexao.commit()
        resultados.append((telefone, ids, "entregue"))

    return resultados


# ---------------------------------------------------------------- relógio
def _ja_cobrou(conexao, agora):
    linha = _um(conexao, "SELECT valor FROM config WHERE chave = %s",
                (CHAVE_ULTIMA_COBRANCA,))
    if not linha or not linha["valor"]:
        return False
    try:
        ultimo = datetime.datetime.fromisoformat(linha["valor"])
    except ValueError:
        return False
    return (agora - ultimo).total_seconds() / 3600 < HORAS_ENTRE_COBRANCAS


def cobrar_o_tel(conexao, enviar=False, agora=None, destino=None):
    """Lembra o Tel das pendências que ficaram sem resposta."""
    agora = agora or datetime.datetime.now(FUSO_MANAUS)
    if not dentro_do_horario(agora):
        return None

    linha = _um(conexao, "SELECT quantas, texto FROM nay_pendencias_esquecidas()")
    if not linha or not linha["quantas"]:
        return None

    if not enviar:
        return linha["texto"]
    if _ja_cobrou(conexao, agora):
        return None

    destino = destino or os.environ.get("TEL_WHATSAPP")
    if not destino:
        raise RuntimeError("TEL_WHATSAPP não configurada no ambiente.")

    enviar_texto(destino, linha["texto"])
    with conexao.cursor() as cur:
        cur.execute(
            "INSERT INTO config (chave, valor) VALUES (%s, %s) "
            "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor",
            (CHAVE_ULTIMA_COBRANCA, agora.isoformat()))
    conexao.commit()
    return linha["texto"]


# ---------------------------------------------------------------- órfãs
# Uma mensagem fica em 'Recebido' durante os 25 segundos da janela de
# agrupamento e depois vira 'Processando'. Passado disso, ela é uma
# mensagem PERDIDA: a execução do n8n morreu antes de reservá-la.
#
# ACONTECEU EM 01/09: um `docker restart` do deploy matou a execução que
# esperava na janela, e o comando do Tel "publica no nosso grupo anunciar
# easy código 5664" ficou parado em 'Recebido' sem ninguém saber. Ele
# reenviou porque percebeu; se fosse um corretor, teria só ficado sem
# resposta.
#
# O alarme não é sobre o n8n estar de pé -- ele estava. É sobre a
# mensagem ter sido engolida, que é o que importa para quem escreveu.
MINUTOS_ATE_ORFA = 5


def mensagens_orfas(conexao, agora=None):
    """As que passaram da janela e nunca foram reservadas."""
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT id, telefone, coalesce(nome,'') AS nome, "
            "       left(coalesce(texto,''), 90) AS texto, "
            "       round(extract(epoch FROM now() - criada_em)/60) AS minutos "
            "  FROM mensagens "
            " WHERE status = 'Recebido' "
            "   AND criada_em < now() - make_interval(mins => %s) "
            " ORDER BY id",
            (MINUTOS_ATE_ORFA,))
        return cur.fetchall()


def avisar_orfas(conexao, enviar=False, agora=None, destino=None):
    """Conta ao Tel o que foi engolido. Sem teto de horário: mensagem
    perdida é perdida a qualquer hora, e ele decide o que fazer."""
    linhas = mensagens_orfas(conexao, agora)
    if not linhas:
        return None

    partes = ["Estas mensagens chegaram e o fluxo morreu antes de processar:"]
    for l in linhas:
        quem = l["nome"] or l["telefone"]
        partes.append(f"• {quem}: \"{l['texto']}\" (há {int(l['minutos'])} min)")
    partes.append("Elas NÃO foram respondidas. Reenvie ou responda à mão.")
    texto = "\n".join(partes)

    if not enviar:
        return texto

    destino = destino or os.environ.get("TEL_WHATSAPP")
    if not destino:
        raise RuntimeError("TEL_WHATSAPP não configurada no ambiente.")
    enviar_texto(destino, texto)

    # Marca como avisada para não repetir de minuto em minuto. NÃO
    # 'Processando': isso faria parecer que alguém tratou.
    with conexao.cursor() as cur:
        cur.execute("UPDATE mensagens SET status = 'Perdida' WHERE id = ANY(%s)",
                    ([l["id"] for l in linhas],))
    conexao.commit()
    return texto


def main():
    enviar = "--enviar" in sys.argv
    conexao = db.conectar()
    try:
        entregues = entregar_respostas(conexao, enviar=enviar)
        cobranca = cobrar_o_tel(conexao, enviar=enviar)
        orfas = avisar_orfas(conexao, enviar=enviar)
    finally:
        conexao.close()

    # Silêncio quando não há nada: roda 1.440 vezes por dia.
    for telefone, ids, estado in entregues:
        print(f"[{estado}] {telefone} respostas={ids}")
    if cobranca:
        print(cobranca)
    if orfas:
        print(orfas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
