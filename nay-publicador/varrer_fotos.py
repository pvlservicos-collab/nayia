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
from buscar_imovel import buscar_imovel, anuncio_encontrado, buscar_no_site

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


LIMITE_DE_CONFERENCIA = 40


def a_conferir(conexao, limite=LIMITE_DE_CONFERENCIA):
    """Os do mercado cujas fotos foram conferidas há mais tempo.

    O CASO (Tel, 28/09): "Código: 964, na hora de disparar ainda está com as
    fotos antigas". O site tinha 4 fotos de 25/09 e a tabela guardava 5, de uma
    carga bem mais velha.

    A CAUSA: `sem_fotos` só olha quem tem ZERO foto. Uma vez que o imóvel
    ganha qualquer foto, nunca mais é visitado -- trocar as fotos no admin não
    chegava ao banco. É o MESMO padrão da mobília e dos lances de escada,
    achados hoje: preenchedor que só preenche vazio e nunca atualiza.

    RODÍZIO, não varredura: reler os ~836 anúncios a cada hora seria martelar
    o site (regra 5). Cada rodada pega os mais antigos, e o catálogo converge
    em algumas horas sem pico. NULO PRIMEIRO -- quem nunca foi conferido é
    quem mais provavelmente está desatualizado.
    """
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT i.codigo FROM imoveis i "
            " WHERE coalesce(i.disponivel, true) "
            "   AND NOT coalesce(i.e_parceiro, false) "
            "   AND coalesce(i.publicado_no_site, false) "
            " ORDER BY i.fotos_conferidas_em NULLS FIRST, i.codigo "
            " LIMIT %s", (limite,))
        return [linha["codigo"] for linha in cur.fetchall()]


def _fotos_do_banco(conexao, codigo):
    with conexao.cursor() as cur:
        cur.execute("SELECT url FROM imovel_fotos WHERE codigo = %s ORDER BY ordem",
                    (codigo,))
        return [l["url"] for l in cur.fetchall()]


def trocar(conexao, codigo, urls):
    """Troca as fotos do imóvel pelas do site, numa transação só.

    APAGA E REGRAVA de propósito: a ordem importa (a primeira é a capa) e
    uma troca parcial deixaria o card com metade das fotos novas e metade
    das velhas -- pior que qualquer um dos dois estados.

    A regra 1 do projeto ("nunca apagar linha de `imoveis`") é sobre o
    CADASTRO. `imovel_fotos` é um retrato do anúncio, e um retrato velho não
    tem valor nenhum -- foi o que mandou as fotos antigas do 964.
    """
    with conexao.cursor() as cur:
        cur.execute("DELETE FROM imovel_fotos WHERE codigo = %s", (codigo,))
        for ordem, url in enumerate(urls, start=1):
            cur.execute(
                "INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) "
                "VALUES (%s, %s, %s, %s)", (codigo, ordem, url, ordem == 1))
    conexao.commit()


def _carimbar(conexao, codigo):
    with conexao.cursor() as cur:
        cur.execute("UPDATE imoveis SET fotos_conferidas_em = now() "
                    " WHERE codigo = %s", (codigo,))
    conexao.commit()


