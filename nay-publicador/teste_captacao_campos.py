"""Prova a tradução do anúncio da OLX para os campos do imóvel, sem rede.

Todas as fixtures são recortes de anúncios REAIS de Manaus abertos em
02/09/2026 -- o `listId` de cada uma está no comentário, e os valores estranhos
(`"5 ou mais"`, `"R$ 0"`, casa classificada como apartamento) não foram
inventados para o teste: foram medidos. A amostra que os produziu tem 217
anúncios; os números estão no cabeçalho de `captacao_campos.py`.

O que estes casos guardam, e por quê:
  * ausente é None e NUNCA zero -- zero é "não tem", None é "não sei", e
    confundir os dois já fez a Nay dizer que um apartamento não tinha vaga;
  * `"5 ou mais"` não é número e `int()` quebra nele;
  * `"R$ 0"` de condomínio é campo pulado, não isenção (58 de 89 medidos);
  * `size` significa área útil, área construída ou tamanho do terreno conforme
    a categoria, e o rótulo que dizia qual não chega até aqui;
  * a fazenda de 12.000 hectares anunciada como "aluguel de R$ 1.500" tinha
    TODOS os campos preenchidos -- quem a pega é o cruzamento preço/área.

    .venv/bin/python teste_captacao_campos.py
"""
import sys

import captacao_campos as cc

falhas = 0
total = 0


def checar(rotulo, condicao, detalhe=""):
    global falhas, total
    total += 1
    if condicao:
        print(f"  OK     {rotulo}")
    else:
        falhas += 1
        print(f"  FALHOU {rotulo} {detalhe}")


def aviso_de(avisos, campo):
    """Os avisos de um campo, juntos, para procurar trecho dentro."""
    return " | ".join(a["aviso"] for a in avisos if a["campo"] == campo)


def campos_que_faltam(lista):
    return [f["campo"] for f in lista]


# --- fixtures ------------------------------------------------------------
# listId 1526317308 -- "Alugo Apartamento de 2 Dormitórios no Condominio
# Conquista Ametista". Anúncio completo e bem preenchido: é o caso feliz.
APTO_ALUGUEL = {
    "olx_id": 1526317308,
    "titulo": "Alugo Apartamento de 2 Dormitórios no Condominio Conquista Ametista",
    "descricao": "Apartamento no 2º andar, nascente.",
    "preco_texto": "R$ 1.600",
    "preco_rotulo": "Aluguel",
    "bairro": "Colônia Terra Nova",
    "municipio": "Manaus",
    "logradouro": "Rua Tudy Moutinho",
    "cep": "69093417",
    "campos": {
        "category": "Apartamentos",
        "real_estate_type": "Aluguel - apartamento padrão",
        "size": "42m²",
        "rooms": "2",
        "bathrooms": "1",
        "garage_spaces": "1",
        "re_features": "Ar condicionado, Área de serviço, Piscina",
        "re_complex_features": "Condomínio fechado, Elevador, Piscina, Portaria",
        "re_types": "Padrão",
    },
    "fotos": ["https://img.olx.com.br/images/48/481626791965796.jpg"],
}

# listId 1531756564 -- "CASA DISPONÍVEL PARA VENDA NO MORADA DOS PÁSSAROS",
# que a OLX classificou como apartamento e cujo condomínio e IPTU vieram
# zerados num prédio com piscina e portaria. Tudo isso é real.
CASA_MAL_CLASSIFICADA = {
    "olx_id": 1531756564,
    "titulo": "CASA DISPONÍVEL PARA VENDA NO MORADA DOS PÁSSAROS",
    "descricao": "Casa Térrea com 3 quartos sendo 1 suíte.",
    "preco_texto": "R$ 1.800.000",
    "preco_rotulo": "Preço",
    "bairro": "Ponta Negra",
    "municipio": "Manaus",
    "logradouro": None,
    "cep": "69037145",
    "campos": {
        "category": "Apartamentos",
        "real_estate_type": "Venda - apartamento padrão",
        "condominio": "R$ 0",
        "iptu": "R$ 0",
        "size": "152m²",
        "rooms": "3",
        "bathrooms": "2",
        "garage_spaces": "4",
        "re_features": "Piscina",
        "re_complex_features": "Condomínio fechado, Piscina, Portaria",
        "re_types": "Padrão",
    },
    "fotos": ["https://img.olx.com.br/images/50/505613799054848.jpg"],
}

