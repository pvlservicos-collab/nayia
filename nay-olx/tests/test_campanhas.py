"""595: as campanhas liberadas à mão (parceiros, donos parados, feedback) e o aviso de baixa (Pedro, 03-04/11/2026)."""
import os
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.environ.get("NAY_GRUPOS_DIR") and not pathlib.Path("/root/nay-grupos").exists():
    os.environ["NAY_GRUPOS_DIR"] = str(pathlib.Path(__file__).resolve().parents[2] / "nay-grupos")

from olx import campanhas as cp  # noqa: E402
from olx import campanhas_baixa as cb  # noqa: E402
from olx import campanhas_respostas as cr  # noqa: E402

MANAUS = timezone(timedelta(hours=-4))
QUARTA_10H = datetime(2026, 11, 4, 10, 0, tzinfo=MANAUS)


def contato(**k):
    c = {"id": 7, "lista": "donos_parados", "nome": "Ana Claudia Rego", "vocativo": "Ana", "telefone": "5592981211884",
         "chave": "559281211884", "tel8": "81211884", "linha": "captacao", "modelo": None, "modelo_valores": None,
         "codigos": [5738], "imoveis": [{"codigo": 5738, "nome": "o apartamento no Estilo Ponta Negra", "valor_venda": 499999}],
         "mensagem": "Olá, Ana! Tudo bem? Aqui é a Nay, da Imob Easy. O seu apartamento no Estilo Ponta Negra (cód. 5738) ainda está disponível?",
         "mensagem_seguinte": "Que bom! O 5738 está no nosso site desde agosto. Toparia ajustar o valor?",
         "seguinte_em": None, "nossas": 1, "classe": None, "enviada_em": QUARTA_10H, "lida_ate": None}
    c.update(k)
    return c


class Horario(unittest.TestCase):
    def test_faixas_com_pausa_do_almoco(self):
        self.assertEqual(cp.faixas("8-12,13:30-18"), [(8, 12), (13.5, 18)])
        self.assertTrue(cp.no_horario("8-12,13:30-18", QUARTA_10H))
        self.assertFalse(cp.no_horario("8-12,13:30-18", QUARTA_10H.replace(hour=12, minute=45)))
        self.assertTrue(cp.no_horario("8-12,13:30-18", QUARTA_10H.replace(hour=13, minute=31)))
        self.assertFalse(cp.no_horario("8-12,13:30-18", QUARTA_10H.replace(hour=18)))

    def test_sabado_e_domingo_nao_envia_mas_a_resposta_pode(self):
        sabado = QUARTA_10H + timedelta(days=3)
        self.assertFalse(cp.no_horario("8-18", sabado))
        self.assertTrue(cp.no_horario("7-21", sabado, so_dia_util=False))

    def test_intervalo_e_modo(self):
        self.assertEqual(cp.intervalo("300-120"), (120, 300))
        self.assertEqual(cp.intervalo("lixo", (1, 2)), (1, 2))
        self.assertEqual(cp.modo({"x": "SIM"}, "x"), "sim")
        self.assertEqual(cp.modo({"x": "talvez"}, "x"), "nao")
        self.assertEqual(cp.modo({}, "campanha_baixa_avisar"), "nao")

    def test_campanha_desligada_ou_fora_do_horario_nao_manda(self):
        self.assertEqual(cp.pode_enviar({"campanha_envio": "nao"}, QUARTA_10H), "campanha_envio = nao")
        self.assertEqual(cp.pode_enviar({"campanha_envio": "sim"}, QUARTA_10H.replace(hour=20)), "fora do horário comercial")


class Linha(unittest.TestCase):
    def test_oficial_a_primeira_e_o_modelo_depois_texto_livre(self):
        c = contato(linha="oficial", modelo="situacao_condominio_1", modelo_valores=["Ana", "Estilo Ponta Negra (cód. 5738)"])
        with mock.patch.object(cp, "oficial_modelo", return_value=("wamid.1", None)) as mo, \
             mock.patch.object(cp, "oficial_texto", return_value=("wamid.2", None)) as tx:
            self.assertTrue(cp.mandar(None, c, c["mensagem"], primeira=True)["ok"])
            mo.assert_called_once_with("5592981211884", "situacao_condominio_1", ["Ana", "Estilo Ponta Negra (cód. 5738)"])
            cp.mandar(None, c, "Que bom!")
            tx.assert_called_once_with("5592981211884", "Que bom!")

    def test_parceria_vai_pela_fila_do_nucleo_e_8595_pela_zapi(self):
        with mock.patch.object(cp, "parceria_texto", return_value=(55, None)) as pa, \
             mock.patch.object(cp, "captacao_texto", return_value=("ABC", None)) as ca:
            s = cp.mandar(None, contato(linha="parceria"), "oi")
            self.assertEqual(s["saida"], 55)
            pa.assert_called_once()
            self.assertEqual(cp.mandar(None, contato(), "oi")["mid"], "ABC")
            ca.assert_called_once_with(None, "5592981211884", "oi")


