"""O fluxo de busca do cliente (475, Pedro 22/10/2026): a mensagem dos grupos e a regra de qual grupo recebe o quê.
"Nunca errar e pedir a coisa errada no grupo errado." O banco é provado no ensaio da 475."""
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

LOCACAO_SO = {"grupo_id": "l", "nome": "Locação CREDENCIADOS", "locacao": True, "venda": False, "locacao_min": None, "venda_min": None}
TODOS = {"grupo_id": "t", "nome": "FECHANDO PARCERIAS 1.0", "locacao": True, "venda": True, "locacao_min": None, "venda_min": None}
ALTO = {"grupo_id": "a", "nome": "Alto Padrão", "locacao": True, "venda": True, "locacao_min": 7000, "venda_min": 800000}


class QualGrupo(unittest.TestCase):
    def test_venda_nunca_vai_ao_grupo_de_locacao(self):
        f = {"finalidade": "venda", "tipo": "apartamento", "teto": 700000}
        self.assertFalse(b.grupo_aceita(LOCACAO_SO, f))
        self.assertTrue(b.grupo_aceita(TODOS, f))

    def test_alto_padrao_so_locacao_de_7_mil_e_venda_de_800_mil(self):
        self.assertFalse(b.grupo_aceita(ALTO, {"finalidade": "locacao", "teto": 4500}))
        self.assertTrue(b.grupo_aceita(ALTO, {"finalidade": "locacao", "teto": 7000}))
        self.assertFalse(b.grupo_aceita(ALTO, {"finalidade": "venda", "teto": 700000}))
        self.assertTrue(b.grupo_aceita(ALTO, {"finalidade": "venda", "teto": 800000}))

    def test_sem_valor_o_alto_padrao_nao_recebe(self):
        self.assertFalse(b.grupo_aceita(ALTO, {"finalidade": "venda", "tipo": "casa"}))

    def test_sem_negocio_nenhum_grupo_recebe(self):
        for g in (LOCACAO_SO, TODOS, ALTO):
            self.assertFalse(b.grupo_aceita(g, {"tipo": "apartamento", "teto": 900000}))

    def test_alugar_e_comprar_ditos_de_outro_jeito(self):
        self.assertEqual(b.finalidade({"finalidade": "aluguel"}), "locacao")
        self.assertEqual(b.finalidade({"finalidade": "compra"}), "venda")


class Mensagem(unittest.TestCase):
    def test_o_molde_do_tel(self):
        # Tel, 22/10: "✅PRECISO DE AP P/ VENDA - bairros: parque dez, flores, Aleixo - 3 quartos - até 700.000 - OBS:"
        t = b.mensagem_de_grupo({"finalidade": "venda", "tipo": "apartamento", "bairros": ["parque dez", "flores", "Aleixo"],
                                 "quartos": 3, "teto": 700000})
        self.assertEqual(t, "✅ PRECISO DE AP P/ VENDA\n- bairros: parque dez, flores, Aleixo\n- 3 quartos\n- até 700.000\n\n"
                            "Tem algum? Me chama no privado.")

    def test_casa_em_condominio_com_obs(self):
        t = b.mensagem_de_grupo({"finalidade": "locacao", "tipo": "casa_condominio", "bairros": ["parque dez", "flores", "Aleixo"],
                                 "quartos": 3, "aceita_menos_quartos": True, "teto": 4500, "mobilia": "mobiliado"})
        self.assertTrue(t.startswith("✅ PRECISO DE CS EM CONDOMÍNIO P/ LOCAÇÃO\n- bairros: parque dez, flores, Aleixo\n"
                                     "- 2 ou 3 quartos\n- até 4.500\n- OBS: mobiliado"))

    def test_sem_o_final_antigo(self):
        t = b.mensagem_de_grupo({"finalidade": "venda", "tipo": "casa", "teto": 500000})
        self.assertNotIn("com as fotos e o valor", t)
        self.assertNotIn("Trabalhamos em parceria", t)
        self.assertTrue(t.startswith("✅ PRECISO DE CASA P/ VENDA"))

    def test_nunca_leva_dado_do_cliente(self):
        t = b.bloco({"finalidade": "locacao", "tipo": "apartamento", "teto": 3000, "nome": "Michelle", "telefone": "92981585907"})
        self.assertNotIn("Michelle", t)
        self.assertNotIn("9298", t)

    def test_sem_bairro_e_qualquer_bairro(self):
        self.assertIn("qualquer bairro", b.bloco({"finalidade": "venda", "tipo": "casa", "teto": 500000}))

    def test_mobilia_so_na_locacao(self):
        self.assertNotIn("mobiliado", b.bloco({"finalidade": "venda", "tipo": "apartamento", "teto": 500000, "mobilia": "mobiliado"}))

    def test_so_no_condominio_vai_assim_ao_grupo(self):
        # 27/10, o Sr. Karis: "só no Ponta Negra Village"
        f = b.limpo({"finalidade": "locacao", "tipo": "casa_condominio", "bairros": ["Ponta Negra"], "teto": 7000,
                     "condominio": "Ponta Negra Village", "so_condominio": True})
        self.assertTrue(f.get("so_condominio"))
        self.assertIn("- OBS: só no Ponta Negra Village", b.bloco(f))
        self.assertIn("de preferência no Ponta Negra Village", b.bloco({**f, "so_condominio": False}))


