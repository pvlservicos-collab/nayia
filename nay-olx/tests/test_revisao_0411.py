"""A revisão das conversas reais de 04/11/2026 (Pedro: "começa pelos erros, revisa tudo, prepara a solução, depois analisa
todas as soluções antes de fazer"). Um teste por erro, com o texto do caso real (o final do telefone no nome da classe).
python -m unittest discover -s tests"""
import os
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.environ.get("NAY_GRUPOS_DIR") and not pathlib.Path("/root/nay-grupos").exists():
    os.environ["NAY_GRUPOS_DIR"] = str(pathlib.Path(__file__).resolve().parents[2] / "nay-grupos")

from olx import buscas as b  # noqa: E402
from olx import whatsapp as w  # noqa: E402

AGORA = datetime.now(timezone.utc)
SIM = {"corretor": "sim", "teste": None}


def _msg(id_, texto, direcao="recebida", origem="texto", criada=None):
    return {"id": id_, "direcao": direcao, "origem": origem, "texto": texto, "criada_em": criada or AGORA, "hora": "04/11 15:48"}


# ─────────────────────────── NAY CORRETORES ───────────────────────────
PEDIDO_2985 = {"codigos": [], "finalidade": "venda", "tipo": "apartamento", "teto": 0, "bairros": [],
               "condominio": "Smille Flores", "so_condominio": True, "quartos": 2, "mobilia": "", "exigencias": ["andar baixo"]}


def _atender(r, cor, linhas=None, nossos=(), um=None):
    """atender_pedido com o banco de mentira: o condomínio vem do cadastro (_no_condominio) e o _consultar não roda."""
    chamadas = []

    def _um(conn, sql, params=None):
        chamadas.append((sql, params))
        if um:
            return um(sql, params)
        return "Smile Flores" if "similarity" in sql and "condominio_nome FROM imoveis" in sql else None
    with mock.patch.object(b.banco, "linhas", side_effect=lambda conn, sql, params=None: list(linhas or [])), \
            mock.patch.object(b.banco, "um", side_effect=_um), \
            mock.patch.object(b.whatsapp, "_consultar", side_effect=AssertionError("com condomínio não usa a busca larga")), \
            mock.patch.object(b.whatsapp, "so_o_que_serve", side_effect=lambda conn, lead, f, cods, **k: list(cods)), \
            mock.patch.object(b.whatsapp, "o_que_existe_afrouxando", return_value=[]), \
            mock.patch.object(b, "_nossos_no_mercado", side_effect=lambda conn, cods: [c for c in cods if c in nossos]), \
            mock.patch.object(b, "_recentes_do_corretor", return_value=[]), mock.patch.object(b.whatsapp, "_ao_crm"):
        baloes = b.atender_pedido(mock.Mock(), cor, r, SIM)
    return baloes, [p for s, p in chamadas if "nai_disparo_enfileirar" in s]


