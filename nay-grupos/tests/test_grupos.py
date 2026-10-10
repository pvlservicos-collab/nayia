"""Testes do que é só conta: a limpeza da leitura, as regras do arquivo, os filtros e a nota.

    cd nay-grupos && python -m unittest discover -s tests -v

Não abrem banco nem rede. A leitura pela IA de verdade se prova com scripts/provar_extracao.py.
"""
import datetime
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from grupos import envio, extrair, lugares, pontuar, regras  # noqa: E402
from grupos.catalogo import andar_do, mobilia_do, tipo_do  # noqa: E402
from grupos.texto import normal  # noqa: E402

R = regras.conferir(json.loads(json.dumps(regras.PADRAO)))[0]
AGORA = datetime.datetime.now(datetime.timezone.utc)
LIMITE = AGORA - datetime.timedelta(days=R["confirmado_dias"])
VIZINHOS = {normal("Adrianópolis"): {normal("Nossa Senhora das Graças"): {"divisa": True, "km": 1.1},
                                    normal("Aleixo"): {"divisa": True, "km": 3.0},
                                    normal("Chapada"): {"divisa": False, "km": 2.5},
                                    normal("Coroado"): {"divisa": False, "km": 4.8},
                                    normal("Tarumã-Açu"): {"divisa": True, "km": 8.6},
                                    normal("Parque das Laranjeiras"): {"divisa": True, "km": None},
                                    normal("Flores"): {"divisa": False, "km": 5.2},
                                    normal("Longe Demais"): {"divisa": False, "km": 12.0}},
            normal("Nossa Senhora das Graças"): {normal("Adrianópolis"): {"divisa": True, "km": 1.1}},
            normal("Coroado"): {normal("Chapada"): {"divisa": False, "km": 6.0}}}


def imovel(codigo=1, **k):
    base = {"codigo": codigo, "tipo": "apartamento", "bairro": "Adrianópolis", "bairro_chave": normal("Adrianópolis"),
            "condominio": "Edifício Teste", "condominio_chave": "teste", "quartos": 2, "suites": 1, "vagas": 1,
            "andar": 3, "mobilia": "mobiliado", "pet": None, "valor_aluguel": 3800.0, "valor_venda": None,
            "confirmado_em": AGORA, "confirmado_como": "anúncio visto no ar"}
    base.update(k)
    if "bairro" in k:
        base["bairro_chave"] = normal(k["bairro"])
    return base


def pedido(**k):
    base = {"operacao": "aluguel", "tipo": "apartamento", "quartos": 2, "preco_max": 4000, "mobiliado": None,
            "andar": None, "suite": None, "vagas": None, "pet": None,
            "bairro_chaves": [normal("Adrianópolis")], "condominio_chaves": [], "condominio_sem_reconhecer": False,
            "local_nao_reconhecido": []}
    base.update(k)
    return base


def nota(p, i):
    etapa, r = pontuar.avaliar(p, i, R, VIZINHOS, LIMITE)
    return etapa, (r or {}).get("nota"), r


class Filtros(unittest.TestCase):
    def test_operacao_diferente_elimina(self):
        self.assertEqual(nota(pedido(operacao="venda"), imovel())[0], "operacao")

    def test_tipo_diferente_elimina(self):
        self.assertEqual(nota(pedido(tipo="casa"), imovel())[0], "tipo")

    def test_fora_do_local_elimina_e_vizinho_passa(self):
        self.assertEqual(nota(pedido(), imovel(bairro="Ponta Negra"))[0], "local")
        self.assertIsNone(nota(pedido(), imovel(bairro="Aleixo"))[0])

    def test_quartos_um_a_menos_elimina_um_a_mais_passa_dois_a_mais_elimina(self):
        self.assertEqual(nota(pedido(), imovel(quartos=1))[0], "quartos")
        self.assertIsNone(nota(pedido(), imovel(quartos=3))[0])
        self.assertEqual(nota(pedido(), imovel(quartos=4))[0], "quartos")

    def test_preco_mais_de_dez_por_cento_acima_elimina(self):
        self.assertEqual(nota(pedido(), imovel(valor_aluguel=4401.0))[0], "preco")
        self.assertIsNone(nota(pedido(), imovel(valor_aluguel=4400.0))[0])

    def test_sem_confirmacao_recente_elimina(self):
        velho = AGORA - datetime.timedelta(days=R["confirmado_dias"] + 1)
        self.assertEqual(nota(pedido(), imovel(confirmado_em=velho))[0], "confirmado")
        self.assertEqual(nota(pedido(), imovel(confirmado_em=None))[0], "confirmado")


