"""04/11 (Pedro): "todos que estão marcados como corretores, mesmo no número Leads, é para a Nay Parceria atender e não a Nay
Leads; esses que eu passei para a Rayssa, pode pôr a Nay para atender todos eles" -- como: "mandar os imóveis e responder
as solicitações dele". O caso: o vasconcelosizaias (92 99198-8585) escreveu no 8595 "EI NAY BOM DIA / TEM ALGUMA COISA ATÉ
300 MIL VENDA" e a Nay Corretores respondeu "Você tem algum imóvel à venda até R$ 300 mil? Pode me mandar?".
python -m unittest discover -s tests"""
import os
import pathlib
import sys
import unittest
from datetime import datetime, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.environ.get("NAY_GRUPOS_DIR") and not pathlib.Path("/root/nay-grupos").exists():
    os.environ["NAY_GRUPOS_DIR"] = str(pathlib.Path(__file__).resolve().parents[2] / "nay-grupos")

from olx import buscas as b  # noqa: E402
from olx import whatsapp as w  # noqa: E402

TEL = "559291988585"
FRASE = "EI NAY BOM DIA\nTEM ALGUMA COISA ATÉ 300 MIL VENDA"
# o que o modelo devolve para a FRASE (o pedido, sem balão: a resposta é do sistema)
PEDIU = {"responder": True, "oferece_imovel": False, "pede_imovel": True,
         "pedido": {"codigos": [], "finalidade": "venda", "tipo": "", "teto": 300000, "bairros": [], "condominio": "",
                    "quartos": 0, "mobilia": ""},
         "baloes": []}
# a busca de 04/11 para "venda até 300 mil" (olx_cliente_buscar no banco): o Pedro mandou à mão o 2228, o 4262 e o 5699
ACHADOS = [{"codigo": c, "perto": False} for c in (2228, 4161, 5699, 4009, 2024, 4262, 9011)]


class OPedido(unittest.TestCase):
    def test_a_frase_do_vasconcelosizaias_vira_pedido_de_venda_ate_300_mil(self):
        f = b.pedido_do_corretor(PEDIU["pedido"])
        self.assertEqual(f, {"teto": 300000, "finalidade": "venda"})
        self.assertEqual(b.falta_no_pedido(f), "")                     # dá para buscar: tem o valor
        # sem dizer "venda": acima de R$ 100 mil é venda (Pedro, 30/10); até R$ 30 mil é aluguel (03/11)
        self.assertEqual(b.pedido_do_corretor({"teto": "300000"})["finalidade"], "venda")
        self.assertEqual(b.pedido_do_corretor({"teto": 3000, "finalidade": "venda"})["finalidade"], "locacao")

    def test_tipo_e_mobilia_no_vocabulario_da_busca(self):
        f = b.pedido_do_corretor({"tipo": "apto", "teto": 3500, "bairros": ["Parque 10"], "quartos": 2, "mobilia": "com modulados e ar"})
        self.assertEqual(f, {"teto": 3500, "finalidade": "locacao", "tipo": "apartamento", "bairros": ["Parque 10"],
                             "quartos": 2, "mobilia": "semi"})
        self.assertEqual(b.pedido_do_corretor({"tipo": "casa em condomínio"})["tipo"], "casa_condominio")
        self.assertNotIn("mobilia", b.pedido_do_corretor({"teto": 500000, "mobilia": "mobiliado"}))   # mobília é da locação

    def test_sem_o_essencial_pergunta_uma_coisa(self):
        # "vc teria alguma coisa?" sem valor e sem lugar: o catálogo inteiro não é resposta
        self.assertEqual(b.falta_no_pedido({}), "É para venda ou locação, e até quanto o seu cliente quer pagar?")
        self.assertEqual(b.falta_no_pedido({"finalidade": "venda"}), "Até quanto o seu cliente quer pagar?")
        # "tem apartamento 2 quartos no Parque 10?": tem o lugar, falta só venda ou locação
        f = b.pedido_do_corretor({"tipo": "apartamento", "bairros": ["Parque 10"], "quartos": 2})
        self.assertEqual(b.falta_no_pedido(f), "É para venda ou locação?")
        self.assertEqual(b.falta_no_pedido({**f, "finalidade": "venda"}), "")