class Erro1_Corretor2985_PedidoComCondominio(unittest.TestCase):
    """…2985: "Vc tem algum apartamento no Smille Flores, andar baixo de dois quartos?" -> 18 imóveis de outros lugares e
    "Tenho sim! Te mandei N opções" cinco vezes; o único Smile Flores (9081) é de parceiro."""

    def test_condominio_dito_e_filtro_obrigatorio_e_o_andar_entra(self):
        f = b.pedido_do_corretor(PEDIDO_2985)
        self.assertTrue(f["so_condominio"])
        self.assertEqual(f["exigencias"], ["andar baixo"])
        self.assertEqual(w.andar_pedido(f), (None, 3))
        # o nome escrito de ouvido acha o do cadastro; o 99 Adrianópolis e os outros Smile, não
        achados = [{"codigo": 9081, "condominio": "Smile Flores"}, {"codigo": 5754, "condominio": "Smile Village Cidade Nova"},
                   {"codigo": 99, "condominio": "Residencial Adrianópolis"}]
        self.assertEqual([a["codigo"] for a in w.so_no_condominio(achados, f)], [9081])

    def test_so_o_de_parceiro_no_condominio_diz_que_nao_tem_e_nunca_tenho_sim(self):
        r = {"intencao": "pedido", "pede_imovel": True, "pedido": PEDIDO_2985}
        cor = {"telefone": "5592981312985", "nome": "x", "imovel": {}}
        baloes, disparos = _atender(r, cor, linhas=[{"codigo": 9081, "condominio_nome": "Smile Flores"}])
        self.assertEqual(disparos, [])                                  # parceria nunca sai ao corretor
        self.assertEqual(baloes, ["Apartamento para venda no Smile Flores com 2 quartos não tenho agora."])
        self.assertNotIn("Tenho sim", baloes[0])
        self.assertEqual(r["_pedido_feito"]["f"]["condominio"], "Smile Flores")
        # e o nosso do condomínio vai
        baloes, disparos = _atender(dict(r), cor, linhas=[{"codigo": 9200, "condominio_nome": "Smile Flores"}], nossos={9200},
                                    um=lambda sql, p: ("Mandei para x: 9200 (card e 5 fotos)." if "nai_disparo_enfileirar" in sql
                                                       else "Smile Flores" if "similarity" in sql else None))
        self.assertEqual(disparos[0][1], [9200])
        self.assertIn("Tenho sim! Te mandei 1 opção", baloes[0])

    def test_o_pedido_vale_entre_turnos_e_a_reclamacao_nao_e_pedido_novo(self):
        em = datetime.now(b.MANAUS).isoformat(timespec="minutes")
        f = b.pedido_do_corretor(PEDIDO_2985)
        f["condominio"] = "Smile Flores"
        # "Venda" (só a finalidade) continua o pedido de antes
        antes = {k: v for k, v in f.items() if k != "finalidade"}
        self.assertEqual(b.herdar_pedido(antes, b.pedido_do_corretor({"finalidade": "venda"})), f)
        # outro lugar dito é outro pedido
        self.assertEqual(b.herdar_pedido(antes, {"bairros": ["Flores"]}), {"bairros": ["Flores"]})
        # "Vc não enviou nenhuma opção": o mesmo pedido, já respondido sem nada: diz uma vez que conferiu
        cor = {"telefone": "5592981312985", "imovel": {"_pedido": {"f": f, "em": em, "mandados": [],
                                                                     "resposta": "Apartamento para venda no Smile Flores com 2 quartos não tenho agora."}}}
        r = {"intencao": "reclamacao", "pedido": {"codigos": []}}
        self.assertEqual(b.entender_corretor(r, ["Vc não enviou nenhuma opção"], None, {}, False, tem_pedido=True), "reclamacao")
        baloes, disparos = _atender(r, cor, linhas=[{"codigo": 9081, "condominio_nome": "Smile Flores"}])
        self.assertEqual(disparos, [])
        self.assertEqual(baloes, ["Conferi de novo: apartamento para venda no Smile Flores com 2 quartos não tenho agora. "
                                  "Se entrar algum, te chamo por aqui."])
        # na vez seguinte a mesma frase não sai de novo
        self.assertEqual(w.sem_repetir(baloes, [baloes[0]]), [])
        # reclamação sem pedido nenhum é com o modelo (não vira busca)
        self.assertEqual(b.entender_corretor({"intencao": "reclamacao"}, ["vc tá enganada"], None, {}, False), "duvida")


TEXTO_5642 = ("✅ PRECISO DE AP P/ LOCAÇÃO\n- bairros: Ponta Negra, Da Paz\n- 1 ou 2 quartos\n- até 2.600\n- OBS: mobiliado\n\n"
              "Tem algum? Me chama no privado.")
LINK_7891 = ("Olha o anúncio que eu encontrei na olx.com.br https://am.olx.com.br/regiao-de-manaus/imoveis/"
             "casa-em-condominio-com-4-quartos-para-alugar-no-residencial-tapajos-taruma-1544586428")
ANUNCIO_7891 = {"olx_id": 1544586428, "anunciante": "Telmario Araújo",
                "titulo": "Casa em condomínio com 4 quartos para alugar no Residencial Tapajós, Tarumã", "preco": 7000}
IM_2462 = {"tipo": "casa em condomínio", "finalidade": "locacao", "bairro": "Tarumã", "condominio": "Residencial Tapajós",
           "quartos": 4, "valor": 7000}


