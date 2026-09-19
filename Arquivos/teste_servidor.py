"""
Testa a camada HTTP de servidor.py com o cliente de teste do Flask --
nenhum socket real aberto, banco e processar_comando simulados. O
teste real (servidor de pé, n8n batendo nele) roda no servidor, à
parte.

Uso:
    .venv/bin/python teste_servidor.py
"""
import os

os.environ["PUBLICADOR_TOKEN"] = "token-de-teste-fake"  # antes do import: servidor.py lê na subida
os.environ["TEL_WHATSAPP"] = "5599999999999"  # numero falso, so pra passar na subida

import servidor  # noqa: E402


class FakeConn:
    def __init__(self):
        self.fechada = False

    def close(self):
        self.fechada = True


def teste_sem_header_autorizacao():
    print("--- sem header Authorization -> 401, sem processar ---")
    cliente = servidor.app.test_client()
    resp = cliente.post("/comando", json={"texto": "VAGAS"})
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 401
    assert resp.get_json() == {"erro": "não autorizado"}
    print("OK\n")


def teste_token_errado():
    print("--- token errado -> 401 ---")
    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={"texto": "VAGAS"},
        headers={"Authorization": "Bearer token-invadindo"},
    )
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 401
    print("OK\n")


def teste_texto_ausente():
    print("--- token certo, sem campo texto -> 400 ---")
    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={},
        headers={"Authorization": "Bearer token-de-teste-fake"},
    )
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 400
    print("OK\n")


def teste_comando_ok():
    print("--- token certo, comando processado com sucesso -> 200, e envia pro WhatsApp do Tel ---")
    fake_conn = FakeConn()
    chamadas_processar = []
    chamadas_envio = []

    def fake_processar(texto, conexao):
        chamadas_processar.append((texto, conexao))
        return "Grade atual:\n- todo dia às 14h: 5644"

    servidor.db.conectar = lambda: fake_conn
    servidor.processar_comando = fake_processar
    servidor.enviar_texto = lambda destino, texto: chamadas_envio.append((destino, texto))

    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={"texto": "VAGAS"},
        headers={"Authorization": "Bearer token-de-teste-fake"},
    )
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 200
    assert resp.get_json() == {"resposta": "Grade atual:\n- todo dia às 14h: 5644"}
    assert chamadas_processar == [("VAGAS", fake_conn)]
    assert fake_conn.fechada, "a conexão deveria ter sido fechada depois do uso"
    assert chamadas_envio == [(servidor.TEL_WHATSAPP, "Grade atual:\n- todo dia às 14h: 5644")]
    print("OK\n")


def teste_envio_whatsapp_falha_nao_quebra_http():
    print("--- envio pro WhatsApp falha -> HTTP continua 200 normalmente ---")
    fake_conn = FakeConn()

    servidor.db.conectar = lambda: fake_conn
    servidor.processar_comando = lambda texto, conexao: "resposta ok"

    def enviar_texto_com_falha(destino, texto):
        raise RuntimeError("Z-API respondeu 403 -- simulado de propósito")

    servidor.enviar_texto = enviar_texto_com_falha

    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={"texto": "VAGAS"},
        headers={"Authorization": "Bearer token-de-teste-fake"},
    )
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 200, "falha no envio pro WhatsApp não pode derrubar a resposta HTTP"
    assert resp.get_json() == {"resposta": "resposta ok"}
    print("OK\n")


def teste_erro_avisa_o_tel_no_whatsapp():
    print("--- processar_comando estoura -> 500 E avisa o Tel pelo WhatsApp ---")
    # Antes deste conserto, o return do 500 acontecia ANTES da linha que
    # envia pro WhatsApp: banco fora do ar virava silêncio absoluto. O Tel
    # mandava o comando, não acontecia nada, e reenviava -- que é o
    # gatilho de duplicata, porque postar_agora não tem idempotência.
    fake_conn = FakeConn()
    chamadas_envio = []

    servidor.db.conectar = lambda: fake_conn
    servidor.processar_comando = lambda texto, conexao: (_ for _ in ()).throw(
        RuntimeError("banco fora do ar")
    )
    servidor.enviar_texto = lambda destino, texto: chamadas_envio.append((destino, texto))

    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={"texto": "posta o 2943"},
        headers={"Authorization": "Bearer token-de-teste-fake"},
    )
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 500
    assert len(chamadas_envio) == 1, "o Tel PRECISA ser avisado quando o comando morre"
    destino, aviso = chamadas_envio[0]
    print("aviso:", aviso)
    assert destino == servidor.TEL_WHATSAPP
    assert "posta o 2943" in aviso, "tem que citar o comando que falhou"
    assert "não postei nada" in aviso, "o Tel precisa saber que pode repetir sem duplicar"
    assert "banco fora do ar" not in aviso, "detalhe interno não sai do processo"
    assert fake_conn.fechada, "a conexão precisa ser fechada mesmo no caminho de erro"
    print("OK\n")


def teste_erro_avisa_mesmo_com_zapi_fora():
    print("--- comando estoura E a Z-API também -> ainda devolve 500, sem crashar ---")
    fake_conn = FakeConn()

    servidor.db.conectar = lambda: fake_conn
    servidor.processar_comando = lambda texto, conexao: (_ for _ in ()).throw(RuntimeError("boom"))

    def enviar_que_tambem_falha(destino, texto):
        raise RuntimeError("Z-API respondeu 403")

    servidor.enviar_texto = enviar_que_tambem_falha

    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={"texto": "VAGAS"},
        headers={"Authorization": "Bearer token-de-teste-fake"},
    )
    print(resp.status_code, resp.get_json())
    assert resp.status_code == 500, "duas falhas seguidas não podem virar exceção não tratada"
    assert resp.get_json() == {"erro": "Erro ao processar o comando. Tente de novo em instantes."}
    print("OK\n")


def teste_erro_nao_vaza_detalhe():
    print("--- processar_comando estoura -> 500 genérico, sem traceback nem credencial ---")
    fake_conn = FakeConn()

    def fake_processar_com_erro(texto, conexao):
        raise RuntimeError("DATABASE_URL=postgresql://nay:SENHA_SECRETA@127.0.0.1:5432/naydb explodiu aqui")

    servidor.db.conectar = lambda: fake_conn
    servidor.processar_comando = fake_processar_com_erro

    cliente = servidor.app.test_client()
    resp = cliente.post(
        "/comando", json={"texto": "posta o 5644"},
        headers={"Authorization": "Bearer token-de-teste-fake"},
    )
    corpo = resp.get_json()
    print(resp.status_code, corpo)
    assert resp.status_code == 500
    assert corpo == {"erro": "Erro ao processar o comando. Tente de novo em instantes."}
    assert "SENHA_SECRETA" not in str(corpo)
    assert "DATABASE_URL" not in str(corpo)
    assert "Traceback" not in str(corpo)
    assert fake_conn.fechada, "a conexão deveria ter sido fechada mesmo com erro"
    print("OK\n")


if __name__ == "__main__":
    teste_sem_header_autorizacao()
    teste_token_errado()
    teste_texto_ausente()
    teste_comando_ok()
    teste_envio_whatsapp_falha_nao_quebra_http()
    teste_erro_avisa_o_tel_no_whatsapp()
    teste_erro_avisa_mesmo_com_zapi_fora()
    teste_erro_nao_vaza_detalhe()
    print("TODOS OS TESTES DO SERVIDOR HTTP PASSARAM")