class Corretor(unittest.TestCase):
    def test_o_que_falta_para_o_cadastro(self):
        im = {"tipo": "apartamento", "finalidade": "locacao", "bairro": "Flores", "quartos": 2, "valor": 3000}
        self.assertEqual(b.falta_no_imovel(im, 0), ["o condomínio", "a mobília", "as fotos"])
        self.assertEqual(b.falta_no_imovel({**im, "condominio": "Smile", "mobilia": "mobiliado"}, 3), [])

    def test_o_novo_nao_apaga_o_que_ja_sabiamos(self):
        self.assertEqual(b.juntar_imovel({"bairro": "Flores", "quartos": 2}, {"bairro": "", "quartos": 0, "valor": 3000}),
                         {"bairro": "Flores", "quartos": 2, "valor": 3000})


class PerguntaAoAnunciante(unittest.TestCase):
    """Pedro, 23/10: sem o link do anúncio, só o nome do prédio."""
    A = {"titulo": "Garden Club - 124m2 - 03 suítes - AP no Parque 10 - Vendo", "preco": 950000, "bairro": "Parque 10",
         "url": "https://am.olx.com.br/regiao-de-manaus/imoveis/garden-club-1490357818"}

    def test_com_o_predio_e_sem_o_link(self):
        t = b.pergunta_ao_anunciante(self.A, "Garden Club Residencial")
        self.assertIn("Vi o seu anúncio na OLX do *Garden Club Residencial* (", t)
        self.assertNotIn("olx.com.br", t)
        self.assertNotIn("124m2", t)

    def test_o_predio_vem_do_trecho_do_titulo_e_nao_do_bairro_do_fim(self):
        """Pedro, 24/10: a Suzy (anuncio do The Club, Parque das Laranjeiras) ouviu 'Condominio Laranjeiras'."""
        f = b.trecho_do_predio
        self.assertEqual(f("ALUGO R$ 4.000, Apto 03 Quartos, Mobiliado, Cond Resid The Club, Parque das Laranjeiras"), "The Club")
        self.assertEqual(f("Edifício Milano - 74m2 - 03 quartos - Apartamento"), "Milano")
        self.assertEqual(f("Cond Shizen l - 260m2 - 03 suítes"), "Shizen l")
        self.assertIsNone(f("VENDO IMÓVEL AMPLO NO PETROPOLIS"))
        self.assertIsNone(f("Smart Tarumã - 2 quartos"))

    def test_sem_predio_vai_o_titulo_e_sem_o_link(self):
        t = b.pergunta_ao_anunciante(self.A)
        self.assertIn("*Garden Club - 124m2", t)
        self.assertNotIn("olx.com.br", t)


