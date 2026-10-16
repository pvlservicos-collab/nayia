"""A Nay do WhatsApp dos clientes da OLX (16/10, 385): o que é puro, sem banco nem Z-API.
python -m unittest discover -s tests"""
import unittest

from olx import whatsapp as w


class Tratamento(unittest.TestCase):
    def test_sra_sr_e_primeiro_nome(self):
        self.assertEqual(w.tratamento({"nome": "Claudia Maria Simonetti", "trat": "Sra."}), ("Sra. Claudia", "a senhora"))
        self.assertEqual(w.tratamento({"nome": "FELIPE LADISLAU", "trat": "Sr."}), ("Sr. Felipe", "o senhor"))
        self.assertEqual(w.tratamento({"nome": "Imobeasy Manaus", "trat": None}), ("Imobeasy", "você"))

    def test_fecho_depois_dos_imoveis(self):
        self.assertIn("chamou a atenção da senhora?", w.fecho({"nome": "Claudia", "trat": "Sra."}))
        self.assertIn("te chamou a atenção?", w.fecho({"nome": "Ana", "trat": None}))
        self.assertTrue(w.fecho({"nome": "Claudia", "trat": "Sra."}, 1).startswith("Essa é a opção que separei. Ela agradou a senhora?"))


class Filtros(unittest.TestCase):
    def test_o_novo_soma_e_vazio_nao_apaga(self):
        antes = {"teto": 3000, "bairros": ["Ponta Negra"]}
        novos = {"teto": 0, "bairros": [], "quartos": 3, "aceita_menos_quartos": False, "aceita_escada": None,
                 "inventado": "x"}
        f = w._filtros(antes, novos)
        self.assertEqual(f, {"teto": 3000, "bairros": ["Ponta Negra"], "quartos": 3, "aceita_menos_quartos": False})

    def test_resumo(self):
        self.assertEqual(w._resumo_dos_filtros({"finalidade": "venda", "teto": 450000, "bairros": ["Flores"], "quartos": 3}),
                         "venda · até R$ 450.000 · Flores · 3 quartos")


class Chave(unittest.TestCase):
    def test_teste_so_os_numeros_da_lista_e_nunca_o_telmario(self):
        cfg = {"whatsapp_responde": "teste", "whatsapp_teste": "96991712835", "whatsapp_nunca": "92994717316"}
        self.assertTrue(w._pode(cfg, "96991712835"))
        self.assertFalse(w._pode(cfg, "92981585907"))
        self.assertFalse(w._pode({**cfg, "whatsapp_responde": "sim"}, "92994717316"))
        self.assertTrue(w._pode({**cfg, "whatsapp_responde": "sim"}, "92981585907"))
        self.assertFalse(w._pode({**cfg, "whatsapp_responde": "nao"}, "96991712835"))


class Turno(unittest.TestCase):
    def test_abertura_e_conversa(self):
        lead = {"nome": "Claudia Maria", "trat": "Sra.", "codigo": 5758, "negocio": "venda", "etapa": "filtrar",
                "perfil": {"duvidas": "aceita financiamento?"}, "quer_visita": False, "filtros": {}, "enviados": [5724]}
        ctx = {"anuncio": {"titulo": "Apartamento no Kopenhagen", "codigo": 5758},
               "imovel": {"valores": {"venda": 270000}, "obs": "interno", "fotos": ["x"]},
               "mensagens": [{"de": "comprador", "texto": "aceita financiamento?"}, {"de": "nos", "texto": "Aceita.", "por": "Nay OLX"}]}
        t = w.montar_turno(lead, ctx, [])
        self.assertIn("trate como: Sra. Claudia (a senhora)", t)
        self.assertIn("VENDA | Apartamento no Kopenhagen | cód. 5758", t)
        self.assertIn("CLIENTE: aceita financiamento?", t)
        self.assertIn("Ainda não há conversa", t)
        self.assertNotIn("interno", t)
        t2 = w.montar_turno(lead, ctx, [{"direcao": "recebida", "texto": "quero mais opções"},
                                         {"direcao": "enviada", "texto": "Até que valor?", "nossa": True},
                                         {"direcao": "enviada", "texto": "oi, aqui é o Tel", "nossa": False, "origem": "humano"}])
        self.assertIn("CLIENTE: quero mais opções", t2)
        self.assertIn("NAY: Até que valor?", t2)
        self.assertIn("EQUIPE: oi, aqui é o Tel", t2)
        self.assertIn("Imóveis já enviados (códigos): 5724", t2)

    def test_acoes_na_ordem_e_o_formato_antigo(self):
        self.assertEqual(w.acoes_da({"acoes": ["fotos", "buscar", "fotos", "x", "visita"]}), ["fotos", "buscar"])
        self.assertEqual(w.acoes_da({"acao": "visita"}), ["visita"])
        self.assertEqual(w.acoes_da({"acoes": []}), [])
        self.assertEqual(w.acoes_da({}), [])
        self.assertEqual(w.acoes_da({"acoes": ["perguntar"]}), ["perguntar"])

    def test_foto_de_uma_parte_pergunta_a_equipe(self):
        # 16/10: "fotos dos quartos com roupeiros" -> ela não sabe qual foto é de qual cômodo: pergunta à equipe
        self.assertIn("você NÃO sabe qual foto é de qual cômodo", w.PROMPT)
        self.assertIn('"perguntar"', w.PROMPT)

    def test_o_prompt_tem_o_roteiro(self):
        for pedaco in ("Até que valor?", "Quais bairros", "serve 2 quartos", "escada", "simulação de financiamento",
                       "Vou pegar as opções no meu sistema", "Dar negativa"):
            self.assertIn(pedaco, w.PROMPT)


if __name__ == "__main__":
    unittest.main()