class Nota(unittest.TestCase):
    def test_tudo_certo_da_cem_e_os_pesos_reescalados_somam_cem(self):
        _, n, r = nota(pedido(), imovel())
        self.assertEqual(n, 100.0)
        self.assertEqual({d["criterio"] for d in r["detalhe"]}, {"preco", "local", "quartos"})
        self.assertAlmostEqual(sum(d["peso"] for d in r["detalhe"]), 100.0, delta=0.2)
        # preço 40, local 20, quartos 15 -> de 75: 53,3 / 26,7 / 20
        self.assertEqual([d["peso"] for d in r["detalhe"]], [53.3, 26.7, 20.0])

    def test_so_entra_o_que_ele_pediu(self):
        # só disse o bairro: a nota é só do local
        p = pedido(quartos=None, preco_max=None, tipo=None)
        _, n, r = nota(p, imovel(quartos=5, valor_aluguel=9000.0))
        self.assertEqual(n, 100.0)
        self.assertEqual([d["criterio"] for d in r["detalhe"]], ["local"])

    def test_preco_de_vinte_abaixo_ate_o_teto_vale_cheio(self):
        for valor in (3200.0, 3600.0, 4000.0):
            self.assertEqual(nota(pedido(), imovel(valor_aluguel=valor))[1], 100.0, valor)

    def test_preco_muito_abaixo_cai_aos_poucos(self):
        # 2.400 é 60% do teto: meio caminho entre 80% (cheio) e 40% (zero) -> 50% do critério
        _, n, r = nota(pedido(), imovel(valor_aluguel=2400.0))
        self.assertEqual(r["detalhe"][0]["rendimento"], 50.0)
        self.assertEqual(n, round((40 * 50 + 20 * 100 + 15 * 100) / 75, 1))

    def test_acima_do_teto_cai_em_linha_reta_e_avisa_que_e_negociavel(self):
        _, n, r = nota(pedido(), imovel(valor_aluguel=4200.0))      # 5% acima: metade
        self.assertTrue(r["acima_do_teto"])
        self.assertEqual(r["detalhe"][0]["rendimento"], 50.0)
        self.assertIn("negociável", r["detalhe"][0]["texto"])

    def _local(self, bairro, **p):
        etapa, _, r = nota(pedido(**p), imovel(bairro=bairro))
        return None if etapa else next(d for d in r["detalhe"] if d["criterio"] == "local")

    def test_bairro_proximo_vale_mais_que_bairro_longe(self):
        # divisa: 85 colado, caindo com a distância entre os centros (zera em 10 km), nunca menos que 45
        self.assertEqual(self._local("Nossa Senhora das Graças")["rendimento"], 75.7)   # 85 x (1 - 1,1/10)
        self.assertEqual(self._local("Aleixo")["rendimento"], 59.5)                     # 85 x (1 - 3/10)
        self.assertEqual(self._local("Tarumã-Açu")["rendimento"], 45.0)                 # o piso de quem faz divisa
        # perto sem divisa: 65 caindo com a distância
        self.assertEqual(self._local("Chapada")["rendimento"], 48.8)                    # 65 x (1 - 2,5/10)
        self.assertEqual(self._local("Coroado")["rendimento"], 33.8)                    # 65 x (1 - 4,8/10)
        ordem = [self._local(b)["rendimento"] for b in ("Adrianópolis", "Nossa Senhora das Graças", "Aleixo", "Chapada", "Coroado")]
        self.assertEqual(ordem, sorted(ordem, reverse=True))
        _, n, _ = nota(pedido(), imovel(bairro="Aleixo"))
        self.assertEqual(n, round((40 * 100 + 20 * 59.5 + 15 * 100) / 75, 1))

    def test_o_card_diz_se_faz_divisa_e_a_distancia(self):
        self.assertEqual(self._local("Aleixo")["texto"], "Aleixo faz divisa com o bairro pedido (centros a 3,0 km)")
        self.assertEqual(self._local("Chapada")["texto"], "Chapada fica perto do bairro pedido, sem divisa (2,5 km)")

    def test_par_posto_a_mao_sem_distancia_vale_o_fixo(self):
        d = self._local("Parque das Laranjeiras")
        self.assertEqual((d["rendimento"], d["texto"]), (65.0, "Parque das Laranjeiras faz divisa com o bairro pedido"))

    def test_longe_demais_e_fora_da_lista_de_proximos_nao_entram(self):
        self.assertIsNone(self._local("Longe Demais"))          # sem divisa e além do km que zera
        self.assertIsNone(self._local("Flores"))                # sem divisa a 5,2 km: passou dos 5 km de "perto"
        self.assertIsNone(self._local("Ponta Negra"))           # o mapa não lista como próximo

    def test_com_dois_bairros_pedidos_vale_o_de_que_ele_esta_mais_perto(self):
        # Chapada: 2,5 km de Adrianópolis e 6 km do Coroado -> vale a de Adrianópolis
        d = self._local("Chapada", bairro_chaves=[normal("Coroado"), normal("Adrianópolis")])
        self.assertEqual(d["rendimento"], 48.8)

    def test_um_quarto_a_mais_vale_sessenta(self):
        _, n, r = nota(pedido(), imovel(quartos=3))
        self.assertEqual([d["rendimento"] for d in r["detalhe"] if d["criterio"] == "quartos"], [60.0])

    def test_mobiliado_andar_e_extras(self):
        p = pedido(mobiliado=True, andar=["terreo", "1_andar"], suite=True, vagas=2, pet=True)
        _, n, r = nota(p, imovel(andar=1, mobilia="mobiliado", suites=1, vagas=2, pet=True))
        self.assertEqual(n, 100.0)
        _, n, r = nota(p, imovel(andar=5, mobilia="vazio", suites=0, vagas=1, pet=None))
        por = {d["criterio"]: d for d in r["detalhe"]}
        self.assertEqual((por["mobiliado"]["rendimento"], por["andar"]["rendimento"], por["extras"]["rendimento"]), (0.0, 0.0, 0.0))
        self.assertEqual(n, 75.0)                                     # sobraram preço 40, local 20, quartos 15

    def test_o_que_o_cadastro_nao_informa_vale_zero_e_a_tela_diz(self):
        _, n, r = nota(pedido(mobiliado=True, andar=["terreo"]), imovel(andar=None, mobilia=None))
        textos = " ".join(d["texto"] for d in r["detalhe"])
        self.assertIn("não informada no cadastro", textos)
        self.assertIn("não informado no cadastro", textos)

    def test_cru_quer_sem_mobilia_e_semi_vale_metade(self):
        self.assertEqual(pontuar._mobilia(False, {"mobilia": "vazio"}, R)[0], 100)
        self.assertEqual(pontuar._mobilia(False, {"mobilia": "mobiliado"}, R)[0], 0)
        self.assertEqual(pontuar._mobilia(True, {"mobilia": "semi"}, R)[0], 50)

    def test_qualquer_andar_sai_da_conta_e_casa_e_terrea(self):
        _, _, r = nota(pedido(andar=["qualquer"]), imovel())
        self.assertNotIn("andar", [d["criterio"] for d in r["detalhe"]])
        _, _, r = nota(pedido(tipo="casa", andar=["terreo"]), imovel(tipo="casa", andar=None))
        self.assertEqual([d["rendimento"] for d in r["detalhe"] if d["criterio"] == "andar"], [100.0])

    def test_condominio_pedido_vale_exato_e_o_resto_do_bairro_a_metade(self):
        p = pedido(condominio_chaves=["eliza miranda"], bairro_chaves=[normal("Japiim")])
        do_condominio = imovel(1, bairro="Distrito Industrial I", condominio="Residencial Eliza Miranda 2 Etapa",
                               condominio_chave="eliza miranda 2 etapa")
        outro_do_bairro = imovel(2, bairro="Japiim", condominio="Outro", condominio_chave="outro")
        de_fora = imovel(3, bairro="Aleixo", condominio="Outro", condominio_chave="outro")
        self.assertIn("condomínio pedido", nota(p, do_condominio)[2]["detalhe"][1]["texto"])
        self.assertEqual(nota(p, outro_do_bairro)[2]["detalhe"][1]["rendimento"], 50.0)
        self.assertEqual(nota(p, de_fora)[0], "local")

    def test_condominio_que_o_cadastro_nao_conhece_o_bairro_vale_a_metade(self):
        p = pedido(condominio_sem_reconhecer=True)
        self.assertEqual(nota(p, imovel())[2]["detalhe"][1]["rendimento"], 50.0)
        self.assertEqual(nota(p, imovel(bairro="Aleixo"))[0], "local")       # vizinho não entra


