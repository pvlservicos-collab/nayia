"""A Nay da OLX decidindo (15/10: por etapas, com o modelo). Puro, sem banco:  python -m unittest discover -s tests

O modelo e o catálogo são injetados: aqui são falsos que devolvem o que o teste quiser. O que se prova é o que fica
em CÓDIGO (as paredes): o que vai ao modelo, o que sai dele e quando a conversa vai para a equipe com aviso no grupo.
"""
import unittest

from olx import nay


def ctx(mensagens, codigo=3883, negocio="venda", telefone=None):
    """Um contexto como `olx_nay_contexto` devolve (a forma real de `imovel`, aninhada)."""
    return {
        "chat": 9, "conta": "proprietarios", "list_id": "1544287948",
        "cliente": {"nome": "FELIPE LADISLAU CARVALHO", "telefone": telefone, "email": None},
        "anuncio": {"codigo": codigo, "negocio": negocio, "titulo": "Casa em condomínio com 4 quartos"} if codigo else None,
        "imovel": {"carac": {"tipo": "Casa de condomínio", "quartos": 4, "suites": 2},
                   "local": {"condominio": "Jardim de Versalhes", "bairro": "Planalto"},
                   "valores": {"venda": 700000.0, "fin": "Sim", "permuta": "carro até 100 mil"},
                   "obs": "o proprietário aceita ap até 400.000", "fotos": ["https://x/1.jpg"]},
        "mensagens": mensagens,
    }


def dele(t):
    return {"de": "comprador", "texto": t, "por": None}


def nosso(t, por="Nay OLX"):
    return {"de": "nos", "texto": t, "por": por}


class Modelo:
    """Um modelo de mentira: guarda o que recebeu e devolve a resposta pronta."""

    def __init__(self, resposta):
        self.resposta, self.prompt, self.turno = resposta, None, None

    def __call__(self, prompt, turno):
        self.prompt, self.turno = prompt, turno
        return self.resposta


class Etapas(unittest.TestCase):
    def test_duvida_responde_e_nao_encaminha(self):
        m = Modelo({"baloes": ["Oi, Felipe! Aqui é a Nay, da Imob Easy. Aceita financiamento, sim.", "Quer conhecer pessoalmente?"],
                    "encaminhar": None})
        d = nay.decidir(ctx([dele("Aceita financiamento?")]), None, m)
        self.assertEqual(len(d.baloes), 2)
        self.assertIsNone(d.passar_para_gente)
        self.assertIsNone(d.aviso_grupo)

    def test_deu_o_whatsapp_vai_para_a_equipe_com_aviso_no_grupo(self):
        m = Modelo({"baloes": ["Perfeito, Felipe! A equipe te chama no WhatsApp para combinar o horário."],
                    "encaminhar": "visita", "nome": "Felipe", "whatsapp": "92991540843", "motivo": "sábado de manhã"})
        d = nay.decidir(ctx([dele("Quero visitar"), nosso("Me passa seu nome e WhatsApp?"), dele("Felipe 92 99154-0843")]), None, m)
        self.assertEqual(d.aviso_grupo.splitlines()[0], "Lead Felipe solicitou visita pela OLX, número (92) 99154-0843.")
        self.assertIn("Imóvel 3883 (casa de condomínio, Jardim de Versalhes, venda)", d.aviso_grupo)
        self.assertIn("sábado de manhã", d.aviso_grupo)
        self.assertIn("quer visita", d.passar_para_gente)

    def test_proposta_vai_como_equipe(self):
        m = Modelo({"baloes": ["Valor quem trata é a equipe. Ela te chama no WhatsApp."], "encaminhar": "equipe",
                    "nome": "", "whatsapp": "5592991540843", "motivo": "proposta de 650 mil"})
        d = nay.decidir(ctx([dele("Faço 650 mil, meu zap 92991540843")]), None, m)
        self.assertTrue(d.aviso_grupo.startswith("Lead FELIPE LADISLAU CARVALHO pela OLX quer falar com a equipe, número (92) 99154-0843."))

    def test_encaminhar_sem_numero_valido_nao_entrega(self):
        m = Modelo({"baloes": ["Me passa seu WhatsApp com DDD?"], "encaminhar": "visita", "whatsapp": "1234"})
        d = nay.decidir(ctx([dele("quero visitar")]), None, m)
        self.assertIsNone(d.passar_para_gente)
        self.assertEqual(d.baloes, ["Me passa seu WhatsApp com DDD?"])

    def test_nada_a_dizer_nao_responde(self):
        self.assertIsNone(nay.decidir(ctx([nosso("A equipe te chama."), dele("ok")]), None, Modelo({"baloes": []})))


