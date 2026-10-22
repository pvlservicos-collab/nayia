"""Testes do que não precisa de banco nem de WhatsApp: o modelo de cadastro, a leva, o telefone e o condomínio."""
from datetime import datetime, timedelta

from cadastro import campos, condominio, ficha, leva


# ── o modelo de cadastro (campos.py) ────────────────────────────────────────────────────────────────────────────
def test_familias_iguais_as_do_editar():
    assert campos.familia("Apartamento") == "vertical"
    assert campos.familia("Cobertura") == "vertical"
    assert campos.familia("Casa de condomínio") == "casa"
    assert campos.familia("Sala/Andar") == "sala"
    assert campos.familia("Loja/Ponto") == "sala"
    assert campos.familia("Lote em Condomínio") == "terreno"
    assert campos.familia("Galpão") == "outro"


def test_tipo_canonico_do_jeito_que_ele_escreve():
    assert campos.tipo_canonico("apto") == "Apartamento"
    assert campos.tipo_canonico("casa em condomínio fechado") == "Casa de condomínio"
    assert campos.tipo_canonico("sala comercial") == "Sala/Andar"
    assert campos.tipo_canonico("terreno") == "Lote"
    assert campos.tipo_canonico("") is None


def test_apartamento_pergunta_o_condominio_antes_e_nao_pergunta_endereco():
    f = {"tipo": "Apartamento", "valor_aluguel": 3500, "_fotos": 5}
    falta = campos.faltam(f, {"papel_conhecido": True, "papel": "proprietario"})
    assert falta[0] == "condominio"
    assert "endereco" not in falta and "unidade" in falta and "andar" in falta and "mobilia" in falta


def test_ao_corretor_nunca_o_numero_do_apartamento():
    """Tel, 20/10 (a Raquel): ao corretor só o andar; o número da unidade só ao proprietário."""
    f = {"tipo": "Apartamento", "condominio": "Reserva das Praias", "condo_id": 213, "valor_venda": 550000}
    corretor = campos.faltam(f, {"papel_conhecido": True, "papel": "corretor"})
    assert "unidade" not in corretor and "andar" in corretor


def test_andar_com_e_sem_elevador():
    assert campos.POR_CHAVE["andar"].texto({"_elevador": "sim"}) == "Em qual andar ele fica?"
    assert campos.POR_CHAVE["andar"].texto({"_elevador": "nao"}) == "Quantos lances de escada até ele?"
    assert "lances de escada" in campos.POR_CHAVE["andar"].texto({})
    assert campos.POR_CHAVE["andar"].preenchida({"x:lances de escada": 2})


def test_abertura_do_tel():
    f = {"tipo": "Apartamento", "condominio": "Reserva das Praias"}
    assert campos.abertura("Raquel Paiva", f) == ("Oi, Raquel! Estou fazendo o cadastro do seu imóvel por esse número, "
                                                  "imóvel Reserva das Praias. Pode me confirmar umas informações, "
                                                  "por favor?")
    assert campos.abertura(None, {"tipo": "Casa", "bairro": "Aleixo"}).startswith("Oi! Estou fazendo")
    assert "imóvel casa no Aleixo" in campos.abertura(None, {"tipo": "Casa", "bairro": "Aleixo"})


def test_condominio_cadastrado_nao_pergunta_nada_do_condominio():
    f = {"tipo": "Apartamento", "condominio": "Life Parque Dez", "condo_id": 28, "bairro": "Parque 10",
         "valor_aluguel": 3500, "_fotos": 5}
    falta = campos.faltam(f, {"papel_conhecido": True, "taxa_no_condominio": True})
    assert not any(k.startswith("c_") for k in falta) and "condominio" not in falta
    assert "taxa_condominio" not in falta and "bairro" not in falta


def test_condominio_novo_pede_as_coisas_do_condominio():
    f = {"tipo": "Apartamento", "condominio": "Residencial Novo Horizonte", "valor_venda": 450000, "_fotos": 3}
    falta = campos.faltam(f, {"papel_conhecido": True})
    assert falta[:3] == ["c_endereco", "c_elevador", "c_lazer"]
    assert "mobilia" not in falta              # venda não pergunta a mobília


def test_condominio_parecido_confirma_antes_de_pedir_o_condominio_novo():
    f = {"tipo": "Apartamento", "condominio": "lyfe parque des", "_condo_candidato": {"id": 28, "nome": "Life Parque Dez"},
         "valor_aluguel": 3000}
    falta = campos.faltam(f, {"papel_conhecido": True})
    assert "condominio_confirma" in falta and "c_endereco" not in falta
    assert campos.POR_CHAVE["condominio_confirma"].texto(f) == "É o condomínio Life Parque Dez?"
    f["_condo_nao"] = True
    assert "c_endereco" in campos.faltam(f, {"papel_conhecido": True})


