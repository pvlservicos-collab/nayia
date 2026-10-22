"""O fluxo de busca do cliente (475, Pedro 22/10/2026): a mensagem dos grupos e a regra de qual grupo recebe o quê.
"Nunca errar e pedir a coisa errada no grupo errado." O banco é provado no ensaio da 475."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from olx import buscas as b  # noqa: E402

LOCACAO_SO = {"grupo_id": "l", "nome": "Locação CREDENCIADOS", "locacao": True, "venda": False, "locacao_min": None, "venda_min": None}
TODOS = {"grupo_id": "t", "nome": "FECHANDO PARCERIAS 1.0", "locacao": True, "venda": True, "locacao_min": None, "venda_min": None}
ALTO = {"grupo_id": "a", "nome": "Alto Padrão", "locacao": True, "venda": True, "locacao_min": 7000, "venda_min": 800000}


class QualGrupo(unittest.TestCase):
    def test_venda_nunca_vai_ao_grupo_de_locacao(self):
        f = {"finalidade": "venda", "tipo": "apartamento", "teto": 700000}
        self.assertFalse(b.grupo_aceita(LOCACAO_SO, f))
        self.assertTrue(b.grupo_aceita(TODOS, f))

    def test_alto_padrao_so_locacao_de_7_mil_e_venda_de_800_mil(self):
        self.assertFalse(b.grupo_aceita(ALTO, {"finalidade": "locacao", "teto": 4500}))
        self.assertTrue(b.grupo_aceita(ALTO, {"finalidade": "locacao", "teto": 7000}))
        self.assertFalse(b.grupo_aceita(ALTO, {"finalidade": "venda", "teto": 700000}))
        self.assertTrue(b.grupo_aceita(ALTO, {"finalidade": "venda", "teto": 800000}))

    def test_sem_valor_o_alto_padrao_nao_recebe(self):
        self.assertFalse(b.grupo_aceita(ALTO, {"finalidade": "venda", "tipo": "casa"}))

    def test_sem_negocio_nenhum_grupo_recebe(self):
        for g in (LOCACAO_SO, TODOS, ALTO):
            self.assertFalse(b.grupo_aceita(g, {"tipo": "apartamento", "teto": 900000}))

    def test_alugar_e_comprar_ditos_de_outro_jeito(self):
        self.assertEqual(b.finalidade({"finalidade": "aluguel"}), "locacao")
        self.assertEqual(b.finalidade({"finalidade": "compra"}), "venda")


class Mensagem(unittest.TestCase):
    def test_o_molde_do_tel_arrumado(self):
        t = b.mensagem_de_grupo([
            {"finalidade": "venda", "tipo": "apartamento", "bairros": ["parque dez", "flores", "Aleixo"], "quartos": 3, "teto": 700000},
            {"finalidade": "locacao", "tipo": "casa de condomínio", "bairros": ["parque dez"], "quartos": 3,
             "aceita_menos_quartos": True, "teto": 4500, "mobilia": "mobiliado"}])
        self.assertIn("*APARTAMENTO PARA VENDA*\n• Bairros: Parque Dez, Flores e Aleixo\n• Quartos: 3 quartos\n• Valor: até R$ 700.000", t)
        self.assertIn("*CASA EM CONDOMÍNIO PARA LOCAÇÃO*\n• Bairros: Parque Dez\n• Quartos: 2 ou 3 quartos\n"
                      "• Valor: até R$ 4.500/mês\n• Obs.: mobiliado", t)
        self.assertTrue(t.startswith("🔎 *PROCURO PARA CLIENTE*"))
        self.assertLessEqual(t.count("🔎") + t.count("✅"), 1)          # "sem muito emoji"

    def test_nunca_leva_dado_do_cliente(self):
        t = b.bloco({"finalidade": "locacao", "tipo": "apartamento", "teto": 3000, "nome": "Michelle", "telefone": "92981585907"})
        self.assertNotIn("Michelle", t)
        self.assertNotIn("9298", t)

    def test_sem_bairro_e_qualquer_bairro(self):
        self.assertIn("qualquer bairro", b.bloco({"finalidade": "venda", "tipo": "casa", "teto": 500000}))

    def test_mobilia_so_na_locacao(self):
        self.assertNotIn("mobiliado", b.bloco({"finalidade": "venda", "tipo": "apartamento", "teto": 500000, "mobilia": "mobiliado"}))


class Corretor(unittest.TestCase):
    def test_o_que_falta_para_o_cadastro(self):
        im = {"tipo": "apartamento", "finalidade": "locacao", "bairro": "Flores", "quartos": 2, "valor": 3000}
        self.assertEqual(b.falta_no_imovel(im, 0), ["o condomínio", "a mobília", "as fotos"])
        self.assertEqual(b.falta_no_imovel({**im, "condominio": "Smile", "mobilia": "mobiliado"}, 3), [])

    def test_o_novo_nao_apaga_o_que_ja_sabiamos(self):
        self.assertEqual(b.juntar_imovel({"bairro": "Flores", "quartos": 2}, {"bairro": "", "quartos": 0, "valor": 3000}),
                         {"bairro": "Flores", "quartos": 2, "valor": 3000})


if __name__ == "__main__":
    unittest.main()
