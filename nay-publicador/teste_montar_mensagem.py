"""
Testa montar_mensagem.py isoladamente -- sem HTTP, sem banco.

Uso:
    .venv/bin/python teste_montar_mensagem.py
"""
from montar_mensagem import montar_mensagem

IMOVEL_BASE = {
    "codigo": "5750", "condominio": "Condomínio Teste", "tipo": "Apartamento",
    "bairro": "Ponta Negra", "area": 98, "quartos": 3, "suites": 1, "banheiros": 2,
    "vagas": 2, "vagas_cobertas": 2, "valor_venda": 500000.0, "valor_aluguel": None,
}

GRUPO_COMUM = {"aceita_venda": True, "aceita_locacao": True}

falhas = 0


def _checar(nome, condicao):
    global falhas
    falhas += 0 if condicao else 1
    print(f"{nome}: {'OK' if condicao else 'FALHOU'}")


print("--- área normal: linha aparece ---")
texto = montar_mensagem(IMOVEL_BASE, GRUPO_COMUM)
print(texto)
_checar("mostra 98m2", "98m2" in texto)
print()

print("--- área zero: linha some, resto do texto continua ---")
imovel_area_zero = dict(IMOVEL_BASE, area=0)
texto = montar_mensagem(imovel_area_zero, GRUPO_COMUM)
print(texto)
_checar("não mostra 'm2' nenhum", "m2" not in texto)
_checar("condomínio continua aparecendo", "Condomínio Teste" in texto)
_checar("quartos continua aparecendo", "3 quartos" in texto)
_checar("valor continua aparecendo", "500.000" in texto)
_checar("código continua aparecendo", "5750" in texto)
print()

print("--- vagas zero (cobertas e totais): linha some, resto continua ---")
imovel_vagas_zero = dict(IMOVEL_BASE, vagas=0, vagas_cobertas=0)
texto = montar_mensagem(imovel_vagas_zero, GRUPO_COMUM)
print(texto)
_checar("não mostra 'vaga' nenhuma", "vaga" not in texto.lower())
_checar("área continua aparecendo", "98m2" in texto)
_checar("valor continua aparecendo", "500.000" in texto)
print()

print("--- área E vagas zero ao mesmo tempo: as duas somem, resto continua ---")
imovel_ambos_zero = dict(IMOVEL_BASE, area=0, vagas=0, vagas_cobertas=0)
texto = montar_mensagem(imovel_ambos_zero, GRUPO_COMUM)
print(texto)
_checar("não mostra 'm2'", "m2" not in texto)
_checar("não mostra 'vaga'", "vaga" not in texto.lower())
_checar("condomínio continua aparecendo", "Condomínio Teste" in texto)
_checar("banheiros continua aparecendo", "2 banheiros" in texto)
print()

print("--- FINANCIAMENTO: imóvel de rua à venda diz se financia ---")
# O Tel pediu em 02/09: casa de rua muitas vezes não pode ser financiada, e sem
# essa linha o corretor leva o cliente e descobre depois. "Via pública" é o
# imóvel SEM condomínio -- medido contra 10 anúncios reais, os quatro sem
# condomínio eram exatamente os de rua.
CASA_DE_RUA = dict(IMOVEL_BASE, codigo="4109", tipo="Casa", condominio=None,
                   aceita_financiamento="Sim")
texto = montar_mensagem(CASA_DE_RUA, GRUPO_COMUM)
print(texto)
_checar("diz que aceita financiamento", "• aceita financiamento" in texto)
_checar("logo depois do valor de venda",
        texto.index("Venda:") < texto.index("aceita financiamento"))
print()

print("--- e diz quando NÃO financia, que é o caso que interessa ---")
texto = montar_mensagem(dict(CASA_DE_RUA, aceita_financiamento="Não"), GRUPO_COMUM)
print(texto)
_checar("diz que NÃO aceita", "• não aceita financiamento" in texto)
print()

print("--- em CONDOMÍNIO também sai: o Tel ampliou a regra em 02/09 ---")
# Nasceu como pedido só para imóvel de rua e ele ampliou com todas as letras:
# "quero deixar que sempre saia se aceita financiamento ou não".
texto = montar_mensagem(dict(IMOVEL_BASE, condominio="Condomínio Teste",
                             aceita_financiamento="Não"), GRUPO_COMUM)
