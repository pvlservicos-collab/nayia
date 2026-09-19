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

print("--- em CONDOMÍNIO a linha não sai: lá ninguém pergunta isso ---")
texto = montar_mensagem(dict(IMOVEL_BASE, condominio="Condomínio Teste",
                             aceita_financiamento="Não"), GRUPO_COMUM)
print(texto)
_checar("nada de financiamento no card de condomínio",
        "financiamento" not in texto.lower())
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

print(f"{'TODOS OS CASOS PASSARAM' if falhas == 0 else str(falhas) + ' CASO(S) FALHARAM'}")
