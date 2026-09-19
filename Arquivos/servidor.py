"""
Serviço HTTP do publicador de grupos -- processo sempre ligado que o
n8n chama via POST /comando (decisão B: n8n dispara por HTTP, a lógica
de negócio inteira fica aqui, não duplicada em código dentro do n8n).

Roda direto no servidor, fora do Docker. O n8n roda em container
(n8n-viux-n8n-1, rede n8n-viux_default) e alcança este processo pelo
gateway do host -- por isso escuta em 0.0.0.0, não só localhost.

Autenticação: header "Authorization: Bearer <PUBLICADOR_TOKEN>" -- só
quem tem o token (o n8n) consegue disparar comando. Token errado,
ausente, ou mal formatado responde 401 sem processar nada.
PUBLICADOR_TOKEN precisa estar configurada para o servidor sequer
subir -- mesmo padrão de erro claro de db.py e enviar_zapi.py.

Erro ao processar: 500 com mensagem genérica pro cliente; o traceback
completo vai só pro log do servidor (app.logger.exception), nunca pra
resposta HTTP -- mesma disciplina de enviar_zapi.py de não deixar
detalhe interno (nem credencial) vazar pra fora do processo.

Decisão de arquitetura (mudou o peso pro publicador, tirou do n8n): o
endpoint manda a resposta direto pro WhatsApp do Tel via Z-API, além
de devolver no HTTP. O HTTP continua respondendo sempre -- é a rede de
segurança pra debug/teste -- mas quem manda a mensagem de verdade
agora é o próprio publicador, não um passo a mais no n8n. Se o envio
pro WhatsApp falhar, isso não derruba a resposta HTTP: só loga e
segue.

Ainda sem systemd -- rodar manualmente para testar:
    export $(cat .env | xargs) && .venv/bin/python servidor.py
"""
import hmac
import os

from flask import Flask, jsonify, request

import db
from enviar_zapi import enviar_texto
from publicador import processar_comando

PORTA = 8080


def _variavel_obrigatoria(nome):
    valor = os.environ.get(nome)
    if not valor:
        raise RuntimeError(
            f"{nome} não configurada no ambiente. Copie .env.example "
            "para .env, preencha o valor, e carregue no ambiente antes "
            "de rodar."
        )
    return valor


PUBLICADOR_TOKEN = _variavel_obrigatoria("PUBLICADOR_TOKEN")
TEL_WHATSAPP = _variavel_obrigatoria("TEL_WHATSAPP")

app = Flask(__name__)


def _autenticado(req):
    recebido = req.headers.get("Authorization", "")
    prefixo = "Bearer "
    if not recebido.startswith(prefixo):
        return False
    return hmac.compare_digest(recebido[len(prefixo):], PUBLICADOR_TOKEN)


def _avisar_tel(mensagem):
    """Manda um texto pro WhatsApp do Tel sem deixar a Z-API derrubar a
    resposta HTTP. O HTTP é a rede de segurança pra debug/teste; o envio
    é o efeito colateral desejado, não a garantia do endpoint."""
    try:
        enviar_texto(TEL_WHATSAPP, mensagem)
    except Exception:
        app.logger.exception("falha ao enviar mensagem pro WhatsApp do Tel")


@app.route("/comando", methods=["POST"])
def comando():
    if not _autenticado(request):
        return jsonify(erro="não autorizado"), 401

    corpo = request.get_json(silent=True) or {}
    texto = corpo.get("texto")
    if not texto:
        return jsonify(erro="campo 'texto' é obrigatório"), 400

    conn = None
    try:
        conn = db.conectar()
        resposta = processar_comando(texto, conexao=conn)
    except Exception:
        app.logger.exception("erro ao processar comando: %r", texto)
        # Este return acontecia ANTES do envio pro WhatsApp lá embaixo,
        # então qualquer falha aqui (banco fora do ar, DATABASE_URL
        # errada) virava silêncio absoluto: o Tel mandava "posta o 2943",
        # nada acontecia, e ele reenviava. Reenviar é exatamente o
        # gatilho de duplicata, porque postar_agora não tem proteção
        # contra repetição -- e isso já aconteceu de verdade em 25/08.
        #
        # "não postei nada" é afirmação verificada, não suposição: os
        # dois caminhos que enviam (_postar_codigo e _postar_easy)
        # capturam a própria falha de envio e devolvem texto de erro em
        # vez de deixar a exceção subir. Uma exceção que chega até aqui
        # veio de antes do envio (db.conectar, parser, carregar_grupos_db)
        # ou de um comando que só mexe em vaga. Quem mudar isso precisa
        # rever esta frase.
        _avisar_tel(
            f'Não consegui processar "{texto}". Deu erro interno e não '
            "postei nada. Pode tentar de novo."
        )
        # Mensagem genérica no HTTP de propósito: o traceback fica só no
        # log, nunca na resposta.
        return jsonify(erro="Erro ao processar o comando. Tente de novo em instantes."), 500
    finally:
        if conn is not None:
            conn.close()

    _avisar_tel(resposta)
    return jsonify(resposta=resposta)


if __name__ == "__main__":
    # debug=False deliberado -- o debugger interativo do Flask expõe
    # traceback e permite execução de código pela própria resposta HTTP
    # se ficar ligado. Ainda é o servidor de desenvolvimento do Flask,
    # não um WSGI de produção (gunicorn etc.) -- ok por ora, considerar
    # ao configurar o systemd depois.
    #
    # threaded=True: enviar_imovel (enviar_zapi.py) pausa 1s+2s+6s por
    # foto -- um postar_agora com várias fotos pode levar 20-30s+. Sem
    # threaded, o servidor de desenvolvimento atende uma requisição por
    # vez, e um VAGAS chegando nesse meio tempo ficaria travado
    # esperando em vez de responder na hora.
    app.run(host="0.0.0.0", port=PORTA, debug=False, threaded=True)
