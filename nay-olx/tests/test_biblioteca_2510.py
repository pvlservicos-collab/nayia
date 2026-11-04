"""As correções das conversas com erro de outubro testadas na Nay Leads (25/10): o recusado não volta na busca, o código
sozinho manda o imóvel e "de novo" é o que libera reenviar as fotos."""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from olx import whatsapp as w  # noqa: E402


class Recusados(unittest.TestCase):
    def test_acumulam_como_as_exigencias(self):
        f = w._filtros({}, {"recusados": ["9019"]})
        f = w._filtros(f, {"recusados": ["Reserva Inglesa"]})
        f = w._filtros(f, {"recusados": []})                      # o modelo esqueceu de repetir: não some
        self.assertEqual(f["recusados"], ["9019", "Reserva Inglesa"])

    def test_codigo_e_nome(self):
        cods, nomes = w.recusados({"recusados": ["#9019", "Liverpool", "x"]})
        self.assertEqual(cods, [9019])
        self.assertEqual(len(nomes), 1)

    def test_o_condominio_recusado_sai_da_busca(self):
        achados = [{"codigo": 1, "condominio": "Liverpool Reserva Inglesa"}, {"codigo": 2, "condominio": "Firenze"}]
        _c, nomes = w.recusados({"recusados": ["liverpool"]})
        self.assertEqual([a["codigo"] for a in w.fora_os_recusados(achados, nomes)], [2])


class CodigoSozinho(unittest.TestCase):
    def test_o_codigo_e_o_pedido(self):
        for t in ("3078", "Cód. 3078", "#3078", "codigo 3078."):
            self.assertEqual(w.codigo_sozinho([t], "Quer que eu te mande mais opções?"), 3078, t)

    def test_numero_que_responde_a_pergunta_nao_e_imovel(self):
        self.assertIsNone(w.codigo_sozinho(["3000"], "Até que valor você procura?"))
        self.assertIsNone(w.codigo_sozinho(["3"], "Quantos quartos?"))

    def test_frase_com_numero_nao_e_codigo_sozinho(self):
        self.assertIsNone(w.codigo_sozinho(["o 3078 aceita pet?"], ""))


class EquipeATona(unittest.TestCase):
    def test_interesse_nao_e_com_a_equipe(self):
        r = {"baloes": ["Vou passar para a equipe."], "acoes": ["equipe"]}
        self.assertTrue(w.equipe_a_toa(r, ["Tenho um cliente interessado nesse apartamento"]).startswith("ATENÇÃO"))
        self.assertTrue(w.equipe_a_toa(r, ["gostei desse"]))

    def test_com_motivo_de_equipe_vale(self):
        r = {"baloes": ["Vou passar para a equipe."], "acoes": ["equipe"]}
        self.assertEqual(w.equipe_a_toa(r, ["tenho interesse, quero fechar e mandar os documentos"]), "")
        self.assertEqual(w.equipe_a_toa({"acoes": ["visita"]}, ["tenho interesse"]), "")


class EscolhaPeloValor(unittest.TestCase):
    CONHECIDOS = ["#2659 · Casa · Village Park, Aleixo · venda R$ 700.000 · 3 quartos",
                  "#5711 · Casa · Village Park, Aleixo · venda R$ 800.000 · 4 quartos",
                  "#5733 · Apartamento · Conquista Rio Negro, Ponta Negra · aluguel R$ 1.900 · 2 quartos"]

    def test_o_valor_escolhe_o_imovel(self):
        for t, cod in (("700mil", 2659), ("o de 800 mil", 5711), ("1,900", 5733), ("1.900", 5733), ("R$ 1.900", 5733), ("700", 2659)):
            self.assertEqual(w.escolha_pelo_valor([t], "Qual deles você quer ver?", self.CONHECIDOS), cod, t)

    def test_resposta_ao_valor_e_teto_nao_escolha(self):
        self.assertIsNone(w.escolha_pelo_valor(["1.900"], "Até que valor você procura?", self.CONHECIDOS))

    def test_valor_que_nao_bate_ou_frase(self):
        self.assertIsNone(w.escolha_pelo_valor(["950 mil"], "", self.CONHECIDOS))
        self.assertIsNone(w.escolha_pelo_valor(["tem algum de 700 mil com piscina?"], "", self.CONHECIDOS))


