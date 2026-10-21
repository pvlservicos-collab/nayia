"""As partes puras da Nay de captação em Python: o turno, o portão de saída e o laço do agente.

    python -m unittest discover -s tests        (na pasta nay-captacao)

Os casos vêm do que o fluxo do n8n já fazia (os comentários dos nós contam cada erro que virou regra).
"""
import random
import sys
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from captacao import cadastro, config, contrato, modelo, resposta, turno, venda  # noqa: E402

LEAD = {"telefone": "5596991712835", "lead_id": 835, "nome": "PEDRO Silva", "tratamento": "Sr.", "imovel_desc": "Apartamento (TESTE)",
        "etapa": "aguardando_situacao", "prompt": "PROMPT"}


def msg(i, texto=None, origem="texto", **mais):
    return {"id": i, "texto": texto, "origem": origem, **LEAD, **mais}


class Turno(unittest.TestCase):
    def test_junta_o_intervalo_e_arruma_o_nome(self):
        t = turno.juntar([msg(2, "até março"), msg(1, "tá alugado")])
        self.assertEqual(t.texto, "tá alugado\naté março")
        self.assertEqual((t.nome, t.qtd, t.ids), ("Pedro", 2, [1, 2]))

    def test_toque_no_botao_e_um_turno_normal(self):
        t = turno.juntar([msg(1, "Disponível")])
        self.assertEqual(t.texto, "Disponível")
        self.assertFalse(t.pediu_parar)

    def test_figurinha_sozinha_nao_vira_turno(self):
        self.assertIsNone(turno.juntar([msg(1, None, "figurinha")]))

    def test_foto_sozinha_segue_o_atendimento_sem_falar_da_foto(self):
        t = turno.juntar([msg(1, None, "imagem")])
        self.assertIn("refazendo em uma linha a ultima pergunta", t.texto)
        self.assertIn("NAO diga que nao consegue ver", t.texto)
        self.assertIn("mandou uma imagem", t.aviso_ao_tel)

    def test_segunda_rodada_de_foto_fica_calada_mas_avisa(self):
        t = turno.juntar([msg(1, None, "imagem", ja_seguiu_depois_de_foto=True)])
        self.assertEqual(t.texto, "")
        self.assertIn("ja tinha seguido", t.aviso_ao_tel)

    def test_foto_com_a_ficha_aberta_na_pergunta_das_fotos(self):
        t = turno.juntar([msg(1, None, "imagem", ficha="a ultima pergunta foi sobre as fotos do imovel")])
        self.assertIn('guardar_ficha com fotos = "recebidas"', t.texto)

    def test_pediu_para_parar_sai_marcado(self):
        self.assertTrue(turno.juntar([msg(1, "não quero mais receber isso")]).pediu_parar)
        self.assertTrue(turno.juntar([msg(1, "número errado")]).pediu_parar)

    def test_cabecalho_tem_o_que_o_prompt_espera(self):
        t = turno.juntar([msg(1, "Alugado", situacao=None, pergunta_pendente="qual é a situação?")])
        c = turno.cabecalho(t, datetime(2026, 10, 8, 20, 30, tzinfo=timezone.utc))
        self.assertIn("agora em Manaus é quinta-feira 08/10/2026 16:30.", c)
        self.assertIn("o proprietário é Sr. Pedro.", c)
        self.assertIn("a pergunta que ficou aberta com ele foi: qual é a situação?.", c)
        self.assertTrue(c.endswith("mensagem do proprietário: Alugado"))

    def test_sem_tratamento_nao_chuta_sr(self):
        t = turno.juntar([msg(1, "oi", tratamento=None)])
        self.assertIn("tratamento desconhecido", turno.cabecalho(t, datetime.now(timezone.utc)))


