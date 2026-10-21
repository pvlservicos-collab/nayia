"""A visita da Nay do WhatsApp dos clientes da OLX (16/10, 389): o que é puro. python -m unittest discover -s tests"""
import unittest
from datetime import datetime, timedelta, timezone

from olx import visita as v

MANAUS = timezone(timedelta(hours=-4))
AGORA = datetime(2026, 10, 16, 15, 30, tzinfo=MANAUS)


class Quando(unittest.TestCase):
    def test_data_e_hora(self):
        self.assertEqual(v.quando_de("17/10", "11:00", AGORA), datetime(2026, 10, 17, 11, 0, tzinfo=MANAUS))
        self.assertEqual(v.quando_de("17/10", "11h30", AGORA), datetime(2026, 10, 17, 11, 30, tzinfo=MANAUS))
        self.assertEqual(v.quando_de("17/10/2026", "9h", AGORA), datetime(2026, 10, 17, 9, 0, tzinfo=MANAUS))

    def test_janeiro_e_do_ano_que_vem(self):
        self.assertEqual(v.quando_de("05/01", "10:00", AGORA).year, 2027)

    def test_sem_hora_de_visita_nao_vale(self):
        self.assertIsNone(v.quando_de("17/10", "", AGORA))
        self.assertIsNone(v.quando_de("17/10", "3h", AGORA))
        self.assertIsNone(v.quando_de("", "11:00", AGORA))
        self.assertIsNone(v.quando_de("31/02", "11:00", AGORA))


class Confirmacao(unittest.TestCase):
    def test_igual_ao_da_parceria(self):
        t = v.texto_confirmacao(5718, datetime(2026, 10, 17, 11, 0, tzinfo=MANAUS))
        self.assertEqual(t, "🏠 *Só para confirmar a solicitação de visita*\n\nVisita ao imóvel:\n\n"
                            "🔑 Código do imóvel: #5718\n📅 Data: 17/10 (sábado)\n🕐 Horário: 11h00\n\n"
                            "Por favor, confirme se os dados estão corretos para que eu possa entrar em contato com o proprietário.")


    def test_com_o_condominio(self):
        # 21/10 (Pedro): o condomínio e o bairro em cima do código
        t = v.texto_confirmacao(3227, datetime(2026, 10, 22, 11, 0, tzinfo=MANAUS), "Residencial Piazza Dell'Acqua, Ponta Negra")
        self.assertIn("🏢 Imóvel: Residencial Piazza Dell'Acqua, Ponta Negra\n🔑 Código do imóvel: #3227", t)


class Resposta(unittest.TestCase):
    def test_sim_nao_e_o_resto(self):
        for t in ("Sim", "pode sim", "Consigo", "ok, confirmado", "posso ir", "Beleza"):
            self.assertEqual(v.resposta(t), "sim", t)
        for t in ("Não", "nao posso", "não consigo nesse horário", "infelizmente tenho outro compromisso", "só outro dia"):
            self.assertEqual(v.resposta(t), "nao", t)
        for t in ("não sei ainda", "qual o endereço?", "vou ver e te falo"):
            self.assertEqual(v.resposta(t), "outro", t)

    def test_394_sim_com_nao_no_meio(self):
        self.assertEqual(v.resposta("Pode sim, não tem problema"), "sim")
        self.assertEqual(v.resposta("Bom dia ! Pode sim só me avisar antes"), "sim")
        self.assertEqual(v.resposta("Sim, qual o endereço?"), "sim")
        self.assertEqual(v.resposta("Não vai dar, tenho outra visita"), "nao")


class Corretores(unittest.TestCase):
    def test_lista_na_ordem(self):
        cfg = {"visita_corretores": "Raquel:5592988285562, Neila: (92) 99111-2222;Katherine:92 3333-4444, sem telefone:, :92999990000"}
        self.assertEqual(v.corretores(cfg), [("Raquel", "92988285562"), ("Neila", "92991112222"), ("Katherine", "9233334444")])
        self.assertEqual(v.corretores({}), [])


class QuemChamar(unittest.TestCase):
    """392: locação chama o Diego (e depois os corretores); venda, só os corretores."""
    CFG = {"visita_locacao": "Diego:5592982092845", "visita_corretores": "Raquel:92988285562, Diego:92982092845"}

    def test_locacao_diego_primeiro_sem_repetir(self):
        self.assertEqual(v.quem_chamar(self.CFG, True), [("Diego", "92982092845"), ("Raquel", "92988285562")])

    def test_venda_so_corretores(self):
        self.assertEqual(v.quem_chamar({"visita_locacao": "Diego:5592982092845"}, False), [])
        self.assertEqual(v.quem_chamar(self.CFG, False), [("Raquel", "92988285562"), ("Diego", "92982092845")])


if __name__ == "__main__":
    unittest.main()
