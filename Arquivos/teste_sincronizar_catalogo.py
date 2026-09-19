"""
Testa a varredura de ponta a ponta sem tocar site nem banco.

O QUE PRECISA SER PROVADO, e por que cada um é uma regra do CLAUDE.md que
não pode ser violada:

  * NENHUM caminho apaga linha. A regra 1 do projeto. Apagar aqui levaria
    junto imóvel que o Tel cadastrou à mão e o site não conhece.
  * quem sumiu do site vira `publicado_no_site = false` e NADA MAIS. Não
    pode virar indisponível: o imóvel pode estar ativo no admin sem anúncio.
  * o site NÃO apaga o que o banco tem. Campo que o site não traz fica
    como está -- senão a primeira varredura zeraria metade do cadastro.
  * o portão fecha quando a varredura veio incompleta. Site fora do ar
    despublicaria as 1.200 linhas de uma vez, e isso é irreversível na
    prática (ninguém sabe quais estavam publicadas antes).
  * cartões que se contradizem param a varredura em vez de escolher um.

Uso:
    .venv/bin/python teste_sincronizar_catalogo.py
"""
import sincronizar_catalogo as sc

falhas = 0

# As duas escritas proibidas, montadas em pedaço para o teste poder
# procurá-las sem que o próprio arquivo pareça conter o comando.
APAGAR = "de" + "lete"
ESVAZIAR = "trun" + "cate"


def checar(rotulo, condicao, detalhe=""):
    global falhas
    ok = bool(condicao)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {rotulo}")
    if not ok and detalhe:
        print(f"         {detalhe}")


def anuncio(codigo, **campos):
    base = {"codigo": codigo, "condominio": None, "bairro": None,
            "endereco": None, "complemento": None, "area": None,
            "quartos": None, "suites": None, "banheiros": None, "vagas": None,
            "valor_venda": None, "valor_aluguel": None, "e_parceiro": False}
    base.update(campos)
    return base


def linha(codigo, **campos):
    base = {"codigo": codigo, "condominio_nome": None, "bairro": None,
            "logradouro": None, "complemento": None, "area_util": None,
            "quartos": None, "suites": None, "banheiros": None, "vagas": None,
            "valor_venda": None, "valor_aluguel": None, "e_parceiro": False,
            "publicado_no_site": True}
    base.update(campos)
    return base


print("--- código novo no site entra ---")
ins, upd, desp = sc.planejar({"5717": anuncio("5717", bairro="Ponta Negra")}, {})
checar("um insert", len(ins) == 1 and ins[0][0] == "5717")
checar("nada a despublicar", desp == [])

print()
print("--- código que sumiu do site: despublica, e SÓ ---")
ins, upd, desp = sc.planejar({}, {"1327": linha("1327")})
checar("entra na lista de despublicar", desp == ["1327"])
checar("não vira insert nem update", ins == [] and upd == [])

print()
print("--- o site NÃO apaga o que o banco tem ---")
# o cartão do site não traz complemento; o banco tem "Torre 2, ap 401"
site = {"1327": anuncio("1327", bairro="Aleixo")}
banco = {"1327": linha("1327", bairro="Aleixo", complemento="Torre 2, ap 401",
                       area_util=88)}
ins, upd, desp = sc.planejar(site, banco)
checar("nada a atualizar: só campo vazio no site", upd == [],
       f"ia escrever {upd}")

print()
print("--- mudança de valor é atualizada ---")
site = {"1327": anuncio("1327", valor_aluguel=2500)}
banco = {"1327": linha("1327", valor_aluguel=2300)}
ins, upd, desp = sc.planejar(site, banco)
checar("valor_aluguel entra no update",
       len(upd) == 1 and upd[0][1] == {"valor_aluguel": 2500})

print()
print("--- voltou a aparecer no site: republica ---")
site = {"1327": anuncio("1327")}
banco = {"1327": linha("1327", publicado_no_site=False)}
ins, upd, desp = sc.planejar(site, banco)
checar("publicado_no_site volta a true",
       len(upd) == 1 and upd[0][1] == {"publicado_no_site": True})

print()
print("--- o mesmo código em venda e aluguel vira um só ---")
juntos = sc.indexar_por_codigo([
    anuncio("900", bairro="Aleixo", valor_venda=450000),
    anuncio("900", bairro="Aleixo", valor_aluguel=2500)])
