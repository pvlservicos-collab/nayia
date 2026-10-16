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


class Organico(unittest.TestCase):
    """390 (16/10): quem escreveu direto no 8595-6408, sem OLX."""
    LEAD = {"id": 9, "chat": None, "origem": "organico", "nome": None, "trat": None, "telefone": "92982508556",
            "codigo": None, "negocio": None, "etapa": "filtrar", "perfil": {}, "filtros": {}, "enviados": []}

    def test_turno_sem_olx(self):
        t = w.montar_turno(self.LEAD, None, [{"direcao": "recebida", "texto": "Boa tarde"}])
        self.assertIn("ORGÂNICO", t)
        self.assertNotIn("O ANÚNCIO NA OLX", t)
        self.assertIn("primeira mensagem (a abertura do orgânico)", t)
        self.assertIn("CLIENTE: Boa tarde", t)

    def test_depois_da_abertura_nao_abre_de_novo(self):
        t = w.montar_turno(self.LEAD, None, [{"direcao": "recebida", "texto": "Boa tarde"},
                                             {"direcao": "enviada", "nossa": True, "texto": "Boa tarde! Aqui é a Nay."}])
        self.assertNotIn("abertura do orgânico", t)

    def test_finalidade_pelo_valor(self):
        self.assertEqual(w.finalidade_sem_dizer(self.LEAD, {"teto": 2500}), "locacao")
        self.assertEqual(w.finalidade_sem_dizer(self.LEAD, {"teto": 450000}), "venda")
        self.assertEqual(w.finalidade_sem_dizer({"negocio": "locacao"}, {"teto": 450000}), "locacao")

    def test_codigos_que_ela_citou(self):
        conversa = [{"direcao": "recebida", "texto": "Gostaria de agendar uma visita"},
                    {"direcao": "enviada", "texto": "Qual imóvel? 9999"},
                    {"direcao": "recebida", "texto": "5758"},
                    {"direcao": "recebida", "texto": "até 2500 reais, ou 3000 mil, R$ 1500 e o #9045"}]
        self.assertEqual(w.codigos_citados(conversa), [9045, 5758])

    def test_ficha_citada_no_turno(self):
        lead = {**self.LEAD, "fichas_citadas": [{"codigo": 5758, "bairro": "Ponta Negra"}]}
        self.assertIn("Ficha do imóvel 5758 (o que ela citou)", w.montar_turno(lead, None, []))

    def test_aviso_diz_de_onde_veio(self):
        self.assertIn("(orgânico, ", w.quem(self.LEAD))
        self.assertIn("(OLX, ", w.quem({**self.LEAD, "origem": "olx", "nome": "Josy"}))


class Seguimento(unittest.TestCase):
    """392: o acompanhamento depois de ~10 min de silêncio."""

    def test_so_um_imovel(self):
        self.assertEqual(w.texto_do_seguimento({"nome": "Carlos Eduardo", "trat": "Sr.", "enviados": []}),
                         "Sr. Carlos, posso estar enviando outras opções semelhantes para o senhor?")
        self.assertEqual(w.texto_do_seguimento({"nome": None, "trat": None, "enviados": []}),
                         "Posso estar enviando outras opções semelhantes para você?")

    def test_depois_das_opcoes(self):
        self.assertTrue(w.texto_do_seguimento({"nome": "Michelle", "trat": "Sra.", "enviados": [9026]})
                        .startswith("Sra. Michelle, conseguiu ver as opções"))