# listId 1531755932 -- "GALPÃO P/ LOCAÇÃO 500 M2 EM FLORES". Categoria que o
# nosso cadastro não fecha sozinho, e `garage_spaces` = "5 ou mais".
GALPAO = {
    "olx_id": 1531755932,
    "titulo": "GALPÃO P/ LOCAÇÃO  500 M2  EM FLORES PRÓX. A NILTON LINS!",
    "descricao": "Galpão com pé direito alto.",
    "preco_texto": "R$ 9.500",
    "preco_rotulo": "Aluguel",
    "bairro": "Flores",
    "municipio": "Manaus",
    "logradouro": None,
    "cep": "69028222",
    "campos": {
        "category": "Comércio e indústria",
        "condominio": "R$ 0",
        "size": "500m²",
        "garage_spaces": "5 ou mais",
    },
    "fotos": ["https://img.olx.com.br/images/53/533647189079728.jpg"],
}

# listId 1528976547 -- "Lote no Condomínio Residencial Jardins". Aqui o `size`
# é o terreno, e condomínio/IPTU vieram com valor de verdade.
LOTE = {
    "olx_id": 1528976547,
    "titulo": "Lote no Condomínio Residencial Jardins - Iranduba",
    "descricao": "Lote plano, pronto para construir.",
    "preco_texto": "R$ 60.000",
    "preco_rotulo": "Preço",
    "bairro": "Cidade Nova",
    "municipio": "Manaus",
    "logradouro": "Rua Oliveira Braga",
    "cep": "69094740",
    "campos": {
        "category": "Terrenos, sítios e fazendas",
        "real_estate_type": "Terrenos",
        "condominio": "R$ 197",
        "iptu": "R$ 54",
        "size": "300m²",
        "re_complex_features": "Condomínio fechado, Portaria",
    },
    "fotos": ["https://img.olx.com.br/images/53/531649781957532.jpg"],
}

# O anúncio que originou tudo isto: fazenda de 12.000 hectares com
# `priceValue: "R$ 1.500"` e `priceLabel: "Aluguel"`. Era R$ 1.500 POR HECTARE,
# à venda. Nenhum campo estava vazio; todos mentiam juntos.
FAZENDA = {
    "olx_id": 1,
    "titulo": "Fazenda de 12.000 hectares",
    "descricao": "Fazenda para pecuária.",
    "preco_texto": "R$ 1.500",
    "preco_rotulo": "Aluguel",
    "bairro": None,
    "municipio": "Manicoré",
    "logradouro": None,
    "cep": None,
    "campos": {
        "category": "Terrenos, sítios e fazendas",
        "real_estate_type": "Aluguel - sítios e chácaras",
        "size": "120000000m²",
    },
    "fotos": [],
}

VAZIO = {"olx_id": 9, "titulo": "Sem nada", "campos": {}, "fotos": []}


print("--- caso feliz: apartamento de aluguel bem preenchido ---")
c = cc.traduzir(APTO_ALUGUEL)
checar("tipo vira o vocabulário da Imob Easy", c["tipo"] == "Apartamento",
       f"veio {c['tipo']!r}")
checar("aluguel vai para valor_aluguel", c["valor_aluguel"] == 1600.0,
       f"veio {c['valor_aluguel']!r}")
checar("e valor_venda fica None, não zero", c["valor_venda"] is None,
       f"veio {c['valor_venda']!r}")
checar("'42m²' vira 42.0", c["area_util"] == 42.0, f"veio {c['area_util']!r}")
checar("quartos e banheiros viram int",
       c["quartos"] == 2 and c["banheiros"] == 1)
checar("características juntam imóvel e condomínio sem repetir 'Piscina'",
       c["caracteristicas"].count("Piscina") == 1,
       f"veio {c['caracteristicas']!r}")
checar("características é lista (a coluna é ARRAY no Postgres)",
       isinstance(c["caracteristicas"], list))
checar("os 16 campos saem sempre, mesmo vazios",
       set(c) == set(cc.CAMPOS), f"faltou/sobrou {set(c) ^ set(cc.CAMPOS)}")

print()
print("--- ausente é None, NUNCA zero ---")
c = cc.traduzir(VAZIO)
for campo in cc.CAMPOS:
    checar(f"{campo} ausente vira None", c[campo] is None, f"veio {c[campo]!r}")