def _im(codigo, bairro, quartos, aluguel, mobilia=None, tipo="apartamento"):
    from grupos.texto import normal
    return {"codigo": codigo, "tipo": tipo, "bairro": bairro, "bairro_chave": normal(bairro), "condominio": None,
            "condominio_chave": "", "planilha_id": None, "quartos": quartos, "suites": 1, "vagas": 1, "andar": 3,
            "mobilia": mobilia, "pet": None, "financiamento": None, "elevador": True, "elevador_como": "",
            "valor_aluguel": aluguel, "valor_venda": None, "confirmado_em": datetime.now(timezone.utc)}


class OpcoesDaBase(unittest.TestCase):
    """Pedro, 23/10: "o ideal não é ter um imóvel enviado e sim 3 a 5 opções ... usar aquele mesmo algoritmo de
    julgamento de imóvel da aba captação ativa que dá notas"."""
    F = {"finalidade": "locacao", "tipo": "apartamento", "teto": 4000, "bairros": ["Flores"], "quartos": 2}
    VIZ = {"flores": {"parque 10 de novembro": {"divisa": True, "km": 1.2}, "aleixo": {"divisa": True, "km": 2.1},
                      "chapada": {"divisa": False, "km": 1.0}}}

    def _rodar(self, imoveis, f=None, quantas=5, ofertavel=lambda conn, c, lead: True):
        from olx import busca_olx as bo
        cat = mock.Mock(side_effect=lambda conn, com_parceiro=False: (list(imoveis), self.VIZ))
        resolver = lambda ficha, g, l: ({**ficha, "bairro_chaves": [x.lower() for x in ficha["bairros"]],
                                         "condominio_chaves": [], "local_nao_reconhecido": []}, None, None)
        with mock.patch.object(bo.gcatalogo, "carregar", cat), mock.patch.object(bo.glugares, "Lugares"), \
                mock.patch.object(bo.glugares, "resolver", side_effect=resolver), \
                mock.patch.object(b.whatsapp, "_ofertavel", side_effect=ofertavel):
            return b.opcoes_da_base(None, {"telefone": "92999990000"}, f or self.F, [9], quantas), cat

    def test_mais_de_uma_opcao_a_melhor_primeiro_e_o_vizinho_entra(self):
        r, _ = self._rodar([_im(1, "Flores", 2, 3900), _im(2, "Parque 10 de Novembro", 2, 3800), _im(3, "Flores", 3, 4000),
                            _im(4, "Ponta Negra", 2, 3900), _im(9, "Flores", 2, 4000)])
        self.assertEqual([x["codigo"] for x in r][:1], [1])
        self.assertEqual(sorted(x["codigo"] for x in r), [1, 2, 3])       # 4: longe; 9: ela já recebeu
        self.assertTrue(all(x["nota"] >= 70 for x in r))

    def test_so_o_vizinho_colado_e_so_na_faixa_de_valor(self):
        """Tel, 23/10: a Edsandra recebeu o Life Flores (Flores-Parque 10: divisa a 2,1 km) e dois de R$ 500 mil para
        teto de 750 mil."""
        r, _ = self._rodar([_im(1, "Aleixo", 2, 3900), _im(2, "Chapada", 2, 3900), _im(3, "Parque 10 de Novembro", 2, 3900),
                            _im(4, "Flores", 2, 3150), _im(5, "Flores", 2, 4450), _im(6, "Flores", 2, 3250)])
        self.assertEqual(sorted(x["codigo"] for x in r), [3, 6])   # 1: divisa longe; 2: perto sem divisa; 4 e 5: fora da faixa

    def test_no_maximo_as_que_faltam_e_abaixo_de_70_nao_vai(self):
        r, _ = self._rodar([_im(c, "Flores", 2, 3900) for c in (11, 12, 13, 14)] + [_im(15, "Flores", 2, 1700)], quantas=2)
        self.assertEqual(len(r), 2)
        r, _ = self._rodar([_im(15, "Flores", 2, 1700)])
        self.assertEqual(r, [])                                             # muito abaixo do teto: nota baixa

    def test_quem_nao_pode_receber_fica_fora_e_o_parceiro_so_se_aceita(self):
        r, cat = self._rodar([_im(1, "Flores", 2, 3900), _im(2, "Flores", 2, 3950)], ofertavel=lambda conn, c, lead: c != 1)
        self.assertEqual([x["codigo"] for x in r], [2])
        self.assertFalse(cat.call_args.kwargs["com_parceiro"])
        _, cat = self._rodar([_im(1, "Flores", 2, 3900)], f={**self.F, "aceita_parceiro": "true"})
        self.assertTrue(cat.call_args.kwargs["com_parceiro"])

    def test_casa_em_condominio_nao_recebe_casa_de_rua(self):
        rua, cond = _im(1, "Flores", 3, None, tipo="casa"), _im(2, "Flores", 3, None, tipo="casa")
        for i, t, v in ((rua, "Casa", 600000), (cond, "Casa de condomínio", 650000)):
            i.update(tipo_cadastro=t, valor_venda=v)
        f = {"finalidade": "venda", "tipo": "casa_condominio", "bairros": ["Flores"], "quartos": 3}
        r, _ = self._rodar([rua, cond], f=f)
        self.assertEqual([x["codigo"] for x in r], [2])

    def test_semi_e_semi(self):
        from olx import busca_olx as bo
        with mock.patch.object(bo.glugares, "resolver", side_effect=lambda ficha, g, l: (ficha, None, None)):
            self.assertEqual(bo.pedido_dos_filtros({**self.F, "mobilia": "semi"}, None, da_base=True)["mobiliado"], "semi")
            self.assertIs(bo.pedido_dos_filtros({**self.F, "mobilia": "semi"}, None)["mobiliado"], True)   # a OLX como era
            self.assertIsNone(bo.pedido_dos_filtros({**self.F, "finalidade": "venda", "mobilia": "mobiliado"}, None,
                                                    da_base=True)["mobiliado"])
            self.assertEqual(bo.pedido_dos_filtros({**self.F, "tipo": "sala"}, None, da_base=True)["tipo"], "sala")
            self.assertIsNone(bo.pedido_dos_filtros({**self.F, "tipo": "tanto_faz"}, None, da_base=True)["tipo"])

    def test_abaixo_do_minimo_nao_busca(self):
        """Pedro, 23/10: "não atendemos leads de imóveis abaixo de 200 mil ou abaixo de 2k de aluguel"."""
        c = {"venda_min": 200000.0, "aluguel_min": 2000.0}
        self.assertTrue(b.abaixo_do_minimo({"finalidade": "venda", "teto": 150000}, c))       # a busca 43
        self.assertFalse(b.abaixo_do_minimo({"finalidade": "venda", "teto": 200000}, c))
        self.assertTrue(b.abaixo_do_minimo({"finalidade": "locacao", "teto": "1800"}, c))
        self.assertFalse(b.abaixo_do_minimo({"finalidade": "aluguel", "teto": 2000}, c))
        self.assertFalse(b.abaixo_do_minimo({"finalidade": "venda"}, c))                       # sem valor: não se sabe
        self.assertIn("R$ 200.000", b.texto_do_minimo(c))

    def test_quem_pede_parceria_e_corretor_e_cliente_nao(self):
        """Pedro, 24/10: 'faz parceria no Kopenhagen?' e corretor; o cliente que fala 'o corretor me disse' nao."""
        f = b.parece_corretor
        for t in ("faz parceria no Kopenhagen?", "Boa tarde, sou corretor, tenho um apto no Flores", "Sou da imobiliária Casa Forte",
                  "meu CRECI é 1234", "Tenho cliente, aceitam parceria?", "Sou corretora de imóveis"):
            self.assertTrue(f(t), t)
        for t in ("o corretor me disse que tem um apartamento", "oi, vi o anúncio do 9024", "quero alugar um 2 quartos", ""):
            self.assertFalse(f(t), t)

    def test_corretor_sem_busca_so_pede_o_que_falta_no_cadastro(self):
        im = {"tipo": "apartamento", "finalidade": "locacao", "bairro": "Flores", "quartos": 3, "valor": 4000}
        self.assertEqual(b.falta_no_imovel(im, 0), ["o condomínio", "a mobília", "as fotos"])
        self.assertEqual(b.falta_no_imovel({**im, "condominio": "The Club", "mobilia": "mobiliado"}, 3), [])

    def test_repete_o_pedido_do_grupo_no_dia_seguinte_se_ninguem_ofereceu(self):
        """Pedro, 24/10: ninguém ofereceu, o mesmo pedido sai de novo no começo do dia seguinte (uma vez por dia)."""
        from datetime import datetime, timedelta
        from unittest import mock
        ontem = (datetime.now(b.MANAUS) - timedelta(days=1)).isoformat(timespec="minutes")
        hoje = datetime.now(b.MANAUS).isoformat(timespec="minutes")
        filtros = {"finalidade": "locacao", "tipo": "apartamento", "teto": 4000, "quartos": 3, "bairros": ["Flores"]}
        busca = {"id": 7, "filtros": filtros, "ofertas": [], "ativada_em": ontem,
                 "grupos": [{"grupo": "g1", "nome": "Grupo 1", "em": ontem, "teste": False}]}
        grupo = {"grupo_id": "g1", "nome": "Grupo 1", "ultimo_envio_em": None}
        c = {"grupos": "sim", "intervalo_min": 15, "teste": None, "de": 0, "ate": 24, "venda_min": 200000.0, "aluguel_min": 2000.0}
        enviados = []
        def linhas(conn, sql, params=None):
            return [busca] if "FROM privado.busca_cliente" in sql else [grupo] if "FROM privado.busca_grupo" in sql else []
        with mock.patch.object(b.banco, "linhas", side_effect=linhas), mock.patch.object(b.banco, "um", return_value=False),                 mock.patch.object(b, "_enviar", side_effect=lambda d, t: enviados.append((d, t)) or "m1"),                 mock.patch.object(b, "passo"), mock.patch.object(b.time, "sleep"):
            self.assertEqual(b.grupos_repete(mock.Mock(), c), 1)
            self.assertEqual(enviados[0][0], "g1")
            self.assertIn("PRECISO DE AP P/ LOCAÇÃO", enviados[0][1])
            # o pedido de hoje não se repete; quem recebeu imóvel de corretor também não
            busca["grupos"][0]["em"] = hoje
            self.assertEqual(b.grupos_repete(mock.Mock(), c), 0)
            busca["grupos"][0]["em"] = ontem
            busca["ofertas"] = [{"tel": "5592999990000", "codigo": 9}]
            self.assertEqual(b.grupos_repete(mock.Mock(), c), 0)

    def test_a_busca_so_termina_com_3_opcoes(self):
        o = [{"codigo": 1, "estado": "cliente"}, {"codigo": 1, "estado": "cliente"}, {"codigo": 2, "estado": "cadastrando"},
             {"codigo": 3, "estado": "grupo"}]
        self.assertEqual(b.opcoes_enviadas({"ofertas": o}), 2)
        self.assertEqual(b.opcoes_enviadas({"ofertas": o + [{"codigo": 4, "estado": "cliente"}]}), b.OPCOES_META)


if __name__ == "__main__":
    unittest.main()
