"""02/11 (Pedro): o negócio vai na Observação (card), os detalhes na Descrição e o interno em Uso interno; nada repete."""
import unittest
from unittest import mock

from olx import buscas


class TestCamposDoCadastro(unittest.TestCase):
    def test_a_regra_vai_no_prompt(self):
        self.assertIn(buscas.REGRA_DOS_CAMPOS, buscas.PROMPT_CORRETOR)
        self.assertIn('"interno": ""', buscas.PROMPT_CORRETOR)

    def test_os_textos_somam_sem_repetir(self):
        antes = {"descricao": "Nascente.", "observacao": "Aceita pet."}
        d = buscas.juntar_imovel(antes, {"descricao": "Com energia solar.", "observacao": "Aceita pet."})
        self.assertEqual(d["descricao"], "Nascente. Com energia solar.")
        self.assertEqual(d["observacao"], "Aceita pet.")
        # o modelo devolveu o texto inteiro de novo, já com o que tinha: fica o dele, sem dobrar
        d = buscas.juntar_imovel(d, {"descricao": "Nascente. Com energia solar. Rua fechada."})
        self.assertEqual(d["descricao"], "Nascente. Com energia solar. Rua fechada.")

    def test_o_link_da_olx_e_interno(self):
        with mock.patch.object(buscas, "predio_do_anuncio", return_value=None):
            im = buscas.imovel_do_anuncio(None, {"url": "https://am.olx.com.br/x-1541661493", "categoria": "Apartamentos",
                                                 "tipo_negocio": "aluguel", "bairro": "Ponta Negra", "titulo": ""})
        self.assertEqual(im["interno"], "Anúncio da OLX: https://am.olx.com.br/x-1541661493")
        self.assertNotIn("observacao", im)


if __name__ == "__main__":
    unittest.main()