checar("sem preço e sem rótulo, nenhum valor é inventado",
       c["valor_venda"] is None and c["valor_aluguel"] is None)

print()
print("--- suíte: a OLX não tem o campo (0 de 217 anúncios) ---")
c = cc.traduzir(CASA_MAL_CLASSIFICADA)
checar("suites nunca vem 0 -- é None, e vira pergunta", c["suites"] is None,
       f"veio {c['suites']!r} (foi assim que o extrator do nosso catálogo"
       " inventou suites=0)")
checar("mas a suíte do texto vira dúvida, com o número",
       "1 suíte" in aviso_de(cc.duvidas(CASA_MAL_CLASSIFICADA, c), "suites"),
       aviso_de(cc.duvidas(CASA_MAL_CLASSIFICADA, c), "suites"))

print()
print("--- vagas: a OLX manda o TOTAL, o banco separa coberta ---")
checar("vagas recebe o total da OLX", c["vagas"] == 4, f"veio {c['vagas']!r}")
checar("vagas_cobertas fica None (o total não diz quantas são cobertas)",
       c["vagas_cobertas"] is None)
checar("e a pergunta já traz o total",
       any(f["campo"] == "vagas_cobertas"
           and f["rotulo"] == "Quantas das 4 vagas são cobertas?"
           for f in cc.o_que_falta(c)),
       str(cc.o_que_falta(c)))
uma_vaga = dict(c, vagas=1, vagas_cobertas=None)
checar("com uma vaga só, a pergunta muda de número gramatical",
       any(f["rotulo"] == "A vaga é coberta?" for f in cc.o_que_falta(uma_vaga)))
sem_vaga = dict(c, vagas=0, vagas_cobertas=None)
checar("com zero vagas, nem se pergunta sobre coberta",
       "vagas_cobertas" not in campos_que_faltam(cc.o_que_falta(sem_vaga)))

print()
print("--- 'R$ 0' de condomínio é campo pulado, não isenção ---")
checar("taxa_condominio 'R$ 0' vira None", c["taxa_condominio"] is None,
       f"veio {c['taxa_condominio']!r}")
checar("iptu 'R$ 0' vira None", c["iptu"] is None, f"veio {c['iptu']!r}")
d = cc.duvidas(CASA_MAL_CLASSIFICADA, c)
checar("e o zero vira dúvida, dizendo que não é isenção",
       "não informado" in aviso_de(d, "taxa_condominio"),
       aviso_de(d, "taxa_condominio"))
checar("condomínio de verdade é gravado",
       cc.traduzir(LOTE)["taxa_condominio"] == 197.0)

print()
print("--- o anunciante erra a categoria (3 de 217 medidos) ---")
checar("o tipo segue a OLX, que é o campo estruturado",
       c["tipo"] == "Apartamento")
checar("mas o texto dizer 'casa' vira dúvida",
       "casa" in aviso_de(d, "tipo"), aviso_de(d, "tipo"))
checar("e a dúvida NÃO bloqueia: o campo continua preenchido",
       c["tipo"] is not None)

print()
print("--- casa de rua x casa de condomínio: sem certeza, não chuta ---")
casa_rua = {"campos": {"category": "Casas",
                       "real_estate_type": "Venda - casa em rua pública"}}
casa_cond = {"campos": {"category": "Casas",
                        "real_estate_type": "Aluguel - casa em condominio fechado"}}
casa_vaga = {"campos": {"category": "Casas"}}
checar("'casa em rua pública' vira Casa",
       cc.traduzir(casa_rua)["tipo"] == "Casa")
checar("'casa em condominio fechado' (a OLX escreve sem acento) vira"
       " Casa de condomínio",
       cc.traduzir(casa_cond)["tipo"] == "Casa de condomínio",
       f"veio {cc.traduzir(casa_cond)['tipo']!r}")
checar("só 'Casas', sem detalhe, fica None -- as duas existem em peso"
       " (322 x 75) e chutar erra calado",
       cc.traduzir(casa_vaga)["tipo"] is None)
checar("e o None vira pergunta obrigatória",
       any(f["campo"] == "tipo" and f["obrigatorio"]
           for f in cc.o_que_falta(cc.traduzir(casa_vaga))))
