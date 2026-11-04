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
                            "Tá certinho? Se estiver, já falo com o proprietário.")


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
    """392 + 31/10: locação chama SÓ o Diego (nunca os corretores); venda, só os corretores."""
    CFG = {"visita_locacao": "Diego:5592982092845", "visita_corretores": "Raquel:92988285562, Diego:92982092845"}

    def test_locacao_so_o_diego(self):
        self.assertEqual(v.quem_chamar(self.CFG, True), [("Diego", "92982092845")])
        self.assertEqual(v.quem_chamar({"visita_corretores": "Raquel:92988285562"}, True), [])

    def test_venda_so_corretores(self):
        self.assertEqual(v.quem_chamar({"visita_locacao": "Diego:5592982092845"}, False), [])
        self.assertEqual(v.quem_chamar(self.CFG, False), [("Raquel", "92988285562"), ("Diego", "92982092845")])


class ELocacao(unittest.TestCase):
    """O imóvel decide quando é só de um; com os dois preços, o que a pessoa procura; sem saber, locação (o Diego)."""

    def _e(self, loc, ven, lead):
        from unittest import mock
        with mock.patch.object(v.banco, "linhas", return_value=[{"de_locacao": loc, "de_venda": ven}]):
            return v._e_locacao(None, {"codigo": 1}, lead)

    def test_imovel_de_um_so(self):
        self.assertTrue(self._e(True, False, {"negocio": "venda"}))
        self.assertFalse(self._e(False, True, {"negocio": "locacao"}))

    def test_dois_precos_pelo_que_ela_procura(self):
        self.assertTrue(self._e(True, True, {"filtros": {"finalidade": "locacao"}}))
        self.assertFalse(self._e(True, True, {"negocio": "venda"}))
        self.assertFalse(self._e(True, True, {"filtros": {"finalidade": "comprar"}}))

    def test_dois_precos_sem_saber_vai_ao_diego(self):
        self.assertTrue(self._e(True, True, {}))


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


class DiegoSemPrazo(unittest.TestCase):
    """31/10 ("tira isso de 30 min"): passou o prazo sem resposta, o Diego continua esperando; a corretora da venda, não."""

    def _venceu(self, telefone):
        from unittest import mock
        consulta = {"id": 7, "visita": 3, "papel": "corretor", "nome": "x", "telefone": telefone, "ate": None, "venceu": True}
        w = mock.Mock(MANAUS=MANAUS)
        with mock.patch.object(v, "_retomar", return_value=0), mock.patch.object(v, "_feedback_pedido", return_value=0), \
                mock.patch.object(v, "perguntas_ao_dono", return_value=0), mock.patch.object(v, "_w", return_value=w), \
                mock.patch.object(v.banco, "linhas", return_value=[consulta]), mock.patch.object(v.banco, "um") as um, \
                mock.patch.object(v, "_visita", return_value={"id": 3, "lead": 1, "codigo": 2462, "estado": "buscando_corretor",
                                                               "quando": AGORA}), \
                mock.patch.object(v, "_lead", return_value={}), mock.patch.object(v, "_proximo_corretor") as prox:
            v.atender(None, {"visita_locacao": "Diego:5592982092845", "visita_corretores": "Neila:5592984118226"})
        return um.call_count, prox.call_count

    def test_diego_continua_esperando(self):
        self.assertEqual(self._venceu("92982092845"), (0, 0))

    def test_corretora_da_venda_passa_a_vez(self):
        self.assertEqual(self._venceu("92984118226"), (1, 1))


class Desmarcou(unittest.TestCase):
    """31/10 (Pedro, o Eduardo ...2424): o cliente desmarcar cancela a visita e avisa corretor e dono."""

    def test_desmarcar_sem_dia_novo(self):
        eduardo = ["boatarde tudo bem? tive um imprevisto, amanha meu sogro vai precisar operar e vamos ter que acompanhar "
                   "ele na cirurgia, podemos marca pra proxima semana? a noite ou fds novamente?"]
        self.assertTrue(v.desmarcou(eduardo))
        self.assertTrue(v.QUER_REMARCAR.search(eduardo[0]))
        self.assertTrue(v.desmarcou(["Vou ter que desmarcar a visita"]))
        self.assertTrue(v.desmarcou(["não vou mais poder ir, desculpa"]))

    def test_remarcar_com_dia_fica_com_o_modelo(self):
        self.assertFalse(v.desmarcou(["tive um imprevisto, pode ser quinta às 18h?"]))
        self.assertFalse(v.desmarcou(["não vou conseguir hoje, dá pra sábado de manhã?"]))

    def test_nao_e_desmarcar(self):
        self.assertFalse(v.desmarcou(["confirmado, estarei lá"]))
        self.assertFalse(v.desmarcou(["qual o endereço?"]))
