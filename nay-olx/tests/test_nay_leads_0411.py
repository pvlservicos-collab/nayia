"""04/11 (Pedro): "o foco da Nay Leads é ser um bom filtro mais do que qualquer outra coisa; ela não pode errar, nem esquecer
o lead, nem mandar imóvel errado ... ela tá falando muito robótica". Um teste por correção, com a frase do caso real.
python -m unittest discover -s tests"""
import unittest
from datetime import datetime
from unittest import mock

from olx import visita as v
from olx import whatsapp as w

MANAUS = w.MANAUS


def _im(**k):
    base = {"codigo": 1, "tipo": "apartamento", "valor_aluguel": 3000, "valor_venda": None, "quartos": 3, "suites": 1,
            "mobilia": "", "andar": "5", "bairro": "Flores", "condominio": "Residencial X", "bairro_ok": None}
    return {**base, **k}


class Regua(unittest.TestCase):
    """A régua única "serve ao pedido" (whatsapp.serve_ao_pedido)."""

    def test_casa_em_flores_nao_recebe_de_bairro_que_nao_e_vizinho(self):
        # lead 130 (a Paula ...8142), 03/11: "casas à venda em Flores com 5 quartos". A Cidade Nova é vizinha de Flores
        # (nai_bairros_ao_redor, conferido no banco em 04/11: Flores, Parque 10 e Cidade Nova sim; Aleixo e Ponta Negra não)
        f = {"finalidade": "venda", "tipo": "casa", "bairros": ["Flores"], "quartos": 5}
        im = _im(codigo=4109, tipo="casa", valor_venda=700000, valor_aluguel=None, quartos=7, bairro="Cidade Nova",
                 bairro_ok=True)
        self.assertEqual(w.serve_ao_pedido(im, f), "")
        self.assertIn("bairro", w.serve_ao_pedido({**im, "bairro": "Ponta Negra", "bairro_ok": False}, f))

    def test_nunca_acima_de_10_por_cento_do_teto(self):
        # lead 119 (01/11): "até R$ 200 mil" e recebeu duas de R$ 255 mil
        f = {"finalidade": "venda", "tipo": "apartamento", "teto": 200000}
        self.assertIn("+10%", w.serve_ao_pedido(_im(valor_venda=255000), f))
        self.assertIn("+10%", w.serve_ao_pedido(_im(valor_venda=221000), f))
        self.assertEqual(w.serve_ao_pedido(_im(valor_venda=220000), f), "")
        # o Decimal do banco não vira outro número (o _int tirava o ponto: 700000.00 -> 70000000)
        from decimal import Decimal
        self.assertEqual(w.serve_ao_pedido(_im(valor_venda=Decimal("199000.00")), f), "")

    def test_quartos_so_a_menos_se_ela_aceitou(self):
        # lead 120 (01/11): pediu 4 quartos e recebeu duas de 3 ("Esse são 3 quartos né")
        f = {"finalidade": "locacao", "tipo": "casa", "quartos": 4}
        self.assertIn("quarto", w.serve_ao_pedido(_im(tipo="casa", quartos=3), f))
        self.assertEqual(w.serve_ao_pedido(_im(tipo="casa", quartos=3), {**f, "aceita_menos_quartos": True}), "")
        self.assertIn("quartos", w.serve_ao_pedido(_im(tipo="casa", quartos=None), f))          # não se sabe: não vai

    def test_sem_mobilia_nunca_recebe_mobiliado(self):
        # o PROMPT: "sem" = "já tem os móveis dele"; modulados e ar servem
        f = {"finalidade": "locacao", "tipo": "apartamento", "mobilia": "sem"}
        self.assertIn("mobiliado", w.serve_ao_pedido(_im(mobilia="mobiliado"), f))
        self.assertEqual(w.serve_ao_pedido(_im(mobilia="semi"), f), "")
        self.assertEqual(w.serve_ao_pedido(_im(mobilia=""), f), "")
        # mobiliado é mobiliado (24/10, a Esther)
        self.assertIn("mobiliado", w.serve_ao_pedido(_im(mobilia="semi"), {**f, "mobilia": "mobiliado"}))

    def test_suites_e_andar_das_exigencias(self):
        # exigências reais da tabela: "pelo menos 1 suíte", "com suíte", "andar alto", "térreo ou primeiro andar"
        self.assertEqual(w.suites_pedidas({"exigencias": ["pelo menos 1 suíte"]}), 1)
        self.assertEqual(w.suites_pedidas({"exigencias": ["com suíte", "duas suítes"]}), 2)
        self.assertEqual(w.andar_pedido({"exigencias": ["andar alto"]}), (8, None))
        self.assertEqual(w.andar_pedido({"exigencias": ["andar mediano ou alto"]}), (4, None))
        self.assertEqual(w.andar_pedido({"exigencias": ["térreo ou primeiro andar"]}), (None, 1))
        self.assertEqual(w.andar_pedido({"exigencias": ["aceita apartamento com escada se for no segundo andar"]}), (None, None))
        f = {"finalidade": "locacao", "tipo": "apartamento", "exigencias": ["pelo menos 1 suíte", "andar alto"]}
        self.assertIn("suíte", w.serve_ao_pedido(_im(suites=0, andar="12"), f))
        self.assertIn("andar", w.serve_ao_pedido(_im(suites=1, andar="3"), f))
        self.assertEqual(w.serve_ao_pedido(_im(suites=1, andar="12"), f), "")
        self.assertEqual(w.serve_ao_pedido(_im(suites=2, andar="Andar alto"), f), "")
        self.assertIn("andar", w.serve_ao_pedido(_im(suites=1, andar=""), f))                    # não se sabe: não vai
        self.assertEqual(w.serve_ao_pedido(_im(suites=1, andar="1º"),
                                           {"tipo": "apartamento", "exigencias": ["térreo ou primeiro andar"]}), "")

    def test_tipo_e_finalidade(self):
        # lead 121 (01/11): "casa ... que seja em condomínio" e foi uma casa de rua
        self.assertIn("tipo", w.serve_ao_pedido(_im(tipo="casa"), {"finalidade": "locacao", "tipo": "casa_condominio"}))
        self.assertIn("venda", w.serve_ao_pedido(_im(valor_venda=None), {"finalidade": "venda"}))

    def test_so_o_que_serve_registra_o_motivo(self):
        fichas = {1: _im(codigo=1, quartos=4), 2: _im(codigo=2, quartos=2, bairro="Japiim")}
        passos = []
        with mock.patch.object(w, "fichas_da_regua", return_value=fichas), \
                mock.patch.object(w, "bairros_que_servem", return_value={"Flores": True, "Japiim": False}), \
                mock.patch.object(w.agentes, "passo", side_effect=lambda l, n, d="", **k: passos.append((n, d))):
            saem = w.so_o_que_serve(None, {"id": 1}, {"finalidade": "locacao", "quartos": 3, "bairros": ["Flores"]}, [1, 2, 3])
        self.assertEqual(saem, [1])
        self.assertEqual([n for n, _d in passos], ["regua_barrou", "regua_barrou"])

    def test_o_anuncio_da_olx_passa_pela_regua(self):
        try:
            from olx import parceiro
        except ImportError:                                  # sem o websocket do Chrome (só no PC do agente)
            self.skipTest("olx.parceiro precisa do websocket")
        a = {"titulo": "Casa 3 quartos", "bairro": "Flores", "imovel": {"tipo": "casa", "quartos": 3, "valor_aluguel": 5000}}
        self.assertIn("+10%", parceiro.anuncio_serve(a, {"finalidade": "locacao", "teto": 4000}))
        self.assertEqual(parceiro.anuncio_serve(a, {"finalidade": "locacao", "teto": 4600, "tipo": "casa_condominio"}), "")