class Melhores(unittest.TestCase):
    def test_o_melhor_primeiro_e_as_alternativas_depois(self):
        catalogo = [imovel(1, valor_aluguel=4200.0), imovel(2), imovel(3, bairro="Aleixo"), imovel(4, quartos=1)]
        r = pontuar.melhores(pedido(), catalogo, R, VIZINHOS, LIMITE)
        self.assertEqual([p["codigo"] for p in r["pares"]], [2, 3, 1])
        self.assertEqual(r["pares"][0]["posicao"], 1)
        self.assertEqual(r["funil"]["quartos"], 3)
        self.assertEqual(pontuar.faixa_da(r["pares"][0]["nota"], R), "verde")

    def test_sem_imovel_diz_onde_parou(self):
        r = pontuar.melhores(pedido(bairro_chaves=[normal("Tarumã")]), [imovel(1)], R, VIZINHOS, LIMITE)
        self.assertEqual((r["pares"], r["motivo"]), ([], "nenhum imóvel nosso nesse local"))

    def test_sem_operacao_e_lugar_nao_reconhecido_nao_comparam(self):
        self.assertIn("aluguel ou venda", pontuar.melhores(pedido(operacao=None), [imovel()], R, VIZINHOS, LIMITE)["motivo"])
        r = pontuar.melhores(pedido(local_nao_reconhecido=["Primer"]), [imovel()], R, VIZINHOS, LIMITE)
        self.assertEqual(r["motivo"], "não reconheci o lugar pedido: Primer")

    def test_faixas(self):
        self.assertEqual([pontuar.faixa_da(n, R) for n in (90, 89.9, 70, 69.9)], ["verde", "amarelo", "amarelo", "registro"])