class OQueVaiAoModelo(unittest.TestCase):
    def test_venda_ou_locacao_e_o_telefone_da_olx(self):
        m = Modelo({"baloes": ["oi"]})
        nay.decidir(ctx([dele("oi")], negocio="locacao", telefone="92991540843"), lambda c, p: "Tem 4 quartos.", m)
        self.assertIn("ESTE ANÚNCIO: LOCAÇÃO", m.turno)
        self.assertIn("(92) 99154-0843", m.turno)
        self.assertIn("Tem 4 quartos.", m.turno)                # a sugestão do catálogo
        self.assertNotIn("aceita ap até", m.turno)              # a observação interna não vai
        self.assertNotIn("https://x/1.jpg", m.turno)
        self.assertIn("VENDA:", m.prompt)
        self.assertIn("LOCAÇÃO:", m.prompt)

    def test_quem_falou(self):
        m = Modelo({"baloes": ["oi"]})
        nay.decidir(ctx([dele("oi"), nosso("Oi! Aqui é a Nay."), nosso("pode me passar seu whatsapp?", por=None), dele("sim")]), None, m)
        self.assertIn("NAY: Oi! Aqui é a Nay.", m.turno)
        self.assertIn("EQUIPE: pode me passar seu whatsapp?", m.turno)

    def test_catalogo_estourando_nao_derruba(self):
        def explode(c, p):
            raise RuntimeError("banco fora")
        self.assertEqual(nay.decidir(ctx([dele("tem piscina?")]), explode, Modelo({"baloes": ["Tem, sim."]})).baloes, ["Tem, sim."])


class Paredes(unittest.TestCase):
    def test_sem_anuncio_ela_nao_fala(self):
        d = nay.decidir(ctx([dele("Ainda está disponível?")], codigo=None), None, Modelo({"baloes": ["x"]}))
        self.assertEqual(d.baloes, [])
        self.assertIn("não sei de qual imóvel", d.passar_para_gente)

    def test_sem_mensagem_do_cliente_nao_responde(self):
        self.assertIsNone(nay.decidir(ctx([]), None, Modelo({"baloes": ["x"]})))

    def test_balao_com_link_telefone_ou_emoji(self):
        self.assertIsNone(nay.limpar_balao("Veja em https://imobeasy.online/imovel/3883"))
        self.assertIsNone(nay.limpar_balao("Me chama no 92 98595-6408"))
        self.assertEqual(nay.limpar_balao("Tem piscina, sim! 😊"), "Tem piscina, sim!")
        self.assertEqual(nay.limpar_balao("Custa R$ 700.000"), "Custa R$ 700.000")

    def test_conversa_longa_demais_vai_para_gente(self):
        msgs = [nosso(f"resposta {i}") for i in range(nay.LIMITE_DE_BALOES)] + [dele("e aí?")]
        self.assertIn("longe demais", nay.decidir(ctx(msgs), None, Modelo({"baloes": ["x"]})).passar_para_gente)

    def test_no_maximo_tres_baloes(self):
        d = nay.decidir(ctx([dele("oi")]), None, Modelo({"baloes": ["a", "b", "c", "d", "e"]}))
        self.assertEqual(d.baloes, ["a", "b", "c"])

    def test_telefone(self):
        self.assertEqual(nay.telefone_valido("+55 (92) 99154-0843"), "92991540843")
        self.assertIsNone(nay.telefone_valido("99154-0843"))   # sem DDD


if __name__ == "__main__":
    unittest.main()