class BuscaSemAfrouxarSozinha(unittest.TestCase):
    def _rodar(self, achados, veto=lambda lead, f, a: a):
        with mock.patch.object(w, "_consultar", return_value=achados), \
                mock.patch.object(w, "so_o_que_serve", side_effect=lambda c, l, f, cods, **k: list(cods)), \
                mock.patch.object(w, "_aceita_parceiro", return_value=False), \
                mock.patch.object(w.agentes, "filtrar_imoveis", side_effect=veto) as vet:
            return w.buscar_na_base(None, {"id": 1, "enviados": [], "negocio": "locacao"},
                                    {"tipo": "casa", "teto": 4000, "bairros": ["Planalto"], "quartos": 4}), vet

    def test_o_mais_proximo_passa_pelo_veto_e_sai_no_maximo_2(self):
        perto = [{"codigo": c, "perto": True, "bairro": "Dom Pedro"} for c in (11, 12, 13, 14)]
        b, vet = self._rodar(perto)
        self.assertTrue(vet.called)                                     # antes o veto pulava os "mais próximos"
        self.assertEqual([a["codigo"] for a in b["achados"]], [11, 12])
        self.assertTrue(b["proximas"])
        exatos = [{"codigo": c, "perto": False, "bairro": "Planalto"} for c in (1, 2, 3, 4, 5)]
        b, _ = self._rodar(exatos + perto)
        self.assertEqual([a["codigo"] for a in b["achados"]], [1, 2, 3, 4, 5])
        self.assertFalse(b["proximas"])

    def test_sem_nada_exato_pergunta_e_nao_manda_card(self):
        # Pedro: "Em Planalto com 4 quartos não tenho agora; serve com 3, ou um bairro vizinho?"
        lead = {"id": 1, "telefone": "92999990000", "nome": "Ana", "etapa": "filtrar", "enviados": []}
        f = {"finalidade": "locacao", "tipo": "casa", "teto": 4000, "bairros": ["Planalto"], "quartos": 4}
        b = {"f": f, "achados": [], "proximas": False, "antes_do_veto": [], "ms": 1, "excluir": [], "nomes_recusados": []}
        from olx import buscas
        with mock.patch.object(w, "buscar_na_base", return_value=b), mock.patch.object(w, "_marcar"), \
                mock.patch.object(w.agentes, "passo"), mock.patch.object(w, "ja_mandou", return_value=[]), \
                mock.patch.object(buscas, "resultado_da_base", return_value=True), \
                mock.patch.object(buscas, "cliente_avisado"), \
                mock.patch.object(w, "pergunta_para_afrouxar",
                                  return_value="Em Planalto com 4 quartos não tenho agora; serve com 3, ou num bairro vizinho?"), \
                mock.patch.object(w, "mandar_imovel") as imovel, mock.patch.object(w, "mandar_texto") as texto:
            w._buscar_e_mandar(None, lead, f)
        imovel.assert_not_called()
        self.assertEqual(texto.call_args[0][2], "Em Planalto com 4 quartos não tenho agora; serve com 3, ou num bairro vizinho?")

    def test_buscar_sem_teto_e_sem_lugar_nao_busca(self):
        # "manda o que tem" sem valor e sem região: buscava qualquer coisa
        r = {"baloes": ["Vou separar as opções para você."], "acoes": ["buscar"], "filtros": {"tipo": "apartamento"}}
        lead = {"id": 1, "negocio": "locacao", "filtros": {}, "enviados": []}
        acoes, passos = w.depois_do_modelo(None, lead, r, ["manda o que tem"], "")
        self.assertNotIn("buscar", acoes)
        self.assertIn("buscar_sem_filtro", [n for n, _d in passos])
        self.assertEqual(w.turno_mudo(r, acoes, passos, ["manda o que tem"]), "buscar")   # prometeu e não vai mandar
        with mock.patch.object(w, "_buscar_e_mandar") as bm, mock.patch.object(w.agentes, "passo"), \
                mock.patch.object(w.agentes, "acao"):
            w._fazer(None, lead, r, "buscar", {"tipo": "apartamento", "bairros": ["Flores"]})
        bm.assert_not_called()