def test_casa_de_rua_pergunta_endereco_e_nao_condominio():
    f = {"tipo": "Casa", "valor_aluguel": 2500, "bairro": "Aleixo", "_fotos": 2}
    falta = campos.faltam(f, {"papel_conhecido": True})
    assert "endereco" in falta and "condominio" not in falta and "unidade" not in falta
    assert campos.POR_CHAVE["area"].texto(f) == "Qual a área construída da casa, em m²?"


def test_sala_e_terreno_sem_quartos():
    assert "quartos" not in campos.faltam({"tipo": "Sala/Andar"}, {"papel_conhecido": True})
    t = campos.faltam({"tipo": "Lote"}, {"papel_conhecido": True})
    assert "quartos" not in t and "banheiros" not in t and "vagas" not in t
    assert campos.POR_CHAVE["area"].texto({"tipo": "Lote"}) == "Qual o tamanho do terreno, em m²?"


def test_papel_desconhecido_e_a_primeira_pergunta():
    assert campos.faltam({"tipo": "Casa"}, {"papel_conhecido": False})[0] == "papel"


def test_pergunta_feita_nao_volta():
    f = {"tipo": "Apartamento", "_feitas": ["condominio", "unidade"]}
    falta = campos.faltam(f, {"papel_conhecido": True, "papel": "proprietario"})
    assert "condominio" not in falta and "unidade" not in falta
    assert "unidade" in campos.ficou_sem(f, {"papel_conhecido": True, "papel": "proprietario"})


def test_valor_sem_finalidade_pergunta_as_duas_coisas():
    assert campos.POR_CHAVE["valor"].texto({}) == "Ele é para alugar ou para vender? E qual o valor?"
    assert campos.POR_CHAVE["valor"].texto({"_finalidade": "locacao"}) == "Qual o valor do aluguel?"


def test_descricao_do_imovel():
    assert campos.descricao_do_imovel({"tipo": "Apartamento", "condominio": "Life Parque Dez"}) == \
        "o apartamento no Life Parque Dez"
    assert campos.descricao_do_imovel({"tipo": "Casa", "bairro": "Aleixo"}) == "a casa no Aleixo"


def test_resumo_com_dinheiro():
    r = campos.resumo_do_que_tem({"valor_venda": 1200000, "valor_aluguel": 3500})
    assert "venda R$ 1,2 milhão" in r and "aluguel R$ 3.500" in r


# ── a leva e o telefone (leva.py) ───────────────────────────────────────────────────────────────────────────────
def _m(i, seg, texto=None, tipo="texto", url=None):
    return leva.Mensagem(f"M{i}", datetime(2026, 10, 20, 10, 0) + timedelta(seconds=seg), tipo, texto, url)


def test_levas_cortam_no_silencio():
    ms = [_m(1, 0, "Apto 3 quartos"), _m(2, 5, tipo="imagem", url="u1"), _m(3, 8, tipo="imagem", url="u2"),
          _m(4, 300, "Casa no Aleixo")]
    lv = leva.separar(ms, 90)
    assert [x.ids for x in lv] == [["M1", "M2", "M3"], ["M4"]]
    assert len(lv[0].fotos) == 2 and lv[0].texto == "Apto 3 quartos"
    assert leva.fechada(lv[0], datetime(2026, 10, 20, 10, 2), 90)
    assert not leva.fechada(lv[1], datetime(2026, 10, 20, 10, 5, 30), 90)


def test_telefone_do_cartao_e_do_texto():
    t = "Apto no Life\nR$ 3.500 120m²\n👤 Contato: Ana Corretora — 5592988887777\nou (92) 9 9111-2222"
    assert leva.fones_do_texto(t) == ["5592988887777", "5592991112222"]
    assert leva.nome_do_contato(t) == "Ana Corretora"


def test_valor_e_area_nao_viram_telefone():
    assert leva.fones_do_texto("Aluguel R$ 3.500, condomínio 450, 120 m2, código 3883, CEP 69050-000") == []
    assert leva.fones_do_texto("venda 1.250.000") == []


def test_celular_sem_o_9():
    assert leva.fones_do_texto("contato 92 8888-7777") == ["5592988887777"]


def test_fone_bonito():
    assert leva.fone_bonito("5592988887777") == "(92) 9 8888-7777"