print(texto)
_checar("sai no card de condomínio também",
        "• não aceita financiamento" in texto)
print()

print("--- sem o dado, a linha some (não vira 'não financia') ---")
# O site não traz o campo em todo anúncio -- o 2943 é um desses. Afirmar que
# não financia um imóvel que financia derruba negócio.
for ausente in (None, "", "   "):
    texto = montar_mensagem(dict(CASA_DE_RUA, aceita_financiamento=ausente),
                            GRUPO_COMUM)
    _checar(f"ausente ({ausente!r}) não vira afirmação",
            "financiamento" not in texto.lower())
print()

print("--- só para LOCAÇÃO a linha não sai: financiamento é de venda ---")
so_aluguel = dict(CASA_DE_RUA, valor_venda=None, valor_aluguel=2500)
texto = montar_mensagem(so_aluguel, GRUPO_COMUM)
print(texto)
_checar("nada de financiamento quando não há venda",
        "financiamento" not in texto.lower())
print()

print("--- no grupo que só vê venda, a linha acompanha o valor ---")
texto = montar_mensagem(CASA_DE_RUA, {"aceita_venda": True, "aceita_locacao": False})
_checar("sai junto com a venda", "• aceita financiamento" in texto)
# E no grupo que não vê venda nenhuma, some junto com o valor.
texto = montar_mensagem(CASA_DE_RUA, {"aceita_venda": False, "aceita_locacao": True})
_checar("sem a linha de venda, sem a de financiamento",
        "financiamento" not in texto.lower())
print()

print("--- O TÍTULO do imóvel de rua diz o bairro (02/09) ---")
# Antes saía só "📍 Casa", que não identifica nada. O Tel: "casa em via
# pública, colocar assim: Casa bairro Flores ou casa conjunto Dom Pedro".
CASA_DE_RUA = dict(IMOVEL_BASE, codigo="5647", tipo="Casa", condominio=None,
                   bairro="Flores", aceita_financiamento="Sim")
texto = montar_mensagem(CASA_DE_RUA, GRUPO_COMUM)
print(texto)
_checar("título traz o bairro", texto.startswith("📍 Casa bairro Flores"))
_checar("e o bairro não se repete numa linha própria",
        texto.count("Flores") == 1)
print()

print("--- bairro que JÁ é conjunto não vira 'bairro Conjunto' ---")
texto = montar_mensagem(dict(CASA_DE_RUA, bairro="Conjunto Dom Pedro"), GRUPO_COMUM)
_checar("sai 'Casa Conjunto Dom Pedro'",
        texto.startswith("📍 Casa Conjunto Dom Pedro"))
print()

print("--- em CONDOMÍNIO o título é o condomínio, e o bairro fica na linha ---")
texto = montar_mensagem(IMOVEL_BASE, GRUPO_COMUM)
_checar("título é o condomínio", texto.startswith("📍 Condomínio Teste"))
_checar("bairro na linha própria", "• Bairro: Ponta Negra" in texto)
print()

print("--- ÁREA CONSTRUÍDA sai com o rótulo; área comum, não ---")
_checar("casa diz 'de área construída'",
        "• 265m2 de área construída"
        in montar_mensagem(dict(CASA_DE_RUA, area=265, area_e_construida=True),
                           GRUPO_COMUM))
_checar("apartamento diz só a metragem",
        "• 49m2" in montar_mensagem(dict(IMOVEL_BASE, area=49,
                                         area_e_construida=False), GRUPO_COMUM))
print()

print("--- VAGAS: total, cobertas, e o que não se sabe ---")
def _vagas(total, cobertas):
    t = montar_mensagem(dict(IMOVEL_BASE, vagas=total, vagas_cobertas=cobertas),
                        GRUPO_COMUM)
    return [l for l in t.split("\n") if "vaga" in l]
