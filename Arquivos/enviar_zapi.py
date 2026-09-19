"""
Doc 28, passo 6: envio de texto e fotos via Z-API.

Reaproveita a estrutura real do nó "Enviar Z-API" do n8n (atendimento a
corretor): mesma URL, mesmo header, mesmo corpo por rota. Diferença
deliberada: lá instancia/token estão hardcoded no nó (dívida técnica já
registrada no histórico, doc 27); aqui vêm de variável de ambiente.

Configuração: copie .env.example para .env e preencha ZAPI_INSTANCIA,
ZAPI_TOKEN e ZAPI_CLIENT_TOKEN. São três valores diferentes na Z-API --
ZAPI_INSTANCIA e ZAPI_TOKEN identificam a instância e vão só no caminho
da URL; ZAPI_CLIENT_TOKEN é o "Token de segurança da conta" (tela de
Segurança do painel Z-API) e vai só no header Client-Token. Confundir
os dois dá 403 "Client-Token not allowed" -- foi exatamente o que
aconteceu na primeira tentativa de envio real, corrigido depois.

As variáveis precisam estar no ambiente do processo -- rode com
`export $(cat .env | xargs)` antes, ou carregue via cron
EnvironmentFile. Não usa python-dotenv porque não foi pedido; se
preferir carregamento automático do .env, é uma adição simples.

Cadência de envio, reproduzindo a do fluxo de corretor -- proteção
deliberada contra banimento do WhatsApp, não acidente: 1s antes do
texto, 2s antes da primeira foto, 6s entre cada foto seguinte.
"""
import os
import time

import requests

BASE_URL = "https://api.z-api.io/instances/{instancia}/token/{token}/{rota}"

PAUSA_ANTES_TEXTO = 1
PAUSA_ANTES_PRIMEIRA_FOTO = 2
PAUSA_ENTRE_FOTOS = 6


def _credenciais():
    instancia = os.environ.get("ZAPI_INSTANCIA")
    token = os.environ.get("ZAPI_TOKEN")
    client_token = os.environ.get("ZAPI_CLIENT_TOKEN")
    if not instancia or not token or not client_token:
        raise RuntimeError(
            "ZAPI_INSTANCIA, ZAPI_TOKEN e/ou ZAPI_CLIENT_TOKEN não "
            "configuradas no ambiente. Copie .env.example para .env, "
            "preencha os valores, e carregue no ambiente antes de rodar."
        )
    return instancia, token, client_token


def _post(rota, payload, timeout=15):
    instancia, token, client_token = _credenciais()
    url = BASE_URL.format(instancia=instancia, token=token, rota=rota)
    resp = requests.post(url, json=payload, headers={"Client-Token": client_token}, timeout=timeout)
    if not resp.ok:
        # Nunca deixar a exceção carregar a URL -- ela tem instancia e
        # token no próprio caminho. status + rota + corpo da resposta já
        # bastam para diagnosticar.
        raise RuntimeError(
            f"Z-API respondeu {resp.status_code} na rota {rota}: {resp.text}"
        )
    return resp.json() if resp.content else {}


def id_da_mensagem(resposta):
    """O messageId que a Z-API devolve ao enviar.

    POR QUE ISSO IMPORTA (01/09): quando o corretor MARCA uma mensagem
    nossa, a Z-API entrega `referenceMessageId` -- o ID daquela mensagem.
    Guardando o ID de cada card que sai, a citação vira o código do
    imóvel por igualdade, sem heurística. Sem guardar, a Nay só podia
    perguntar "de qual imóvel você fala?".

    O nome do campo varia entre rotas e versões da Z-API, então aceita as
    três formas conhecidas em vez de fixar uma.
    """
    if not isinstance(resposta, dict):
        return None
    for chave in ("messageId", "id", "zaapId"):
        valor = resposta.get(chave)
        if valor:
            return str(valor)
    return None


def enviar_texto(destino, texto):
    return _post("send-text", {"phone": destino, "message": texto})


def enviar_foto(destino, url_foto):
    return _post("send-image", {"phone": destino, "image": url_foto})


def enviar_imovel(destino, texto, fotos, pausa=time.sleep):
    """Manda o texto e depois as fotos, na cadência definida.

    `pausa` é injetável para teste -- por padrão é time.sleep de verdade.
    """
    pausa(PAUSA_ANTES_TEXTO)
    resultado_texto = enviar_texto(destino, texto)

    resultados_fotos = []
    for i, url_foto in enumerate(fotos):
        pausa(PAUSA_ANTES_PRIMEIRA_FOTO if i == 0 else PAUSA_ENTRE_FOTOS)
        resultados_fotos.append(enviar_foto(destino, url_foto))

    return {"texto": resultado_texto, "fotos": resultados_fotos}