class Resposta(unittest.TestCase):
    def test_emoji_nunca_sai(self):
        self.assertEqual(resposta.limpar("Você está bem-vinda! 😊"), "Você está bem-vinda!")

    def test_silencio_nao_vira_mensagem(self):
        for s in ("SILENCIO", "silêncio.", " *Silencio* "):
            self.assertEqual(resposta.baloes(s), [])

    def test_promessa_de_retorno_do_tel_e_cortada(self):
        self.assertEqual(resposta.limpar("Vou passar para o Tel e ele te retorna."), "")
        self.assertEqual(resposta.limpar("Anotado, Sr. João. Vou verificar e já te retorno."), "Anotado, Sr. João.")
        self.assertEqual(resposta.limpar("Trabalho com o Tel, na Imob Easy."), "Trabalho com o Tel, na Imob Easy.")

    def test_nunca_diz_que_nao_ve_a_imagem(self):
        self.assertEqual(resposta.limpar("Não consigo abrir a imagem por aqui. Até quando vai o contrato?"),
                         "Até quando vai o contrato?")

    def test_ate_tres_baloes_e_a_pergunta_fica_no_ultimo(self):
        bs = resposta.baloes("Maravilha, Sr. Pedro!\n\nQual o valor?\n\nObrigada.\n\nQuarto balão", random.Random(1))
        self.assertEqual([b.texto for b in bs], ["Maravilha, Sr. Pedro!", "Qual o valor?", "Obrigada."])
        self.assertEqual([b.pergunta for b in bs], [None, None, "Qual o valor?"])
        self.assertTrue(3 <= bs[0].pausa <= 7 and 4 <= bs[1].pausa <= 9)

    def test_o_que_anotou_e_a_pergunta_saem_em_duas_mensagens(self):
        bs = resposta.baloes("Certo, anotei aqui. Quantos quartos (e quantas suítes), banheiros e vagas de garagem ele tem?")
        self.assertEqual([b.texto for b in bs],
                         ["Certo, anotei aqui.", "Quantos quartos (e quantas suítes), banheiros e vagas de garagem ele tem?"])
        self.assertEqual(bs[-1].pergunta, "Quantos quartos (e quantas suítes), banheiros e vagas de garagem ele tem?")

    def test_duas_mensagens_sem_quebrar_o_sr_nem_o_valor(self):
        self.assertEqual(
            [b.texto for b in resposta.baloes("Perfeito, Sr. Pedro. Anotei R$ 2.500,00. O Sr. tem algum outro imóvel?")],
            ["Perfeito, Sr. Pedro. Anotei R$ 2.500,00.", "O Sr. tem algum outro imóvel?"])

    def test_pergunta_sozinha_ou_na_frente_sai_inteira(self):
        for s in ("Qual o valor do aluguel?", "Qual o valor do aluguel? Pode ser aproximado.", "Obrigada, Sra. Ana. Bom dia!"):
            self.assertEqual([b.texto for b in resposta.baloes(s)], [s])

    def test_duas_perguntas_ficam_juntas_depois_do_que_anotou(self):
        self.assertEqual([b.texto for b in resposta.baloes("Anotado. Ele tem elevador? E portaria 24 horas?")],
                         ["Anotado.", "Ele tem elevador? E portaria 24 horas?"])

    def test_nunca_passa_de_tres_mensagens(self):
        bs = resposta.baloes("Oi.\n\nTudo bem.\n\nCerto, anotei. Qual o valor?")
        self.assertEqual([b.texto for b in bs], ["Oi.", "Tudo bem.", "Certo, anotei. Qual o valor?"])
        self.assertEqual(len(resposta.baloes("Oi.\n\nCerto, anotei. Qual o valor?")), 3)


class Agente(unittest.TestCase):
    def test_roda_a_ferramenta_e_devolve_a_ultima_fala(self):
        pedidos, usadas = [], []

        def chamar(corpo):
            pedidos.append(corpo)
            if len(pedidos) == 1:
                return {"id": "r1", "output": [{"type": "function_call", "name": "guardar_situacao", "call_id": "c1",
                                                "arguments": '{"situacao": "alugado", "prazo": "", "valor": ""}'}]}
            return {"id": "r2", "output": [{"type": "message", "content": [{"type": "output_text", "text": "Até quando vai o contrato?"}]}]}

        def executar(nome, args):
            usadas.append((nome, args))
            return '[{"instrucao": "gravado"}]'

        texto, feito = modelo.responder("PROMPT", [{"role": "assistant", "content": "modelo"}], "turno", [], executar, chamar)
        self.assertEqual(texto, "Até quando vai o contrato?")
        self.assertEqual(usadas, [("guardar_situacao", {"situacao": "alugado", "prazo": "", "valor": ""})])
        self.assertEqual(feito[0]["args"], {"situacao": "alugado"})
        self.assertEqual(pedidos[0]["input"][0], {"role": "system", "content": "PROMPT"})
        self.assertEqual(pedidos[1]["previous_response_id"], "r1")
        self.assertEqual(pedidos[1]["input"], [{"type": "function_call_output", "call_id": "c1", "output": '[{"instrucao": "gravado"}]'}])

    def test_laco_sem_fim_de_ferramenta_vira_falha(self):
        def chamar(corpo):
            return {"id": "r", "output": [{"type": "function_call", "name": "dados_do_lead", "call_id": "c", "arguments": "{}"}]}
        with self.assertRaises(modelo.FalhaDoModelo):
            modelo.responder("P", [], "t", [], lambda n, a: "x", chamar)

    def test_o_acrescimo_leva_o_modelo_e_a_indicacao(self):
        frase = ("Sra. Maria, estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, "
                 "a Sra. teria alguém para indicar que queira alugar ou vender?")
        a = (modelo.ACRESCIMO.replace("{modelo}", "Olá, Sr. Pedro!").replace("{indicacao}", frase)
             .replace("{honorarios}", modelo.HONORARIOS_COM_VALOR.replace("{frase}", "no valor de R$ 350.000 ... 6%?")))
        self.assertIn('"Olá, Sr. Pedro!"', a)
        self.assertIn("TOCOU NO BOTAO", a)
        self.assertIn("guardar_indicacao", a)
        self.assertIn('"' + frase + '"', a)
        self.assertIn("guardar_honorarios", a)
        self.assertNotIn("{", a)

    def test_a_frase_da_indicacao_sai_inteira_numa_mensagem(self):
        frase = ("Sra. Maria, estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, "
                 "a Sra. teria alguém para indicar que queira alugar ou vender?")
        self.assertEqual([b.texto for b in resposta.baloes(frase)], [frase])
        self.assertEqual([b.texto for b in resposta.baloes("Certo, obrigada. " + frase)], ["Certo, obrigada.", frase])