checar("cobertura não vira Apartamento, apesar de a OLX escrever"
       " 'apartamento cobertura'",
       cc.traduzir({"campos": {"category": "Apartamentos",
                               "real_estate_type": "Venda - apartamento cobertura"}}
                   )["tipo"] == "Cobertura")
checar("kitnet fica None: o tipo não existe no nosso cadastro",
       cc.traduzir({"campos": {"category": "Apartamentos",
                               "real_estate_type": "Aluguel - apartamento kitchenette"}}
                   )["tipo"] is None)

print()
print("--- 'N ou mais' não é número (59 de 217 anúncios) ---")
c = cc.traduzir(GALPAO)
checar("'5 ou mais' vira 5 sem quebrar", c["vagas"] == 5, f"veio {c['vagas']!r}")
d = cc.duvidas(GALPAO, c)
checar("e vira dúvida, porque o real pode ser mais",
       "5 ou mais" in aviso_de(d, "vagas"), aviso_de(d, "vagas"))
checar("categoria de comércio não fecha tipo nenhum nosso",
       c["tipo"] is None)
checar("e a dúvida diz o que a OLX disse",
       "Comércio e indústria" in aviso_de(d, "tipo"), aviso_de(d, "tipo"))

print()
print("--- `size` significa três coisas conforme a categoria ---")
checar("em comércio, `size` é o terreno e NÃO vira área útil",
       c["area_util"] is None, f"veio {c['area_util']!r}")
checar("e o motivo aparece na dúvida, com o número que foi ignorado",
       "500m²" in aviso_de(d, "area_util"), aviso_de(d, "area_util"))
c_lote = cc.traduzir(LOTE)
checar("em terreno também não vira área útil", c_lote["area_util"] is None)
checar("em apartamento vira (a OLX chama de 'Área útil')",
       cc.traduzir(APTO_ALUGUEL)["area_util"] == 42.0)
casa_com_area = {"campos": {"category": "Casas",
                            "real_estate_type": "Venda - casa em rua pública",
                            "size": "152m²"}}
c_casa = cc.traduzir(casa_com_area)
checar("em casa vira, mas avisando que a OLX chama de 'área construída'",
       c_casa["area_util"] == 152.0
       and "construída" in aviso_de(cc.duvidas(casa_com_area, c_casa), "area_util"),
       aviso_de(cc.duvidas(casa_com_area, c_casa), "area_util"))

print()
print("--- lote: não se pergunta quantos banheiros tem um terreno ---")
checar("tipo do lote em condomínio", c_lote["tipo"] == "Lote em Condomínio",
       f"veio {c_lote['tipo']!r}")
faltam = campos_que_faltam(cc.o_que_falta(c_lote))
for campo in ("quartos", "banheiros", "vagas", "suites", "mobilia"):
    checar(f"{campo} não é perguntado num lote", campo not in faltam, str(faltam))
checar("mas a área do lote continua sendo perguntada", "area_util" in faltam)
# Regressão: terreno vale por m² numa faixa muito mais larga que apartamento
# (os 95 lotes do catálogo vão de R$ 288 a R$ 26.071/m²). Este lote sai a
# R$ 200/m² e é normal -- se a faixa de imóvel construído for usada aqui,
# TODO lote vira dúvida e o Tel para de ler os avisos.
checar("lote normal a R$ 200/m² não vira dúvida de valor",
       aviso_de(cc.duvidas(LOTE, c_lote), "valor_venda") == "",
       aviso_de(cc.duvidas(LOTE, c_lote), "valor_venda"))

print()
print("--- a fazenda de 12.000 hectares: todos os campos preenchidos,"
      " todos mentindo ---")
c = cc.traduzir(FAZENDA)
d = cc.duvidas(FAZENDA, c)
checar("o valor foi gravado como aluguel, que é o que a OLX disse",
       c["valor_aluguel"] == 1500.0)
checar("preço por m² absurdo vira dúvida -- é o cruzamento que a pega",
       "por m²" in aviso_de(d, "valor_aluguel"), aviso_de(d, "valor_aluguel"))
checar("e a área absurda também",
       "grande demais" in aviso_de(d, "area_util"), aviso_de(d, "area_util"))
checar("nada disso bloqueia: os campos continuam preenchidos",
       c["valor_aluguel"] is not None)