class Leitura(unittest.TestCase):
    def test_limpar_guarda_os_tipos_e_os_duvidosos(self):
        bruto = {"operacao": "aluguel", "tipo": "apartamento", "bairros": [" Adrianópolis ", "Vieiralves"], "condominio": None,
                 "quartos": 2, "preco_max": 4000, "mobiliado": True, "andar": None, "suite": None, "vagas": None,
                 "pet": None, "contato": None, "observacao": None, "trecho": "x",
                 "confianca": {c: "certo" for c in extrair.CAMPOS} | {"mobiliado": "duvidoso", "vagas": "duvidoso"}}
        f = extrair.limpar(bruto)
        self.assertEqual((f["bairros"], f["preco_max"], f["mobiliado"]), (["Adrianópolis", "Vieiralves"], 4000.0, True))
        self.assertEqual(f["duvidosos"], ["mobiliado"])               # vagas é nulo: não há o que duvidar
        self.assertEqual(f["confianca"]["vagas"], "nao_informado")

    def test_teto_que_nao_combina_com_a_operacao_fica_duvidoso(self):
        f = extrair.limpar({"operacao": "aluguel", "preco_max": 2, "bairros": [], "confianca": {}})
        self.assertIn("preco_max", f["duvidosos"])

    def test_pedido_vazio_nao_e_pedido(self):
        self.assertIsNone(extrair.limpar({"bairros": [], "confianca": {}, "contato": "Fulana"}))

    def test_o_que_nem_vai_para_a_ia(self):
        self.assertIsNotNone(extrair.nao_precisa_ler("bom dia"))
        self.assertIsNotNone(extrair.nao_precisa_ler("📍 Smart Tower\n• 2 quartos\nlocação: 2.600\nCódigo: 5712"))
        self.assertIsNone(extrair.nao_precisa_ler("Busco aluguel Primer cidada nova, cru. Valor máximo 2 mil"))

    def test_extrair_com_a_ia_de_mentira(self):
        resposta = {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps({"pedidos": [
            {"operacao": "venda", "tipo": None, "bairros": [], "condominio": "Eliza Miranda", "quartos": 3, "preco_max": None,
             "mobiliado": None, "andar": ["terreo"], "suite": True, "vagas": None, "pet": None, "contato": None,
             "observacao": None, "trecho": "Procuro Eliza Miranda",
             "confianca": {c: "certo" for c in extrair.CAMPOS}}]})}]}]}
        fichas = extrair.extrair("Procuro Eliza Miranda para venda com 3 quartos e suite, Térreo", chamar=lambda corpo: resposta)
        self.assertEqual(len(fichas), 1)
        self.assertEqual((fichas[0]["condominio"], fichas[0]["andar"], fichas[0]["suite"]), ("Eliza Miranda", ["terreo"], True))