class Erro2_OfertaPedidoEVisita(unittest.TestCase):
    def test_8585_tem_alguma_coisa_e_pedido(self):
        self.assertEqual(b.entender_corretor({"intencao": "pedido", "pedido": {"teto": 300000}},
                                             ["EI NAY BOM DIA", "TEM ALGUMA COISA ATÉ 300 MIL VENDA"], None, {}, False), "pedido")
        self.assertIn("TEM ALGUMA COISA ATÉ 300 MIL VENDA", b.PROMPT_CORRETOR)

    def test_5642_o_nosso_pedido_do_grupo_encaminhado_nao_e_pedido_dele(self):
        t, achou = b.sem_nosso_pedido(TEXTO_5642)
        self.assertTrue(achou)
        self.assertNotIn("PRECISO DE", t)
        self.assertIn("NOSSO pedido do grupo", t)
        self.assertIn("Ponta Negra", t)
        # é a busca cujo pedido foi ao grupo
        busca = {"id": 109, "filtros": {"finalidade": "locacao", "tipo": "apartamento", "bairros": ["Ponta Negra", "Da Paz"],
                                        "quartos": 2, "aceita_menos_quartos": True, "teto": 2600, "mobilia": "mobiliado"}}
        self.assertEqual(b.busca_do_pedido_citado([{"id": 1, "filtros": {"finalidade": "venda", "teto": 1}}, busca], [TEXTO_5642]), busca)
        # o modelo leu pedido; com o imóvel dele junto é oferta, sem imóvel nenhum não é nada
        oferta = {"intencao": "pedido", "pede_imovel": True, "imovel": {"condominio": "Conquista Rio Negro", "valor": 2400}}
        self.assertEqual(b.entender_corretor(oferta, [TEXTO_5642, "Alugo -Mobiliado"], None, {}, True), "oferta")
        self.assertEqual(b.entender_corretor({"intencao": "pedido", "pede_imovel": True}, [TEXTO_5642], None, {}, True), "outro")

    def test_7891_o_anuncio_e_nosso(self):
        with mock.patch.object(b, "imovel_do_anuncio", return_value=dict(IM_2462)), \
                mock.patch.object(b.banco, "um", return_value=2462):
            self.assertEqual(b.nosso_do_anuncio(None, ANUNCIO_7891), {"codigo": 2462})
        with mock.patch.object(b, "imovel_do_anuncio", return_value=dict(IM_2462)), mock.patch.object(b.banco, "um", return_value=None):
            self.assertEqual(b.nosso_do_anuncio(None, ANUNCIO_7891), {"codigo": None})        # o Tel é o anunciante
            self.assertIsNone(b.nosso_do_anuncio(None, {**ANUNCIO_7891, "anunciante": "Ana Corretora"}))

    def test_7891_cliente_dele_quer_visitar_o_nosso_e_visita_para_a_equipe(self):
        r = {"intencao": "oferta", "oferece_imovel": True, "imovel": dict(IM_2462),
             "baloes": ["Vou confirmar com o cliente sobre a visita de amanhã e retorno."]}
        novas = ["Temos cliente interessado em visitar amanhã", "Se possível agenda a visita para amanhã às 14:30 h"]
        self.assertEqual(b.entender_corretor(r, novas, {"codigo": 2462}, IM_2462, False), "visita")
        # sem visita no texto, o imóvel "oferecido" é o do nosso anúncio: não é cadastro
        self.assertEqual(b.entender_corretor(r, ["Essa casa ainda está disponível e aberta a parceria ?"], {"codigo": 2462},
                                             IM_2462, False), "duvida")
        um = mock.Mock(return_value=None)
        with mock.patch.object(b.whatsapp, "_ao_crm") as crm, mock.patch.object(b.banco, "um", um):
            baloes = b._atender_visita(mock.Mock(), {"telefone": "5592993987891", "nome": "Lucas"}, {"codigo": 2462}, [], novas,
                                       r["baloes"])
        self.assertIn("#2462", crm.call_args.args[0])
        self.assertIn("visitar", crm.call_args.args[0])
        self.assertTrue(any("estado = 'humano'" in c.args[1] for c in um.call_args_list))
        self.assertEqual(baloes, ["Show! Vou ver o horário com a equipe e já te retorno por aqui."])   # nada de "o cliente"

    def test_7891_o_turno_diz_que_o_anuncio_e_nosso(self):
        cor = {"origem": "olx", "imovel": {}, "busca": None}
        with mock.patch.object(b, "condominio_citado", return_value=""), mock.patch.object(b.banco, "linhas", return_value=[]):
            t = b._turno_corretor(None, cor, [_msg(22027, LINK_7891)], [], 0, ANUNCIO_7891, {}, [], nosso={"codigo": 2462})
        self.assertIn("ANÚNCIO NOSSO", t)
        self.assertIn("#2462", t)
        self.assertNotIn("ANÚNCIO DA OLX deste imóvel", t)


SIMON = {"tipo": "apartamento", "finalidade": "venda", "bairro": "Centro", "condominio": "Edifício Simon Bolivar",
         "valor": 250000, "quartos": 1}
SMART = {"tipo": "apartamento", "finalidade": "locacao", "bairro": "Tarumã", "condominio": "Smart Tarumã", "valor": 1600,
         "quartos": 2, "area": 45, "mobilia": "com modulados e ar", "andar": "4º andar"}
TORQUATO = {"tipo": "apartamento", "finalidade": "locacao", "condominio": "Conquista Torquato Tapajós", "quartos": 2,
            "area": 42, "valor": 2500, "mobilia": "mobiliado", "bairro": "Tarumã"}
GIRASSOL = {"tipo": "apartamento", "finalidade": "locacao", "condominio": "Jardim Paradiso Girassol", "quartos": 3, "area": 53,
            "valor": 2000, "mobilia": "mobiliado", "bairro": "Tarumã"}


