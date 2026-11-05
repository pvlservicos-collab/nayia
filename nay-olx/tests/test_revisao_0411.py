"""A revisão das conversas reais de 04/11/2026 (Pedro: "começa pelos erros, revisa tudo, prepara a solução, depois analisa
todas as soluções antes de fazer"). Um teste por erro, com o texto do caso real (o final do telefone no nome da classe).
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


if __name__ == "__main__":
    unittest.main()
