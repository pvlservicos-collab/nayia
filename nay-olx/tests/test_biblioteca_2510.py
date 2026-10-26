"""As correções das conversas com erro de outubro testadas na Nay Leads (25/10): o recusado não volta na busca, o código
sozinho manda o imóvel e "de novo" é o que libera reenviar as fotos."""
import os
import sys
import unittest

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


class DeNovo(unittest.TestCase):
    def test_so_pedindo_de_novo(self):
        for t in ("manda as fotos de novo", "não chegaram as fotos", "reenvia por favor"):
            self.assertTrue(w.DE_NOVO.search(t), t)
        self.assertFalse(w.DE_NOVO.search("manda as fotos"))


if __name__ == "__main__":
    unittest.main()
