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
    def test_o_molde_do_tel(self):
        # Tel, 22/10: "✅PRECISO DE AP P/ VENDA - bairros: parque dez, flores, Aleixo - 3 quartos - até 700.000 - OBS:"
        t = b.mensagem_de_grupo({"finalidade": "venda", "tipo": "apartamento", "bairros": ["parque dez", "flores", "Aleixo"],
                                 "quartos": 3, "teto": 700000})
        self.assertEqual(t, "✅ PRECISO DE AP P/ VENDA\n- bairros: parque dez, flores, Aleixo\n- 3 quartos\n- até 700.000\n\n"
                            "Tem algum? Me chama no privado.")

    def test_casa_em_condominio_com_obs(self):
        t = b.mensagem_de_grupo({"finalidade": "locacao", "tipo": "casa_condominio", "bairros": ["parque dez", "flores", "Aleixo"],
                                 "quartos": 3, "aceita_menos_quartos": True, "teto": 4500, "mobilia": "mobiliado"})
        self.assertTrue(t.startswith("✅ PRECISO DE CS EM CONDOMÍNIO P/ LOCAÇÃO\n- bairros: parque dez, flores, Aleixo\n"
                                     "- 2 ou 3 quartos\n- até 4.500\n- OBS: mobiliado"))

    def test_sem_o_final_antigo(self):
        t = b.mensagem_de_grupo({"finalidade": "venda", "tipo": "casa", "teto": 500000})
        self.assertNotIn("com as fotos e o valor", t)
        self.assertNotIn("Trabalhamos em parceria", t)
        self.assertTrue(t.startswith("✅ PRECISO DE CASA P/ VENDA"))

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


class PerguntaAoAnunciante(unittest.TestCase):
    """Pedro, 23/10: sem o link do anúncio, só o nome do prédio."""
    A = {"titulo": "Garden Club - 124m2 - 03 suítes - AP no Parque 10 - Vendo", "preco": 950000, "bairro": "Parque 10",
         "url": "https://am.olx.com.br/regiao-de-manaus/imoveis/garden-club-1490357818"}

    def test_com_o_predio_e_sem_o_link(self):
        t = b.pergunta_ao_anunciante(self.A, "Garden Club Residencial")
        self.assertIn("Vi o seu anúncio na OLX do *Garden Club Residencial* (", t)
        self.assertNotIn("olx.com.br", t)
        self.assertNotIn("124m2", t)

    def test_sem_predio_vai_o_titulo_e_sem_o_link(self):
        t = b.pergunta_ao_anunciante(self.A)
        self.assertIn("*Garden Club - 124m2", t)
        self.assertNotIn("olx.com.br", t)


if __name__ == "__main__":
    unittest.main()