def _atender(r=PEDIU, achados=ACHADOS, recentes=(), nossos=None, disparo=None, c=None, afrouxar=()):
    """atender_pedido com o banco de mentira; devolve (balões, as chamadas ao banco.um, o _enviar, o _ao_crm). Sem
    `disparo`, a função da fila responde que mandou todos os que recebeu (como nai_enviar_imoveis_para)."""
    chamadas = []

    def um(conn, sql, params=None):
        chamadas.append((sql, params))
        if "nai_disparo_enfileirar" not in sql:
            return None
        return disparo if disparo is not None else             "Mandei para (92) 99198-8585: " + ", ".join(f"{x} (card e 9 fotos)" for x in params[1]) + "."
    so_nossos = (lambda conn, cods: [x for x in cods if x in nossos]) if nossos is not None else (lambda conn, cods: list(cods))
    with mock.patch.object(b.whatsapp, "_consultar", return_value=list(achados)), \
            mock.patch.object(b.whatsapp, "so_o_que_serve", side_effect=lambda conn, lead, f, cods, **k: list(cods)), \
            mock.patch.object(b.whatsapp, "o_que_existe_afrouxando", return_value=list(afrouxar)), \
            mock.patch.object(b.whatsapp, "_ao_crm") as ao_crm, \
            mock.patch.object(b, "_nossos_no_mercado", side_effect=so_nossos), \
            mock.patch.object(b, "_recentes_do_corretor", return_value=list(recentes)), \
            mock.patch.object(b, "_enviar", return_value="m1") as enviar, \
            mock.patch.object(b.banco, "um", side_effect=um):
        conn = mock.Mock()
        baloes = b.atender_pedido(conn, {"telefone": TEL, "nome": "vasconcelosizaias552"}, r, c or {"corretor": "sim", "teste": None})
    return baloes, chamadas, enviar, ao_crm