def conferir(conexao, escrever=False, limite=LIMITE_DE_CONFERENCIA,
             pausa=time.sleep, log=print, buscar=None):
    """Relê as fotos no site e troca as que mudaram. Devolve o que mudou.

    CARIMBA MESMO QUANDO NÃO MUDA: sem isso o rodízio voltaria sempre aos
    mesmos e o resto do catálogo nunca seria conferido.

    ANÚNCIO SEM FOTO NÃO APAGA AS QUE TEMOS: página que não abriu, ou que o
    site serviu pela metade, devolveria lista vazia -- e o imóvel ficaria sem
    foto nenhuma no disparo. É a armadilha do dict truthy, de novo.
    """
    # O SITE, E SÓ O SITE. O trabalho desta função é "as fotos do site são a
    # verdade, troque as nossas". Com `buscar_imovel` a comparação daria sempre
    # igual, ela carimbaria `fotos_conferidas_em` e declararia conferido sem ter
    # olhado nada -- um vigia que vira carimbo. Ver `buscar_no_site`.
    buscar = buscar or buscar_no_site
    trocados = []
    falhas_seguidas = 0
    for i, codigo in enumerate(a_conferir(conexao, limite)):
        if i:
            pausa(random.uniform(PAUSA_MIN, PAUSA_MAX))
        try:
            imovel = buscar(str(codigo))
        except Exception as erro:
            falhas_seguidas += 1
            if falhas_seguidas >= MAX_FALHAS_SEGUIDAS:
                log(f"ABORTADO: {falhas_seguidas} falhas seguidas.")
                break
            continue
        falhas_seguidas = 0

        urls = [u for u in ((imovel or {}).get("fotos") or []) if u]
        if not urls:
            continue                      # não apaga o que temos
        if urls == _fotos_do_banco(conexao, codigo):
            if escrever:
                _carimbar(conexao, codigo)
            continue

        trocados.append((codigo, len(urls)))
        if escrever:
            trocar(conexao, codigo, urls)
            _carimbar(conexao, codigo)
    return trocados


def _despublicar(conexao, codigo):
    """Tira o imóvel da oferta porque o anúncio não está mais no ar.

    SÓ `publicado_no_site`, nunca `disponivel`: o imóvel pode seguir à venda
    sem anúncio publicado, e marcar indisponível aqui inventaria um fato que
    ninguém disse. É a regra 2 do projeto, escrita no CLAUDE.md desde o
    começo.
    """
    with conexao.cursor() as cur:
        cur.execute("UPDATE imoveis SET publicado_no_site = false, "
                    "       sincronizado_em = now() "
                    " WHERE codigo = %s AND coalesce(publicado_no_site, false)",
                    (codigo,))
    conexao.commit()


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
        # PÁGINA MORTA NÃO É "SEM FOTO" (Tel, 29/09). O 2133 (Life Ponta
        # Negra) foi oferecido a uma corretora, o card saiu da TABELA e as
        # fotos nunca foram -- não existia nenhuma. O anúncio dele redireciona
        # para `nao-encontrado`: veio da planilha do site antigo (importação de
        # 26/09), apareceu na LISTAGEM, e a varredura o marcou publicado.
        #
        # A PÁGINA DO ANÚNCIO É A AUTORIDADE sobre estar no ar; a listagem pode
        # trazer card velho. Aqui já se pagou a requisição, então a resposta
        # vale: despublica.
        #
        # Isto NÃO fere a regra 2 -- ela diz que sumir do site vira
        # `publicado_no_site = false` e NUNCA indisponível. É exatamente o que
        # se faz. E é por imóvel, com prova; nada a ver com a despublicação em
        # massa que a varredura só permite em passagem completa.
        if not anuncio_encontrado(imovel):
            resultados.append((codigo, 0, "anuncio fora do ar -- despubliquei"))
            if escrever:
                _despublicar(conexao, codigo)
            continue

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
    p.add_argument("--conferir", type=int, default=LIMITE_DE_CONFERENCIA,
                   help="quantos imóveis JÁ COM foto reconferir por rodada")
    p.add_argument("--silencioso", action="store_true",
                   help="só fala quando gravou algo (para o cron)")
    args = p.parse_args()

    conexao = db.conectar()
    try:
        log = (lambda *a: None) if args.silencioso else print
        resultados = varrer(conexao, escrever=args.escrever, limite=args.limite,
                            log=log)
        # A CONFERÊNCIA DAS QUE JÁ EXISTEM roda depois, no mesmo comando: o
        # `varrer` cuida de quem não tem foto nenhuma, e este de quem tem
        # foto VELHA -- o caso do 964. São dois problemas diferentes com a
        # mesma cura, e separá-los em dois crons seria dois lugares para
        # lembrar de olhar.
        trocados = conferir(conexao, escrever=args.escrever,
                            limite=args.conferir, log=log)
        for codigo, quantas in trocados:
            print(f"  {codigo}: fotos trocadas ({quantas} do site)")
    finally:
        conexao.close()

    gravados = [r for r in resultados if r[2] == "gravado"]
    if args.silencioso and not gravados and not trocados:
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