_checar("2 vagas sendo 1 coberta", _vagas(2, 1) == ["• 2 vagas sendo 1 vaga coberta"])
_checar("todas cobertas", _vagas(2, 2) == ["• 2 vagas cobertas"])
_checar("uma coberta só, no singular", _vagas(1, 1) == ["• 1 vaga coberta"])
_checar("nenhuma coberta é descoberta", _vagas(2, 0) == ["• 2 vagas descobertas"])
# None é "não sei", não "nenhuma" -- dizer "descobertas" de uma vaga coberta é
# erro que o corretor descobre na visita.
_checar("sem o dado, não afirma cobertura", _vagas(2, None) == ["• 2 vagas"])
_checar("uma vaga é 'vaga', não 'vagas'", _vagas(1, None) == ["• 1 vaga"])
_checar("sem vaga nenhuma, sem linha", _vagas(0, None) == [])
print()

print("--- SOL, MOBÍLIA e (incluso a tx) ---")
_checar("nascente", "• nascente" in montar_mensagem(dict(IMOVEL_BASE, sol="Nascente"), GRUPO_COMUM))
_checar("poente", "• poente" in montar_mensagem(dict(IMOVEL_BASE, sol="Poente"), GRUPO_COMUM))
_checar("sol vazio não vira linha",
        "nascente" not in montar_mensagem(dict(IMOVEL_BASE, sol=""), GRUPO_COMUM))
# As três redações que existem no cadastro, medidas: 234 semi, 140 mobiliado,
# 40 só ar-condicionado.
_checar("semi-mobiliado", "• semi-mobiliado" in montar_mensagem(
    dict(IMOVEL_BASE, mobilia="semi-mobiliado (moveis planejados + ar)"), GRUPO_COMUM))
_checar("mobiliado", "• mobiliado" in montar_mensagem(
    dict(IMOVEL_BASE, mobilia="mobiliado (moveis + cama + tudo)"), GRUPO_COMUM))
_checar("só ar-condicionado vira 'climatizado'", "• climatizado" in montar_mensagem(
    dict(IMOVEL_BASE, mobilia="so ar-condicionado"), GRUPO_COMUM))

ALUGUEL = dict(IMOVEL_BASE, valor_venda=None, valor_aluguel=2600.0)
_checar("taxa inclusa aparece ao lado do valor",
        "Locação: R$ 2.600 (incluso a tx)" in montar_mensagem(
            dict(ALUGUEL, incluso_no_aluguel="Água, Taxa de Gás, Taxa de Condomínio"),
            GRUPO_COMUM))
_checar("sem condomínio incluso, sem parênteses",
        "Locação: R$ 2.600\n" in montar_mensagem(
            dict(ALUGUEL, incluso_no_aluguel="Água"), GRUPO_COMUM))
_checar("sem o dado, sem parênteses",
        "Locação: R$ 2.600\n" in montar_mensagem(ALUGUEL, GRUPO_COMUM))
print()

print("--- LANCES DE ESCADA (Tel, 14/09) ---")
# Para quem sobe com cliente idoso ou com criança, é a informação que decide a
# visita -- e não está em lugar nenhum da página do anúncio: mora em
# `extras->>'lances de escada'` e veio da importação.
_checar("3 lances vira linha",
        "• 3 lances de escada" in montar_mensagem(
            dict(IMOVEL_BASE, lances_de_escada="3"), GRUPO_COMUM))
_checar("1 lance no singular",
        "• 1 lance de escada" in montar_mensagem(
            dict(IMOVEL_BASE, lances_de_escada="1"), GRUPO_COMUM))
# ZERO NÃO É AUSÊNCIA, mas também não vira linha: 616 dos 626 imóveis que têm
# a chave trazem "0". Imprimir "0 lances de escada" em 616 cards é ruído.
_checar("zero NÃO vira linha",
        "escada" not in montar_mensagem(
            dict(IMOVEL_BASE, lances_de_escada="0"), GRUPO_COMUM))
_checar("sem o dado, sem linha",
        "escada" not in montar_mensagem(IMOVEL_BASE, GRUPO_COMUM))
_checar("lixo no campo não vira linha",
        "escada" not in montar_mensagem(
            dict(IMOVEL_BASE, lances_de_escada="nao sei"), GRUPO_COMUM))
