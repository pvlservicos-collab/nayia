"""512: a regra das dúvidas acompanhadas (Pedro, 28/10/2026: o Felipe ...0843 do 9051 e a dona que disse "Vou solicitar")."""
import os
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.environ.get("NAY_GRUPOS_DIR") and not pathlib.Path("/root/nay-grupos").exists():
    os.environ["NAY_GRUPOS_DIR"] = str(pathlib.Path(__file__).resolve().parents[2] / "nay-grupos")

from olx import duvidas as dv  # noqa: E402

AGORA = datetime(2026, 10, 28, 15, 0, tzinfo=timezone(timedelta(hours=-4)))


def duvida(**k):
    d = {"id": 1, "linha": "captacao", "estado": "aberta", "perguntada_em": AGORA - timedelta(hours=5),
         "dono_tel": "9291634742", "dono_nome": "Yara", "dono_motivo": None, "cobrancas": 0}
    d.update(k)
    return d


class Decidir(unittest.TestCase):
    def test_o_dono_disse_vou_solicitar_o_cliente_sabe_e_o_lembrete_espera_o_dia_seguinte(self):
        d = duvida(dono_perguntado_em=AGORA - timedelta(hours=4, minutes=58), ultima_do_dono=AGORA - timedelta(hours=4, minutes=57))
        r = {"situacao": "dono_vai_ver", "aviso_ao_cliente": "Sr. Felipe, ainda estou aguardando...", "lembrete_ao_dono": "Oi, Yara!"}
        self.assertEqual(dv.decidir(d, r, AGORA), ["avisar_cliente"])
        d["cliente_avisado_em"] = AGORA - timedelta(hours=3)
        self.assertEqual(dv.decidir(d, r, AGORA + timedelta(hours=16)), ["lembrar_dono"])

    def test_sem_resposta_lembra_em_3h_e_depois_de_2_lembretes_vai_ao_tel(self):
        r = {"situacao": "dono_sem_resposta", "lembrete_ao_dono": "Oi! Conseguiu ver?"}
        d = duvida(dono_perguntado_em=AGORA - timedelta(hours=3, minutes=5), cliente_avisado_em=AGORA)
        self.assertEqual(dv.decidir(d, r, AGORA), ["lembrar_dono"])
        d.update(cobrancas=2, dono_cobrado_em=AGORA - timedelta(hours=1))
        self.assertEqual(dv.decidir(d, r, AGORA), [])
        self.assertEqual(dv.decidir(d, r, AGORA + timedelta(hours=20)), ["ao_tel"])

    def test_o_dono_respondeu_entrega_mesmo_com_o_tel(self):
        r = {"situacao": "dono_respondeu", "resposta": "Aceita pet, sim."}
        self.assertEqual(dv.decidir(duvida(com_o_tel_no_pv="perguntada"), r, AGORA), ["entregar"])
        self.assertEqual(dv.decidir(duvida(), {"situacao": "dono_respondeu", "resposta": ""}, AGORA), [])

    def test_ja_respondido_ou_nao_era_duvida_encerra(self):
        for s in ("nao_e_duvida", "cliente_ja_respondido", "cliente_desistiu"):
            self.assertEqual(dv.decidir(duvida(), {"situacao": s}, AGORA), ["encerrar"])

    def test_ninguem_perguntou_ao_dono_pergunta_depois_de_1h_e_sem_contato_vai_ao_tel(self):
        r = {"situacao": "dono_nao_perguntado", "pergunta_ao_dono": "Olá Yara, ..."}
        self.assertEqual(dv.decidir(duvida(perguntada_em=AGORA - timedelta(minutes=20)), r, AGORA), [])
        self.assertEqual(dv.decidir(duvida(), r, AGORA), ["perguntar_dono"])
        self.assertEqual(dv.decidir(duvida(dono_tel=None, dono_motivo="dois_donos"), r, AGORA), ["ao_tel"])

    def test_com_o_tel_so_confere(self):
        r = {"situacao": "dono_sem_resposta", "lembrete_ao_dono": "Oi!", "aviso_ao_cliente": "Ainda aguardando."}
        self.assertEqual(dv.decidir(duvida(com_o_tel_no_pv="fila"), r, AGORA), [])
        self.assertEqual(dv.decidir(duvida(estado="com_o_tel"), r, AGORA), [])

    def test_equipe_na_conversa_segura_o_aviso_ao_cliente(self):
        r = {"situacao": "dono_vai_ver", "aviso_ao_cliente": "Ainda aguardando.", "lembrete_ao_dono": "Oi!"}
        self.assertEqual(dv.decidir(duvida(ultima_do_dono=AGORA - timedelta(hours=1)), r, AGORA, equipe_agora=True), [])


class Turno(unittest.TestCase):
    def test_o_turno_liga_as_tres_pessoas(self):
        d = duvida(cliente_nome="FELIPE", cliente_papel="lead", codigo=9051, imovel="San Marino Residencial",
                   pergunta="Fotos da parte de trás", dono_papel="proprietario", dono_perguntado_em=AGORA - timedelta(hours=4))
        t = dv.montar_turno(d, [{"em": AGORA, "quem": "Cliente", "texto": "fotos de trás"}],
                            [{"em": AGORA, "quem": "Dono (Parceria)", "texto": "Vou solicitar"}], [], AGORA, "Sr. Felipe")
        for pedaco in ("FELIPE", "#9051 San Marino", "o proprietário Yara", "Vou solicitar", "Sr. Felipe", "perguntamos"):
            self.assertIn(pedaco, t)


if __name__ == "__main__":
    unittest.main()