def _oferta(cor, r, b_=None, fotos=14, docs=0, ja=None, novas=()):
    cadastros, ums = [], []

    def cadastrar(conn, c, busca, ativo, fotos_do_anuncio=None, anuncio=None, com_fotos=True):
        cadastros.append({"cor": c, "busca": busca, "ativo": ativo, "com_fotos": com_fotos})
        return 9140 + len(cadastros)
    with mock.patch.object(b, "cadastrar", side_effect=cadastrar), \
            mock.patch.object(b.banco, "um", side_effect=lambda conn, sql, params=None: ums.append((sql, params))), \
            mock.patch.object(b, "condominio_da_base", return_value=None), mock.patch.object(b, "_qtd_fotos", return_value=fotos), \
            mock.patch.object(b.whatsapp, "_ao_crm") as crm, mock.patch.object(b, "passo"), \
            mock.patch.object(b, "oferecer_ao_cliente", return_value="cliente"), mock.patch.object(b, "_fechar_se_completa"):
        baloes = b._atender_oferta(mock.Mock(), cor, r, b_, SIM, ja=ja if ja is not None else b.sem_marcas(cor.get("imovel")),
                                   anuncio=None, do_anuncio={}, fotos=fotos, docs=docs, fotos_anuncio=[], novas=list(novas),
                                   baloes=[])
    return baloes, cadastros, ums, crm


class Erro3_UmImovelPorOferta(unittest.TestCase):
    def test_o_que_e_outro_imovel(self):
        self.assertFalse(b.mesmo_imovel(SIMON, SMART))                      # o #9130
        self.assertFalse(b.mesmo_imovel(TORQUATO, GIRASSOL))                # o #9132
        self.assertFalse(b.mesmo_imovel({"condominio": "Residencial Conquista Tarumã", "valor": 2100}, SMART))   # o anúncio
        self.assertTrue(b.mesmo_imovel({"condominio": "Smart Taruma", "valor": 1600}, SMART))
        self.assertTrue(b.mesmo_imovel({"bairro": "Tarumã"}, {"area": 45, "andar": "4º andar"}))   # só somou dados

    def test_8525_oferta_nova_abre_pre_cadastro_novo(self):
        cor = {"telefone": "5592982508525", "nome": "x", "codigo": 9130, "imovel": dict(SIMON), "busca": None}
        r = {"intencao": "oferta", "oferece_imovel": True, "imovel": dict(SMART)}
        _, cadastros, ums, _ = _oferta(cor, r, novas=["Tenho ap so no smart taruma 1600"])
        c = cadastros[0]["cor"]
        self.assertIsNone(c["codigo"])                                      # não é o #9130
        self.assertEqual((c["imovel"]["valor"], c["imovel"]["finalidade"]), (1600, "locacao"))
        self.assertNotIn("Simon", str(c["imovel"]))
        upd = next(p for s, p in ums if "SET imovel = %s::jsonb" in s)
        self.assertTrue(upd[2])                                             # o código do corretor zera: o novo entra no lugar

    def test_8020_dois_imoveis_de_uma_vez_viram_dois_rascunhos(self):
        cor = {"telefone": "5592991398020", "nome": "x", "codigo": None, "imovel": {}, "busca": None}
        r = {"intencao": "oferta", "oferece_imovel": True, "imovel": dict(TORQUATO), "mais_imoveis": [dict(GIRASSOL)]}
        _, cadastros, _, crm = _oferta(cor, r, fotos=40)
        self.assertEqual(len(cadastros), 2)
        self.assertFalse(any(x["ativo"] for x in cadastros))               # nada vira Disponível sozinho
        self.assertEqual(cadastros[0]["cor"]["imovel"]["condominio"], "Conquista Torquato Tapajós")
        self.assertEqual(cadastros[1]["cor"]["imovel"]["condominio"], "Jardim Paradiso Girassol")
        self.assertFalse(cadastros[1]["com_fotos"])                         # as fotos ficam num só, e a equipe separa
        self.assertIn("#9141", crm.call_args.args[0])
        self.assertIn("#9142", crm.call_args.args[0])


VILLAGE_VERT = ("*Ótima oportunidade!* \nhttps://www.imoveis.manaus.br/imovel/4200066/apartamento-venda-manaus-am-adrianopolis-"
                "condominio-village-vert\n\n🏡 APARTAMENTO – CONDOMÍNIO VILLAGE VERT ✨💎\n📍 Av. Umberto Calderaro, 2200 – "
                "Adrianópolis\n📐 Área: 142 m²\n\n🛏️ ESPAÇO E CONFORTO:\n" + "✅ ambiente amplo e elegante 🛋️✨\n" * 25
                + "💰 VALORES E CONDIÇÕES:\n✅ Valor de venda de: R$ 699.000,00 por R$ 660.000,00\n✅ Condomínio: R$ 1.490,00")


