"""416 (19/10): buscar imóvel de parceiro na OLX. O que é puro, sem banco, sem Chrome, sem Z-API.
python -m unittest discover -s tests   (com NAY_GRUPOS_DIR apontando para o nay-grupos, se não for /root/nay-grupos)"""
import os
import pathlib
import unittest
from unittest import mock

_AQUI = pathlib.Path(__file__).resolve()
if not os.environ.get("NAY_GRUPOS_DIR") and not pathlib.Path("/root/nay-grupos").exists():
    os.environ["NAY_GRUPOS_DIR"] = str(_AQUI.parents[2] / "nay-grupos")

from olx import busca_olx as b  # noqa: E402
from olx import parceiro as p  # noqa: E402
from olx import whatsapp as w  # noqa: E402

ANUNCIO = {
    "listId": 1400001, "subject": "Apartamento 3 quartos no Parque 10", "price": "R$ 2.500", "url": "https://am.olx.com.br/x",
    "locationDetails": {"neighbourhood": "Parque 10 de Novembro"},
    "properties": [{"name": "category", "value": "Apartamentos"}, {"name": "rooms", "value": "3"},
                   {"name": "size", "value": "80m²"}, {"name": "garage_spaces", "value": "1"},
                   {"name": "re_complex_features", "value": "Piscina, Elevador, Academia"}],
    "olxPay": {"transactionalSellerName": "Fulano Imóveis"}, "images": [{"original": "https://img/1.jpg"}],
}


class Busca(unittest.TestCase):
    def test_uma_url_por_bairro_e_a_faixa_larga(self):
        us = b.urls_da_busca({"finalidade": "locacao", "tipo": "apartamento", "teto": 3000, "bairros": ["Parque 10", "Flores"]})
        self.assertEqual(len(us), 2)
        self.assertTrue(us[0].startswith("https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?"))
        self.assertIn("ps=1800", us[0])
        self.assertIn("pe=3300", us[0])
        self.assertIn("q=apartamento+Parque+10", us[0])

    def test_venda_e_qualquer_bairro(self):
        us = b.urls_da_busca({"finalidade": "venda", "tipo": "casa", "bairros": ["Flores"], "qualquer_bairro": True})
        self.assertEqual(len(us), 1)
        self.assertIn("/imoveis/venda/", us[0])
        self.assertIn("q=casa", us[0])

    def test_anuncio_vira_imovel_da_nota(self):
        im = b.para_imovel(ANUNCIO, "aluguel")
        self.assertEqual((im["tipo"], im["quartos"], im["vagas"], im["valor_aluguel"], im["elevador"]),
                         ("apartamento", 3, 1, 2500.0, True))
        self.assertIsNone(im["valor_venda"])
        sem = dict(ANUNCIO, properties=[x for x in ANUNCIO["properties"] if x["name"] != "re_complex_features"]
                   + [{"name": "re_complex_features", "value": "Piscina"}])
        self.assertIs(b.para_imovel(sem, "aluguel")["elevador"], False)

    def test_os_nossos_ficam_fora(self):
        self.assertFalse(b.e_nosso(ANUNCIO))
        self.assertTrue(b.e_nosso(dict(ANUNCIO, olxPay={"transactionalSellerName": "IMOB EASY Manaus"})))

    def test_lista_do_next(self):
        flight = 'lixo "ads":[{"listId": 9, "subject": "a"}, {"x": 1}],"totalOfAds":1 resto'
        self.assertEqual([a["listId"] for a in b.anuncios_da_lista(flight)], [9])

    def test_pedido_dos_filtros(self):
        with mock.patch.object(b.glugares, "resolver", side_effect=lambda ficha, g, l: (ficha, None, None)):
            ped = b.pedido_dos_filtros({"finalidade": "locacao", "tipo": "Apartamento", "teto": "3000", "quartos": 3,
                                        "aceita_menos_quartos": True, "aceita_escada": False, "mobilia": "mobiliado",
                                        "bairros": ["Flores"]}, None)
        self.assertEqual((ped["operacao"], ped["tipo"], ped["quartos"], ped["preco_max"], ped["elevador"], ped["mobiliado"]),
                         ("aluguel", "apartamento", 2, 3000.0, True, True))


class Contato(unittest.TestCase):
    def test_mascara(self):
        self.assertTrue(p.bate_com_a_mascara("92999812345", "(92) 99981-****"))
        self.assertTrue(p.bate_com_a_mascara("92999812345", "+55 92 9998****"))
        self.assertFalse(p.bate_com_a_mascara("92988880000", "(92) 99981-****"))
        self.assertFalse(p.bate_com_a_mascara("92988880000", None))

    def test_linha(self):
        self.assertEqual(p.escolher_linha(["captacao", "parceria_saida"], "Ana", False), ("parceria", "Ana"))
        self.assertEqual(p.escolher_linha(["corretores"], None, True), ("parceria", None))
        self.assertEqual(p.escolher_linha(["captacao_saida"], None, False), ("captacao", None))
        # dono da campanha ou cliente da OLX: a Captação não pergunta (as Nays de lá responderiam)
        self.assertEqual(p.escolher_linha(["captacao"], None, True), (None, None))
        # só no CRM ou nada: não falamos com ele -> grupo
        self.assertEqual(p.escolher_linha(["crm"], None, False), (None, None))
        self.assertEqual(p.escolher_linha([], None, False), (None, None))

    def test_pergunta_sem_parceiro(self):
        t = p.pergunta("JOÃO silva", {"titulo": "Apto no Parque 10", "preco_texto": "R$ 2.500", "bairro": "Parque 10",
                                      "url": "https://am.olx.com.br/x"})
        self.assertTrue(t.startswith("Olá, João! Tudo bem? Aqui é a Nay, da Imob Easy."))
        self.assertIn("*Apto no Parque 10* (R$ 2.500, Parque 10). Ele ainda está disponível?", t)
        self.assertTrue(t.endswith("https://am.olx.com.br/x"))
        self.assertTrue(p.pergunta(None, {"titulo": "x", "url": "u"}).startswith("Olá! Tudo bem?"))


class Resposta(unittest.TestCase):
    def test_sem_o_modelo_as_palavras_claras(self):
        with mock.patch.object(p.modelo, "chamar", side_effect=RuntimeError("sem modelo")):
            self.assertEqual(p.disponivel("Sim, está disponível!"), "sim")
            self.assertEqual(p.disponivel("Já foi alugado, desculpa"), "nao")
            self.assertEqual(p.disponivel("Sim, mas não aceita pet"), "duvida")
            self.assertEqual(p.disponivel("Qual o perfil do cliente?"), "duvida")

    def test_o_modelo_decide(self):
        with mock.patch.object(p.modelo, "chamar", return_value={"disponivel": "nao"}):
            self.assertEqual(p.disponivel("ok"), "nao")


class Gatilho(unittest.TestCase):
    def test_chave(self):
        cfg = {"busca_parceiro": "teste", "whatsapp_teste": "96991712835, 92981585907"}
        self.assertEqual(w.busca_na_olx_vale(cfg, "96991712835"), (True, True))
        self.assertEqual(w.busca_na_olx_vale(cfg, "92981585907"), (False, False))     # a Michelle é cliente de verdade
        self.assertEqual(w.busca_na_olx_vale(cfg, "92911112222"), (False, False))
        self.assertEqual(w.busca_na_olx_vale({**cfg, "busca_parceiro": "sim"}, "92911112222"), (True, False))
        self.assertEqual(w.busca_na_olx_vale({**cfg, "busca_parceiro": "nao"}, "96991712835"), (False, False))


if __name__ == "__main__":
    unittest.main()
