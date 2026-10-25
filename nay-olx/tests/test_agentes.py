"""Os agentes da Nay Leads (489, Pedro 24/10/2026): o prompt do Atendimento cortado pelo caminho que o Mestre escolheu,
o veto dos imóveis e o "calar" só de cortesia. O JEV e o banco não são chamados aqui (são falsos)."""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from olx import agentes as ag  # noqa: E402
from olx import whatsapp  # noqa: E402

PROMPT = whatsapp.PROMPT


class Corte(unittest.TestCase):
    def test_o_prompt_de_hoje_se_divide(self):
        p = ag.partes_do_prompt(PROMPT)
        self.assertIsNotNone(p, "o formato do PROMPT mudou: o corte não reconhece as seções")
        for k in ("abertura", "roteiro", "visita", "fotos", "foto_parte", "organico", "nunca", "json"):
            self.assertTrue(p.get(k), k)

    def test_todo_caminho_leva_as_regras_que_valem_sempre(self):
        for rotas in (["imoveis"], ["duvida"], ["visita"], ["fotos"], ["equipe"]):
            t, sec = ag.prompt_para(PROMPT, rotas, False)
            for k in ("equipe_conversa", "quando_equipe", "confirmacao", "nunca", "fala", "json"):
                self.assertIn(k, sec, f"{rotas} sem {k}")
            self.assertLess(len(t), len(PROMPT))

    def test_cada_caminho_leva_a_sua_parte(self):
        self.assertIn("4. VISITA", ag.prompt_para(PROMPT, ["visita"], False)[0])
        self.assertNotIn("4. VISITA", ag.prompt_para(PROMPT, ["imoveis"], False)[0])
        self.assertIn("2. OUTRAS OPÇÕES", ag.prompt_para(PROMPT, ["imoveis"], False)[0])
        self.assertIn("5. FOTOS", ag.prompt_para(PROMPT, ["fotos"], False)[0])
        self.assertIn("=== QUANDO VEIO DIRETO", ag.prompt_para(PROMPT, ["duvida"], True)[0])
        self.assertNotIn("=== QUANDO VEIO DIRETO", ag.prompt_para(PROMPT, ["duvida"], False)[0])

    def test_formato_estranho_vai_inteiro(self):
        t, sec = ag.prompt_para("um prompt sem seções", ["imoveis"], False)
        self.assertEqual(t, "um prompt sem seções")


class Mestre(unittest.TestCase):
    conversa = [{"direcao": "recebida", "texto": "oi"}, {"direcao": "enviada", "origem": "resposta", "texto": "Oi! Até que valor?"},
                {"direcao": "recebida", "texto": "até 3 mil no Aleixo"}]

    corte = False

    def _planejar(self, probs, modo="sim", conversa=None, pode_calar=True):
        corte = self.corte
        with mock.patch.object(ag, "modo", return_value=modo), mock.patch.object(ag, "registrar"), \
             mock.patch.object(ag, "corte_ligado", return_value=corte), \
             mock.patch.object(ag, "jev", return_value=(probs, {"ms": 300})):
            return ag.planejar(PROMPT, {"id": 1, "telefone": "559200000000"}, conversa or self.conversa,
                               ["até 3 mil no Aleixo"], False, pode_calar)

    def test_caminho_de_imoveis_com_o_corte(self):
        self.corte = True
        p = self._planejar({"imoveis": 0.9, "duvida": 0.1, "visita": 0.05, "fotos": 0.02, "equipe": 0.01, "cortesia": 0.01})
        self.corte = False
        self.assertEqual(p["rotas"], ["imoveis"])
        self.assertFalse(p["geral"])
        self.assertLess(len(p["prompt"]), len(PROMPT))

    def test_sem_o_corte_o_atendimento_recebe_o_prompt_inteiro(self):
        p = self._planejar({"imoveis": 0.9, "duvida": 0.1, "visita": 0.05, "fotos": 0.02, "equipe": 0.01, "cortesia": 0.01})
        self.assertEqual(p["rotas"], ["imoveis"])
        self.assertEqual(p["prompt"], PROMPT)

    def test_sem_certeza_vai_o_prompt_inteiro(self):
        p = self._planejar({"imoveis": 0.1, "duvida": 0.2, "visita": 0.1, "fotos": 0.1, "equipe": 0.1, "cortesia": 0.4})
        self.assertTrue(p["geral"])
        self.assertEqual(p["prompt"], PROMPT)

    def test_primeira_mensagem_vai_inteiro(self):
        p = self._planejar({"imoveis": 0.9}, conversa=[{"direcao": "recebida", "texto": "oi, quero alugar"}])
        self.assertTrue(p["geral"])

    def test_cortesia_cala_so_com_as_travas(self):
        so_ok = {"imoveis": 0.05, "duvida": 0.05, "visita": 0.05, "fotos": 0.01, "equipe": 0.01, "cortesia": 0.95}
        self.assertTrue(self._planejar(so_ok)["calar"])
        self.assertFalse(self._planejar(so_ok, pode_calar=False)["calar"], "pergunta pendente: não cala")

    def test_jev_fora_do_ar_vai_inteiro(self):
        with mock.patch.object(ag, "modo", return_value="sim"), mock.patch.object(ag, "registrar"), \
             mock.patch.object(ag, "jev", side_effect=RuntimeError("caiu")):
            p = ag.planejar(PROMPT, {"id": 1}, self.conversa, ["x"], False, True)
        self.assertTrue(p["geral"])
        self.assertEqual(p["prompt"], PROMPT)

    def test_sombra_e_nao_nao_mudam_nada(self):
        for m in ("sombra", "nao"):
            p = self._planejar({"imoveis": 0.9, "cortesia": 0.0}, modo=m)
            self.assertEqual(p["prompt"], PROMPT)
            self.assertFalse(p["calar"])


class Veto(unittest.TestCase):
    achados = [{"codigo": 1, "tipo": "apartamento", "quartos": 2, "bairro": "Aleixo", "preco": 2800},
               {"codigo": 2, "tipo": "casa", "quartos": 4, "bairro": "Ponta Negra", "preco": 9000}]

    def _filtrar(self, probs, modo="sim"):
        with mock.patch.object(ag, "modo", return_value=modo), mock.patch.object(ag, "registrar"), \
             mock.patch.object(ag, "jev", return_value=(probs, {"ms": 200})):
            return ag.filtrar_imoveis({"id": 1}, {"teto": 3000, "bairros": ["aleixo"]}, self.achados)

    def test_barra_o_que_nao_serve(self):
        self.assertEqual([a["codigo"] for a in self._filtrar({"i1": 0.9, "i2": 0.1})], [1])

    def test_sombra_so_registra(self):
        self.assertEqual(len(self._filtrar({"i1": 0.9, "i2": 0.1}, modo="sombra")), 2)

    def test_sem_resposta_sai_tudo(self):
        with mock.patch.object(ag, "modo", return_value="sim"), mock.patch.object(ag, "registrar"), \
             mock.patch.object(ag, "jev", side_effect=RuntimeError("caiu")):
            self.assertEqual(len(ag.filtrar_imoveis({"id": 1}, {}, self.achados)), 2)


if __name__ == "__main__":
    unittest.main()