class NuncaSemResposta(unittest.TestCase):
    class Agora(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 11, 2, 15, 19, tzinfo=MANAUS)

    def test_posso_visitar_agora(self):
        # lead 60, 02/11 15:19: "Posso visitar agora?" -> o modelo marcou a visita para 02/11 15:19, sem balão, e
        # pedir_confirmacao recusou calada (a menos de 30 min)
        agora = self.Agora.now()
        self.assertEqual(v.por_que_nao(9109, "02/11", "15:19", agora), "cedo")
        self.assertEqual(v.por_que_nao(9109, "02/11", "17:00", agora), "")
        self.assertEqual(v.por_que_nao(9109, "", "", agora), "sem_dia_hora")
        r = {"baloes": [], "acoes": ["visita"], "visita": {"codigo": 9109, "data": "02/11", "hora": "15:19"}}
        with mock.patch.object(w, "datetime", self.Agora):
            acoes, passos = w.depois_do_modelo(None, {"id": 60, "codigo": 9109, "enviados": [], "filtros": {}}, r,
                                               ["Boa tarde", "Posso visitar agora?"], "")
            self.assertNotIn("visita", acoes)
            self.assertEqual(w.turno_mudo(r, acoes, passos, ["Boa tarde", "Posso visitar agora?"]), "visita")
            aviso = w.aviso_do_mudo("visita", r, agora)
            self.assertIn("16h00", aviso)                        # 15:19 + 30 min, na meia hora seguinte
            extra, baloes = w.ultima_rede(r, "visita", ["Posso visitar agora?"], agora)
        self.assertEqual(extra, [])
        self.assertIn("16h00", baloes[0])

    def test_a_lorena_perguntou_e_nao_ficou_muda(self):
        # a Lorena ...9301, 03/11: "Só tem 1 dormitório?" e os bairros dela, sem resposta
        novas = ["Só tem 1 dormitório?", "Parque 10, Parque Mosaico, Aleixo ou Adrianópolis"]
        self.assertEqual(w.turno_mudo({"baloes": [], "acoes": []}, [], [], novas), "mudo")
        self.assertEqual(w.turno_mudo({"baloes": []}, [], [("fotos_sem_pedir", "x")], novas), "fotos")
        self.assertEqual(w.turno_mudo({"baloes": ["Só 1 quarto, sim."]}, [], [], novas), "")
        self.assertEqual(w.turno_mudo({"baloes": []}, [], [], ["Obrigada"]), "")                # cortesia: pode calar
        # a frase padrão da rede também volta ao modelo antes
        self.assertEqual(w.turno_mudo({"baloes": ["Vou confirmar isso e já te falo."], "_balao_padrao": True},
                                      ["perguntar"], [], novas), "mudo")
        extra, baloes = w.ultima_rede({"baloes": []}, "mudo", novas)
        self.assertEqual(extra, ["perguntar"])
        self.assertIn(baloes[0], w.BALOES_SEM_RESPOSTA["perguntar"])

    def test_o_card_do_anuncio_vai_a_quem_pediu_o_link(self):
        # a Lorena: "Me manda o link? Eu esqueci qual é 😅" -> só as fotos (o anúncio contava como card visto)
        lead = {"id": 1, "codigo": 9111, "telefone": "92999999301", "enviados": []}
        r = {"fotos": {"codigos": [9111]}, "_novas": ["Me manda o link? Eu esqueci qual é 😅"]}
        with mock.patch.object(w, "_ofertavel", return_value=True), mock.patch.object(w, "card_ja_foi", return_value=False), \
                mock.patch.object(w, "fotos_ja_foram", return_value=True), mock.patch.object(w, "_marcar"), \
                mock.patch.object(w, "ja_mandou", return_value=[]), mock.patch.object(w.time, "sleep"), \
                mock.patch.object(w.agentes, "acao"), mock.patch.object(w.agentes, "passo"), \
                mock.patch.object(w, "mandar_texto") as texto, mock.patch.object(w, "mandar_imovel") as imovel:
            w._fazer(None, lead, r, "fotos", {})
        imovel.assert_called_once_with(None, lead, 9111, com_card=True, com_fotos=False, repetir=False)
        texto.assert_not_called()                     # saiu "Já te mandei as fotos desse aqui em cima na conversa..."

    def test_abertura_no_meio_da_conversa_e_resposta_comum(self):
        # a Paula ...8142 (lead 130), 03/11 09:04: o Chaves na Mão mandou uma consulta nova (#3166) no meio da conversa;
        # a abertura deu ValueError 3 vezes e ela foi marcada humano_em "a Nay não conseguiu abrir"
        conversa = [{"id": 21283, "direcao": "enviada", "origem": "resposta", "nossa": True, "criada_em": 1,
                     "texto": "Boa tarde, Sra. Paula! Aqui é a Nay, da Imob Easy."},
                    {"id": 21576, "direcao": "recebida", "texto": "Pode sim", "criada_em": 2}]
        lead = {"id": 130, "telefone": "92999998142", "origem": "chavesnamao", "codigo": 3166, "negocio": "venda",
                "nome": "Paula", "trat": "Sra.", "etapa": "nova", "enviados": [5613], "filtros": {}, "portal": []}
        turnos, marcas = [], []
        with mock.patch.object(w.banco, "linhas", return_value=[{"id": 130}]), \
                mock.patch.object(w, "_lead", return_value=dict(lead)), mock.patch.object(w, "_pode", return_value=True), \
                mock.patch.object(w, "_conversa", return_value=conversa), \
                mock.patch.object(w, "_gente_escreveu", return_value=None), mock.patch.object(w.banco, "um"), \
                mock.patch.object(w, "_contexto", return_value=None), \
                mock.patch.object(w.visita, "para_o_modelo", return_value=None), \
                mock.patch.object(w.visita, "ativa", return_value=False), \
                mock.patch.object(w, "imoveis_da_conversa", return_value=[]), \
                mock.patch.object(w, "saber_dos_imoveis", return_value=[]), \
                mock.patch.object(w.agentes, "novo_turno"), mock.patch.object(w.agentes, "passo"), \
                mock.patch.object(w.agentes, "registrar"), \
                mock.patch.object(w.modelo, "chamar", side_effect=lambda p, t, no="": turnos.append(t) or {"baloes": []}), \
                mock.patch.object(w, "_marcar", side_effect=lambda c, lid, **k: marcas.append(k)), \
                mock.patch.object(w, "_ao_crm") as crm:
            w._FALHAS.pop(130, None), w._ESPERA.pop(130, None), w._AVISADOS.discard(130)
            for _ in range(3):
                w._ESPERA.pop(130, None)
                w.abrir(None, {})
            self.assertGreater(w._ESPERA.get(130, 0), w.time.monotonic() + 600)   # tenta de novo daqui a 15 min
            for _ in range(3):                                                    # e falha outras três vezes
                w._ESPERA.pop(130, None)
                w.abrir(None, {})
        self.assertIn("JÁ estão conversando", turnos[0])
        self.assertIn("no meio da conversa, ela deixou o contato de novo", turnos[0])
        self.assertNotIn("Ainda não há conversa", turnos[0])
        self.assertFalse(any("humano_em" in k for k in marcas))        # falha da Nay nunca passa a conversa à equipe
        self.assertEqual(crm.call_count, 1)                             # a equipe é avisada uma vez só
        w._FALHAS.pop(130, None), w._ESPERA.pop(130, None), w._AVISADOS.discard(130)


class FrasesSemRobo(unittest.TestCase):
    def test_a_oferta_que_chega_sozinha(self):
        # buscas.py: "Boa notícia! Encontrei uma opção que combina com o que você procura:"
        t = w.abre_oferta({"nome": "Paula", "trat": "Sra."}, 1)
        self.assertNotIn("Boa notícia", t)
        self.assertIn("a senhora", t)
        self.assertNotEqual(w.abre_oferta({"nome": "Paula", "trat": "Sra."}, 1, [t]), t)

    def test_a_confirmacao_da_visita_fecha_como_gente(self):
        t = v.texto_confirmacao(9109, datetime(2026, 11, 2, 16, 0, tzinfo=MANAUS), "Ponta Negra Village, Ponta Negra")
        self.assertIn("📅 Data: 02/11 (segunda)", t)
        self.assertTrue(t.endswith("Tá certinho? Se estiver, já falo com o proprietário."))
        self.assertNotIn("Por favor, confirme", t)


if __name__ == "__main__":
    unittest.main()
