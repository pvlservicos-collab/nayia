#!/usr/bin/env python3
"""A FICHA DO ANÚNCIO: lê imobeasy.com/anuncios/<codigo> e guarda TUDO,
organizado, em `imovel_ficha` -- a base que a Nay consulta antes de responder
sobre um imóvel (29/09/2026).

POR QUE EXISTE. O Paulo perguntou do Living Comfort (5664) e a Nay disse "é
somente à vista". O anúncio diz "Aceita Financiamento? Sim". No banco dela o
5664 não tinha descrição, nem características, nem os campos do site: a tabela
`imoveis` vem da LISTAGEM (sincronizar_catalogo.py), que não traz nada disso, e
`preencher_do_anuncio.py` só completa algumas colunas vazias. Pedro: "precisamos
fazer com que ela leia toda ficha do imóvel quando tiver uma pergunta dessa,
tudo fique disponível de maneira arquitetada dentro do sistema, como um rag".

O QUE GUARDA, por código:
  * campos: todo par rótulo/valor da página, INCLUSIVE os que o site esconde em
    comentário HTML ("Aceita Financiamento?", "Incluso no Aluguel", "Garantia de
    Aluguel", "Permuta", "Valor de Aluguel"...). Chave normalizada: minúscula,
    sem acento, sem "?" -- a mesma forma das chaves de `imoveis.extras`.
  * as características do imóvel e as do condomínio, a descrição e as
    observações, cada uma no seu campo;
  * o CARD DOS GRUPOS, montado pelo mesmo `montar_mensagem` do publicador --
    é ele que a Nay manda desde a 191 (`nai_card_do_imovel`), para o card
    dela ser igual ao do grupo.

REGRAS DO PROJETO: nunca escreve em `imoveis`; pausa de 1,5 s entre
requisições; simulação por padrão, só grava com --escrever.

    python3 ficha_do_anuncio.py 5664 1360          # simula dois
    python3 ficha_do_anuncio.py --todos --escrever # todos os do site
"""
import argparse
import json
import sys
import time
import unicodedata

from bs4 import BeautifulSoup, Comment

import db
from buscar_imovel import (anuncio_encontrado, baixar_anuncio, extrair_imovel,
                           _complementar_do_banco, _chave_da_caracteristica)
from montar_mensagem import montar_mensagem

PAUSA = 1.5
# O envio privado ao corretor passa um grupo sem regra de piso: mostra venda E
# locação quando o imóvel tem as duas. É o mesmo dicionário do comando "manda
# o 5750 pro Sergio".
GRUPO_SEM_REGRA = {"aceita_venda": True, "aceita_locacao": True}


def chave(rotulo):
    t = unicodedata.normalize("NFD", str(rotulo or "")).lower()
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = t.replace("?", "").replace(":", "").strip()
    return " ".join(t.split())


def _pares(raiz):
    for label in raiz.find_all("label", class_="form-control-label"):
        span = label.find_next_sibling("span", class_="form-control")
        valor = span.get_text(" ", strip=True) if span else ""
        valor = " ".join(valor.split())
        if valor:
            yield chave(label.get_text(" ", strip=True)), valor


def _secao(soup, nome):
    """Os blocos de uma seção (título `slim-card-title` até o título seguinte)."""
    titulo = soup.find("div", class_="slim-card-title",
                       string=lambda s: s and _chave_da_caracteristica(s) == nome)
    if not titulo:
        return []
    blocos = []
    for irmao in titulo.find_next_siblings():
        if "slim-card-title" in (irmao.get("class") or []):
            break
        blocos.append(irmao)
    return blocos


def _lista(soup, nome):
    itens = []
    for bloco in _secao(soup, nome):
        for item in bloco.find_all("div", class_="col-md-4"):
            texto = " ".join(item.get_text(" ", strip=True).split())
            if texto and texto not in itens:
                itens.append(texto)
    return itens


def _texto(soup, nome):
    partes = []
    for bloco in _secao(soup, nome):
        for span in bloco.find_all("span", class_="form-control"):
            t = span.get_text("\n", strip=True)
            if t and t not in partes:
                partes.append(t)
    return "\n".join(partes) or None


def ler_ficha(codigo):
    html = baixar_anuncio(codigo)
    soup = BeautifulSoup(html, "html.parser")
    imovel = _complementar_do_banco(extrair_imovel(html, codigo))
    if not anuncio_encontrado(imovel):
        return None
    campos = {}
    # o visível primeiro; o comentado só completa o que a página não mostrou
    raizes = [soup] + [BeautifulSoup(str(c), "html.parser")
                       for c in soup.find_all(string=lambda t: isinstance(t, Comment))]
    for raiz in raizes:
        for k, v in _pares(raiz):
            campos.setdefault(k, v)
    return {
        "campos": campos,
        "caracteristicas_imovel": _lista(soup, "caracteristicas do imovel"),
        "caracteristicas_condominio": _lista(soup, "caracteristicas do condominio"),
        "descricao": _texto(soup, "descricao do anuncio"),
        "observacoes": _texto(soup, "observacoes"),
        "card": montar_mensagem(imovel, GRUPO_SEM_REGRA),
        "valor_venda": imovel.get("valor_venda"),
        "valor_aluguel": imovel.get("valor_aluguel"),
    }


