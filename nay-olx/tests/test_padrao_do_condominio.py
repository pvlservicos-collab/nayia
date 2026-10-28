"""O padrão do condomínio na nota (Tel, 28/10/2026: a lead 63 veio pelo Prime Arena, de 2019, e recebeu o Amazonas Flat,
antigo; "gente que vem por esses mais novos 80% de chance a mais de querer fechar em um condomínio mais novo")."""
import os
import pathlib
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.environ.get("NAY_GRUPOS_DIR") and not pathlib.Path("/root/nay-grupos").exists():
    os.environ["NAY_GRUPOS_DIR"] = str(pathlib.Path(__file__).resolve().parents[2] / "nay-grupos")

from olx import buscas as b  # noqa: E402


def par(codigo, nota):
    return {"codigo": codigo, "nota": nota,
            "detalhe": [{"criterio": "preco", "texto": "x", "peso": 60.0, "pontos": nota * 0.6},
                        {"criterio": "local", "texto": "y", "peso": 40.0, "pontos": nota * 0.4}]}


class PadraoDoCondominio(unittest.TestCase):
    def test_antigo_cai_abaixo_do_corte_e_o_recente_passa_na_frente(self):
        classe = {4904: {"recente": False, "nome": "Amazonas Flat"},
                  3176: {"recente": True, "ano": 2019, "nome": "Prime Arena"}}
        r = b.com_padrao([par(4904, 100), par(3176, 85)], classe, "veio pelo Prime Arena (2019)")
        self.assertEqual([p["codigo"] for p in r], [3176, 4904])
        self.assertAlmostEqual(r[0]["nota"], 90.0)
        self.assertLess(r[1]["nota"], 70)                       # 100 de nota em condomínio antigo: 66,7, fora do corte

    def test_pesos_e_pontos_continuam_somando_100(self):
        r = b.com_padrao([par(1, 80)], {1: {"recente": True, "nome": "X"}}, "pediu condomínio novo")[0]
        self.assertAlmostEqual(sum(d["peso"] for d in r["detalhe"]), 100, delta=0.2)
        self.assertAlmostEqual(sum(d["pontos"] for d in r["detalhe"]), r["nota"], delta=0.3)
        self.assertIn("é recente", r["detalhe"][-1]["texto"])

    def test_fora_da_lista_e_nao_recente(self):
        r = b.com_padrao([par(7, 100)], {}, "veio pelo Prime Arena")[0]
        self.assertEqual(r["detalhe"][-1]["pontos"], 0)


if __name__ == "__main__":
    unittest.main()