class OEnvio(unittest.TestCase):
    def test_tem_sim_manda_ate_5_pela_parceria_e_nao_pede_imovel_a_ele(self):
        baloes, chamadas, enviar, _ = _atender()
        disparos = [p for s, p in chamadas if "nai_disparo_enfileirar" in s]
        self.assertEqual(len(disparos), 1)
        tel, codigos, quem = disparos[0]
        self.assertEqual(tel, TEL)
        self.assertEqual(codigos, [2228, 4161, 5699, 4009, 2024])      # os 5 primeiros da busca, na ordem dela
        self.assertIn("automático", quem)                              # a parede das 24 h vale (nai_turno_feito_a_mao)
        self.assertEqual(baloes, ["Tenho sim! Te mandei 5 opções pelo nosso número de parcerias, o 92 9445-3618."])
        self.assertNotIn("Pode me mandar", " ".join(baloes))
        self.assertNotIn("parceria nossa", " ".join(baloes).lower())
        enviar.assert_not_called()                                      # nada sai pelo 8595 aqui: só a resposta, depois

    def test_o_que_ja_foi_para_ele_nao_vai_de_novo(self):
        # o Pedro mandou o 2228, o 4262 e o 5699 às 09:39: na volta seguinte esses ficam de fora
        baloes, chamadas, _, _ = _atender(recentes=(2228, 4262, 5699))
        codigos = [p for s, p in chamadas if "nai_disparo_enfileirar" in s][0][1]
        self.assertEqual(codigos, [4161, 4009, 2024, 9011])
        self.assertIn("4 opções", baloes[0])

    def test_tudo_ja_enviado_diz_isso_e_nao_repete(self):
        baloes, chamadas, _, _ = _atender(recentes=[a["codigo"] for a in ACHADOS])
        self.assertFalse([p for s, p in chamadas if "nai_disparo_enfileirar" in s])
        self.assertEqual(baloes, ["As que tenho nesse perfil já te mandei pelo nosso número de parcerias, o 92 9445-3618."])

    def test_parceiro_e_fora_do_mercado_nunca_vao(self):
        # parceria nunca sai ao corretor: o que não é nosso e Disponível sai da lista antes do disparo
        _, chamadas, _, _ = _atender(nossos={4161, 2024})
        self.assertEqual([p for s, p in chamadas if "nai_disparo_enfileirar" in s][0][1], [4161, 2024])

    def test_o_mais_proximo_entra_no_maximo_2_depois_do_exato(self):
        achados = [{"codigo": 1, "perto": True}, {"codigo": 2, "perto": True}, {"codigo": 3, "perto": True},
                   {"codigo": 4, "perto": False}]
        _, chamadas, _, _ = _atender(achados=achados, disparo="Mandei para x: 4 (card e 3 fotos), 1 (card e 3 fotos), 2 (card e 3 fotos).")
        self.assertEqual([p for s, p in chamadas if "nai_disparo_enfileirar" in s][0][1], [4, 1, 2])

    def test_nada_no_perfil_diz_e_pergunta_uma_coisa(self):
        baloes, chamadas, _, _ = _atender(achados=[], afrouxar=[("valor", "")])
        self.assertFalse([p for s, p in chamadas if "nai_disparo_enfileirar" in s])
        self.assertEqual(baloes, ["Imóvel para venda até R$ 300.000 não tenho agora; serve um pouco acima de R$ 300.000?"])
        r = {**PEDIU, "pedido": {"finalidade": "locacao", "tipo": "apartamento", "teto": 4000, "bairros": ["Flores"], "quartos": 3}}
        baloes, _, _, _ = _atender(r=r, achados=[], afrouxar=[("quartos", "2"), ("bairro", "Parque 10")])
        self.assertEqual(baloes, ["Apartamento para locação em Flores com 3 quartos até R$ 4.000 não tenho agora; serve com 2 quartos?"])
        self.assertNotIn(" ou ", baloes[0])                              # UMA coisa
        baloes, _, _, _ = _atender(achados=[])
        self.assertEqual(baloes, ["Imóvel para venda até R$ 300.000 não tenho agora."])

    def test_sem_o_essencial_pergunta_e_nao_busca(self):
        r = {**PEDIU, "pedido": {"finalidade": "", "teto": 0}}
        baloes, chamadas, _, _ = _atender(r=r)
        self.assertEqual(baloes, ["É para venda ou locação, e até quanto o seu cliente quer pagar?"])
        self.assertFalse(chamadas)

    def test_pediu_o_codigo_vai_esse(self):
        r = {**PEDIU, "pedido": {"codigos": ["#5742"]}}
        baloes, chamadas, _, _ = _atender(r=r, disparo="Mandei para x: 5742 (card e 9 fotos).")
        self.assertEqual([p for s, p in chamadas if "nai_disparo_enfileirar" in s][0][1], [5742])
        self.assertEqual(baloes, ["Te mandei pelo nosso número de parcerias, o 92 9445-3618."])
        baloes, chamadas, _, _ = _atender(r=r, nossos=set())                 # de parceiro ou fora do mercado
        self.assertEqual(baloes, ["Esse não está disponível no momento."])
        self.assertNotIn("parcer", baloes[0].lower().replace("parcerias", ""))

    def test_a_parede_das_24_h_recusou_tudo(self):
        baloes, _, _, ao_crm = _atender(disparo="Não mandei nada para (92) 99198-8585:\n2228: já foi para esse número hoje às 09h39")
        self.assertIn("já te mandei", baloes[0])
        ao_crm.assert_not_called()

    def test_o_envio_nao_saiu_por_outro_motivo_nao_promete_e_avisa_a_equipe(self):
        baloes, _, _, ao_crm = _atender(disparo="Não mandei nada para (92) 99198-8585:\n2228: não achei esse código")
        self.assertEqual(baloes, [])
        ao_crm.assert_called_once()

    def test_em_teste_nada_vai_a_parceria(self):
        baloes, chamadas, enviar, _ = _atender(c={"corretor": "teste", "teste": "5596991712835"})
        self.assertFalse([p for s, p in chamadas if "nai_disparo_enfileirar" in s])
        self.assertIn("[teste: iria pela Parceria", enviar.call_args.args[1])
        self.assertIn("Tenho sim!", baloes[0])


