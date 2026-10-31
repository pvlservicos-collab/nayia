"""550: a agenda e a saída da Nay velha fora do n8n (agenda_nai.py) e o conferidor separado (conferir.py).

    python teste_agenda_nai.py

Sem banco e sem Z-API: as pontas são trocadas por gravadores.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agenda_nai as ag  # noqa: E402
import conferir  # noqa: E402
import enviador_manual as em  # noqa: E402


def linha(i, **mais):
    j = {"id": i, "rota": "send-text", "telefone": "5592991234567", "chave_esperada": conferir.chave("5592991234567"),
         "corpo": {"phone": "5592991234567", "message": "Oi"}, "codigo": None, "papel": "turno"}
    j.update(mais)
    return j


class Agenda(unittest.TestCase):
    def setUp(self):
        self.chaves = {"entrada": "n8n", "agenda_de": "n8n"}
        self.chamadas, self.enviados, self.gravados = [], [], []
        ag.chave_de = lambda conn, nome: self.chaves[nome]
        ag.turnos_prontos = lambda conn: (self.chamadas.append("turnos"), [11, 12])[1]
        ag.tick = lambda conn: (self.chamadas.append("tick"), 3)[1]
        ag.liberar = lambda conn, turno: (self.chamadas.append(("liberar", turno)), [linha(100 + (turno or 0))])[1]
        ag.enviar_zapi = lambda rota, corpo: (self.enviados.append(corpo), {"messageId": "M"})[1]
        ag.gravar = lambda conn, sql, args: self.gravados.append((sql.split("(")[0], args)) or "ok"
        ag.log = lambda *_: None
        ag.ENTRE_ENVIOS_S = 0

    def test_com_as_chaves_no_n8n_nao_faz_nada(self):
        feitas, _ = ag.uma_rodada(None, -999)
        self.assertEqual((feitas, self.chamadas, self.enviados), (0, [], []))

    def test_entrada_python_libera_cada_turno_fechado(self):
        self.chaves["entrada"] = "python"
        feitas, _ = ag.uma_rodada(None, -999)
        self.assertEqual(self.chamadas, ["turnos", ("liberar", 11), ("liberar", 12)])
        self.assertEqual(feitas, 2)
        self.assertEqual([g[0] for g in self.gravados], ["SELECT nai_confirmar_envio"] * 2)

    def test_agenda_python_roda_o_tick_e_libera_sem_turno(self):
        self.chaves["agenda_de"] = "python"
        _, ultimo = ag.uma_rodada(None, -999)
        self.assertEqual(self.chamadas, ["tick", ("liberar", None)])
        self.chamadas.clear()
        ag.uma_rodada(None, ultimo)          # menos de 60 s depois: não roda de novo
        self.assertEqual(self.chamadas, [])

    def test_o_que_nao_confere_e_bloqueado_e_nao_sai(self):
        self.chaves["entrada"] = "python"
        ag.turnos_prontos = lambda conn: [7]
        ag.liberar = lambda conn, turno: [linha(1, chave_esperada="5592xxxx0000")]
        ag.uma_rodada(None, -999)
        self.assertEqual(self.enviados, [])
        self.assertEqual(self.gravados, [("SELECT nai_registrar_bloqueio", (1, "chave_nao_confere_py"))])


class Conferidor(unittest.TestCase):
    def test_o_enviador_manual_usa_o_mesmo(self):
        self.assertIs(em.motivo_para_nao_enviar, conferir.motivo_para_nao_enviar)
        self.assertIs(em.chave, conferir.chave)

    def test_foto_de_outro_imovel_nao_sai(self):
        j = linha(1, rota="send-image", codigo=5551,
                  corpo={"phone": "5592991234567", "image": "https://imobeasy.online/fotos/9004/1.jpg"})
        self.assertEqual(conferir.motivo_para_nao_enviar(j), "foto_sem_codigo")


if __name__ == "__main__":
    unittest.main()
