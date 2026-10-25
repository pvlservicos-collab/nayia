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
        # 21/10: o card de novo, para ela apontar o imóvel da visita sem o código
        self.assertEqual(w.acoes_da({"acoes": ["card", "visita"]}), ["card", "visita"])

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
        self.assertIsNone(w.que_seguimento(self.CARLOS, c))        # prometeu as fotos e elas ainda não saíram
        self.assertEqual(w.que_seguimento(self.CARLOS, c, entregou_depois=True),
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


class UmaConfirmacaoSo(unittest.TestCase):
    """394 (16/10): o Felipe recebeu três "vou separar" e nenhum imóvel; a Michelle, "Obrigada" e outra confirmação."""

    def test_so_agradeceu(self):
        for t in (["Obrigada"], ["Fico no aguardo então. Obrigada"[:0] + "Fico no aguardo"], ["ok", "obrigado 🙏"], ["Aguardo"],
                  ["Tá bom"], ["Valeu!"]):
            self.assertTrue(w.so_agradeceu(t), t)
        for t in (["Obrigada, e tem fotos da cozinha?"], ["Pode sim"], ["14h"], [""], []):
            self.assertFalse(w.so_agradeceu(t), t)

    def test_visita_e_sim_no_mesmo_turno(self):
        self.assertEqual(w.acoes_da({"acoes": ["visita", "confirmou_visita"]}), ["visita"])

    def test_codigo_da_pergunta(self):
        lead = {"codigo": 3883}
        self.assertEqual(w.codigo_da_pergunta(lead, "o 9026 aceita pet?"), 9026)
        self.assertIsNone(w.codigo_da_pergunta(lead, "fotos dos quartos do 9026, 9037 e 5724"))
        self.assertEqual(w.codigo_da_pergunta(lead, "a localização exata"), 3883)

    def test_afrouxar(self):
        f = {"finalidade": "venda", "tipo": "casa_condominio", "teto": 900000, "bairros": ["Flores"], "quartos": 3,
             "mobilia": "mobiliado"}
        passos = w._afrouxar(f)
        self.assertEqual(passos[0], (f, False))
        # 24/10 (a Esther): a mobília NÃO afrouxa; mobiliado é mobiliado em todos os passos
        self.assertTrue(all(g["mobilia"] == "mobiliado" for g, _ in passos))
        self.assertTrue(passos[1][0]["aceita_menos_quartos"])
        self.assertEqual(passos[2][0]["bairros"], [])
        self.assertEqual(passos[3][0]["teto"], 1080000)
        self.assertEqual(len(passos), 4)

    def test_a_necessidade_cresce_e_nao_se_perde(self):
        # 24/10 (Pedro, a Esther): cada coisa nova entra e fica
        f = w._filtros({"teto": 4000, "mobilia": "mobiliado", "exigencias": ["cozinha completa"]},
                       {"perto_de": "Distrito Industrial", "pet": "2 gatas", "exigencias": ["lavanderia completa", "cozinha completa"]})
        self.assertEqual(f["mobilia"], "mobiliado")
        self.assertEqual(f["perto_de"], "Distrito Industrial")
        self.assertEqual(f["pet"], "2 gatas")
        self.assertEqual(f["exigencias"], ["cozinha completa", "lavanderia completa"])
        # o modelo esquece de repetir: nada some
        g = w._filtros(f, {"teto": 3900, "exigencias": [], "perto_de": ""})
        self.assertEqual((g["teto"], g["perto_de"], g["pet"], g["exigencias"]), (3900, "Distrito Industrial", "2 gatas", f["exigencias"]))

    def test_perto_e_distancia_do_banco(self):
        from unittest import mock
        achados = [{"bairro": "Aleixo", "codigo": 1}, {"bairro": "Ponta Negra", "codigo": 2}, {"bairro": "Sem Coordenada", "codigo": 3}]
        km = {"Aleixo": 5.0, "Ponta Negra": 16.0}
        with mock.patch.object(w, "distancias_km", return_value=km):
            self.assertEqual([a["codigo"] for a in w.so_perto(None, achados, {"perto_de": "Distrito"})], [1])
            self.assertEqual([a["codigo"] for a in w.so_perto(None, achados, {"perto_de": "Distrito", "perto_km": 20})], [1, 2])
            self.assertEqual(len(w.so_perto(None, achados, {})), 3)                      # sem perto_de não filtra
        with mock.patch.object(w, "distancias_km", return_value={}):                    # lugar que não é bairro: não filtra
            self.assertEqual(len(w.so_perto(None, achados, {"perto_de": "Shopping"})), 3)

    def test_resposta_do_revisor_curta(self):
        # 24/10 (a Esther recebeu um balão enorme com sugestões e uma distância errada)
        longa = ("Sra. Esther, conferi aqui: não tenho nenhum imóvel com aceitação de pet já confirmada, porque essa informação "
                 "depende do proprietário. Das mobiliadas com condomínio incluso e até R$ 4.000 que ainda não te mostrei, a mais "
                 "fora de Ponta Negra é o Ariranhas (código 5729), no bairro Da Paz. Não sei dizer a distância dele até o Distrito.")
        self.assertEqual(w.resposta_curta("Fica tudo, sim.", lambda p, u: 1 / 0), "Fica tudo, sim.")      # curta: nem chama o modelo
        self.assertEqual(w.resposta_curta(longa, lambda p, u: {"texto": w.SEM_INFORMACAO}), w.SEM_INFORMACAO)
        self.assertEqual(w.texto_da_resposta({"codigo": 2944, "imovel": "Maison Rochelle", "resposta": "Fica tudo, sim."}),
                         "Sobre o #2944 (Maison Rochelle): Fica tudo, sim.")
        self.assertLessEqual(len(w.resposta_curta(longa, lambda p, u: 1 / 0)), 240)                      # sem modelo: 2 frases

    def test_nao_achou_responde_curto(self):
        self.assertEqual(w.CONTINUO_VERIFICANDO, "Entendi, por enquanto ainda procurando opções.")

    def test_fecho_das_mais_proximas(self):
        self.assertTrue(w.fecho({"nome": "Felipe", "trat": "Sr."}, 3, proximas=True)
                        .startswith("Essas são as opções mais próximas do que o senhor procura."))

    def test_valor_nao_e_codigo(self):
        c = [{"direcao": "recebida", "texto": "apartamento até 2500, uns 3000 no máximo, aluguel de 2800 e o 5758"}]
        self.assertEqual(w.codigos_citados(c), [5758])

    def test_filtros_qualquer_bairro_e_teto(self):
        f = w._filtros({"bairros": ["Flores"], "teto": 900000}, {"qualquer_bairro": True, "teto": "R$ 1.000.000"})
        self.assertEqual(f["bairros"], [])
        self.assertEqual(f["teto"], 1000000)

    def test_um_balao_quando_busca(self):
        self.assertEqual(w._baloes_do({"baloes": "um texto solto"}), ["um texto solto"])


class RespostaDaFila(unittest.TestCase):
    """391: a resposta do Tel na fila de perguntas, como chega ao cliente."""

    def test_com_codigo_e_imovel(self):
        self.assertEqual(w.texto_da_resposta({"codigo": 9026, "imovel": "Turim Residencial", "resposta": "fica tudo,  sim"}),
                         "Sobre o #9026 (Turim Residencial): Fica tudo, sim")

    def test_sem_codigo(self):
        self.assertEqual(w.texto_da_resposta({"codigo": None, "imovel": None, "resposta": "pode sim"}),
                         "Sobre a sua pergunta: Pode sim")



class TestMobiliaNoRoteiro(unittest.TestCase):
    """19/10: a locação residencial pergunta mobiliado / modulados e ar / tanto faz, e o resumo guarda a resposta."""

    def test_pergunta_no_roteiro(self):
        self.assertIn("prefere mobiliado, só com modulados e ar-condicionado, ou", w.PROMPT)
        self.assertIn('"tanto_faz" = ela disse que', w.PROMPT)

    def test_resumo_leva_a_mobilia(self):
        self.assertIn("modulados e ar", w._resumo_dos_filtros({"finalidade": "locacao", "mobilia": "semi"}))
        self.assertIn("mobília tanto faz", w._resumo_dos_filtros({"mobilia": "tanto_faz"}))
        self.assertNotIn("mob", w._resumo_dos_filtros({"finalidade": "venda"}))

    def test_tanto_faz_fica_guardado(self):
        self.assertEqual(w._filtros({}, {"mobilia": "tanto_faz"})["mobilia"], "tanto_faz")

if __name__ == "__main__":
    unittest.main()


class Parceiro(unittest.TestCase):
    """400 (Pedro, 17/10): imóvel de parceiro vai ao cliente final do 8595, nunca a corretor; ela não diz "parceiro"."""
    def test_pergunta_ao_banco_com_o_telefone(self):
        from unittest import mock
        with mock.patch.object(w.banco, "um", return_value=True) as um:
            self.assertTrue(w._ofertavel(None, 5553, {"telefone": "92999990000"}))
            self.assertEqual(um.call_args[0][1:], ("SELECT olx_imovel_vai_ao_cliente(%s, %s)", (5553, "92999990000")))
            w._ofertavel(None, 5553)
            self.assertEqual(um.call_args[0][2], (5553, None))       # sem pessoa: parceiro não sai

    def test_sem_telefone_nao_aceita(self):
        self.assertFalse(w._aceita_parceiro(None, {"telefone": ""}))

    def test_o_prompt_proibe_a_palavra(self):
        self.assertIn('"de parceiro"', w.PROMPT)

    def test_o_prompt_nao_pede_o_codigo(self):
        # 21/10 (Pedro): "tira para pedir esse código do imóvel que os clientes não entendem"
        self.assertIn("NUNCA peça o código do imóvel", w.PROMPT)
        self.assertIn("Pedir o código do imóvel", w.PROMPT)


class EquipeJaRespondeu(unittest.TestCase):
    """22/10 (Eudes): "Qual andar?" 09:31, o Tel respondeu 09:32, e às 10:02 a Nay respondeu de novo."""

    def test_o_que_veio_antes_da_equipe_ja_foi_respondido(self):
        from datetime import datetime, timezone
        t = lambda h, m: datetime(2026, 10, 22, h, m, tzinfo=timezone.utc)  # noqa: E731
        conversa = [{"id": 10, "direcao": "recebida", "texto": "Sim", "criada_em": t(13, 30)},
                    {"id": 11, "direcao": "recebida", "texto": "Qual andar?", "criada_em": t(13, 31)},
                    {"id": 0, "direcao": "enviada", "origem": "equipe_crm", "texto": "é andar baixo", "criada_em": t(13, 32)}]
        self.assertEqual(w.novas_depois_da_equipe(conversa, 9, t(13, 32)), [])
        depois = conversa + [{"id": 12, "direcao": "recebida", "texto": "Com quem eu vou", "criada_em": t(14, 33)}]
        self.assertEqual([m["id"] for m in w.novas_depois_da_equipe(depois, 9, t(13, 32))], [12])
        self.assertEqual([m["id"] for m in w.novas_depois_da_equipe(conversa, 9, None)], [10, 11])


class FinalidadePeloValor(unittest.TestCase):
    """22/10 (…6380): "até R$ 1.000.000" e ela perguntou "Você procura para comprar ou alugar?"."""

    def test_o_valor_diz(self):
        pergunta = ["Certo, apartamento em Adrianópolis até R$ 1.000.000. Você procura para comprar ou alugar?"]
        self.assertEqual(w.finalidade_pelo_valor({"baloes": pergunta, "filtros": {"teto": 1000000}}), "venda")
        self.assertEqual(w.finalidade_pelo_valor({"baloes": ["Seria para alugar ou comprar?"], "filtros": {"teto": 3500}}), "locacao")

    def test_sem_a_pergunta_ou_valor_do_meio_nao_mexe(self):
        self.assertIsNone(w.finalidade_pelo_valor({"baloes": ["Quais bairros te atendem?"], "filtros": {"teto": 1000000}}))
        self.assertIsNone(w.finalidade_pelo_valor({"baloes": ["Seria para alugar ou comprar?"], "filtros": {"teto": 60000}}))
        self.assertIsNone(w.finalidade_pelo_valor({"baloes": ["Seria para alugar ou comprar?"], "filtros": {}}))


class QuartosQueElaDisse(unittest.TestCase):
    """22/10 (…6380): "Quantos quartos?" -> "3" -> "Se aparecer um apartamento de 2 quartos, também serve?"."""

    def test_ela_disse_e_o_modelo_perguntou_se_serve_menos(self):
        conversa = [{"direcao": "enviada", "texto": "Quantos quartos você procura?"}, {"direcao": "recebida", "texto": "3"}]
        r = {"baloes": ["Anotei. Se aparecer um apartamento de 2 quartos, também serve?"], "filtros": {"quartos": 3}}
        self.assertEqual(w.quartos_que_ela_disse(r, conversa), 3)
        self.assertIn("NÃO pergunte se serve menos quartos", w.pergunta_a_toa(r, conversa))

    def test_do_anuncio_pode_perguntar(self):
        # os 3 quartos vieram do anúncio: ela não disse o número, a pergunta vale
        conversa = [{"direcao": "recebida", "texto": "quero outras opções"}]
        r = {"baloes": ["Serve 2 quartos também?"], "filtros": {"quartos": 3}}
        self.assertIsNone(w.quartos_que_ela_disse(r, conversa))
        self.assertEqual(w.pergunta_a_toa({"baloes": ["Quais bairros?"], "filtros": {"teto": 900000}}, conversa), "")