# A armadilha que este teste existe para travar: a fazenda é de uma categoria
# em que `traduzir()` RECUSA o `size` como área útil. Se a conferência de
# valor olhasse só `campos["area_util"]`, ela seria None e o único caso real
# conhecido passaria batido -- com a função inteira parecendo funcionar.
checar("a conferência cai no `size` cru quando area_util foi recusada",
       c["area_util"] is None and "120.000.000 m²" in aviso_de(d, "valor_aluguel"),
       aviso_de(d, "valor_aluguel"))
# Sem casas decimais suficientes o aviso sairia "R$ 0,00 por m²" e perderia
# justamente o número que prova o absurdo; e "1.2e+08 m²" não diz nada a
# ninguém no WhatsApp.
checar("o preço por m² minúsculo aparece, em vez de virar R$ 0,00",
       "0,000013" in aviso_de(d, "valor_aluguel"), aviso_de(d, "valor_aluguel"))
checar("e a área sai por extenso, não em notação científica",
       "e+" not in aviso_de(d, "valor_aluguel"))
checar("sítio e fazenda não viram Lote: não existe esse tipo no cadastro",
       c["tipo"] is None, f"veio {c['tipo']!r}")
checar("e a dúvida mostra o que a OLX disse, para escolher na mão",
       "sítios" in aviso_de(d, "tipo"), aviso_de(d, "tipo"))
checar("fora de Manaus vira dúvida do anúncio inteiro (campo None)",
       "Manicoré" in aviso_de(d, None), aviso_de(d, None))
checar("anúncio sem foto vira dúvida", "foto" in aviso_de(d, None))

print()
print("--- valor fora da faixa do nosso catálogo ---")
barato = {"preco_texto": "R$ 30.000", "preco_rotulo": "Preço",
          "campos": {"category": "Casas",
                     "real_estate_type": "Venda - casa em rua pública"}}
caro = {"preco_texto": "R$ 45.000", "preco_rotulo": "Aluguel",
        "campos": {"category": "Apartamentos",
                   "real_estate_type": "Aluguel - apartamento padrão"}}
checar("venda abaixo de R$ 50 mil vira dúvida",
       "abaixo" in aviso_de(cc.duvidas(barato), "valor_venda"))
checar("aluguel acima de R$ 20 mil vira dúvida",
       "passa de" in aviso_de(cc.duvidas(caro), "valor_aluguel"))
normal = {"preco_texto": "R$ 390.000", "preco_rotulo": "Preço",
          "campos": {"category": "Apartamentos",
                     "real_estate_type": "Venda - apartamento padrão",
                     "size": "70m²"}}
checar("venda normal (R$ 5.571/m²) NÃO vira dúvida de valor",
       aviso_de(cc.duvidas(normal), "valor_venda") == "",
       aviso_de(cc.duvidas(normal), "valor_venda"))

print()
print("--- venda x aluguel: dois sinais, e o desacordo vira dúvida ---")
discorda = {"preco_texto": "R$ 390.000", "preco_rotulo": "Aluguel",
            "campos": {"category": "Casas",
                       "real_estate_type": "Venda - casa em rua pública"}}
c = cc.traduzir(discorda)
checar("o tipo do anúncio decide (é a lista fechada que o anunciante escolheu)",
       c["valor_venda"] == 390000.0 and c["valor_aluguel"] is None)
checar("e o desacordo com o rótulo do preço vira dúvida",
       "rótulo do preço" in aviso_de(cc.duvidas(discorda, c), "valor_venda"),
       aviso_de(cc.duvidas(discorda, c), "valor_venda"))
sem_negocio = {"preco_texto": "R$ 390.000", "campos": {"category": "Casas"}}
c = cc.traduzir(sem_negocio)
checar("sem nenhum dos dois sinais, o preço NÃO é gravado a esmo",
       c["valor_venda"] is None and c["valor_aluguel"] is None)
checar("e a dúvida diz que o preço ficou de fora",
       "não foi gravado" in aviso_de(cc.duvidas(sem_negocio, c), "valor"),
       aviso_de(cc.duvidas(sem_negocio, c), "valor"))
checar("com valor nenhum, o pseudo-campo 'valor' é perguntado, obrigatório",
       any(f["campo"] == "valor" and f["obrigatorio"] for f in cc.o_que_falta(c)))
checar("com aluguel preenchido, não se pergunta o valor de venda junto",
       "valor" not in campos_que_faltam(cc.o_que_falta(cc.traduzir(APTO_ALUGUEL))))

