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


class OndeFalarComODono(unittest.TestCase):
    """492 (Pedro, 24/10): pelo número em que o dono já conversa (Parceria); senão pelo 8595; nunca pelo oficial."""

    def _mandar(self, linha_no_banco, parceria_aceita=True):
        from unittest import mock
        sqls, pelo_8595 = [], []

        def um(conn, sql, args=()):
            sqls.append(sql)
            if "nay_leads_linha_do_dono" in sql:
                return linha_no_banco
            if "nay_leads_mandar_pela_parceria" in sql:
                return 77 if parceria_aceita else None
            return None
        with mock.patch.object(v.banco, "um", um), mock.patch.object(v, "_mandar_para", lambda *a: pelo_8595.append(a)):
            saiu = v.mandar_ao_dono(None, 5, "92991112222", "Ana", "Olá, Ana!", "visita #1")
        return saiu, sqls, pelo_8595

    def test_ja_conversa_na_parceria_vai_por_la(self):
        saiu, sqls, pelo_8595 = self._mandar("parceria")
        self.assertEqual(saiu, "parceria")
        self.assertFalse(pelo_8595)

    def test_sem_conversa_vai_pelo_8595(self):
        saiu, sqls, pelo_8595 = self._mandar("captacao")
        self.assertEqual(saiu, "captacao")
        self.assertEqual(len(pelo_8595), 1)
        self.assertFalse(any("mandar_pela_parceria" in s for s in sqls))

    def test_a_parceria_recusou_cai_no_8595(self):
        saiu, _, pelo_8595 = self._mandar("parceria", parceria_aceita=False)
        self.assertEqual(saiu, "captacao")
        self.assertEqual(len(pelo_8595), 1)


class CardAoCorretor(unittest.TestCase):
    """27/10 (Pedro, a Neila no #3841): com a "Visita confirmada" o corretor recebe o card do imóvel, só o card."""

    def _mandar(self, card, falha=False):
        from unittest import mock
        enviados = []

        def mandar(conn, lead, fone, texto):
            if falha:
                raise RuntimeError("Z-API fora")
            enviados.append((lead, fone, texto))
        with mock.patch.object(v.banco, "um", lambda conn, sql, args=(): card if "nai_card_do_imovel" in sql else None), \
                mock.patch.object(v, "_mandar_para", mandar):
            saiu = v.mandar_card_ao_corretor(None, {"id": 13, "lead": 5, "codigo": 3841, "corretor_telefone": "92984118226"})
        return saiu, enviados

    def test_o_card_vai_ao_telefone_do_corretor(self):
        saiu, enviados = self._mandar("🏢 Mont Clair\nCódigo: 3841")
        self.assertTrue(saiu)
        self.assertEqual(enviados, [(5, "92984118226", "🏢 Mont Clair\nCódigo: 3841")])

    def test_sem_card_nao_manda_nada(self):
        saiu, enviados = self._mandar(None)
        self.assertFalse(saiu)
        self.assertFalse(enviados)

    def test_o_card_que_falha_nao_derruba_a_confirmacao(self):
        saiu, _ = self._mandar("card", falha=True)
        self.assertFalse(saiu)


if __name__ == "__main__":
    unittest.main()