class DepoisDoModelo(unittest.TestCase):
    """26/10: o card responde, pediu opções busca, nunca sem balão (com _ofertavel falso-verdadeiro, sem banco)."""

    def rodar(self, r, novas, lead=None, ultima=""):
        lead = lead or {"codigo": 3078, "enviados": [], "filtros": {}}
        # 04/11: sem banco, as fotos ainda não foram (a trava das fotos repetidas lê privado.olx_cliente_enviada)
        with mock.patch.object(w, "_ofertavel", return_value=True), mock.patch.object(w, "fotos_ja_foram", return_value=False):
            return w.depois_do_modelo(None, lead, r, novas, ultima)

    def test_o_card_responde_no_lugar_do_vou_confirmar(self):
        r = {"baloes": ["Vou confirmar o valor e já retorno."], "acoes": ["perguntar"]}
        acoes, passos = self.rodar(r, ["qual o valor e quantos quartos?"])
        self.assertEqual(acoes, ["fotos"])
        self.assertEqual(r["fotos"], {"codigos": [3078]})
        # 04/11 (Pedro: "card" é jargão): era "Vou te mandar o card com as informações e as fotos dele."
        self.assertNotIn("card", r["baloes"][0])
        self.assertIn(r["baloes"][0], w.MANDO_O_IMOVEL)
        self.assertEqual(passos[0][0], "card_responde")

    def test_o_que_o_card_nao_traz_continua_na_equipe(self):
        r = {"baloes": ["Vou confirmar."], "acoes": ["perguntar"]}
        acoes, _p = self.rodar(r, ["qual o valor? aceita pet?"])
        self.assertEqual(acoes, ["fotos", "perguntar"])

    def test_quem_ja_recebeu_o_card_nao_recebe_de_novo(self):
        r = {"baloes": ["Vou confirmar o andar."], "acoes": ["perguntar"]}
        acoes, _p = self.rodar(r, ["qual o valor do condomínio?"], {"codigo": 3078, "enviados": [3078], "filtros": {}})
        self.assertEqual(acoes, ["perguntar"])

    def test_pediu_opcoes_e_os_filtros_bastam_busca(self):
        r = {"baloes": ["Quantos quartos você procura?"], "acoes": [],
             "filtros": {"finalidade": "locacao", "teto": 7000, "bairros": ["Ponta Negra"]}}
        acoes, _p = self.rodar(r, ["tem outras opções?"], {"enviados": [], "filtros": {}})
        self.assertEqual(acoes, ["buscar"])
        self.assertFalse(r["baloes"][0].endswith("?"))

    def test_sem_os_filtros_nao_busca(self):
        r = {"baloes": ["Até que valor?"], "acoes": [], "filtros": {"finalidade": "locacao"}}
        self.assertEqual(self.rodar(r, ["tem outras opções?"], {"enviados": [], "filtros": {}})[0], [])

    def test_nunca_vai_a_equipe_sem_balao(self):
        r = {"baloes": [], "acoes": ["perguntar"]}
        self.rodar(r, ["tem essa disponibilidade?"], {"enviados": [], "filtros": {}})
        self.assertIn(r["baloes"][0], w.BALOES_SEM_RESPOSTA["perguntar"])
        self.assertTrue(r["_balao_padrao"])            # 04/11: a frase pronta é a rede; o modelo é chamado de novo antes

    def test_filtro_nao_e_pergunta(self):
        # o lead 52: a faixa de valor "com condomínio incluso" não pede o card do Maison
        r = {"baloes": ["Quais bairros atendem você?"], "acoes": ["perguntar"]}
        acoes, _p = self.rodar(r, ["Entre 3.5 a 3.7k", "4k no máximo", "Com condomínio incluso"], {"codigo": 2944, "enviados": [], "filtros": {}})
        self.assertEqual(acoes, ["perguntar"])
        self.assertEqual(r["baloes"], ["Quais bairros atendem você?"])

    def test_fotos_e_informacoes_sem_motivo_de_equipe(self):
        # o lead 32: "poderia passar as fotos e informações para enviar a ela?" -> o card, não a equipe
        r = {"baloes": ["Vou passar para a equipe."], "acoes": ["equipe"]}
        acoes, _p = self.rodar(r, ["poderia passar as fotos e informações para enviar a ela?"], {"codigo": 5735, "enviados": [], "filtros": {}})
        self.assertEqual(acoes, ["fotos"])
        self.assertEqual(r["fotos"], {"codigos": [5735]})

    def test_so_no_condominio(self):
        achados = [{"codigo": 1, "condominio": "Ponta Negra Village"}, {"codigo": 2, "condominio": "Residencial Tapajós"}]
        f = {"condominio": "ponta negra village", "so_condominio": True}
        self.assertEqual([a["codigo"] for a in w.so_no_condominio(achados, f)], [1])
        self.assertEqual(len(w.so_no_condominio(achados, {"condominio": "ponta negra village"})), 2)


