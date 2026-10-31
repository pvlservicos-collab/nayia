"""550: o vigia do número e o relatório do dia fora do n8n (captacao/rotinas.py), sem banco e sem Z-API.

    python -m unittest discover -s tests        (na pasta nay-captacao)
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from captacao import rotinas  # noqa: E402


class Banco:
    """Responde cada SQL pelo começo do texto e guarda o que foi pedido."""

    def __init__(self, quem="n8n", motivo=None, relatorio=()):
        self.quem, self.motivo, self.relatorio, self.pedidos = quem, motivo, list(relatorio), []

    def linhas(self, conn, sql, params=None):
        self.pedidos.append((sql.split("(")[0].strip(), params))
        if "rotinas_de" in sql:
            return [{"quem": self.quem}]
        if "captacao_vigiar" in sql:
            return [{"motivo": self.motivo}]
        if "captacao_relatorio_da_vez" in sql:
            return self.relatorio
        return [{"id": 1}]


class Rotinas(unittest.TestCase):
    def setUp(self):
        self.enviados = []
        self.envio_ok = True
        self._antes = (rotinas.envio.pela_captacao, rotinas.banco.linhas)
        rotinas.envio.pela_captacao = lambda phone, msg, delay=None: (self.enviados.append((phone, msg)), self.envio_ok)[1]

    def tearDown(self):
        rotinas.envio.pela_captacao, rotinas.banco.linhas = self._antes

    def rodar(self, b, ultimo=None):
        rotinas.banco.linhas = b.linhas
        rotinas.uma_volta(None, {} if ultimo is None else ultimo)
        return [p[0] for p in b.pedidos]

    def test_com_a_chave_no_n8n_nada_roda(self):
        self.assertEqual(self.rodar(Banco("n8n", "parou", [{"phone": "5592", "message": "R", "delay": 2}])),
                         ["SELECT coalesce"])
        self.assertEqual(self.enviados, [])

    def test_vigia_que_pausou_vai_as_notificacoes_do_crm(self):
        b = Banco("python", motivo="só 1 dos últimos 10 disparos teve resposta")
        feitos = self.rodar(b)
        self.assertIn("SELECT nay_aviso_equipe", feitos)
        aviso = [p for p in b.pedidos if p[0] == "SELECT nay_aviso_equipe"][0][1]
        self.assertIn("pausou sozinha", aviso[0])
        self.assertIn("só 1 dos últimos 10", aviso[1])

    def test_vigia_sem_motivo_nao_avisa(self):
        self.assertNotIn("SELECT nay_aviso_equipe", self.rodar(Banco("python", motivo=None)))

    def test_relatorio_sai_pela_captacao(self):
        self.rodar(Banco("python", relatorio=[{"phone": "559299", "message": "Relatório", "delay": 2}]))
        self.assertEqual(self.enviados, [("559299", "Relatório")])

    def test_relatorio_que_nao_saiu_vai_as_notificacoes(self):
        self.envio_ok = False
        b = Banco("python", relatorio=[{"phone": "559299", "message": "Relatório", "delay": 2}])
        self.rodar(b)
        self.assertIn(("SELECT nay_aviso_equipe", ("Relatório",)), b.pedidos)

    def test_cada_rotina_no_seu_ritmo(self):
        ultimo = {}
        self.rodar(Banco("python"), ultimo)
        b = Banco("python")
        self.rodar(b, ultimo)        # logo depois: nem vigia nem relatório
        self.assertEqual([p[0] for p in b.pedidos], ["SELECT coalesce"])


if __name__ == "__main__":
    unittest.main()