class _Resposta:
    def __init__(self, status=200, content=b"", corpo=None):
        self.status_code, self.content, self._corpo = status, content, corpo
        self.headers = {"content-type": "application/json"}

    def json(self):
        return self._corpo


class Cadastro(unittest.TestCase):
    def test_a_foto_da_conversa_vai_para_a_api_do_site_com_o_codigo_e_o_id(self):
        idas = []

        class Pedir:
            @staticmethod
            def get(url, timeout):
                return _Resposta(200, b"\xff\xd8\xff" + b"0" * 2000)

            @staticmethod
            def post(url, data, timeout, headers):
                idas.append((url, len(data), headers["x-foto-id"]))
                return _Resposta(200, corpo={"ok": True})

        config.FOTO_SEGREDO = "s"
        self.assertIsNone(cadastro._trazer(3755, "capt60_ABC", "https://imobeasy.online/fotos-captacao/whatsapp/60/ABC.jpg", Pedir))
        self.assertEqual(idas, [(config.SITE_API_URL + "/api/captacao/crm/imovel/3755/foto", 2003, "capt60_ABC")])

    def test_foto_que_nao_baixa_ou_que_o_site_recusa_vira_erro_escrito(self):
        class NaoBaixa:
            @staticmethod
            def get(url, timeout):
                return _Resposta(404, b"")

        class Recusa:
            @staticmethod
            def get(url, timeout):
                return _Resposta(200, b"0" * 5000)

            @staticmethod
            def post(url, data, timeout, headers):
                return _Resposta(400, corpo={"ok": False, "erro": "o arquivo não é jpg, png nem webp"})

        self.assertIn("não baixei (HTTP 404", cadastro._trazer(1, "x", "u", NaoBaixa))
        self.assertIn("o arquivo não é jpg", cadastro._trazer(1, "x", "u", Recusa))


class Contrato(unittest.TestCase):
    """325: o contrato dito como começo + duração (Pedro, 09/10)."""
    HOJE = date(2026, 10, 9)

    def test_a_duracao_em_meses(self):
        for dito, meses in [("24 meses", 24), ("2 anos", 24), ("dois anos", 24), ("um ano e meio", 18), ("36", 36),
                            ("é contrato de dois anos", 24), ("trinta e seis meses", 36), ("1 ano", 12)]:
            self.assertEqual(contrato.meses_da_duracao(dito), meses, dito)
        self.assertIsNone(contrato.meses_da_duracao("não sei"))

    def test_o_comeco_sem_o_ano_e_a_ultima_vez_que_o_mes_passou(self):
        self.assertEqual(contrato.inicio_do_contrato("foi alugado em fevereiro ou março", self.HOJE), (2026, 2))
        self.assertEqual(contrato.inicio_do_contrato("novembro", self.HOJE), (2025, 11))
        self.assertEqual(contrato.inicio_do_contrato("em março do ano passado", self.HOJE), (2025, 3))
        self.assertEqual(contrato.inicio_do_contrato("julho de 24", self.HOJE), (2024, 7))

    def test_dez_meses_nao_e_dezembro_e_comeco_no_futuro_nao_vale(self):
        self.assertIsNone(contrato.inicio_do_contrato("há dez meses", self.HOJE))
        self.assertIsNone(contrato.inicio_do_contrato("dezembro de 2027", self.HOJE))
        self.assertIsNone(contrato.inicio_do_contrato("início do ano", self.HOJE))

    def test_com_os_dois_sai_o_prazo_do_jeito_que_o_banco_le(self):
        prazo, pergunta = contrato.prazo_ou_pergunta("foi alugado em fevereiro ou março", "contrato de dois anos", self.HOJE)
        self.assertEqual(prazo, "fevereiro de 2028 (começou em fev/2026, 24 meses)")
        self.assertIsNone(pergunta)
        self.assertLessEqual(len(prazo), 60)          # o fluxo recusa prazo com mais de 60 letras

    def test_so_o_comeco_pede_a_duracao_e_so_a_duracao_pede_o_comeco(self):
        prazo, pergunta = contrato.prazo_ou_pergunta("fevereiro", "", self.HOJE)
        self.assertIsNone(prazo)
        self.assertIn(contrato.PERGUNTA_DA_DURACAO, pergunta)
        prazo, pergunta = contrato.prazo_ou_pergunta("início do ano", "24 meses", self.HOJE)
        self.assertIsNone(prazo)
        self.assertIn(contrato.PERGUNTA_DO_COMECO, pergunta)