class Lugar(unittest.TestCase):
    class _Nomes:
        def bairro(self, escrito):
            conhecidos = {"Adrianópolis": ("exato", ["Adrianópolis"]), "Vieiralves": ("lugar", ["Nossa Senhora das Graças"]),
                          "cidada nova": ("parecido", ["Cidade Nova"])}
            como, oficiais = conhecidos.get(escrito, (None, []))
            return {"escrito": escrito, "tipo": "bairro", "como": como, "oficiais": oficiais, "sugestao": None}

        def condominio(self, escrito):
            if escrito == "Parque Vile":
                return {"escrito": escrito, "tipo": "condominio", "como": "apelido", "oficiais": ["Parque Ville Municipal"],
                        "chaves": ["ville municipal"], "bairros": ["Alvorada"], "sugestao": None}
            return {"escrito": escrito, "tipo": "condominio", "como": None, "oficiais": [], "chaves": [], "bairros": [],
                    "sugestao": "Prime Mosaico"}

    def test_dois_bairros_e_o_conjunto_vira_bairro(self):
        p, local, duv = lugares.resolver({"bairros": ["Adrianópolis", "Vieiralves"], "operacao": "aluguel"}, None, self._Nomes())
        self.assertEqual(local["bairros"], ["Adrianópolis", "Nossa Senhora das Graças"])
        self.assertEqual((duv, p["local_nao_reconhecido"]), ([], []))

    def test_apelido_de_condominio_traz_a_chave_e_o_bairro_dele(self):
        p, local, duv = lugares.resolver({"bairros": [], "condominio": "Parque Vile", "operacao": "aluguel"}, None, self._Nomes())
        self.assertEqual((p["condominio_chaves"], p["bairro_chaves"], duv), (["ville municipal"], ["alvorada"], []))

    def test_condominio_desconhecido_com_bairro_parecido_fica_duvidoso_mas_compara_pelo_bairro(self):
        p, local, duv = lugares.resolver({"bairros": ["cidada nova"], "condominio": "Primer", "operacao": "aluguel"}, None, self._Nomes())
        self.assertEqual((p["bairro_chaves"], p["condominio_sem_reconhecer"], p["local_nao_reconhecido"]), (["cidade nova"], True, []))
        self.assertEqual(duv, ["bairros", "condominio"])
        self.assertEqual(local["itens"][1]["sugestao"], "Prime Mosaico")

    def test_nada_reconhecido_nao_compara(self):
        p, _, _ = lugares.resolver({"bairros": [], "condominio": "Primer", "operacao": "aluguel"}, None, self._Nomes())
        self.assertEqual(p["local_nao_reconhecido"], ["Primer"])

    def test_operacao_do_nome_do_grupo_so_quando_a_mensagem_nao_disse(self):
        p, local, _ = lugares.resolver({"bairros": ["Adrianópolis"]}, "🟢 Locação OFERTA e BUSCA 🔍 - CREDENCIADOS", self._Nomes())
        self.assertEqual((p["operacao"], local["operacao_origem"]), ("aluguel", "nome do grupo"))
        p, local, _ = lugares.resolver({"bairros": ["Adrianópolis"], "operacao": "venda"}, "Locação", self._Nomes())
        self.assertEqual((p["operacao"], local["operacao_origem"]), ("venda", "mensagem"))
        self.assertIsNone(lugares.resolver({"bairros": ["Adrianópolis"]}, "PARCERIAS IMÓVEIS GERAL", self._Nomes())[0]["operacao"])


