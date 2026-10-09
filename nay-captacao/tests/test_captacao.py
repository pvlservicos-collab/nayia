"""As partes puras da Nay de captação em Python: o turno, o portão de saída e o laço do agente.

    python -m unittest discover -s tests        (na pasta nay-captacao)

Os casos vêm do que o fluxo do n8n já fazia (os comentários dos nós contam cada erro que virou regra).
"""
import random
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from captacao import cadastro, config, modelo, resposta, turno  # noqa: E402

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


if __name__ == "__main__":
    unittest.main()