print()
print("--- mobília: um rótulo na OLX, três níveis no nosso cadastro ---")
mob = {"titulo": "Alugo apartamento Mobiliado no parque mosaico",
       "campos": {"category": "Apartamentos", "re_features": "Mobiliado, Piscina"}}
semi = {"titulo": "Casa duplex semi-mobiliado c/ 4 suítes",
        "campos": {"category": "Casas", "re_features": "Mobiliado"}}
so_ar = {"titulo": "Apartamento", "campos": {"category": "Apartamentos",
                                             "re_features": "Ar condicionado"}}
checar("'Mobiliado' vira o texto EXATO da coluna mobilia",
       cc.traduzir(mob)["mobilia"] == cc.MOBILIA_MOBILIADO,
       f"veio {cc.traduzir(mob)['mobilia']!r}")
checar("o texto do anúncio baixa o nível para semi",
       cc.traduzir(semi)["mobilia"] == cc.MOBILIA_SEMI,
       f"veio {cc.traduzir(semi)['mobilia']!r}")
checar("ar-condicionado sozinho NÃO afirma nível de mobília",
       cc.traduzir(so_ar)["mobilia"] is None)
checar("mas sugere um, como dúvida",
       "so ar-condicionado" in aviso_de(cc.duvidas(so_ar), "mobilia"),
       aviso_de(cc.duvidas(so_ar), "mobilia"))
checar("e o nível preenchido também vira dúvida, porque a OLX só tem um",
       "três níveis" in aviso_de(cc.duvidas(mob), "mobilia"))

print()
print("--- o telefone do proprietário não pode ir para o site ---")
# Medido: 4 dos 7 anúncios abertos traziam telefone no corpo da descrição.
com_tel = dict(APTO_ALUGUEL,
               descricao="Jean Lunas - Corretor de imóveis<br>- Fone: 92 995176229")
com_par = dict(APTO_ALUGUEL,
               descricao="Código do anúncio: MORADA 2 (92) 99191-0064<br>Casa térrea")
com_zap = dict(APTO_ALUGUEL, descricao="Chama no whatsapp para agendar.")
checar("telefone com DDD solto vira dúvida",
       "telefone" in aviso_de(cc.duvidas(com_tel), "descricao"))
checar("telefone com DDD entre parênteses também",
       "telefone" in aviso_de(cc.duvidas(com_par), "descricao"))
checar("pedido de contato sem número também",
       "contato" in aviso_de(cc.duvidas(com_zap), "descricao"))
sem_tel = dict(APTO_ALUGUEL,
               descricao="Apartamento de 42m² no 2º andar, R$ 1.600,00, CEP 69093417.")
checar("mas valor, área e CEP não são confundidos com telefone",
       aviso_de(cc.duvidas(sem_tel), "descricao") == "",
       aviso_de(cc.duvidas(sem_tel), "descricao"))

print()
print("--- números em português, no formato do Brasil ---")
checar("'R$ 1.800.000' -> 1800000.0 (o ponto é milhar, não decimal)",
       cc._numero("R$ 1.800.000") == 1800000.0,
       f"veio {cc._numero('R$ 1.800.000')!r}")
checar("'R$ 3.700,50' -> 3700.50", cc._numero("R$ 3.700,50") == 3700.50,
       f"veio {cc._numero('R$ 3.700,50')!r}")
checar("'138m²' -> 138.0", cc._numero("138m²") == 138.0)
checar("'Sob consulta' -> None", cc._numero("Sob consulta") is None)
checar("None -> None", cc._numero(None) is None)
checar("o aviso sai com separador brasileiro",
       "R$ 1.800.000" in cc._reais(1800000.0).join(["R$ ", ""]),
       cc._reais(1800000.0))
checar("e com centavos também", cc._reais(1234.5, 2) == "1.234,50",
       cc._reais(1234.5, 2))

print()
print("--- a lista de perguntas é ordenada: obrigatório primeiro ---")
faltam = cc.o_que_falta(cc.traduzir(VAZIO))
obrig = [f["obrigatorio"] for f in faltam]
checar("nenhum opcional aparece antes de um obrigatório",
       obrig == sorted(obrig, reverse=True), str(obrig))
checar("a primeira pergunta é o tipo", faltam[0]["campo"] == "tipo",
       faltam[0]["campo"])