class Fake:
    """Um banco de mentira: guarda os SQL e responde pelo começo do texto."""
    def __init__(self, respostas):
        self.respostas, self.sql = respostas, []

    def _r(self, sql, params):
        self.sql.append((" ".join(sql.split()), params))
        for chave, valor in self.respostas.items():
            if chave in sql:
                return valor(params) if callable(valor) else valor
        return None

    def um(self, conn, sql, params=None):
        return self._r(sql, params)

    def linhas(self, conn, sql, params=None):
        return self._r(sql, params) or []

    @staticmethod
    def js(v):
        import json
        return json.dumps(v, ensure_ascii=False)


class Envio(unittest.TestCase):
    def setUp(self):
        cp._PROXIMO[0] = 0.0

    def test_liberada_sai_e_vira_enviada(self):
        f = Fake({"count(*) FROM privado.campanha_contato": 0, "max(enviada_em)": False,
                  "campanha_reservar": [contato(estado="enviando")]})
        with mock.patch.object(cp, "banco", f), mock.patch.object(cp, "no_horario", return_value=True), \
             mock.patch.object(cp, "mandar", return_value={"ok": True, "mid": "M1"}) as m:
            self.assertTrue(cp.enviar_um(None, {"campanha_envio": "sim"}))
        m.assert_called_once()
        self.assertTrue(any("estado = 'enviada'" in s for s, _ in f.sql))
        self.assertTrue(any("campanha_evento" in s for s, _ in f.sql))

    def test_teste_so_reserva_os_numeros_de_teste_e_teto_do_dia_para(self):
        f = Fake({"count(*) FROM privado.campanha_contato": 0, "max(enviada_em)": False, "campanha_reservar": []})
        with mock.patch.object(cp, "banco", f), mock.patch.object(cp, "no_horario", return_value=True):
            self.assertFalse(cp.enviar_um(None, {"campanha_envio": "teste"}))
        self.assertEqual([p for s, p in f.sql if "campanha_reservar" in s], [(True,)])
        f = Fake({"count(*) FROM privado.campanha_contato": 60})
        with mock.patch.object(cp, "banco", f), mock.patch.object(cp, "no_horario", return_value=True):
            self.assertFalse(cp.enviar_um(None, {"campanha_envio": "sim", "campanha_teto_dia": "60"}))
        self.assertFalse(any("campanha_reservar" in s for s, _ in f.sql))

    def test_8595_desconectado_volta_para_a_fila_e_incerto_vira_erro(self):
        for erro, estado in (("o 8595 está desconectado", "'liberada'"), ("sem confirmação: ReadTimeout", "'erro'")):
            cp._PROXIMO[0] = 0.0
            f = Fake({"count(*) FROM privado.campanha_contato": 0, "max(enviada_em)": False,
                      "campanha_reservar": [contato(estado="enviando")]})
            with mock.patch.object(cp, "banco", f), mock.patch.object(cp, "no_horario", return_value=True), \
                 mock.patch.object(cp, "mandar", return_value={"ok": False, "erro": erro}):
                self.assertFalse(cp.enviar_um(None, {"campanha_envio": "sim"}))
            self.assertTrue(any(f"estado = {estado}" in s for s, _ in f.sql), erro)