# ── o condomínio (condominio.py) ────────────────────────────────────────────────────────────────────────────────
def test_condominio_claro_liga_e_duvida_confirma():
    exato = [{"id": 28, "nome": "Life Parque Dez", "bairro": "Parque 10", "faixa": 1, "parecenca": 1.0},
             {"id": 680, "nome": "RESIDENCIAL NO PARQUE DEZ", "bairro": "Parque 10", "faixa": 3, "parecenca": 0.69}]
    assert condominio.escolher(exato)[0] == "ligar"
    erro = [{"id": 28, "nome": "Life Parque Dez", "faixa": 4, "parecenca": 0.63},
            {"id": 41, "nome": "Flex Parque Dez", "faixa": 4, "parecenca": 0.56}]
    assert condominio.escolher(erro) == ("ligar", erro[0])
    empate = [{"id": 1, "nome": "A", "faixa": 4, "parecenca": 0.5}, {"id": 2, "nome": "B", "faixa": 4, "parecenca": 0.49}]
    assert condominio.escolher(empate)[0] == "confirmar"
    assert condominio.escolher([]) == ("novo", None)


def test_ligar_traz_o_bairro_do_condominio():
    f = condominio.ligar({"condominio": "life parque", "_condo_candidato": {}}, {"id": 28, "nome": "Life Parque Dez",
                                                                                "bairro": "Parque 10 de Novembro"})
    assert f["condo_id"] == 28 and f["condominio"] == "Life Parque Dez" and f["bairro"] == "Parque 10 de Novembro"
    assert "_condo_candidato" not in f


def test_resposta_da_confirmacao():
    assert condominio.resposta_da_confirmacao("Sim, é esse") is True
    assert condominio.resposta_da_confirmacao("é") is True
    assert condominio.resposta_da_confirmacao("não, é o Life Smart") is False
    assert condominio.resposta_da_confirmacao("fica na Darcy Vargas") is None


# ── a ficha (ficha.py) ──────────────────────────────────────────────────────────────────────────────────────────
def test_do_modelo_e_para_o_site():
    saida = {"tipo": "apto", "valor_aluguel": 3500.0, "quartos": 3.0, "bloco": "B", "unidade": "302",
             "tamanho_terreno": None, "aceita_financiamento": "sim", "condominio_lazer": ["piscina"], "papel": "corretor",
             "caracteristicas": [], "e_imovel": True, "contato_telefone": "92 98888-7777"}
    f = ficha.do_modelo(saida)
    assert f["tipo"] == "Apartamento" and f["quartos"] == 3 and isinstance(f["quartos"], int)
    assert f["p:bloco"] == "B" and f["c:lazer"] == ["piscina"] and f["_papel"] == "corretor"
    assert "e_imovel" not in f and "caracteristicas" not in f
    corpo = ficha.para_o_site(f)
    assert corpo["privado"] == {"bloco": "B", "unidade": "302"}
    assert corpo["extras"] == {"aceita financiamento": "Sim"}
    assert "c:lazer" not in corpo and "_papel" not in corpo and corpo["valor_aluguel"] == 3500.0


def test_juntar_soma_lista_e_corrige_o_resto():
    f = ficha.juntar({"caracteristicas": ["varanda"], "quartos": 2}, {"caracteristicas": ["piscina"], "quartos": 3})
    assert f == {"caracteristicas": ["varanda", "piscina"], "quartos": 3}


def test_condominio_novo_para_o_site():
    f = {"condominio": "Res. Novo", "tipo": "Apartamento", "bairro": "Flores", "c:logradouro": "Av. das Flores",
         "c:elevador": "sim", "c:lazer": ["piscina", "academia"]}
    corpo = ficha.condominio_para_o_site(f)
    assert corpo["elevador"] == "Sim, possui elevador" and corpo["tipo"] == "apartamentos"
    assert corpo["lazer"] == ["piscina", "academia"] and corpo["cidade"] == "Manaus"


def test_schema_estrito_tem_tudo_obrigatorio():
    for s in (ficha.SCHEMA_LEVA, ficha.SCHEMA_RESPOSTA):
        assert set(s["required"]) == set(s["properties"]) and s["additionalProperties"] is False


# 22/10: o que o Tel manda depois do anúncio ("4 banheiros", "64m2") completa o cadastro, não vira imóvel novo.
def test_complemento_curto_nao_e_anuncio():
    assert not leva.parece_anuncio("condominio Vila Palmas\n4 banheiros", {"condominio": "Vila Palmas", "banheiros": 4})
    assert not leva.parece_anuncio("64m2", {"area_util": 64})
    assert not leva.parece_anuncio("valor 600 mil", {"valor_venda": 600000})


def test_anuncio_e_anuncio():
    texto = ("*VENDO | Condomínio de Casa Vila Palmas* *Casa DUPLEX* R$ 798.000 Flores • 157,50m2 de área construída "
             "• 2 Suítes • 2 quartos • 3 banheiros • 2 vagas • área gourmet • piscina no condomínio • segurança 24h")
    assert leva.parece_anuncio(texto, {"valor_venda": 798000, "tipo": "Casa de condomínio"})
    assert leva.parece_anuncio("Apto 3 quartos no Weekend Club, venda R$ 450 mil, 2 vagas, 90m2",
                               {"valor_venda": 450000, "condominio": "Weekend Club", "quartos": 3})