class Erro4_PerguntaOQueEleJaDisse(unittest.TestCase):
    def test_1009_o_texto_longo_inteiro_e_as_fotos_como_documento(self):
        self.assertGreater(VILLAGE_VERT.index("R$ 660.000,00"), 600)       # cortado em 600, o valor sumia
        conversa = ([_msg(22314, VILLAGE_VERT)] + [_msg(22315 + i, "", origem="documento") for i in range(25)]
                    + [_msg(22340, "Qual é o valor de venda? Pode me mandar pelo menos 3 fotos do imóvel por aqui?",
                            direcao="enviada", origem="resposta")])
        self.assertEqual(b.docs_recebidos(conversa), 25)
        with mock.patch.object(b, "condominio_citado", return_value=""):
            t = b._turno_corretor(None, {"origem": "parceria", "imovel": {}}, conversa, [], 0, docs=25)
        self.assertIn("R$ 660.000,00", t)
        self.assertIn("CORRETOR: [25 arquivos (fotos mandadas como documento)]", t)   # uma linha só para as 25
        self.assertEqual(t.count("arquivos (fotos mandadas"), 1)
        self.assertIn("mais 25 mandadas como ARQUIVO", t)
        self.assertNotIn("as fotos", t.split("FALTA PARA O CARD:")[1].split("\n")[0])
        self.assertIn("JÁ PERGUNTADO (não repita): Qual é o valor de venda?", t)
        self.assertGreaterEqual(b.CONVERSA_DO_CORRETOR, 80)

    def test_1009_o_imovel_e_anotado_mesmo_sem_servir_a_busca(self):
        cor = {"telefone": "5592986141009", "nome": "x", "codigo": None, "imovel": {}, "busca": 44}
        vv = {"tipo": "apartamento", "finalidade": "venda", "bairro": "Adrianópolis", "condominio": "Village Vert", "area": 142,
              "valor": 660000, "quartos": 4, "suites": 4}
        _, cadastros, ums, _ = _oferta(cor, {"intencao": "oferta", "oferece_imovel": True, "serve": "nao", "imovel": vv},
                                       b_={"id": 44, "lead": 1, "filtros": {}})
        self.assertIsNone(cadastros[0]["busca"])                            # não vai àquela busca, mas entra na base
        upd = next(p for s, p in ums if "SET imovel = %s::jsonb" in s)
        self.assertIn("Village Vert", upd[0])

    def test_3703_suites_sao_quartos_e_o_condominio_da_base_da_o_bairro(self):
        base = lambda conn, n: {"nome": "Bella Sonata Residencial", "bairro": "Tarumã"} if "sonata" in (n or "").lower() else None
        with mock.patch.object(b, "condominio_da_base", side_effect=base):
            im = b.completar_imovel(None, {"tipo": "casa", "bairro": "Turismo", "suites": 3, "valor": 850000},
                                    ["Condomínio Bela sonata", "Porteira fechada", "Casa com 3 suítes\nSala cozinha e sala de vídeo"])
        self.assertEqual((im["quartos"], im["condominio"], im["bairro"], im["tipo"]),
                         (3, "Bella Sonata Residencial", "Tarumã", "casa em condomínio"))
        self.assertIn("Suítes são quartos", b.PROMPT_CORRETOR)

    def test_5600_a_pergunta_feita_nao_sai_de_novo(self):
        conversa = [_msg(22344, "Essa duplex é casa ou apartamento? Quantos quartos tem?", direcao="enviada", origem="resposta")]
        baloes = ["Obrigada pelas informações e pelas fotos! É casa ou apartamento? E qual é a área em m²?"]
        self.assertEqual(b.sem_pergunta_repetida(baloes, b.ja_perguntado(conversa)),
                         ["Obrigada pelas informações e pelas fotos! E qual é a área em m²?"])
        self.assertEqual(b.sem_pergunta_repetida(["É casa ou apartamento?"], b.ja_perguntado(conversa)), [])


# ─────────────────────────── NAY LEADS ───────────────────────────
LORENA = {"id": 148, "telefone": "92992649301", "codigo": 5724, "enviados": [5724, 9128, 9048], "filtros": {}}


