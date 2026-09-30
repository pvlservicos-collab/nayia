"""Preenche `tipo` e `area_util` do que está vazio, lendo o anúncio.

O CASO (09/09): o Tel pediu listas por categoria ("Nay lista de apartamento
para locação"). Ao medir, **17 dos 54 imóveis de locação estavam sem `tipo`**
-- quase um terço ficaria de fora de qualquer lista, calado. No catálogo
inteiro são 50 disponíveis sem tipo.

POR QUE FALTA: a varredura lê a LISTAGEM (`/anuncios?ad_type=...`), e o card da
listagem não traz o tipo. Ele está na página do ANÚNCIO, no `h5` do topo
("Apartamento / Condomínio Acquarelle"). Conferido em 09/09: o 2943, o 2014 e
o 887 estão vazios na tabela e dizem "Apartamento" na página.

POR QUE `area_util` PODE SER LIDA AQUI, se a varredura não escreve essa coluna:
o CLAUDE.md registra que a "Área" do card da LISTAGEM mistura área útil com
área de terreno -- por isso a varredura não a escreve. Na página do anúncio os
rótulos são separados e sem ambiguidade: "Área" (apartamento), "Área
Construída" e "Tamanho do Terreno" (casa). `buscar_imovel` já lê o certo. A
proibição era da fonte ruim, não do campo.

SÓ PREENCHE O QUE ESTÁ VAZIO. Nunca sobrescreve o que já existe: o cadastro
tem dono, e este script é remendo de fonte incompleta, não fonte de verdade.

E NÃO PERGUNTA DUAS VEZES A MESMA COISA (09/09, à tarde). Na primeira rodada
de verdade ele preencheu o tipo de 63 imóveis e a área de **um**: o anúncio dos
outros 62 diz, com todas as letras, `Área Construída: 0.0 m2` -- o cadastro
está vazio na origem. Como a busca era "área igual a zero", os mesmos 62
seriam pedidos ao site DE NOVO a cada hora, para sempre: ~1.500 requisições
por dia que nunca trariam nada, contra a regra do projeto de não martelar o
site. Agora "o anúncio não tem esse dado" fica gravado em
`extras -> 'area_no_anuncio'` e o imóvel sai da fila. Quando alguém preencher
a área no admin, a varredura das :17 escreve o valor e o marcador deixa de
importar -- ele só governa a fila deste script.

    .venv/bin/python varrer_tipos.py             # só mostra
    .venv/bin/python varrer_tipos.py --escrever  # grava
    .venv/bin/python varrer_tipos.py --limite 5  # testa com poucos
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

# Falha acima disso é site fora do ar ou mudança de layout, não imóvel sem
# tipo. Continuar pedindo só empilha erro -- mesma regra do `varrer_fotos`.
MAX_FALHAS_SEGUIDAS = 5


def sem_tipo(conexao, limite=None):
    """Os disponíveis, publicados, sem tipo OU sem área -- **menos** os que já
    responderam que o anúncio não tem o dado.

    `publicado_no_site` é exigência: sem anúncio no ar não há página para ler,
    e pedir daria a página de "não encontrado" em cada um.

    O `area_no_anuncio = 'ausente'` é o que impede a fila de ser eterna: sem
    ele, imóvel cujo anúncio diz `Área Construída: 0.0 m2` volta para a fila
    toda hora. Note que ele só vale enquanto a área continuar vazia -- o
    `coalesce(area_util,0) = 0` vem antes na conjunção.
    """
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT codigo FROM imoveis"
            " WHERE coalesce(disponivel, true)"
            "   AND coalesce(publicado_no_site, false)"
            "   AND (coalesce(tipo,'') = ''"
            "        OR (coalesce(area_util,0) = 0"
            "            AND coalesce(extras->>'area_no_anuncio','') <> 'ausente'))"
            " ORDER BY codigo" + (" LIMIT %s" if limite else ""),
            (limite,) if limite else None)
        return [linha["codigo"] for linha in cur.fetchall()]


def gravar(conexao, codigo, tipo, area):
    """`coalesce` NO SQL, não no Python: entre ler e gravar alguém pode ter
    preenchido no admin, e a varredura das :17 roda no meio. Deixar o banco
    decidir fecha a janela.

    Área que o anúncio não trouxe vira MARCADOR, não linha repetida na fila.
    O marcador entra por `||` sobre o `extras` que já existe -- lá dentro moram
    "aceita financiamento", "aceita permuta" e "incluso no aluguel".
    """
    marcar_ausente = not area
    with conexao.cursor() as cur:
        cur.execute(
            "UPDATE imoveis"
            "   SET tipo = coalesce(NULLIF(tipo,''), %s),"
            "       area_util = CASE WHEN coalesce(area_util,0) = 0"
            "                        THEN %s ELSE area_util END,"
            "       extras = CASE WHEN %s"
            "                     THEN coalesce(extras,'{}'::jsonb)"
            "                          || jsonb_build_object('area_no_anuncio','ausente')"
            "                     ELSE extras END,"
            "       sincronizado_em = now()"
            " WHERE codigo = %s",
            (tipo or None, area or None, marcar_ausente, codigo))
    conexao.commit()


def varrer(conexao, escrever=False, limite=None, pausa=time.sleep, log=print):
    codigos = sem_tipo(conexao, limite)
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
            resultados.append((codigo, None, None, f"erro: {erro}"))
            if falhas_seguidas >= MAX_FALHAS_SEGUIDAS:
                log(f"ABORTADO: {falhas_seguidas} falhas seguidas.")
                break
            continue

        falhas_seguidas = 0
        tipo = (imovel or {}).get("tipo")
        area = (imovel or {}).get("area")
        if not tipo and not area:
            # A PÁGINA RESPONDEU, e a resposta é "não tenho". Marcar também
            # aqui: sem isso este é o caso que volta para a fila toda hora,
            # que é exatamente o que se está consertando.
            if escrever:
                gravar(conexao, codigo, None, None)
            resultados.append((codigo, None, None,
                               "o anuncio nao diz" if escrever
                               else "o anuncio nao diz (simulado)"))
            continue

        if escrever:
            gravar(conexao, codigo, tipo, area)
            resultados.append((codigo, tipo, area, "gravado"))
        else:
            resultados.append((codigo, tipo, area, "simulado"))

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

    gravados = [r for r in resultados if r[3] == "gravado"]
    if args.silencioso and not gravados:
        return 0
    if not resultados:
        if not args.silencioso:
            print("nenhum imóvel sem tipo nem área. Nada a fazer.")
        return 0

    for codigo, tipo, area, estado in resultados:
        print(f"[{estado}] {codigo}: {tipo or '-'} / {area or '-'}m2")
    if not args.escrever:
        print("\n(simulação -- rode com --escrever para gravar)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