class Regras(unittest.TestCase):
    def _arquivo(self, conteudo):
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        f.write(conteudo)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_o_arquivo_do_repositorio_e_igual_ao_padrao(self):
        r, avisos = regras.carregar(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config.json"))
        self.assertEqual((r, avisos), (R, []))

    def test_mudar_um_peso_vale_e_o_resto_fica(self):
        r, avisos = regras.carregar(self._arquivo('{"pesos": {"preco": 50}, "cortes": {"verde": 85}}'))
        self.assertEqual((r["pesos"]["preco"], r["pesos"]["local"], r["cortes"], avisos), (50, 20, {"verde": 85, "amarelo": 70}, []))

    def test_escrever_ativo_nao_liga_envio(self):
        r, avisos = regras.carregar(self._arquivo('{"modo": "ativo"}'))
        self.assertEqual(r["modo"], "treino")
        self.assertTrue(any("nada é enviado sozinho" in a for a in avisos))

    def test_arquivo_estragado_vale_o_padrao_com_aviso(self):
        r, avisos = regras.carregar(self._arquivo('{"pesos": '))
        self.assertEqual(r, R)
        self.assertTrue(avisos)

    def test_distancia_que_zera_torta_fica_o_padrao_e_o_envio_manual_se_desliga_no_arquivo(self):
        r, avisos = regras.carregar(self._arquivo('{"local": {"km_que_zera": 0}, "envio_manual": false}'))
        self.assertEqual((r["local"], r["envio_manual"], len(avisos)), (R["local"], False, 1))
        self.assertTrue(R["envio_manual"])

    def test_valor_torto_fica_o_padrao(self):
        r, avisos = regras.carregar(self._arquivo('{"pesos": {"preco": "muito"}, "cortes": {"verde": 50, "amarelo": 70}, "xis": 1}'))
        self.assertEqual((r["pesos"]["preco"], r["cortes"]), (40, {"verde": 90, "amarelo": 70}))
        self.assertEqual(len(avisos), 3)


class Cadastro(unittest.TestCase):
    def test_tipo_mobilia_e_andar_do_cadastro(self):
        self.assertEqual([tipo_do(t) for t in ("Apartamento", "Casa de condomínio", "Flat", "Cobertura", "Sala/Andar", "Loja/Ponto", "Lote em Condomínio")],
                         ["apartamento", "casa", "apartamento", "apartamento", "sala", "sala", "outro"])
        self.assertEqual([mobilia_do(m) for m in ("", "semi-mobiliado (moveis planejados + ar)", "mobiliado (moveis + cama + tudo)", "so ar-condicionado")],
                         [None, "semi", "mobiliado", "vazio"])
        self.assertEqual([andar_do(a) for a in ("Térreo", "1º", "3ª", "18", "Andar alto", "", None)], [0, 1, 3, 18, 99, None, None])


class Envio(unittest.TestCase):
    def test_o_envio_nao_existe_nesta_versao(self):
        with self.assertRaises(envio.EnvioBloqueado):
            envio.enviar("um telefone", "qualquer coisa")
        with open(envio.__file__, encoding="utf-8") as f:
            fonte = f.read()
        # o módulo não tem como mandar nada: não importa coisa nenhuma nem conhece endereço de rede
        self.assertNotIn("import ", fonte)
        self.assertNotIn("http", fonte)


if __name__ == "__main__":
    unittest.main()