class ImovelDeVenda(unittest.TestCase):
    """12/10: o disparo foi para donos de imóvel à VENDA e a Nay pedia "o valor para locação" (venda.py)."""

    DO_FLUXO = ('gravado. situacao: disponivel. prazo: -. valor da locacao: -. proxima etapa: aguardando_valor. agora peca o '
                'valor atualizado da locacao, uma pergunta so, assim: "Sr. Júlio Oliveira, o Sr. pode me atualizar o valor do '
                'imovel para locacao?". NAO comente se o valor esta bom, alto ou baixo.')

    class Banco:
        def __init__(self, linhas):
            self.resposta = linhas

        def linhas(self, conn, sql, params=None):
            return self.resposta

    def test_o_valor_sai_como_gente_escreve(self):
        self.assertEqual(venda.reais(580000), "R$ 580.000")
        self.assertEqual(venda.reais(1250000.5), "R$ 1.250.000,50")
        self.assertEqual(venda.reais("310000.00"), "R$ 310.000")

    def test_a_pergunta_confirma_o_valor_do_cadastro_no_tratamento_dele(self):
        self.assertEqual(venda.pergunta("Sr.", "Júlio Oliveira", 580000),
                         "Sr. Júlio, aqui no nosso cadastro o imóvel está à venda por R$ 580.000. Esse valor continua?")
        self.assertEqual(venda.pergunta(None, "VIVIAN souza", 310000),
                         "Vivian, aqui no nosso cadastro o imóvel está à venda por R$ 310.000. Esse valor continua?")
        self.assertTrue(venda.pergunta(None, None, 310000).startswith("Aqui no nosso cadastro"))

    def test_imovel_de_venda_troca_o_pedido_da_locacao(self):
        v = venda.do_cadastro(None, self.Banco([{"valor_venda": 580000, "tratamento": "Sr.", "nome": "Júlio Oliveira"}]), "5592")
        saida = venda.no_lugar_da_locacao([{"instrucao_para_voce": self.DO_FLUXO}], v)[0]["instrucao_para_voce"]
        self.assertNotIn("para locacao?", saida)
        self.assertNotIn("valor atualizado da locacao", saida)
        self.assertIn("gravado. situacao: disponivel", saida)
        self.assertIn('"Sr. Júlio, aqui no nosso cadastro o imóvel está à venda por R$ 580.000. Esse valor continua?"', saida)
        self.assertIn('guardar_venda com valor = "R$ 580.000"', saida)

    def test_locacao_e_imovel_fora_do_cadastro_ficam_como_estao(self):
        self.assertIsNone(venda.do_cadastro(None, self.Banco([]), "5592"))
        linhas = [{"instrucao_para_voce": self.DO_FLUXO}]
        self.assertEqual(venda.no_lugar_da_locacao(linhas, None)[0]["instrucao_para_voce"], self.DO_FLUXO)
        self.assertEqual(venda.secao(None), "")

    def test_outra_instrucao_do_fluxo_nao_e_tocada(self):
        v = {"valor": "R$ 580.000", "frase": "x"}
        alugado = "gravado. situacao: alugado. proxima etapa: aguardando_prazo. agora pergunte ate quando vai o contrato de locacao."
        self.assertEqual(venda.no_lugar_da_locacao([{"instrucao_para_voce": alugado}], v)[0]["instrucao_para_voce"], alugado)

    def test_sem_imovel_ligado_pergunta_venda_ou_locacao_em_vez_de_presumir(self):
        s = venda.sem_imovel(None, self.Banco([{"tratamento": "Sra.", "nome": "MARIA das Graças"}]), "5592")
        self.assertEqual(s["frase"], "Sra. Maria, o imóvel é para venda ou para locação?")
        saida = venda.no_lugar_da_locacao([{"instrucao_para_voce": self.DO_FLUXO}], None, s)[0]["instrucao_para_voce"]
        self.assertIn('"Sra. Maria, o imóvel é para venda ou para locação?"', saida)
        self.assertIn("guardar_venda (sem valor)", saida)
        # a pergunta da locação continua lá, mas só para depois de ele dizer LOCACAO
        self.assertLess(saida.index("venda ou para locação"), saida.index("pode me atualizar o valor do imovel para locacao"))
        self.assertIn("NAO SABEMOS", venda.secao(None, s))
        self.assertNotIn("{", venda.secao(None, s))
        self.assertIsNone(venda.sem_imovel(None, self.Banco([]), "5592"))

    def test_imovel_de_venda_vence_o_sem_imovel(self):
        v = {"valor": "R$ 580.000", "frase": "x?"}
        self.assertIn("PARA VENDA", venda.secao(v, {"frase": "y?"}))
        saida = venda.no_lugar_da_locacao([{"instrucao_para_voce": self.DO_FLUXO}], v, {"frase": "y?"})[0]["instrucao_para_voce"]
        self.assertIn('"x?"', saida)
        self.assertNotIn("y?", saida)

    def test_a_secao_do_prompt_leva_o_valor_e_a_frase(self):
        v = {"valor": "R$ 580.000", "frase": "Sr. Júlio, aqui no nosso cadastro o imóvel está à venda por R$ 580.000. Esse valor continua?"}
        sec = venda.secao(v)
        self.assertIn("PARA VENDA", sec)
        self.assertIn('"' + v["frase"] + '"', sec)
        self.assertIn('guardar_venda com valor = "R$ 580.000"', sec)
        self.assertNotIn("{", sec)