# A POSIÇÃO é a que ele escreveu: depois do bairro, antes da metragem.
_linhas = montar_mensagem(dict(IMOVEL_BASE, lances_de_escada="3"),
                          GRUPO_COMUM).split("\n")
_i_escada = next(i for i, l in enumerate(_linhas) if "escada" in l)
_i_bairro = next((i for i, l in enumerate(_linhas) if "Bairro" in l), 0)
_i_area = next((i for i, l in enumerate(_linhas) if "m2" in l), 99)
_checar("vem depois do bairro e antes da metragem",
        _i_bairro < _i_escada < _i_area)
print()


print("--- AVISO DE SAÍDA NO EASY (Tel, 15/09) ---")
from montar_mensagem import montar_aviso_de_saida
ACQ = dict(codigo="5611", tipo="Apartamento", condominio="Condomínio Acquarelle",
           bairro="Ponta Negra", sol="Nascente", area=88, quartos=3, suites=1,
           valor_aluguel=4600.0, incluso_no_aluguel="Água, Taxa de Gás, Taxa de Condomínio")
_checar("o exemplo literal do Tel",
        montar_aviso_de_saida(ACQ, "alugado") ==
        "🛑 condomínio acquarelle alugado\n• Bairro: Ponta Negra\n• apto nascente\n"
        "• 88m2\n• 3 quartos sendo 1 suíte\nlocação: 4.600 (incluso a TX)\nCódigo: 5611")
# O valor é o do negócio que ACABOU: alugado mostra locação e esconde a venda,
# porque o imóvel continua à venda.
_ambos = dict(ACQ, valor_venda=900000.0)
_checar("alugado com os dois valores mostra só a locação",
        "venda" not in montar_aviso_de_saida(_ambos, "alugado"))
_checar("vendido mostra a venda, não a locação",
        "venda: 900.000" in montar_aviso_de_saida(_ambos, "vendido")
        and "locação" not in montar_aviso_de_saida(_ambos, "vendido"))
_checar("sem taxa inclusa, sem o (incluso a TX)",
        "locação: 4.600\n" in montar_aviso_de_saida(dict(ACQ, incluso_no_aluguel="Água"), "alugado"))
_checar("sem sol, a linha do tipo não sai",
        "apto" not in montar_aviso_de_saida(dict(ACQ, sol=None), "alugado"))
_checar("casa de condomínio vira 'casa'",
        "• casa poente" in montar_aviso_de_saida(dict(ACQ, tipo="Casa de condomínio", sol="Poente"), "alugado"))
# Imóvel de rua: o título já diz o bairro, e a linha "Bairro" repetiria.
_rua = montar_aviso_de_saida(dict(codigo="5712", tipo="Casa", bairro="Flores",
                                  quartos=3, valor_venda=650000), "vendido")
_checar("de rua: título com bairro e sem linha repetida",
        _rua.startswith("🛑 casa bairro flores vendido") and "Bairro:" not in _rua)
_checar("sem valor do negócio, a linha de valor não sai",
        "locação" not in montar_aviso_de_saida(dict(ACQ, valor_aluguel=None), "alugado"))
print()

print("--- o card inteiro, do jeito que o Tel escreveu ---")
print(montar_mensagem(dict(codigo="5647", tipo="Casa", condominio=None,
                           bairro="Flores", area=265, area_e_construida=True,
                           quartos=4, suites=2, banheiros=4,
                           vagas=2, vagas_cobertas=1,
                           valor_venda=780000.0, aceita_financiamento="Sim"),
                      GRUPO_COMUM))
print()

print(f"{'TODOS OS CASOS PASSARAM' if falhas == 0 else str(falhas) + ' CASO(S) FALHARAM'}")
# SAIR COM ERRO QUANDO FALHA (15/09). Este arquivo imprimia "N CASO(S)
# FALHARAM" e saía com código 0 -- e o `rodar_testes.sh` só olha o código de
# saída. Resultado medido: cinco casos vermelhos de `postar_easy` passaram
# despercebidos desde o commit 64d946a, com a suíte inteira dizendo "TODAS
# PASSARAM". Suíte que não falha quando falha é a família do bug 18.
if falhas:
    raise SystemExit(1)