class AVoltaDoCorretor(unittest.TestCase):
    """corretores_volta com a frase real: o que sai pelo 8595 é a resposta do pedido, nunca o "Pode me mandar?"."""

    def test_o_vasconcelosizaias_ouve_tenho_sim_e_nao_pode_me_mandar(self):
        agora = datetime.now(timezone.utc)
        conversa = [{"id": 22193, "direcao": "recebida", "origem": "texto", "texto": "EI NAY BOM DIA", "criada_em": agora, "hora": "04/11 09:28"},
                    {"id": 22194, "direcao": "recebida", "origem": "texto", "texto": "TEM ALGUMA COISA ATÉ 300 MIL VENDA",
                     "criada_em": agora, "hora": "04/11 09:28"}]
        cor = {"telefone8": "91988585", "telefone": TEL, "nome": "vasconcelosizaias552", "origem": "grupo", "estado": "conversando",
               "ultima_lida": 22192, "busca": None, "codigo": None, "imovel": {}}
        modelo_disse = {**PEDIU, "baloes": ["Bom dia! Você tem algum imóvel à venda até R$ 300 mil? Pode me mandar?"]}

        def linhas(conn, sql, params=None):
            if "FROM privado.busca_corretor WHERE telefone8" in sql:
                return [cor]
            return []
        enviados = []
        with mock.patch.object(b, "_pendentes_corretores", return_value=[{"t8": "91988585", "telefone": TEL, "ate": 22194}]), \
                mock.patch.object(b, "corretores_marcados", return_value=frozenset()), \
                mock.patch.object(b, "_conversa_corretor", return_value=conversa), \
                mock.patch.object(b, "anuncio_da_conversa", return_value=None), \
                mock.patch.object(b, "_qtd_fotos", return_value=0), \
                mock.patch.object(b.whatsapp, "_fichas_citadas", return_value=[]), \
                mock.patch.object(b.modelo, "chamar", return_value=modelo_disse) as chamar, \
                mock.patch.object(b, "atender_pedido", return_value=["Tenho sim! Te mandei 3 opções pelo nosso número de parcerias, o 92 9445-3618."]) as atender, \
                mock.patch.object(b.banco, "linhas", side_effect=linhas), mock.patch.object(b.banco, "um", return_value=None), \
                mock.patch.object(b, "_enviar", side_effect=lambda d, t: enviados.append((d, t)) or "m1"), \
                mock.patch.object(b, "_guardar_enviada"), mock.patch.object(b.time, "sleep"):
            self.assertEqual(b.corretores_volta(mock.Mock(), {"corretor": "sim", "teste": None}), 1)
        atender.assert_called_once()
        self.assertIn("pede_imovel", chamar.call_args.args[0])          # o prompt ensina o pedido
        self.assertEqual(enviados, [(TEL, "Tenho sim! Te mandei 3 opções pelo nosso número de parcerias, o 92 9445-3618.")])
        self.assertFalse(any("Pode me mandar" in t for _d, t in enviados))

    def test_o_prompt_nao_devolve_a_pergunta(self):
        self.assertIn("NUNCA peça imóvel a ele nem devolva a pergunta", b.PROMPT_CORRETOR)
        self.assertIn("NÃO está pedindo imóvel", b.PROMPT_CORRETOR)
        self.assertIn('"pedido"', b.PROMPT_CORRETOR)


