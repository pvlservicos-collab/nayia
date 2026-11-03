"""03/11 (Pedro): a Nay das Dúvidas no grupo "Dúvidas Imobeasy": espera 5 s por pessoa, junta, responde com conselho."""
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from olx import grupo_duvidas as g

AGORA = datetime(2026, 11, 3, 14, 0, 0, tzinfo=timezone.utc)


def _m(mid, quem, seg_atras, texto="oi", tipo="texto", nome=None):
    t = AGORA - timedelta(seconds=seg_atras)
    return {"message_id": mid, "remetente": quem, "remetente_nome": nome or quem, "tipo": tipo, "texto": texto,
            "midia_url": None, "enviada_em": t, "guardada_em": t}


class Espera(unittest.TestCase):
    def test_so_quem_ficou_5s_quieto(self):
        msgs = [_m("1", "lucas", 12, "o 5725"), _m("2", "lucas", 9, "aceita pet?"), _m("3", "rayssa", 2, "e o 1125?")]
        prontos = g.prontos(msgs, AGORA)
        self.assertEqual([[m["message_id"] for m in l] for l in prontos], [["1", "2"]])

    def test_uma_leva_por_pessoa_na_ordem(self):
        msgs = [_m("1", "rayssa", 20), _m("2", "lucas", 15), _m("3", "rayssa", 8)]
        self.assertEqual([[m["message_id"] for m in l] for l in g.prontos(msgs, AGORA)], [["1", "3"], ["2"]])


class Texto(unittest.TestCase):
    def test_junta_as_mensagens(self):
        self.assertEqual(g.texto_da_leva([_m("1", "x", 9, "o 5725"), _m("2", "x", 6, "aceita pet?")]), "o 5725\naceita pet?")

    def test_audio_transcrito(self):
        with mock.patch.object(g.duvidas, "transcrever", return_value="tem garagem?"):
            m = {**_m("1", "x", 9, None, tipo="audio"), "midia_url": "https://x/a.ogg"}
            self.assertEqual(g.texto_da_leva([m]), "[áudio] tem garagem?")

    def test_codigos_e_nao_valores(self):
        self.assertEqual(g.codigos_do_texto("o 5725 e o 1125 até 3.500 ou 4000 reais, 3 mil"), [5725, 1125])
        self.assertEqual(g.codigos_do_texto("desconto no 2944, consegue por 3.500? e 4,5k no 887."), [2944, 887])


class Saida(unittest.TestCase):
    def test_resposta_com_o_nome_e_o_numero(self):
        r = {"responder": True, "resposta": "Pedro, o 5725 aceita pet.", "conselho": "Pergunte o porte."}
        self.assertEqual(g.mensagem_final(r, "Pedro Victor", 3),
                         "Sobre a dúvida 3 do Pedro, o 5725 aceita pet.\n\n💡 Pergunte o porte.")
        self.assertTrue(g.mensagem_final({**r, "resposta": "Sim, aceita."}, "Rayssa", 1).startswith(
            "Sobre a dúvida 1 da Rayssa, sim, aceita."))
        self.assertTrue(g.mensagem_final({**r, "resposta": "Aceita."}, "Fulana", 15).startswith("Sobre a dúvida 15 de Fulana, aceita."))
        self.assertTrue(g.mensagem_final({**r, "resposta": "OLX não."}, None, 2).startswith("Sobre a dúvida 2, OLX não."))

    def test_nao_responde_ok(self):
        self.assertIsNone(g.mensagem_final({"responder": False, "resposta": "", "conselho": ""}))

    def test_turno_com_os_dados(self):
        t = g.montar_turno("Lucas", "aceita pet?", [{"codigo": 5725, "aluguel": 3600.0, "dono": None}], AGORA)
        self.assertIn("QUEM PERGUNTOU: Lucas", t)
        self.assertIn('"aluguel": 3600', t)
        self.assertNotIn("dono", t)

    def test_o_prompt_tem_as_regras_do_tel(self):
        self.assertIn("Pet: perguntar o porte", g.PROMPT)


if __name__ == "__main__":
    unittest.main()
