"""Prova o extrator da OLX sem tocar na rede.

Usa um HTML montado com o MESMO formato do real (bloco
`<script id="initial-data" data-json="...">` com o JSON escapado em HTML) --
o formato foi conferido contra um anúncio de verdade em 02/09/2026.

O que estes casos guardam, e cada um veio de uma pegadinha medida:
  * o host `www` redireciona para a home e devolve uma página SEM o anúncio,
    com status 200 -- erro silencioso, do tipo pior;
  * a OLX às vezes não manda campo nenhum, e ausente NÃO é zero;
  * bloqueio do Cloudflare tem que virar erro próprio, não "não achei o dado".

    .venv/bin/python teste_extrair_olx.py
"""
import html
import json
import sys

import extrair_olx as ex

falhas = 0


def checar(rotulo, condicao, detalhe=""):
    global falhas
    if condicao:
        print(f"  OK   {rotulo}")
    else:
        falhas += 1
        print(f"  FALHOU {rotulo} {detalhe}")


def montar_html(anuncio):
    bruto = json.dumps({"props": {"pageProps": {"ad": anuncio}}}, ensure_ascii=False)
    return ('<html><body><script id="initial-data" type="application/json" '
            f'data-json="{html.escape(bruto, quote=True)}"></script></body></html>')


ANUNCIO = {
    "listId": 1526572128,
    "subject": "Casa bem localizada no parque das laranjeiras.",
    "body": "Casa com 3 quartos sendo 1 suíte",
    "priceValue": "R$ 390.000",
    "priceLabel": "Preço",
    "location": {"neighbourhood": "Flores", "municipality": "Manaus",
                 "address": "Rua Barão de Indaiá", "zipcode": "69058448"},
    "properties": [{"name": "rooms", "value": "3"},
                   {"name": "bathrooms", "value": "3"},
                   {"name": "garage_spaces", "value": "2"}],
    "images": [{"original": "https://img.olx.com.br/images/48/481626791965796.jpg"},
               {"original": "https://img.olx.com.br/images/50/505613799054848.jpg"}],
}

print("--- o anúncio completo ---")
a = ex.extrair(montar_html(ANUNCIO))
checar("id do anúncio", a["olx_id"] == 1526572128)
checar("título", a["titulo"].startswith("Casa bem localizada"))
checar("preço vem como TEXTO, não convertido",
       a["preco_texto"] == "R$ 390.000",
       "converter aqui é que fez a fazenda de 12.000 hectares virar aluguel de R$ 1.500")
checar("bairro", a["bairro"] == "Flores")
checar("logradouro", a["logradouro"] == "Rua Barão de Indaiá")
checar("quartos", a["campos"]["rooms"] == "3")
checar("TODAS as fotos, não só a capa", len(a["fotos"]) == 2)
checar("a foto é a original", a["fotos"][0].endswith("481626791965796.jpg"))

print()
print("--- anúncio sem campo nenhum: ausente NÃO é zero ---")
magro = {"listId": 1, "subject": "Sem nada", "images": [], "properties": []}
b = ex.extrair(montar_html(magro))
checar("campos vazios, não zerados", b["campos"] == {})
checar("sem foto é lista vazia", b["fotos"] == [])
checar("bairro ausente é None, não string vazia", b["bairro"] is None,
       "zero e vazio já fizeram a Nay dizer que um apartamento não tinha vaga")

print()
print("--- a página errada (o `www` que redireciona para a home) ---")
try:
    ex.extrair("<html><body><h1>OLX</h1></body></html>")
    checar("página sem anúncio levanta erro", False)
except RuntimeError as erro:
    checar("página sem anúncio levanta erro", "initial-data" in str(erro))

print()
print("--- o host regional é obrigatório ---")
checar("www vira am",
       ex._regionalizar("https://www.olx.com.br/regiao-de-manaus/imoveis/x-1")
       == "https://am.olx.com.br/regiao-de-manaus/imoveis/x-1")
checar("am continua am",
       ex._regionalizar("https://am.olx.com.br/x-1") == "https://am.olx.com.br/x-1")

print()
print("--- bloqueio do Cloudflare vira erro próprio ---")


class RespostaFalsa:
    def __init__(self, status, texto):
        self.status_code, self.text = status, texto


try:
    ex.baixar_html("https://am.olx.com.br/x-1",
                   buscar=lambda u: RespostaFalsa(403, "Sorry, you have been blocked"))
    checar("403 vira OlxBloqueado", False)
except ex.OlxBloqueado as erro:
    checar("403 vira OlxBloqueado", "bloqueado" in str(erro).lower(),
           "confundir bloqueio com formato mudado manda consertar a coisa errada")

# O Cloudflare às vezes devolve 200 com a página de bloqueio dentro.
try:
    ex.baixar_html("https://am.olx.com.br/x-1",
                   buscar=lambda u: RespostaFalsa(200, "... Attention Required ..."))
    checar("200 com página de bloqueio também é bloqueio", False)
except ex.OlxBloqueado:
    checar("200 com página de bloqueio também é bloqueio", True)

print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
sys.exit(1 if falhas else 0)