class QuemAtende(unittest.TestCase):
    """O corretor marcado é da Nay Corretores, não da Nay Leads; o "Enviar para Rayssa" não cala a Nay Corretores."""

    def setUp(self):
        b._MARCADOS.update(em=0.0, fins=None)

    def tearDown(self):
        b._MARCADOS.update(em=0.0, fins=None)

    def test_os_marcados_sao_os_do_crm_menos_equipe_visitas_e_nossos_numeros(self):
        def linhas(conn, sql, params=None):
            assert "crm_leads_corretores" in sql
            return [{"fone8": "91988585", "motivo": "conversou com a Nay Corretores, na lista de corretores"},
                    {"fone8": "93006380", "motivo": "disse que é corretor, fala do cliente dele"},
                    {"fone8": "11112222", "motivo": "da equipe"},
                    {"fone8": "88285562", "motivo": "acompanha visitas"},
                    {"fone8": "33334444", "motivo": "corretor/CRECI/imobiliária no nome"}]
        cfg = {"visita_corretores": "Raquel:92988285562", "visita_locacao": "Diego:92977776666"}
        um = lambda conn, sql, params=None: ["94453618"] if "busca_nossos_numeros" in sql else None
        with mock.patch.object(b.banco, "linhas", side_effect=linhas), mock.patch.object(b.banco, "chaves", return_value=cfg), \
                mock.patch.object(b.banco, "um", side_effect=um), \
                mock.patch.object(b, "_marcados_no_crm", return_value=(
                    {"55556666", "94453618", "72260211"}, {"33334444"},
                    {"91988585", "93006380", "55556666", "94453618", "33334444", "11112222", "88285562"})):
            m = b.corretores_marcados(mock.Mock())
        # a equipe, o corretor das visitas (Raquel), o "Cliente" escolhido à mão no CRM e o número da Parceria ficam de fora;
        # e só os mandados para a Rayssa (o 72260211, com o Lucas, não foi)
        self.assertEqual(m, frozenset({"91988585", "93006380", "55556666"}))
        self.assertTrue(b.e_corretor_marcado(None, "5592991988585"))
        self.assertFalse(b.e_corretor_marcado(None, "5592933334444"))

    def test_lido_uma_vez_a_cada_10_min_e_falha_nao_derruba(self):
        with mock.patch.object(b.banco, "linhas", side_effect=RuntimeError("caiu")) as linhas:
            self.assertEqual(b.corretores_marcados(mock.Mock()), frozenset())    # falhou: fica a regra de antes
            self.assertEqual(b.corretores_marcados(mock.Mock()), frozenset())
        self.assertEqual(linhas.call_count, 1)

    def test_a_fila_da_nay_corretores_pega_o_marcado_mesmo_com_a_nay_leads_e_a_rayssa(self):
        capturado = {}

        def linhas(conn, sql, params=None):
            capturado.update(sql=sql, params=params)
            return []
        with mock.patch.object(b, "corretores_marcados", return_value=frozenset({"92491844", "93006380"})), \
                mock.patch.object(b.banco, "linhas", side_effect=linhas):
            b._pendentes_corretores(mock.Mock())
        sql = capturado["sql"]
        self.assertIn("busca_corretor_e(m.telefone)", sql)
        self.assertIn("= ANY(%(marcados)s::text[])", sql)
        self.assertEqual(capturado["params"]["marcados"], ["92491844", "93006380"])
        # o que ele escreveu há dois dias, quando a equipe ou a Nay Leads ainda estavam com ele, não é respondido agora
        self.assertEqual(capturado["params"]["janela"], 12)
        # a etapa 'rayssa' (captacao_etapa_manual) e o olx_lead_whatsapp parado não tiram o marcado da fila
        self.assertNotIn("captacao_etapa_manual", sql)
        self.assertNotIn("olx_lead_whatsapp", sql)
        # fica de fora: a Nay da campanha com ele e a consulta de visita esperando resposta
        self.assertIn("l.humano_assumiu_em IS NULL", sql)
        self.assertIn("v.estado = 'esperando'", sql)

    def test_a_nay_leads_nao_responde_o_corretor_marcado(self):
        lead = {"id": 41, "telefone": "5592993006380", "humano_em": None, "parada_motivo": None}
        with mock.patch.object(b, "e_corretor_marcado", return_value=True), \
                mock.patch.object(w, "_marcar") as marcar, mock.patch.object(w, "agentes"), \
                mock.patch.object(w.banco, "um", return_value="agora"), \
                mock.patch.object(w, "_conversa", side_effect=AssertionError("não devia ler a conversa")):
            self.assertFalse(w._responder_um(mock.Mock(), {}, lead, 22078))
        k = marcar.call_args.kwargs
        self.assertEqual(k["ultima_lida"], 22078)
        self.assertEqual(k["humano_em"], "agora")
        self.assertIn("Nay Corretores", k["parada_motivo"])

    def test_cliente_que_nao_e_corretor_segue_com_a_nay_leads(self):
        lead = {"id": 7, "telefone": "5592981585907", "humano_em": None, "parada_motivo": None}
        with mock.patch.object(b, "e_corretor_marcado", return_value=False), \
                mock.patch.object(w, "_gente_escreveu", side_effect=RuntimeError("seguiu")), \
                mock.patch.object(w.banco, "um", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "seguiu"):
                w._responder_um(mock.Mock(), {}, lead, 1)


if __name__ == "__main__":
    unittest.main()