class LinkDaOlx(unittest.TestCase):
    def test_o_numero_do_anuncio_sai_do_link(self):
        t = ("https://am.olx.com.br/regiao-de-manaus/imoveis/apartamento-com-2-quartos-a-venda-no-kopenhagen-parque-10-de-"
             "novembro-1544287925?rec=a&custom_tag=vi_web")
        self.assertEqual(w.LINK_OLX.findall(t), ["1544287925"])
        self.assertEqual(w.LINK_OLX.findall("o apartamento 5758 da olx"), [])

    def test_numero_dentro_do_link_nao_e_codigo(self):
        conv = [{"direcao": "recebida", "texto": "https://am.olx.com.br/x/apto-kopenhagen-1544287925?gallery_id=1020&rec=a"}]
        self.assertEqual(w.codigos_citados(conv), [])
        self.assertEqual(w.codigos_citados([{"direcao": "recebida", "texto": "e o 5758?"}]), [5758])


class Documento(unittest.TestCase):
    def test_creci_inventado_fura(self):
        from olx import paredes
        furos = paredes.conferir(["O CRECI da imobiliária é PJ 482."], "CLIENTE: qual o seu creci?", False)
        self.assertEqual([p for _i, p, _x in furos], ["documento"])
        self.assertEqual(paredes.conferir(["O CRECI é J-482."], "SISTEMA: CRECI da Imob Easy J-482", False), [])
        # 482 solto num preço ou área do turno não autoriza o CRECI
        self.assertEqual([p for _i, p, _x in paredes.conferir(["O CRECI é PJ 482."], "Ficha: 482 m2", False)], ["documento"])

    def test_a_equipe_disse_so_com_resposta_da_equipe(self):
        from olx import paredes
        b = ["A equipe me informou que não há casas até R$ 150.000."]
        self.assertIn("equipe_disse", [p for _i, p, _x in paredes.conferir(b, "CLIENTE: até 150 mil", False)])
        self.assertNotIn("equipe_disse", [p for _i, p, _x in paredes.conferir(b, "EQUIPE: até 150 mil não temos\nCLIENTE: ok", False)])


class DeNovo(unittest.TestCase):
    def test_so_pedindo_de_novo(self):
        for t in ("manda as fotos de novo", "não chegaram as fotos", "reenvia por favor"):
            self.assertTrue(w.DE_NOVO.search(t), t)
        self.assertFalse(w.DE_NOVO.search("manda as fotos"))


if __name__ == "__main__":
    unittest.main()
