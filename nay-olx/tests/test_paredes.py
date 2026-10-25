"""As paredes de saída (25/10, o validador da Nay Parceria aplicado na Nay Leads e na Nay da OLX)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from olx import paredes  # noqa: E402

TURNO = ('Ficha do imóvel 3841 (o que ela citou): {"valores": {"aluguel": 3700, "condo": 1350.0, "venda": 700000.0}}\n'
         "IMÓVEIS DESTA CONVERSA:\n  #2944 · Apartamento · Maison Rochelle · aluguel R$ 3.800 · 3 quartos\n"
         "CLIENTE: quero alugar até 3 mil no Adrianópolis\nNAY: Quantos quartos?")


class Valores(unittest.TestCase):
    def test_valor_da_ficha_passa_em_qualquer_formato(self):
        for b in ("O aluguel é R$ 3.700.", "Fica em R$ 700.000 para venda.", "O condomínio é R$ 1.350,00.",
                  "O Maison Rochelle sai por R$ 3.800.", "Até R$ 3.000, certo?", "Até R$ 3 mil, certo?"):
            self.assertEqual(paredes.conferir([b], TURNO, False), [], b)

    def test_valor_inventado_fura(self):
        f = paredes.conferir(["Esse sai por R$ 2.500 com tudo incluso."], TURNO, False)
        self.assertEqual([(p, x) for _i, p, x in f], [("valor", "R$ 2.500")])

    def test_codigo_fora_da_conversa_fura(self):
        self.assertEqual(paredes.conferir(["Te mando o #3841 e o #2944."], TURNO, False), [])
        self.assertEqual([p for _i, p, _x in paredes.conferir(["O código 5120 é ótimo."], TURNO, False)], ["codigo"])


    def test_a_escala_do_valor_dito(self):
        turno = "CLIENTE: casa até 420 no Aleixo"
        self.assertEqual(paredes.conferir(["Até R$ 420.000, certo?"], turno, False), [])
        self.assertEqual([p for _i, p, _x in paredes.conferir(["Até R$ 430.000, certo?"], turno, False)], ["valor"])


class Voz(unittest.TestCase):
    def test_parceria_e_olx_que_ela_mesma_disse(self):
        turno = "CLIENTE: vocês fazem parceria? vi o anúncio"
        self.assertEqual(paredes.conferir(["Sobre parceria, a equipe te responde."], turno, False), [])
        self.assertEqual(paredes.conferir(["Sobre o anúncio, já te mando."], turno, True), [])

    def test_parceria_negativa_e_bastidor_furam(self):
        casos = {"Esse é de um parceiro nosso.": "parceria", "Infelizmente não temos nesse bairro.": "negativa",
                 "Vou ver na minha ficha aqui.": "bastidor", "Sou um robô da Imob Easy.": "bastidor"}
        for b, parede in casos.items():
            self.assertIn(parede, [p for _i, p, _x in paredes.conferir([b], TURNO, False)], b)

    def test_o_fecho_de_sempre_passa(self):
        b = "Ok, muito grata, Sra. Claudia! Vou pegar as opções no meu sistema para lhe enviar."
        self.assertEqual(paredes.conferir([b], TURNO, False), [])

    def test_olx_so_fura_no_organico(self):
        b = "Vi que você chamou pelo anúncio da OLX."
        self.assertEqual(paredes.conferir([b], TURNO, False), [])
        self.assertEqual([p for _i, p, _x in paredes.conferir([b], TURNO, True)], ["olx"])


class Cortar(unittest.TestCase):
    def test_corta_so_o_balao_que_fura(self):
        sobra, furos = paredes.cortar(["Tenho uma opção ótima!", "Sai por R$ 1.990."], TURNO, False)
        self.assertEqual(sobra, ["Tenho uma opção ótima!"])
        self.assertEqual(len(furos), 1)

    def test_aviso_lista_cada_furo_uma_vez(self):
        furos = paredes.conferir(["R$ 1.990", "R$ 1.990 e parceiro"], TURNO, False)
        a = paredes.aviso(furos)
        self.assertEqual(a.count("R$ 1.990"), 1)
        self.assertIn("parceiro", a)


if __name__ == "__main__":
    unittest.main()