checar("todo item tem rótulo em português e a marca de obrigatório",
       all(f["rotulo"] and isinstance(f["obrigatorio"], bool) for f in faltam))
checar("nenhum rótulo saiu como nome de coluna",
       all(f["rotulo"] != f["campo"] for f in faltam),
       str([f for f in faltam if f["rotulo"] == f["campo"]]))
checar("respondido some da lista",
       "bairro" not in campos_que_faltam(
           cc.o_que_falta(dict(cc.traduzir(VAZIO), bairro="Flores"))))
checar("zero é resposta e some da lista, igual a qualquer outro valor",
       "vagas" not in campos_que_faltam(
           cc.o_que_falta(dict(cc.traduzir(VAZIO), vagas=0))))

print()
print("--- nada disto pode quebrar com lixo na entrada ---")
for entrada in (None, {}, {"campos": None}, {"campos": {"rooms": ""}},
                {"preco_texto": "", "campos": {"size": "abc"}},
                {"campos": {"rooms": "0", "garage_spaces": "0"}}):
    try:
        campos = cc.traduzir(entrada)
        cc.o_que_falta(campos)
        cc.duvidas(entrada, campos)
        checar(f"aguenta {entrada!r}", True)
    except Exception as erro:  # noqa: BLE001 -- é isto que o teste procura
        checar(f"aguenta {entrada!r}", False, f"{type(erro).__name__}: {erro}")
checar("'0' explícito da OLX é zero mesmo (o anunciante escolheu 0)",
       cc.traduzir({"campos": {"rooms": "0"}})["quartos"] == 0)
checar("e zero quarto vira dúvida",
       "zero quartos" in aviso_de(cc.duvidas({"campos": {"rooms": "0"}}), "quartos"))
checar("duvidas() sem campos calcula sozinho",
       cc.duvidas(FAZENDA) == cc.duvidas(FAZENDA, cc.traduzir(FAZENDA)))


# =========================================================================
# Casos da revisão de 02/09/2026, todos MEDIDOS contra a OLX ao vivo (Mac) e
# contra a tabela `imoveis` em produção, e todos vermelhos antes do conserto.
# =========================================================================

print()
print("--- vaga zerada pela OLX é campo pulado, não 'não tem vaga' ---")
# listId 1508281340: "Venda - apartamento padrão", 95m², 3 quartos, 2
# banheiros, condomínio R$ 660 -- e `garage_spaces: "0"`. Apartamento assim
# tem vaga. Medido: 6 dos 148 anúncios que trazem o campo mandam "0".
APTO_VAGA_ZERADA = {
    "preco_texto": "R$ 390.000",
    "preco_rotulo": "Preço",
    "bairro": "Flores",
    "municipio": "Manaus",
    "campos": {
        "category": "Apartamentos",
        "real_estate_type": "Venda - apartamento padrão",
        "size": "95m²", "rooms": "3", "bathrooms": "2",
        "garage_spaces": "0", "condominio": "R$ 660",
    },
    "fotos": ["https://img.olx.com.br/images/50/505613799054848.jpg"],
}
c = cc.traduzir(APTO_VAGA_ZERADA)
checar("vagas NÃO vira 0 -- 0 afirmaria ao corretor que não tem vaga",
       c["vagas"] is None, f"veio {c['vagas']!r}")
faltam = campos_que_faltam(cc.o_que_falta(c))
checar("e por ser None a vaga volta a ser perguntada", "vagas" in faltam)
checar("perguntada como obrigatória",
       any(f["campo"] == "vagas" and f["obrigatorio"]
           for f in cc.o_que_falta(c)))
d = cc.duvidas(APTO_VAGA_ZERADA, c)
checar("e o Tel é avisado de que a OLX mandou zero",
       "zero vagas" in aviso_de(d, "vagas"), aviso_de(d, "vagas"))
checar("mas nada disso bloqueia o resto do anúncio",
       c["quartos"] == 3 and c["banheiros"] == 2 and c["area_util"] == 95.0)
checar("zero que o TEL responde na plataforma continua sendo resposta",
       "vagas_cobertas" not in campos_que_faltam(cc.o_que_falta(dict(c, vagas=0))))
checar("zero banheiros também vira dúvida",
       "zero banheiros" in aviso_de(
           cc.duvidas({"campos": {"bathrooms": "0"}}), "banheiros"))