class Erro5_Lorena9301_PromessaDeFoto(unittest.TestCase):
    ULTIMA = "O Estilo Golf tem 2 quartos, sendo 1 suíte. A senhora quer as fotos do Vista dos Jatobás ou do Estilo Golf?"

    def test_ja_te_mando_e_promessa(self):
        for t in ("Já te mando as fotos do apartamento no Conquista Rio Negro.", "Te mando aqui as informações e as fotos dele.",
                  "Vou separar as fotos da sala do apartamento no Conquista Rio Negro e já retorno"):
            self.assertTrue(w.PROMETE_FOTO.search(t), t)
        self.assertFalse(w.PROMETE_FOTO.search("O Estilo Golf tem 2 quartos, sendo 1 suíte."))
        self.assertEqual(w.promessa_sem_entrega(["Já te mando as fotos do apartamento no Conquista Rio Negro."], [])[0], [])

    def _depois(self, fotos_antigas: bool):
        r = {"baloes": ["Já te mando as fotos do apartamento no Conquista Rio Negro."], "acoes": ["fotos"],
             "fotos": {"codigos": [5724]}}
        # as fotos do 5724 foram 22 h antes (03/11 12:51): "já foram" sempre, mas não nas últimas 2 h
        ja_foram = (lambda conn, lead, c, horas=None: horas is None) if fotos_antigas else (lambda *a, **k: True)
        with mock.patch.object(w, "fotos_ja_foram", side_effect=ja_foram), mock.patch.object(w, "card_visto", return_value=True), \
                mock.patch.object(w, "_ofertavel", return_value=True):
            acoes, passos = w.depois_do_modelo(None, dict(LORENA), r, ["Conquista"], self.ULTIMA)
        return r, acoes, passos

    def test_pediu_foto_de_fotos_antigas_recebe_de_novo(self):
        r, acoes, _ = self._depois(fotos_antigas=True)
        self.assertIn("fotos", acoes)
        self.assertTrue(r["_pediu_foto"])
        self.assertEqual(w._baloes_do(r), ["Já te mando as fotos do apartamento no Conquista Rio Negro."])
        with mock.patch.object(w, "fotos_ja_foram", side_effect=lambda conn, lead, c, horas=None: horas is None), \
                mock.patch.object(w, "card_visto", return_value=True), mock.patch.object(w, "_ofertavel", return_value=True), \
                mock.patch.object(w, "mandar_imovel") as imovel, mock.patch.object(w, "_marcar"), \
                mock.patch.object(w, "ja_mandou", return_value=[]), mock.patch.object(w.time, "sleep"), \
                mock.patch.object(w.agentes, "acao"), mock.patch.object(w.agentes, "passo"):
            w._fazer(None, dict(LORENA), r, "fotos", {})
        imovel.assert_called_once_with(None, mock.ANY, 5724, com_card=False, com_fotos=True, repetir=False)

    def test_fotos_de_agora_ha_pouco_nao_repetem_e_a_promessa_sai(self):
        r, acoes, passos = self._depois(fotos_antigas=False)
        self.assertNotIn("fotos", acoes)
        self.assertEqual(w._baloes_do(r), [])                                # "Já te mando as fotos" não sai sem foto
        self.assertIn("promessa_sem_acao", [n for n, _d in passos])
        self.assertEqual(w.turno_mudo(r, acoes, passos, ["Conquista"]), "fotos")   # o modelo responde em texto


ALEXANDRE = {"id": 155, "telefone": "55997016541", "codigo": 5724, "enviados": [5724], "filtros": {}}


class Erro6_Alexandre6541_PerguntaDescartada(unittest.TestCase):
    def test_o_prompt_resolve_na_hora(self):
        self.assertIn("Resolva NA HORA", w.PROMPT)
        self.assertIn("Nunca prometa separar ou mandar foto sem a acao", w.PROMPT)
        self.assertNotIn("diga que vai separar\n   essas fotos e já retorna", w.PROMPT)
        from olx import agentes
        self.assertIsNotNone(agentes.partes_do_prompt(w.PROMPT))           # o corte por caminho continua lendo o PROMPT

    def test_vou_separar_sem_acao_nenhuma_nao_sai(self):
        r = {"baloes": ["Vou separar as fotos da sala do apartamento no Conquista Rio Negro e já retorno, Sr. Alexandre."],
             "acoes": []}
        with mock.patch.object(w, "_ofertavel", return_value=True):
            acoes, passos = w.depois_do_modelo(None, dict(ALEXANDRE), r, ["Olá boa noite", "Você tem foto da sala?"], "")
        self.assertEqual(w._baloes_do(r), [])
        self.assertEqual(w.turno_mudo(r, acoes, passos, ["Você tem foto da sala?"]), "mudo")
        # com "perguntar" a promessa é cumprida pela fila: fica
        r = {"baloes": ["Vou separar as fotos da sala do apartamento no Conquista Rio Negro e já retorno."], "acoes": ["perguntar"]}
        with mock.patch.object(w, "_ofertavel", return_value=True):
            w.depois_do_modelo(None, dict(ALEXANDRE), r, ["Você tem foto da sala?"], "")
        self.assertEqual(len(w._baloes_do(r)), 1)

    def _fechar(self, modelo_disse, gente=None, ja_entregue=False):
        p = {"id": 379, "chave": "55997016541", "codigo": 5724, "criada_em": AGORA - timedelta(minutes=10),
             "pergunta": "Fotos da sala do apartamento no Conquista Rio Negro (#5724)"}

        def linhas(conn, sql, params=None):
            return [p] if "FROM pergunta_fila" in sql else [{"id": 155}] if "olx_lead_whatsapp" in sql else []
        um = mock.Mock(side_effect=lambda conn, sql, params=None: ja_entregue if "EXISTS" in sql else None)
        with mock.patch.object(w.banco, "linhas", side_effect=linhas), mock.patch.object(w.banco, "um", um), \
                mock.patch.object(w, "_lead", return_value=dict(ALEXANDRE, humano_em=None)), \
                mock.patch.object(w, "_gente_escreveu", return_value=gente), \
                mock.patch.object(w.modelo, "chamar", return_value={"texto": modelo_disse}), \
                mock.patch.object(w.agentes, "passo"), mock.patch.object(w, "mandar_texto") as texto:
            n = w.fechar_descartadas(mock.Mock())
        return n, texto, [c.args[1] for c in um.call_args_list]

    def test_a_pergunta_descartada_e_fechada_com_o_cliente(self):
        n, texto, sqls = self._fechar("As fotos que tenho do apartamento são essas aí de cima; na visita dá para ver a sala de perto.")
        self.assertEqual(n, 1)
        self.assertIn("visita", texto.call_args.args[2])
        self.assertTrue(any("entregue_em = now()" in s for s in sqls))
        # o modelo prometeu de novo: vai a frase pronta, sem promessa
        _, texto, _ = self._fechar("Vou verificar com a equipe e já retorno.")
        self.assertNotRegex(texto.call_args.args[2], w.PROMESSA)
        # a equipe falou com ele depois da pergunta, ou ele já recebeu resposta: nada sai
        n, texto, sqls = self._fechar("x", gente=AGORA)
        self.assertEqual(n, 0)
        texto.assert_not_called()
        self.assertTrue(any("a equipe está na conversa" in s for s in sqls))
        n, texto, _ = self._fechar("x", ja_entregue=True)
        texto.assert_not_called()