class NuncaRepetir(unittest.TestCase):
    """392b (16/10): o Carlos recebeu "posso estar enviando outras opções semelhantes?" três vezes."""
    CARLOS = {"nome": "Carlos Eduardo", "trat": "Sr.", "enviados": []}

    @staticmethod
    def conv(*pares):
        return [{"direcao": "recebida" if d == "c" else "enviada", "texto": t} for d, t in pares]

    def test_o_dia_do_carlos(self):
        c = self.conv(("c", "Vc teria fotos dele?"), ("n", "Claro, Sr. Carlos. Vou separar as fotos do apartamento e já envio."))
        self.assertEqual(w.que_seguimento(self.CARLOS, c),
                         "Sr. Carlos, posso estar enviando outras opções semelhantes para o senhor?")
        c += self.conv(("n", "Sr. Carlos, posso estar enviando outras opções semelhantes para o senhor?"),
                       ("c", "Eu só tô aguardando você me falar a questão do valor"),
                       ("n", "Sr. Carlos, ainda estou aguardando a confirmação da equipe sobre o menor valor. Assim que me "
                             "responderem, retorno por aqui."))
        self.assertIsNone(w.que_seguimento(self.CARLOS, c))          # promessa: espera (16:41)
        c += self.conv(("c", "Pode sim"),
                       ("n", "Perfeito, Sr. Carlos. Até que valor de aluguel por mês o senhor procura?"))
        self.assertIsNone(w.que_seguimento(self.CARLOS, c))          # pergunta: espera (16:53)

    def test_oferta_so_uma_vez(self):
        c = self.conv(("n", "Sr. Carlos, posso estar enviando outras opções semelhantes para o senhor?"), ("c", "ok"),
                      ("n", "Combinado, Sr. Carlos."))
        self.assertIsNone(w.que_seguimento(self.CARLOS, c))

    def test_depois_das_opcoes_e_da_promessa(self):
        mi = {"nome": "Michelle", "trat": "Sra.", "enviados": [9026]}
        fecho = self.conv(("c", "obrigada"), ("n", "Essas são as opções que separei. Alguma chamou a atenção da senhora? "
                                                  "Posso agendar uma visita ou procurar mais opções."))
        self.assertTrue(w.que_seguimento(mi, fecho).startswith("Sra. Michelle, conseguiu ver as opções"))
        self.assertIsNone(w.que_seguimento(mi, self.conv(
            ("c", "Obrigada"), ("n", "Imagina, Sra. Michelle. Já reforcei com a equipe. Assim que tiver um retorno, aviso por aqui."))))

    def test_balao_e_pergunta_repetidos(self):
        ja = ["Perfeito, Sr. Carlos. Enquanto confirmo com a equipe, vou procurar opções. Até que valor de aluguel por mês o "
              "senhor procura?"]
        self.assertEqual(w.sem_repetir(["Certo, Sr. Carlos! Até que valor de aluguel por mês o senhor procura?"], ja), [])
        self.assertEqual(w.sem_repetir(["Anotei os 2 quartos. Até que valor de aluguel o senhor procura por mês?",
                                        "E quais bairros atendem o senhor?"], ja),
                         ["Anotei os 2 quartos.", "E quais bairros atendem o senhor?"])
        self.assertEqual(w.sem_repetir([ja[0]], ja), [])

    def test_mesmo_assunto_na_fila(self):
        self.assertTrue(w._mesmo_assunto(
            "Qual o menor valor do aluguel? E fica tudo como nas fotos (televisão, geladeira, sofá, cama)?",
            "Confirmar o menor valor do aluguel e se televisão, geladeira, sofá e cama ficam no apartamento 9026."))
        self.assertFalse(w._mesmo_assunto("Aceita pet?", "Qual o menor valor do aluguel?"))


class RespostaDaFila(unittest.TestCase):
    """391: a resposta do Tel na fila de perguntas, como chega ao cliente."""

    def test_com_codigo_e_imovel(self):
        self.assertEqual(w.texto_da_resposta({"codigo": 9026, "imovel": "Turim Residencial", "resposta": "fica tudo,  sim"}),
                         "Sobre o #9026 (Turim Residencial): Fica tudo, sim")

    def test_sem_codigo(self):
        self.assertEqual(w.texto_da_resposta({"codigo": None, "imovel": None, "resposta": "pode sim"}),
                         "Sobre a sua pergunta: Pode sim")


if __name__ == "__main__":
    unittest.main()
