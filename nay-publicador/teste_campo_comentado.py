"""
Prova que o extrator do anúncio enxerga o campo que o site deixa COMENTADO.

O CASO (Tel, 14/09): ele disparou o 5718 e o card saiu sem "(incluso a tx)".
Eu respondi que o dado não existia -- olhando a tabela `imoveis`, onde de fato
está vazio -- e disse que ele nunca tinha marcado. **Estava errado.** O anúncio
traz o campo:

    <label class="form-control-label">Incluso no Aluguel</label>
    <span class="form-control">Água, Taxa de Gás, Taxa de Condomínio, IPTU</span>

só que o site envolve esse bloco inteiro em `<!-- ... -->`. O BeautifulSoup
trata comentário como texto opaco, então `soup.find("label", ...)` não entra
ali -- o extrator baixava a página e não via o campo.

MEDIDO no 5718 em 14/09: ficam DENTRO do comentário os rótulos "Valor de
Aluguel", "Aceita Financiamento?" e "Incluso no Aluguel". Três campos que nunca
chegaram ao card por este motivo, e um deles é o valor do aluguel.

O CLAUDE.md afirmava "o site NÃO publica esse dado -- conferido no HTML inteiro
do 5729". A conferência de então leu o texto renderizado, não o HTML, e a frase
errada guiou decisões por semanas -- inclusive a minha, ontem.

E "Lances de Escada" é rótulo VISÍVEL: nunca foi lido porque ninguém o pediu.
O 5718 traz "3", que é exatamente o número do exemplo que o Tel escreveu.

Uso:
    .venv/bin/python teste_campo_comentado.py
"""
from bs4 import BeautifulSoup

from buscar_imovel import _campo

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


def sopa(html):
    return BeautifulSoup(html, "html.parser")


# A marcação é a do anúncio real, recortada do 5718 em 14/09.
BLOCO = """
  <div class="col-md-12">
    <div class="form-group bd-t-0-force">
      <label class="form-control-label">Incluso no Aluguel</label>
      <span class="form-control">Água, Taxa de Gás, Taxa de Condomínio, IPTU</span>
    </div>
  </div>
"""

VISIVEL = """
<div class="col-md">
  <div class="form-group">
    <label class="form-control-label">Lances de Escada</label>
    <span class="form-control">3</span>
  </div>
</div>
"""

print("--- o campo VISÍVEL continua sendo lido ---")
checar("Lances de Escada", _campo(sopa(VISIVEL), "Lances de Escada"), "3")

print()
print("--- o campo DENTRO DO COMENTÁRIO passa a ser lido ---")
checar("Incluso no Aluguel comentado",
       _campo(sopa("<div><!--" + BLOCO + "--></div>"), "Incluso no Aluguel"),
       "Água, Taxa de Gás, Taxa de Condomínio, IPTU")
checar("e fora do comentário também",
       _campo(sopa("<div>" + BLOCO + "</div>"), "Incluso no Aluguel"),
       "Água, Taxa de Gás, Taxa de Condomínio, IPTU")

print()
print("--- a página real do 5718: três campos dentro do comentário ---")
# É a forma exata que o site serve: a seção de valores inteira comentada.
PAGINA_5718 = """
<html><body>
  """ + VISIVEL + """
  <!--
  <div class="row">
    <div class="form-group">
      <label class="form-control-label">Valor de Aluguel</label>
      <span class="form-control">R$  2.500,00</span>
    </div>
    <div class="form-group">
      <label class="form-control-label">Aceita Financiamento?</label>
      <span class="form-control">Não</span>
    </div>
  </div>
  """ + BLOCO + """
  -->
</body></html>
"""
s5718 = sopa(PAGINA_5718)
checar("o incluso sai", _campo(s5718, "Incluso no Aluguel"),
       "Água, Taxa de Gás, Taxa de Condomínio, IPTU")
# O espaço duplo é do site, e o `get_text(" ", strip=True)` não colapsa
# espaço DENTRO de um nó de texto -- só apara as pontas. Quem lê o valor
# (`_parse_valor`) já trata; o teste registra a forma real em vez de fingir
# que a página é limpa.
checar("o valor de aluguel sai", _campo(s5718, "Valor de Aluguel"),
       "R$  2.500,00")
checar("o financiamento sai", _campo(s5718, "Aceita Financiamento?"), "Não")
checar("o lance de escada sai", _campo(s5718, "Lances de Escada"), "3")

print()
print("--- o que não existe continua devolvendo None ---")
checar("rótulo inexistente", _campo(s5718, "Piscina Olímpica"), None)
checar("página vazia", _campo(sopa("<html></html>"), "Incluso no Aluguel"), None)
# Rótulo PARECIDO não vale: a busca é por igualdade, e afirmar taxa inclusa de
# um campo que fala de outra coisa põe conta errada no card do corretor.
checar("rótulo parecido não casa",
       _campo(sopa('<label class="form-control-label">Incluso no Aluguel?</label>'
                   '<span class="form-control">x</span>'), "Incluso no Aluguel"),
       None)

print()
print("--- e dá para desligar a busca no comentário ---")
checar("com a busca desligada, não acha",
       _campo(sopa("<div><!--" + BLOCO + "--></div>"), "Incluso no Aluguel",
              dentro_de_comentario=False),
       None)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO CAMPO COMENTADO PASSARAM")
