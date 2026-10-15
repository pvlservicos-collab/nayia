"""As partes puras: a leitura do que a OLX responde. Roda em qualquer máquina:  python -m unittest discover -s tests

Os JSON são os exemplos da documentação da OLX (developers.olx.com.br, 13/10/2026) e a resposta real que a conta
de proprietários deu à sonda nesse dia (-6).
"""
import unittest

from olx import api, nay


class Importacao(unittest.TestCase):
    def test_aceita(self):
        r = api.ler_importacao({"token": "06fb", "statusCode": 0, "statusMessage": "The ads were imported and will be processed", "errors": []})
        self.assertTrue(r.aceita)
        self.assertEqual(r.token, "06fb")
        self.assertEqual(r.permissao, "ok")

    def test_sem_permissao_a_resposta_de_13_10(self):
        r = api.ler_importacao({"token": None, "statusCode": -6, "statusMessage": "Without permission", "errors": []})
        self.assertFalse(r.aceita)
        self.assertEqual(r.permissao, "sem_permissao")
        self.assertIn("plano profissional", r.mensagem)

    def test_um_anuncio_falhou_e_cancelou_tudo(self):
        r = api.ler_importacao({"token": None, "statusCode": -4, "statusMessage": "An ad had problems on import",
                                "errors": [{"id": "IE3050V", "status": "error", "messages": [{"category": "NO_REGION"}]}]})
        self.assertFalse(r.aceita)
        self.assertEqual(r.erros, {"IE3050V": "NO_REGION"})
        self.assertIsNone(r.permissao)      # erro do anúncio, não da conta

    def test_sem_vaga(self):
        r = api.ler_importacao({"token": None, "statusCode": -7, "statusMessage": "Trying to import 10 ad(s), but user just have slot for 2 more.", "errors": []})
        self.assertFalse(r.aceita)
        self.assertEqual(r.permissao, "sem_vaga")

    def test_entrou_so_uma_parte(self):
        r = api.ler_importacao({"token": "t", "statusCode": -8, "errors": [], "statusMessage":
                                'Trying to import 3 ad(s), only 1 were imported and will be processed. The following ads were ignored due to limit exceeded: IE10V, IE11L'})
        self.assertTrue(r.aceita)
        self.assertEqual(r.ignorados, {"IE10V", "IE11L"})

    def test_resposta_sem_codigo_nao_decide_nada(self):
        with self.assertRaises(api.ErroDaOlx):
            api.ler_importacao({"reason": "ACCESS_DENIED"})


class Status(unittest.TestCase):
    def test_ainda_na_fila(self):
        s = api.ler_status({"autoupload_status": "pending", "ads": {"IE1V": {"status": "queued", "operation": "insert", "message": []}}})
        self.assertIsNone(s["IE1V"]["estado"])

    def test_publicado(self):
        s = api.ler_status({"autoupload_status": "done", "ads": {"IE1V": {"status": "accepted", "operation": "insert", "message": [],
                                                                         "url": "http://www.olx.com.br/vi/8000005.htm", "list_id": "8000005"}}})
        self.assertEqual(s["IE1V"], {"estado": "publicado", "list_id": "8000005", "url": "http://www.olx.com.br/vi/8000005.htm", "mensagem": None})

    def test_edicao_aceita_vem_como_accept(self):
        s = api.ler_status({"ads": {"IE1V": {"status": "accept", "operation": "edit", "list_id": "8000000", "message": []}}})
        self.assertEqual(s["IE1V"]["estado"], "publicado")

    def test_recusado_pela_moderacao(self):
        s = api.ler_status({"ads": {"IE1V": {"status": "refused", "operation": "insert", "message": [{"error": "REFUSED_SUSPECT_PRICE"}]}}})
        self.assertEqual(s["IE1V"]["estado"], "recusado")
        self.assertEqual(s["IE1V"]["mensagem"], "REFUSED_SUSPECT_PRICE")

    def test_removido(self):
        s = api.ler_status({"ads": {"IE1V": {"status": "accepted", "operation": "delete", "message": []}}})
        self.assertEqual(s["IE1V"]["estado"], "removido")

    def test_remocao_que_falhou_continua_no_ar(self):
        s = api.ler_status({"ads": {"IE1V": {"status": "error", "operation": "delete", "message": [{"error": "REFUSED_GENERIC"}]}}})
        self.assertEqual(s["IE1V"]["estado"], "publicado")
        self.assertIn("não removeu", s["IE1V"]["mensagem"])

    def test_foto_com_erro_aparece_no_motivo(self):
        s = api.ler_status({"ads": {"IE1V": {"status": "accepted", "operation": "insert", "message": [], "list_id": "1234",
                                             "image_errors": [{"image_url": "https://x/1.jpg", "status": "ERROR_DOWNLOADING_IMAGE"}]}}})
        self.assertEqual(s["IE1V"]["estado"], "publicado")
        self.assertEqual(s["IE1V"]["mensagem"], "foto: ERROR_DOWNLOADING_IMAGE")


class Nay(unittest.TestCase):
    def test_a_nay_da_olx_ainda_nao_responde(self):
        self.assertIsNone(nay.decidir({"mensagens": [{"de": "comprador", "texto": "Ainda está disponível?"}]}))


if __name__ == "__main__":
    unittest.main()


class AvisoNoGrupo(unittest.TestCase):
    """15/10: quem escreve na OLX aparece no grupo da equipe (olx/grupo.py)."""

    def setUp(self):
        from olx import grupo
        self.g = grupo

    def test_o_aviso_da_mensagem_do_felipe(self):
        conversa = {"chat": 9, "conta": "proprietarios", "nome": "FELIPE LADISLAU CARVALHO", "telefone": "92991540843",
                    "list_id": "1544287948", "codigo": 3050}
        t = self.g.montar_aviso(conversa, [{"texto": "Poder tia me passar mais informações", "hora": "21:39"}])
        self.assertIn("conta Proprietários", t)
        self.assertIn("*FELIPE LADISLAU CARVALHO* · (92) 99154-0843", t)
        self.assertIn("Imóvel 3050, anúncio 1544287948", t)
        self.assertIn("21:39 — Poder tia me passar mais informações", t)

    def test_duas_mensagens_seguidas_vao_num_aviso_so(self):
        pend = [{"id": 11, "chat": 7, "texto": "Olá boa tarde"}, {"id": 12, "chat": 7, "texto": "Gostaria de marcar uma visita"},
                {"id": 13, "chat": 9, "texto": "oi"}]
        grupos = self.g.agrupar(pend)
        self.assertEqual([c["chat"] for c, _ in grupos], [7, 9])
        self.assertEqual(len(grupos[0][1]), 2)

    def test_espera_a_pessoa_terminar_de_escrever(self):
        self.assertFalse(self.g.pronto_para_mandar([{"idade_s": 30}, {"idade_s": 5}], 20))
        self.assertTrue(self.g.pronto_para_mandar([{"idade_s": 30}, {"idade_s": 25}], 20))
        self.assertTrue(self.g.pronto_para_mandar([{"idade_s": 130}, {"idade_s": 2}], 20))   # esperou demais
        self.assertFalse(self.g.pronto_para_mandar([], 20))

    def test_telefone(self):
        self.assertEqual(self.g.telefone_bonito("5592995180839"), "(92) 99518-0839")
        self.assertEqual(self.g.telefone_bonito(None), "")
