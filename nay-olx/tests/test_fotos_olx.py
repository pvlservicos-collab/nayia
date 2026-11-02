"""02/11 (o 9115): a foto do anúncio da OLX vai para a nossa pasta; o link da OLX só fica se não baixar."""
import os
import tempfile
import unittest
from unittest import mock

from olx import fotos_olx

JPG = b"\xff\xd8\xff" + b"x" * 5000


class TestFotosOlx(unittest.TestCase):
    def test_foto_de_fora_da_olx_fica_como_esta(self):
        url = "https://imobeasy.online/fotos-captacao/whatsapp-busca/1/a.jpg"
        self.assertEqual(fotos_olx.guardar(9115, 1, url), url)

    def test_baixa_e_grava_na_pasta_da_olx(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(fotos_olx, "PASTA", d), \
                mock.patch.object(fotos_olx, "baixar", return_value=(JPG, "jpg")):
            nova = fotos_olx.guardar(9115, 3, "https://img.olx.com.br/images/40/408635338169141.jpg")
            self.assertEqual(nova, "https://imobeasy.online/fotos-captacao/olx/9115/03.jpg")
            self.assertTrue(os.path.exists(os.path.join(d, "olx", "9115", "03.jpg")))

    def test_nao_baixou_fica_o_link_da_olx(self):
        url = "https://img.olx.com.br/images/40/408635338169141.jpg"
        with mock.patch.object(fotos_olx, "baixar", side_effect=ValueError("resposta 404")):
            self.assertEqual(fotos_olx.guardar(9115, 1, url), url)

    def test_extensao_pela_assinatura(self):
        self.assertEqual(fotos_olx.extensao(JPG), "jpg")
        self.assertIsNone(fotos_olx.extensao(b"<html>"))


if __name__ == "__main__":
    unittest.main()