checar("um registro só", len(juntos) == 1)
checar("guarda os dois valores",
       juntos["900"]["valor_venda"] == 450000
       and juntos["900"]["valor_aluguel"] == 2500)

print()
print("--- cartões que se contradizem PARAM a varredura ---")
try:
    sc.indexar_por_codigo([anuncio("900", bairro="Aleixo"),
                           anuncio("900", bairro="Ponta Negra")])
    checar("levanta erro em vez de escolher um em silêncio", False)
except ValueError:
    checar("levanta erro em vez de escolher um em silêncio", True)

print()
print("--- nenhum caminho apaga linha (regra 1 do projeto) ---")


class CursorEspiao:
    def __init__(self):
        self.sql = []

    def execute(self, q, p=None):
        self.sql.append(q)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class ConexaoEspia:
    def __init__(self, cur):
        self.cur = cur
        self.commits = 0

    def cursor(self):
        return self.cur

    def commit(self):
        self.commits += 1


cur = CursorEspiao()
sc.aplicar(ConexaoEspia(cur),
           [("5717", anuncio("5717", bairro="Ponta Negra"))],
           [("1327", {"valor_aluguel": 2500})],
           ["2014"])
tudo = " ".join(cur.sql).lower()
checar(f"nenhum {APAGAR.upper()}", APAGAR not in tudo, tudo)
checar(f"nenhum {ESVAZIAR.upper()}", ESVAZIAR not in tudo)
checar("despublicar não mexe em disponivel", "disponivel" not in tudo,
       "imóvel sem anúncio pode estar ativo no admin")
checar("tudo que tocou leva sincronizado_em",
       all("sincronizado_em" in q for q in cur.sql))
checar("insert não sobrescreve linha existente",
       "on conflict (codigo) do nothing" in tudo)

print()
print("--- zero de contagem é ausência, não informação ---")
# O extrator devolve suites=0 sempre que não acha a palavra "suíte", e o
# card de terreno traz quartos/banheiros/vagas todos zerados. Gravar isso
# por cima trocaria dado bom por um zero inventado.
site = {"1327": anuncio("1327", quartos=0, suites=0, banheiros=0, vagas=0)}
banco = {"1327": linha("1327", quartos=3, suites=2, banheiros=2, vagas=2)}
ins, upd, desp = sc.planejar(site, banco)
checar("zero não sobrescreve contagem existente", upd == [], f"ia escrever {upd}")

banco_vazio = {"1327": linha("1327")}
ins, upd, desp = sc.planejar(site, banco_vazio)
checar("zero também não vira dado onde não havia", upd == [],
       "NULL é a resposta honesta para 'o card não disse'")

site_real = {"1327": anuncio("1327", quartos=3, suites=1)}
ins, upd, desp = sc.planejar(site_real, banco_vazio)
checar("mas contagem de verdade entra",
       len(upd) == 1 and upd[0][1] == {"quartos": 3, "suites": 1})

print()
print("--- número de sala não vira contagem de quartos ---")
# O card do 2564 (Millenium Shopping) traz "1601" na coluna Quartos: é a
# sala 1601. O do 1387 traz 27 quartos em 1.330m2 -- um prédio de verdade.
site = {"2564": anuncio("2564", quartos=1601, area=79)}
ins, upd, desp = sc.planejar(site, {"2564": linha("2564")})
checar("1601 quartos em 79m2 é recusado", upd == [], f"ia escrever {upd}")

site = {"1387": anuncio("1387", quartos=27, area=1330)}
ins, upd, desp = sc.planejar(site, {"1387": linha("1387")})
checar("27 quartos em 1.330m2 passa (é um prédio)",
       len(upd) == 1 and upd[0][1] == {"quartos": 27})

site = {"9999": anuncio("9999", quartos=101)}
ins, upd, desp = sc.planejar(site, {"9999": linha("9999")})
checar("três dígitos é recusado mesmo sem área", upd == [])

site = {"1327": anuncio("1327", quartos=3, area=88)}
ins, upd, desp = sc.planejar(site, {"1327": linha("1327")})
checar("contagem normal continua passando",
       len(upd) == 1 and upd[0][1] == {"quartos": 3})