print()
print("--- área zerada: '0' (texto) e 0 (número) tinham resultados diferentes ---")
for bruto in ("0", "0m²", "0,00", 0):
    entrada = {"campos": {"category": "Apartamentos", "size": bruto}}
    checar(f"size={bruto!r} não vira área 0",
           cc.traduzir(entrada)["area_util"] is None,
           f"veio {cc.traduzir(entrada)['area_util']!r}")
checar("e a área volta a ser perguntada, obrigatória",
       any(f["campo"] == "area_util" and f["obrigatorio"]
           for f in cc.o_que_falta(cc.traduzir(
               {"campos": {"category": "Apartamentos", "size": "0"}}))))
checar("área de verdade continua passando",
       cc.traduzir({"campos": {"category": "Apartamentos",
                               "size": "95m²"}})["area_util"] == 95.0)

print()
print("--- condomínio e IPTU tinham piso e nenhum teto ---")
# listId 1531505674, aberto ao vivo: terreno de R$ 90.000 em que o anunciante
# repetiu o preço em `condominio` E em `iptu`. Gravava R$ 90.000 de taxa
# mensal, calado. Outros medidos no mesmo dia: R$ 330.000 e R$ 108.223.
TERRENO_TAXA_ABSURDA = {
    "preco_texto": "R$ 90.000",
    "preco_rotulo": "Preço",
    "bairro": "Cidade de Deus",
    "municipio": "Manaus",
    "campos": {
        "category": "Terrenos, sítios e fazendas",
        "real_estate_type": "Terrenos",
        "size": "1032m²",
        "condominio": "R$ 90.000", "iptu": "R$ 90.000",
    },
    "fotos": ["https://img.olx.com.br/images/53/533647189079728.jpg"],
}
d = cc.duvidas(TERRENO_TAXA_ABSURDA)
checar("condomínio do tamanho do imóvel vira dúvida",
       "passa de" in aviso_de(d, "taxa_condominio"), aviso_de(d, "taxa_condominio"))
checar("e a dúvida diz que é o MESMO valor do imóvel",
       "MESMO valor do imóvel" in aviso_de(d, "taxa_condominio"))
checar("IPTU absurdo também", "passa de" in aviso_de(d, "iptu"))
checar("mas o valor continua gravado: dúvida não bloqueia",
       cc.traduzir(TERRENO_TAXA_ABSURDA)["taxa_condominio"] == 90000.0)
# 8 dos 244 anúncios medidos trazem `"R$ 1"`, que é o "R$ 0" com outra cara.
d1 = cc.duvidas({"campos": {"condominio": "R$ 1", "iptu": "R$ 1"}})
checar("condomínio de R$ 1 vira dúvida (não existe um abaixo de R$ 50)",
       "baixo demais" in aviso_de(d1, "taxa_condominio"), aviso_de(d1, "taxa_condominio"))
checar("IPTU de R$ 1 também", "baixo demais" in aviso_de(d1, "iptu"))
checar("condomínio normal de R$ 660 NÃO vira dúvida",
       aviso_de(cc.duvidas({"campos": {"condominio": "R$ 660"}}),
                "taxa_condominio") == "")
checar("IPTU normal de R$ 750 NÃO vira dúvida",
       aviso_de(cc.duvidas({"campos": {"iptu": "R$ 750"}}), "iptu") == "")

print()
print("--- título ou descrição vindo como número não pode derrubar duvidas() ---")
# `extrair_olx` devolve `subject` e `body` crus do JSON, sem conversão. O
# `"" + 3.7` levantava TypeError e derrubava justamente a função que protege
# o Tel. Achado por fuzz com os tipos que JSON entrega.
for entrada in ({"titulo": 3.7, "descricao": None},
                {"titulo": None, "descricao": 120000000},
                {"titulo": 3, "descricao": 7, "campos": {"re_features": "Mobiliado"}}):
    try:
        campos = cc.traduzir(entrada)
        cc.o_que_falta(campos)
        cc.duvidas(entrada, campos)
        checar(f"aguenta {entrada!r}", True)
    except Exception as erro:  # noqa: BLE001 -- é isto que o teste procura
        checar(f"aguenta {entrada!r}", False, f"{type(erro).__name__}: {erro}")

print()
print(f"{total - falhas} de {total} casos passaram.")
sys.exit(1 if falhas else 0)
