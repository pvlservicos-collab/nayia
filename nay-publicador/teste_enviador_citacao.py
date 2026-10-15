"""373: a mensagem de negociação da captação ativa sai como "Responder em particular" à mensagem do corretor no grupo.

    python teste_enviador_citacao.py

Sem banco e sem Z-API: as duas pontas são trocadas por gravadores.
"""
import os
import sys
import unittest

os.environ.setdefault("DATABASE_URL", "x")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import enviador_manual as em  # noqa: E402

CORPO = {"phone": "5592991234567", "message": "Boa tarde! Tenho uma casa que aceita financiamento."}
LINHA = {"id": 1, "rota": "send-text", "corpo": dict(CORPO), "telefone": "5592991234567",
         "chave_esperada": em.chave("5592991234567"), "codigo": None}


class Citacao(unittest.TestCase):
    def rodar(self, citacao, respostas):
        enviados = []
        em.liberar = lambda conn: [dict(LINHA, corpo=dict(CORPO))]
        em.gravar = lambda conn, sql, args: "ok"
        em.citacao_do_grupo = lambda conn, j: citacao
        em.enviar_zapi = lambda rota, corpo: (enviados.append(corpo), respostas.pop(0))[1]
        em.log = lambda *_: None
        em.uma_rodada(None)
        return enviados

    def test_com_citacao_vai_em_particular_citando_o_grupo(self):
        env = self.rodar({"grupo": "120363039682957370-group", "message_id": "2AA1A396"}, [{"messageId": "X"}])
        self.assertEqual(len(env), 1)
        self.assertEqual(env[0]["phone"], "120363039682957370-group")
        self.assertEqual(env[0]["messageId"], "2AA1A396")
        self.assertIs(env[0]["privateAnswer"], True)
        self.assertEqual(env[0]["message"], CORPO["message"])

    def test_recusada_cai_no_pv_normal(self):
        env = self.rodar({"grupo": "1-group", "message_id": "M"}, [{"error": "400 message not found"}, {"messageId": "Y"}])
        self.assertEqual(len(env), 2)
        self.assertEqual(env[1], CORPO)

    def test_sem_citacao_e_o_envio_de_sempre(self):
        env = self.rodar(None, [{"messageId": "Z"}])
        self.assertEqual(env, [CORPO])


if __name__ == "__main__":
    unittest.main()