class Classificar(unittest.TestCase):
    def test_botao_do_modelo(self):
        self.assertEqual(cr.classe_do_botao("Disponível"), "disponivel")
        self.assertEqual(cr.classe_do_botao(" alugado! "), "alugado")
        self.assertIsNone(cr.classe_do_botao("alugado desde setembro"))

    def test_valor_em_reais(self):
        for dito, reais in (("2.300", 2300), ("R$ 2.300,00", 2300), ("450 mil", 450000), ("1,2 milhão", 1200000),
                            ("4,5 mil", 4500), (2300, 2300), ("2,300", 2300), ("450.000", 450000)):
            self.assertEqual(cr.valor_em_reais(dito), reais, dito)
        self.assertIsNone(cr.valor_em_reais("não sei"))

    def test_ler_confere_a_classe_o_valor_e_os_codigos(self):
        c = contato(codigos=[5738, 5739])
        r = cr.ler({"classe": "baixa", "novo_valor": "450 mil", "codigos": [5738, 9999], "resposta": "Combinado!"}, c)
        self.assertEqual((r["classe"], r["novo_valor"], r["codigos"]), ("baixa", 450000, [5738]))
        self.assertEqual(cr.ler({"classe": "disponível"}, c)["classe"], "disponivel")
        self.assertEqual(cr.ler({"classe": "sei la", "novo_valor": 10}, c), {"classe": "outra_coisa", "novo_valor": None,
                                                                             "codigos": [], "resposta": "", "resumo": ""})

    def test_modelo_fora_do_ar_o_botao_ainda_vale_e_o_resto_vai_a_equipe(self):
        def falha(*a, **k):
            raise RuntimeError("fora")
        self.assertEqual(cr.classificar(contato(), "Vendido", falha)["classe"], "vendido")
        self.assertEqual(cr.classificar(contato(), "quem é?", falha)["classe"], "outra_coisa")

    def test_o_turno_leva_a_lista_os_imoveis_e_a_resposta(self):
        t = cr.turno(contato(), "já aluguei")
        self.assertIn("LISTA: donos_parados", t)
        self.assertIn("5738", t)
        self.assertIn("já aluguei", t)


class Resposta(unittest.TestCase):
    def test_resposta_segura(self):
        self.assertEqual(cr.resposta_segura("Obrigada por avisar, Ana! Tem outro imóvel para alugar?"),
                         "Obrigada por avisar, Ana! Tem outro imóvel para alugar?")
        self.assertIsNone(cr.resposta_segura("Pronto, já atualizei o valor no site!"))       # nunca diz que mudou
        self.assertIsNone(cr.resposta_segura("Veja em https://imobeasy.com/imovel/5738"))
        self.assertIsNone(cr.resposta_segura("Me liga no 99999-1234"))
        self.assertIsNone(cr.resposta_segura("Oba 😀🎉"))
        self.assertIsNone(cr.resposta_segura("x" * 400))
        self.assertIsNone(cr.resposta_segura(""))

    def test_decidir(self):
        disp = {"classe": "disponivel", "resposta": ""}
        self.assertEqual(cr.decidir(contato(), disp, None, None, True), ("seguinte", ""))
        self.assertEqual(cr.decidir(contato(), disp, "nay_parceria", None, True)[0], "nada")         # outra Nay atende
        self.assertEqual(cr.decidir(contato(), disp, None, "a equipe pelo CRM", True)[0], "nada")     # já responderam
        self.assertEqual(cr.decidir(contato(), disp, None, None, False)[0], "nada")                   # campanha_responde = nao
        self.assertEqual(cr.decidir(contato(nossas=3), disp, None, None, True)[0], "nada")            # 3 mensagens: equipe
        self.assertEqual(cr.decidir(contato(seguinte_em=QUARTA_10H), disp, None, None, True)[0], "nada")
        alug = {"classe": "alugado", "resposta": "Obrigada por avisar! Tem outro imóvel?"}
        self.assertEqual(cr.decidir(contato(), alug, None, None, True), ("resposta", ""))
        self.assertEqual(cr.decidir(contato(), {"classe": "alugado", "resposta": "já mudei para alugado"}, None, None, True)[0], "nada")
        self.assertEqual(cr.decidir(contato(), {"classe": "outra_coisa", "resposta": "Oi"}, None, None, True)[0], "nada")
        # corretor parceiro disse disponível: não há métricas, vai a resposta curta do modelo
        par = contato(lista="parceiros_disponivel", mensagem_seguinte=None)
        self.assertEqual(cr.decidir(par, {"classe": "disponivel", "resposta": "Perfeito, obrigada! Sigo divulgando."}, None, None, True),
                         ("resposta", ""))

    def test_aviso_a_equipe_manda_conferir_e_diz_que_nada_mudou(self):
        t = cr.texto_do_aviso(contato(), {"classe": "baixa", "novo_valor": 450000, "codigos": [5738]}, "faço 450 mil")
        self.assertIn("TOPOU BAIXAR", t)
        self.assertIn("R$ 450.000", t)
        self.assertIn("crm_campanha_baixa_confirmar", t)
        self.assertIn("A Nay não mudou nada no imóvel", t)
        self.assertIn("…1884", t)
        self.assertIn("mudar a situação", cr.texto_do_aviso(contato(), {"classe": "alugado", "codigos": []}, "aluguei"))