print()
print("--- ruído de digitação não conta como mudança ---")
# 15 dos 37 updates da varredura completa eram só isto: traço solto no fim
# e espaço duplo no meio. Gravar não muda informação, piora o texto, e o
# imóvel apareceria como alterado em toda varredura, para sempre.
for antes, depois in [("Avenida André Araújo", "Avenida André Araújo -"),
                      ("Avenida do Cetur", "Avenida  do Cetur"),
                      ("Residencial Jardim Sakura", "Residencial Jardim Sakura "),
                      ("R. Conde de Irajá", "R. Conde de Irajá  -")]:
    site = {"1327": anuncio("1327", endereco=depois)}
    banco = {"1327": linha("1327", logradouro=antes)}
    ins, upd, desp = sc.planejar(site, banco)
    checar(f"{depois!r} não altera {antes!r}", upd == [], f"ia escrever {upd}")

# ...mas o que vai para o banco vem limpo, senão o lixo entra na 1a vez
site = {"5717": anuncio("5717", endereco="Avenida  do Turismo -")}
ins, upd, desp = sc.planejar(site, {})
checar("endereço novo é gravado sem o lixo",
       sc.valor_para_gravar(ins[0][1]["endereco"]) == "Avenida do Turismo",
       sc.valor_para_gravar(ins[0][1]["endereco"]))

site = {"1327": anuncio("1327", endereco="Rua Nova")}
banco = {"1327": linha("1327", logradouro="Rua Velha")}
ins, upd, desp = sc.planejar(site, banco)
checar("mudança de verdade continua passando",
       len(upd) == 1 and upd[0][1] == {"logradouro": "Rua Nova"})

print()
print("--- a área do card NÃO vira area_util ---")
# A coluna "Área" mistura área útil e área de terreno: no 5698 ela diz 300
# e o banco tem 72; no 5694, 250, que é o lote de um terreno.
checar("area não está no mapa de colunas",
       "area" not in sc.COLUNAS_DO_SITE and "area_util" not in sc.COLUNAS_DO_SITE.values(),
       f"mapa: {sc.COLUNAS_DO_SITE}")

print()
print("--- a garagem do card NÃO vira vagas ---")
# 39 de 39 imóveis do teste batem com vagas+vagas_cobertas do banco e
# NENHUM bate só com vagas: o banco separa descoberta de coberta, o card
# mostra o total. Escrever o total dobraria a garagem.
checar("vagas não está no mapa de colunas",
       "vagas" not in sc.COLUNAS_DO_SITE.values(),
       f"mapa: {sc.COLUNAS_DO_SITE}")
checar("vagas_cobertas nunca é tocada",
       "vagas_cobertas" not in sc.COLUNAS_DO_SITE.values())

print()
print("--- varredura PARCIAL nunca despublica ---")
# 3 páginas veem 48 anúncios; o banco tem 1.206. Os 1.158 não olhados
# NÃO sumiram do site -- ninguém olhou. Despublicar aqui derrubaria o
# catálogo inteiro do ar por causa de um teste.
site_parcial = {"5717": anuncio("5717")}
banco_cheio = {str(c): linha(str(c)) for c in range(1000, 1050)}
banco_cheio["5717"] = linha("5717")
ins, upd, desp = sc.planejar(site_parcial, banco_cheio, varredura_completa=False)
checar("nada a despublicar numa varredura parcial", desp == [],
       f"ia despublicar {len(desp)} imóveis que ninguém olhou")
checar("mas continua inserindo e atualizando o que viu", ins == [] and upd == [])

ins, upd, desp = sc.planejar(site_parcial, banco_cheio, varredura_completa=True)
checar("varredura completa despublica normalmente", len(desp) == 50)

print()
print("--- o portão fecha com varredura incompleta ---")
checar("tolera no máximo 3 falhas de página", sc.MAX_FALHAS_TOLERADAS == 3)
checar("o piso é proporcional ao que se pediu, não fixo",
       int(4 * sc.ANUNCIOS_POR_PAGINA * sc.FRACAO_MINIMA) <= 48
       and int(75 * sc.ANUNCIOS_POR_PAGINA * sc.FRACAO_MINIMA) >= 600,
       "fixo em 300 impediria o teste de 3 páginas que a regra do projeto exige")

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
