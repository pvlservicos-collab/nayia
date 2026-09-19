"""
Preenche `imovel_fotos` do que está faltando, lendo o anúncio no site.

O CASO (01/09, 15h27): a Regiane colou o card do 2014 (Rio Amazonas
Residencial) e perguntou "Tem imagens?". A Nay respondeu "desse imóvel
não temos imagens cadastradas no momento" -- e as imagens existem: o
disparo daquele card no grupo saiu COM fotos.

POR QUE A RESPOSTA DIVERGIU DA REALIDADE: são duas fontes.
  * o publicador lê o anúncio AO VIVO (`buscar_imovel.py`) e por isso
    manda as fotos que estão lá agora;
  * a Nay, no n8n, lê a tabela `imovel_fotos` -- e o 2014 tem ZERO linhas
    nela.
Medido em 01/09: dos 300 imóveis nossos e disponíveis, 270 têm foto na
tabela e **30 não têm nenhuma**. Para esses 30 ela diz "não temos
imagens" com toda a convicção.

POR QUE UM VARREDOR SÓ PARA O QUE FALTA: a foto vem da página do anúncio
individual, uma requisição por imóvel. Varrer os 300 de hora em hora
seria martelar o site sem motivo -- 90% já está lá. Este script pede só
o que falta, então hoje são 30 páginas e amanhã serão as dos imóveis
novos. Fica silencioso quando não falta nada.

NUNCA APAGA. Imóvel que perdeu as fotos no site mantém as que já tinha:
apagar deixaria a Nay sem nada para mandar, que é pior que uma foto
antiga. O que muda é acrescentar.

    .venv/bin/python varrer_fotos.py             # só mostra
    .venv/bin/python varrer_fotos.py --escrever  # grava
    .venv/bin/python varrer_fotos.py --limite 5  # testa com poucos
"""
import argparse
import random
import sys
import time

import requests

import db
from buscar_imovel import buscar_imovel

PAUSA_MIN = 1.0
PAUSA_MAX = 2.0

# Falha acima disso é site fora do ar ou mudança de layout, não imóvel
# sem foto. Continuar pedindo só empilha erro.
MAX_FALHAS_SEGUIDAS = 5


def sem_fotos(conexao, limite=None):
    """Os nossos, disponíveis, publicados e sem NENHUMA foto na tabela.

    `publicado_no_site` é exigência, não detalhe: sem anúncio no ar não há
    página para ler, e pedir daria 404 em cada um.
    """
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT i.codigo FROM imoveis i "
            " WHERE coalesce(i.disponivel, true) "
            "   AND NOT coalesce(i.e_parceiro, false) "
            "   AND coalesce(i.publicado_no_site, false) "
            "   AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo) "
            " ORDER BY i.codigo" + (" LIMIT %s" if limite else ""),
            (limite,) if limite else None)
        return [linha["codigo"] for linha in cur.fetchall()]


def gravar(conexao, codigo, urls):
    """A primeira é a capa -- `buscar_imovel` já devolve na ordem certa,
    com a do `og:image` na frente."""
    with conexao.cursor() as cur:
        for ordem, url in enumerate(urls, start=1):
            cur.execute(
                "INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) "
                "VALUES (%s, %s, %s, %s)",
                (codigo, ordem, url, ordem == 1))
    conexao.commit()


def varrer(conexao, escrever=False, limite=None, pausa=time.sleep, log=print):
    codigos = sem_fotos(conexao, limite)
    if not codigos:
        return []

    resultados = []
    falhas_seguidas = 0
    for i, codigo in enumerate(codigos):
        if i:
            pausa(random.uniform(PAUSA_MIN, PAUSA_MAX))
        try:
            imovel = buscar_imovel(str(codigo))
        except requests.RequestException as erro:
            falhas_seguidas += 1
            resultados.append((codigo, 0, f"erro: {erro}"))
            if falhas_seguidas >= MAX_FALHAS_SEGUIDAS:
                log(f"ABORTADO: {falhas_seguidas} falhas seguidas.")
                break
            continue

        falhas_seguidas = 0
        urls = [u for u in ((imovel or {}).get("fotos") or []) if u]
        if not urls:
            # O anúncio existe e não tem foto: aí "não temos imagens" é
            # verdade, e não há nada a fazer.
            resultados.append((codigo, 0, "o anuncio nao tem foto"))
            continue

        if escrever:
            gravar(conexao, codigo, urls)
            resultados.append((codigo, len(urls), "gravado"))
        else:
            resultados.append((codigo, len(urls), "simulado"))

    return resultados


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--escrever", action="store_true")
    p.add_argument("--limite", type=int, default=None)
    p.add_argument("--silencioso", action="store_true",
                   help="só fala quando gravou algo (para o cron)")
    args = p.parse_args()

    conexao = db.conectar()
    try:
        resultados = varrer(conexao, escrever=args.escrever, limite=args.limite,
                            log=(lambda *a: None) if args.silencioso else print)
    finally:
        conexao.close()

    gravados = [r for r in resultados if r[2] == "gravado"]
    if args.silencioso and not gravados:
        return 0
    if not resultados:
        if not args.silencioso:
            print("nenhum imóvel sem foto. Nada a fazer.")
        return 0

    for codigo, n, estado in resultados:
        print(f"[{estado}] {codigo}: {n} foto(s)")
    if not args.escrever:
        print("\n(simulação -- rode com --escrever para gravar)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