class Processar(unittest.TestCase):
    def _rodar(self, classe, resposta="", outro=None, respondeu=None, c=None):
        c = c or contato()
        f = Fake({"campanha_quem_atende": outro})
        enviados = []
        with mock.patch.object(cr, "banco", f), mock.patch.object(cp, "banco", f), \
             mock.patch.object(cr, "novas", return_value=[{"criada_em": QUARTA_10H, "texto": "sim"}]), \
             mock.patch.object(cr, "alguem_respondeu", return_value=respondeu), \
             mock.patch.object(cr.grupo, "ao_crm", return_value=True) as grp, \
             mock.patch.object(cp, "mandar", side_effect=lambda conn, c, t, primeira=False: enviados.append(t) or {"ok": True, "mid": "X"}):
            acao = cr.processar(None, {"campanha_responde": "sim"}, c,
                                chamar=lambda *a, **k: {"classe": classe, "resposta": resposta, "novo_valor": "2.300"})
        return acao, enviados, f, grp

    def test_disponivel_do_dono_manda_as_metricas_e_so_anota(self):
        acao, enviados, f, grp = self._rodar("disponivel")
        self.assertEqual(acao, "seguinte")
        self.assertEqual(enviados, [contato()["mensagem_seguinte"]])
        self.assertTrue(any("nay_aviso_equipe('nay-olx', 'nota'" in s for s, _ in f.sql))
        grp.assert_not_called()                                  # disponível não tem o que conferir
        self.assertFalse(any("UPDATE imoveis" in s for s, _ in f.sql))

    def test_baixa_responde_curto_anota_o_valor_e_avisa_o_grupo_sem_mudar_o_imovel(self):
        acao, enviados, f, grp = self._rodar("baixa", "Combinado! Vou passar o valor novo para a equipe atualizar.")
        self.assertEqual(acao, "resposta")
        self.assertEqual(enviados, ["Combinado! Vou passar o valor novo para a equipe atualizar."])
        self.assertTrue(any("classe = %s, novo_valor" in s and p[0] == "baixa" and p[1] == 2300 for s, p in f.sql))
        grp.assert_called_once()
        self.assertFalse(any("UPDATE imoveis" in s for s, _ in f.sql))

    def test_com_outra_nay_no_contato_nao_responde_por_cima(self):
        acao, enviados, f, grp = self._rodar("disponivel", outro="nay_parceria")
        self.assertEqual((acao, enviados), ("nada", []))
        acao, enviados, f, grp = self._rodar("alugado", "Obrigada!", respondeu="a Parceria (Nay ou equipe)")
        self.assertEqual((acao, enviados), ("nada", []))
        grp.assert_called_once()                                 # mas a equipe fica sabendo para conferir


class Baixa(unittest.TestCase):
    def test_texto_da_baixa(self):
        t = cb.texto_da_baixa({"nome": "Claudia Souza", "trat": "Sra."}, "o apartamento no Vision Residence", 3985, 4400, 4300, "locacao")
        self.assertEqual(t, "Oi, Sra. Claudia! Boa notícia: o apartamento no Vision Residence (cód. 3985), que mandei para a "
                            "senhora, baixou de R$ 4.400 para R$ 4.300 por mês. A senhora quer agendar uma visita?")
        t = cb.texto_da_baixa({"nome": None}, "a casa no Tarumã", 4980, 255000, 240000, "venda")
        self.assertEqual(t, "Oi! Boa notícia: a casa no Tarumã (cód. 4980), que te mandei, baixou de R$ 255.000 para "
                            "R$ 240.000. Quer agendar uma visita?")

    def test_nasce_desligado(self):
        f = Fake({})
        with mock.patch.object(cb, "banco", f):
            self.assertEqual(cb.atender(None, {}), 0)
        self.assertEqual(f.sql, [])

    def test_so_avisa_quando_o_cadastro_ja_mostra_o_valor(self):
        f = Fake({"FROM privado.campanha_baixa b JOIN imoveis": [
            {"id": 1, "estado": "confirmada", "valor_novo": 4300, "velha": False, "disponivel": True, "atual": 4400},
            {"id": 2, "estado": "confirmada", "valor_novo": 4300, "velha": False, "disponivel": True, "atual": 4300},
            {"id": 3, "estado": "confirmada", "valor_novo": 4300, "velha": True, "disponivel": True, "atual": 4400},
            {"id": 4, "estado": "avisando", "valor_novo": 4300, "velha": False, "disponivel": False, "atual": 4300}]})
        with mock.patch.object(cb, "banco", f):
            cb.conferir_baixas(None)
        mud = {p[2]: p[0] for s, p in f.sql if s.startswith("UPDATE privado.campanha_baixa")}
        self.assertEqual(mud, {2: "avisando", 3: "expirada", 4: "cancelada"})       # a 1 espera a equipe mudar o cadastro


if __name__ == "__main__":
    unittest.main()