GRAVAR = """
INSERT INTO imovel_ficha (codigo, encontrado, campos, caracteristicas_imovel, caracteristicas_condominio,
                          descricao, observacoes, card, valor_venda, valor_aluguel, lido_em, erro)
VALUES (%(codigo)s, %(encontrado)s, %(campos)s::jsonb, %(ci)s, %(cc)s, %(descricao)s, %(observacoes)s,
        %(card)s, %(valor_venda)s, %(valor_aluguel)s, now(), %(erro)s)
ON CONFLICT (codigo) DO UPDATE SET
  encontrado = EXCLUDED.encontrado,
  -- anúncio que falhou na leitura NÃO apaga a ficha boa de antes: só marca o erro
  campos = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.campos ELSE imovel_ficha.campos END,
  caracteristicas_imovel = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.caracteristicas_imovel ELSE imovel_ficha.caracteristicas_imovel END,
  caracteristicas_condominio = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.caracteristicas_condominio ELSE imovel_ficha.caracteristicas_condominio END,
  descricao = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.descricao ELSE imovel_ficha.descricao END,
  observacoes = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.observacoes ELSE imovel_ficha.observacoes END,
  card = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.card ELSE imovel_ficha.card END,
  valor_venda = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.valor_venda ELSE imovel_ficha.valor_venda END,
  valor_aluguel = CASE WHEN EXCLUDED.erro IS NULL THEN EXCLUDED.valor_aluguel ELSE imovel_ficha.valor_aluguel END,
  lido_em = CASE WHEN EXCLUDED.erro IS NULL THEN now() ELSE imovel_ficha.lido_em END,
  erro = EXCLUDED.erro,
  tentado_em = now()
"""


def codigos_do_site(conexao):
    with conexao.cursor() as cur:
        cur.execute("""
            SELECT codigo FROM imoveis
             WHERE NOT coalesce(e_parceiro, false)
               AND (coalesce(publicado_no_site, false)
                    OR nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site))
             ORDER BY codigo""")
        return [r["codigo"] for r in cur.fetchall()]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("codigos", nargs="*", type=int)
    ap.add_argument("--todos", action="store_true", help="todos os imóveis nossos do site")
    ap.add_argument("--escrever", action="store_true")
    ap.add_argument("--silencioso", action="store_true")
    a = ap.parse_args()

    conexao = db.conectar()
    conexao.autocommit = True
    codigos = codigos_do_site(conexao) if a.todos else a.codigos
    if not codigos:
        ap.error("diga os códigos ou --todos")

    lidos = nao_achados = erros = 0
    for n, codigo in enumerate(codigos):
        if n:
            time.sleep(PAUSA)
        erro = None
        try:
            f = ler_ficha(codigo)
        except Exception as e:           # um anúncio ruim não para a volta
            f, erro = None, f"{type(e).__name__}: {e}"[:300]
        if f is None and erro is None:
            nao_achados += 1
        elif erro:
            erros += 1
        else:
            lidos += 1
        if not a.silencioso or erro:
            if f:
                print(f"{codigo}: {len(f['campos'])} campos, {len(f['caracteristicas_imovel'])}+"
                      f"{len(f['caracteristicas_condominio'])} caract., financiamento="
                      f"{f['campos'].get('aceita financiamento')!r}")
            else:
                print(f"{codigo}: {'ERRO ' + erro if erro else 'anúncio não encontrado'}")
        if a.escrever:
            with conexao.cursor() as cur:
                cur.execute(GRAVAR, {
                    "codigo": codigo, "encontrado": f is not None or erro is not None,
                    "campos": json.dumps((f or {}).get("campos", {}), ensure_ascii=False),
                    "ci": (f or {}).get("caracteristicas_imovel", []),
                    "cc": (f or {}).get("caracteristicas_condominio", []),
                    "descricao": (f or {}).get("descricao"), "observacoes": (f or {}).get("observacoes"),
                    "card": (f or {}).get("card"),
                    "valor_venda": (f or {}).get("valor_venda"), "valor_aluguel": (f or {}).get("valor_aluguel"),
                    "erro": erro})
    if not a.silencioso or erros:
        print(f"-- {lidos} fichas lidas, {nao_achados} fora do site, {erros} erros"
              + ("" if a.escrever else " (simulação: nada gravado)"))
    return 1 if erros and not lidos else 0


if __name__ == "__main__":
    sys.exit(main())