class Erro7_Karoline0222_LocalizacaoInventada(unittest.TestCase):
    def test_localizacao_so_da_ficha(self):
        self.assertIn("LOCALIZAÇÃO SÓ DA FICHA", w.PROMPT)
        self.assertNotIn("Avenidas de referência do bairro\": \"fica no <bairro>", w.PROMPT)
        linha = {"codigo": 9104, "tipo": "Casa", "condo": None, "bairro": "Parque 10 de Novembro", "quartos": 4,
                 "valor_venda": None, "valor_aluguel": 6500, "av_conjunto": None,
                 "av_bairro": "Maneca Marques, Mário Ypiranga, Perimetral, Tancredo Neves"}
        with mock.patch.object(w.banco, "linhas", return_value=[linha]):
            l = w.imoveis_da_conversa(None, {"codigo": 9104, "enviados": []})[0]
        self.assertIn("NÃO são a localização do imóvel", l)
        self.assertNotIn("avenidas de referência do bairro", l)


ALLEFE = {"id": 152, "telefone": "92999992423", "enviados": [5722, 9133], "negocio": "locacao",
          "filtros": {"finalidade": "locacao", "tipo": "apartamento", "teto": 2200, "bairros": ["Tarumã"], "quartos": 2,
                      "mobilia": "mobiliado"}}


class Erro8_Allefe2423_SimAoAfrouxar(unittest.TestCase):
    PERGUNTA = "Em Tarumã com 2 quartos não tenho agora; serve um pouco acima de R$ 2.200?"

    def test_serve_sim_aplica_e_busca(self):
        g, o_que = w.afrouxar_aceito(ALLEFE["filtros"], ["Blz", "Serve sim"], self.PERGUNTA)
        self.assertEqual(g, {"teto": 2400})                                  # +20% com a folga de 10% da busca
        r = {"baloes": ["Que bom, Sra. Allefe. Até quanto a senhora consegue chegar no aluguel?"], "acoes": [], "filtros": {}}
        acoes, passos = w.depois_do_modelo(None, dict(ALLEFE), r, ["Blz", "Serve sim"], self.PERGUNTA)
        self.assertEqual(acoes, ["buscar"])
        self.assertEqual(w._filtros(ALLEFE["filtros"], r["filtros"])["teto"], 2400)
        self.assertFalse(any(x.endswith("?") for x in w._baloes_do(r)))    # nada de "Até quanto consegue chegar?"
        self.assertIn("afrouxar_aceito", [n for n, _d in passos])

    def test_os_outros_afrouxar_e_o_nao(self):
        f = ALLEFE["filtros"]
        self.assertEqual(w.afrouxar_aceito(f, ["sim"], "Em Tarumã com 2 quartos não tenho agora; serve com 1?")[0],
                         {"aceita_menos_quartos": True})
        self.assertEqual(w.afrouxar_aceito(f, ["pode ser"], "Em Tarumã não achei agora; serve num bairro vizinho, como Ponta Negra?")[0],
                         {"bairros": ["Tarumã", "Ponta Negra"]})
        self.assertEqual(w.afrouxar_aceito(f, ["não, só no Tarumã"], self.PERGUNTA), ({}, ""))
        self.assertEqual(w.afrouxar_aceito(f, ["Serve sim"], "Quer conhecer o apartamento?"), ({}, ""))


