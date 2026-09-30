"""
A OBS que o Tel escreve no admin sai no card, logo acima do código (14/09).

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * A OBS DO 5738 SAI: ela mora na seção "Observações", num `<p>`;

  * O TEXTO ANTIGO NÃO SAI. A seção "Observações" do 1885 guarda a descrição
    antiga inteira, com mais de mil caracteres, sem rótulo -- pegar a seção
    toda publicaria isso em 14 grupos. E dentro dele há "Obs :1 Sala Íntima..."
    e "Obs: todas as suites...": anotação de texto colado, não a OBS dele. Só
    "OBS" em maiúsculo no começo da linha conta;

  * O RODAPÉ NÃO SAI: a mesma página diz "Tem uma observação sobre esse
    anúncio? ... Clique Aqui!";

  * A POSIÇÃO: sempre logo acima de "Código:".

Uso:
    .venv/bin/python teste_observacao_do_card.py
"""
from bs4 import BeautifulSoup

from buscar_imovel import _observacao
from montar_mensagem import montar_mensagem

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


def pagina(descricao, observacoes):
    return BeautifulSoup(f"""
    <div class="card-body">
      <div class="slim-card-title mg-t-20 tx-left">Descrição do Anúncio</div><hr>
      <div class="row no-gutters tx-left"><div class="col-md-12"><div class="form-group">
        <span class="form-control">{descricao}</span></div></div></div>
    </div>
    <div class="card-body">
      <div class="slim-card-title mg-t-20 tx-left">Observações</div><hr>
      <div class="row no-gutters tx-left"><div class="col-md-12"><div class="form-group">
        <span class="form-control">{observacoes}</span></div></div></div>
    </div>
    <div class="card-footer"><p class="tx-11">Tem uma observação sobre esse anúncio?
      Você é o proprietário? Já foi vendido? Informe pra gente! Clique Aqui!</p></div>
    """, "html.parser")


print("--- de onde a OBS sai ---")
checar("o 5738: seção Observações, num <p>",
       _observacao(pagina("Apartamento localizado no condomínio Estilo Ponta Negra\n- 2 quarto",
                          "<p>OBS: Apartamento nunca habitado vendido porteira fechada.</p>")),
       "Apartamento nunca habitado vendido porteira fechada.")
checar("linha OBS dentro da descrição também vale",
       _observacao(pagina("Casa ampla\nOBS: Aceita financiamento e Fgts como entrada", "")),
       "Aceita financiamento e Fgts como entrada")
checar("OBS com traço", _observacao(pagina("", "<p>OBS - aceita pet</p>")), "aceita pet")

print()
print("--- o que NÃO pode sair ---")
ANTIGO = ("Uma das melhores quadras do condomínio numa região super arborizada."
          "<br>Obs :1 Sala Íntima podendo servir de brinquedoteca;"
          "<br>Obs: todas as suites com banheiro no blindex e varanda externa;")
checar("o texto antigo do 1885, sem rótulo e com 'Obs' capitalizado",
       _observacao(pagina(ANTIGO, ANTIGO)), None)
checar("o rodapé 'Tem uma observação sobre esse anúncio?'",
       _observacao(pagina("sem nada", "")), None)
checar("'OBS' no MEIO da frase não é rótulo",
       _observacao(pagina("apartamento amplo, OBS: nada", "")), None)
checar("a mesma OBS nas duas seções sai uma vez",
       _observacao(pagina("OBS: porteira fechada", "<p>OBS: porteira fechada</p>")),
       "porteira fechada")

print()
print("--- o card ---")
card = montar_mensagem(dict(codigo="5738", tipo="Apartamento", condominio="Estilo Ponta Negra",
                            bairro=None, area=48, quartos=2, suites=1, banheiros=2, vagas=1,
                            valor_venda=499999.0,
                            observacao="Apartamento nunca habitado vendido porteira fechada."),
                       {"aceita_venda": True, "aceita_locacao": True}).split("\n")
checar("a OBS vem logo acima do código",
       card[-2:], ["OBS: Apartamento nunca habitado vendido porteira fechada.", "Código: 5738"])
card = montar_mensagem(dict(codigo="1", tipo="Casa", quartos=2, valor_venda=1.0),
                       {"aceita_venda": True}).split("\n")
checar("sem OBS, o card de sempre", any(l.startswith("OBS") for l in card), False)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA OBS DO CARD PASSARAM")