class OutroImovel(unittest.TestCase):
    """447: a lista 5 com o modelo outro_imovel_04, que só sai depois que a Meta aprovar."""

    def test_a_foto_da_meta_da_so_os_aprovados(self):
        import json
        import tempfile
        from captacao import disparo
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
            json.dump({"lido_em": "x", "modelos": [{"name": "outro_imovel_04", "status": "PENDING"},
                                                   {"name": "situacao_imovel_cadastrado_1", "status": "APPROVED"},
                                                   {"name": "situacao_imovel_cadastrado_1", "status": "APPROVED"},
                                                   {"nome": "cadastro_imobeasy_02", "status": "APPROVED"}]}, f)
        self.assertEqual(disparo.aprovados_na_foto(f.name), ["cadastro_imobeasy_02", "situacao_imovel_cadastrado_1"])
        Path(f.name).write_text("{quebrado", encoding="utf-8")
        self.assertIsNone(disparo.aprovados_na_foto(f.name))
        self.assertIsNone(disparo.aprovados_na_foto(f.name + ".nao-existe"))

    def test_lead_sem_modelo_proprio_usa_o_de_sempre(self):
        from captacao import disparo
        self.assertEqual(disparo.modelo_do_lead(None), config.MODELO_DE_ABERTURA)
        self.assertEqual(disparo.modelo_do_lead(" outro_imovel_04 "), "outro_imovel_04")

    def test_a_abertura_do_outro_imovel_no_lugar_da_situacao(self):
        self.assertEqual(modelo.ACRESCIMO, modelo.ABERTURA_SITUACAO + modelo.CONTRATO + modelo.FIM)
        a = modelo.ACRESCIMO_OUTRO_IMOVEL
        for marca in ("{modelo}", "{imovel}", "{indicacao}", "{honorarios}", "Tenho outro imóvel", "Não tenho outro",
                      "demanda alta neste fim de ano", "trabalhar com ele novamente", "o contrato de locacao desse imovel vai",
                      "QUANDO COMECOU"):
            self.assertIn(marca, a)
        self.assertNotIn("Disponível, Alugado e Vendido", a)

    def test_a_abertura_das_listas_3_e_4_pergunta_imovel_para_vender(self):
        v = modelo.ACRESCIMO_OUTRO_VENDER
        for marca in ("{modelo}", "{imovel}", "{situacao_antiga}", "{indicacao}", "demanda alta de imoveis", "para vender"):
            self.assertIn(marca, v)
        self.assertNotIn("QUANDO COMECOU", v)
        self.assertEqual(set(modelo.SITUACAO_ANTIGA), {"vendido", "removido"})


if __name__ == "__main__":
    unittest.main()