class Erro9_Allefe2423_CardSozinho(unittest.TestCase):
    """21:34: o card do 9132 saiu sozinho. Não foi a Nay: foi o "Enviar imóvel" do CRM (captacao_envio_pedido 52; o 53 e o
    49 do ...0662 também), que manda só card e fotos."""

    def _enviar(self, humano_em=None, gente=None):
        pedido = {"id": 52, "telefone": "5592999992423", "codigos": [9132]}

        def linhas(conn, sql, params=None):
            return [pedido] if "captacao_envio_pedido" in sql else [{"id": 152}] if "olx_lead_whatsapp" in sql else []
        ordem = mock.Mock()
        with mock.patch.object(w.banco, "linhas", side_effect=linhas), mock.patch.object(w.banco, "um", return_value=None), \
                mock.patch.object(w, "_lead", return_value={**ALLEFE, "nome": "Allefe", "humano_em": humano_em}), \
                mock.patch.object(w, "_ofertavel", return_value=True), mock.patch.object(w, "_gente_escreveu", return_value=gente), \
                mock.patch.object(w, "ja_mandou", return_value=[]), mock.patch.object(w, "_marcar"), \
                mock.patch.object(w, "mandar_texto", ordem.texto), mock.patch.object(w, "mandar_imovel", ordem.imovel):
            w.enviar_pedidos(mock.Mock())
        return [c[0] for c in ordem.mock_calls]

    def test_o_envio_do_crm_vem_com_uma_frase_antes(self):
        self.assertEqual(self._enviar(), ["texto", "imovel"])
        self.assertEqual(self._enviar(humano_em="x"), ["imovel"])           # a equipe está com ela: só o que a equipe mandou
        self.assertEqual(self._enviar(gente=AGORA), ["imovel"])             # a equipe acabou de escrever


class Erro10_Joyce0113_PromessaENegativa(unittest.TestCase):
    BALOES = ["O endereço exato do galpão no Centro eu passo quando marcarmos a visita.",
              "Vou separar outros galpões no Centro com aluguel até R$ 5.000 e te mando."]

    def test_a_busca_vazia_tira_a_promessa_de_mandar(self):
        sobra, tiradas = w.promessa_sem_entrega(self.BALOES, ["buscar"], opcoes_vazias=True)
        self.assertEqual(sobra, self.BALOES[:1])
        self.assertEqual(tiradas, self.BALOES[1:])
        self.assertEqual(w.promessa_sem_entrega(self.BALOES, ["buscar"])[0], self.BALOES)   # achou: a promessa vale

    def _buscar(self, recente: bool):
        lead = {"id": 160, "telefone": "92999990113", "etapa": "imoveis_enviados", "enviados": [5752], "nome": "Joyce"}
        f = {"finalidade": "locacao", "tipo": "galpao", "teto": 5000, "bairros": ["Centro", "Cachoeirinha"]}
        previa = {"b": {"f": f, "achados": [], "proximas": False, "antes_do_veto": [], "ms": 1, "excluir": [], "nomes_recusados": []},
                  "novos": []}
        from olx import buscas
        with mock.patch.object(w, "buscar_na_base", side_effect=AssertionError("a busca prévia vale")), \
                mock.patch.object(w, "_marcar"), mock.patch.object(w.agentes, "passo"), mock.patch.object(w, "ja_mandou", return_value=[]), \
                mock.patch.object(buscas, "resultado_da_base", return_value=False), mock.patch.object(buscas, "cliente_avisado"), \
                mock.patch.object(w.banco, "um", return_value=True), mock.patch.object(w, "pergunta_para_afrouxar", return_value=""), \
                mock.patch.object(w, "negativa_recente", return_value=recente), mock.patch.object(w, "mandar_texto") as texto:
            w._buscar_e_mandar(None, lead, f, previa=previa)
        return texto

    def test_a_negativa_nao_se_repete_em_poucos_minutos(self):
        self._buscar(recente=True).assert_not_called()
        self.assertRegex(self._buscar(recente=False).call_args.args[2], w.NEGATIVA)
        self.assertTrue(w.NEGATIVA.search("Ainda não apareceu nada nesse perfil; vou continuar de olho e te aviso por aqui."))


class Erro11_0662_BomDia(unittest.TestCase):
    def test_bom_dia_que_abre_o_dia_pede_resposta(self):
        card = [{"texto": "📍 Verdes Mares I ... Código: 9060", "criada_em": datetime(2026, 11, 3, 22, 46, tzinfo=timezone.utc)}]
        manha = datetime(2026, 11, 4, 11, 26, tzinfo=timezone.utc)
        self.assertTrue(w.saudacao_que_pede_resposta(["Bom dia!"], card, manha))
        self.assertFalse(w.saudacao_que_pede_resposta(["Bom dia!"], card, card[0]["criada_em"] + timedelta(minutes=5)))
        self.assertFalse(w.saudacao_que_pede_resposta(["Obrigada"], card, manha))
        self.assertFalse(w.saudacao_que_pede_resposta(["Bom dia!"], [], manha))


if __name__ == "__main__":
    unittest.main()
