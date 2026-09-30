#!/usr/bin/env python3
"""Preenche na tabela o "Incluso no Aluguel" e os "Lances de Escada" do anúncio.

POR QUE EXISTE (Tel, 14/09): ele disparou o 5718 e o card saiu sem
"(incluso a tx)". Eu respondi que o dado não existia. Estava errado -- o
anúncio traz o campo, só que o site envolve a seção em `<!-- ... -->` e o
extrator não entrava ali (ver `teste_campo_comentado.py`).

O CARD já foi consertado e lê da página ao vivo. Este script é para a TABELA,
porque quem lê dela é outra coisa: a LISTA (`nay_linha_da_lista`), que é o que
ele cola no WhatsApp, e as buscas da Nay. Sem preencher, a lista continua
dizendo que o 5718 não tem taxa inclusa enquanto o card diz que tem -- duas
respostas diferentes para a mesma pergunta.

POR QUE A VARREDURA NÃO RESOLVE: ela lê a LISTAGEM (12 anúncios por página),
que não traz nenhum destes dois campos. Eles só existem na página do anúncio
individual, uma requisição por imóvel.

REGRAS DO PROJETO, seguidas aqui:
  * COMPLEMENTAR: só escreve onde está vazio. Nunca sobrescreve, nunca apaga
    -- e é isso que preserva o que o Tel marcou à mão pelo comando
    `NNNN incluso a tx` (o 5729 é assim: o site não diz e ele marcou).
  * Simulação por padrão. Só grava com `--escrever`.
  * Pausa entre requisições. Não martelar o site.
  * `sincronizado_em = now()` no que for tocado.

    .venv/bin/python preencher_taxa_e_escada.py            # simula, locação
    .venv/bin/python preencher_taxa_e_escada.py --escrever
    .venv/bin/python preencher_taxa_e_escada.py --todos    # o catálogo inteiro
    .venv/bin/python preencher_taxa_e_escada.py --codigo 5718
"""
import argparse
import time

import db
from buscar_imovel import buscar_imovel

PAUSA = 1.5


def alvos(conn, todos=False, codigo=None):
    """Os imóveis a olhar, do mais novo para o mais velho.

    Por padrão só a LOCAÇÃO no mercado: é dela que o Tel reclamou, são 85
    requisições em vez de 1.231, e o "incluso no aluguel" não tem sentido em
    imóvel que só se vende.
    """
    with conn.cursor() as cur:
        if codigo:
            cur.execute("SELECT codigo::text AS codigo FROM imoveis "
                        " WHERE codigo::text = %s", (str(codigo),))
        elif todos:
            cur.execute("SELECT codigo::text AS codigo FROM imoveis "
                        " ORDER BY codigo DESC")
        else:
            cur.execute(
                "SELECT codigo::text AS codigo FROM imoveis "
                " WHERE coalesce(valor_aluguel,0) > 0 "
                "   AND nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) "
                " ORDER BY codigo DESC")
        return [l["codigo"] for l in cur.fetchall()]


def _o_que_falta(conn, codigo):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT extras->>'incluso no aluguel' AS incluso, "
            "       extras->>'lances de escada'   AS escada "
            "  FROM imoveis WHERE codigo::text = %s", (codigo,))
        return cur.fetchone()


def preencher(conexao=None, escrever=False, todos=False, codigo=None,
              pausa=PAUSA, buscar=None, ao_vivo=True):
    buscar = buscar or buscar_imovel
    fechar = conexao is None
    conn = conexao or db.conectar()
    mudancas = []
    try:
        for i, cod in enumerate(alvos(conn, todos, codigo)):
            atual = _o_que_falta(conn, cod) or {}
            # NÃO BAIXA O QUE JÁ TEM. Sem esta guarda seriam 85 requisições
            # para escrever em 50 -- e a pausa de 1,5s faz cada uma custar.
            if atual.get("incluso") and atual.get("escada"):
                continue
            if i and pausa and ao_vivo:
                time.sleep(pausa)
            try:
                imovel = buscar(cod)
            except Exception as exc:
                mudancas.append({"codigo": cod, "erro": str(exc)[:80]})
                continue
            # Página que não abre ou anúncio fora do ar devolve dict vazio --
            # e dict vazio é TRUTHY, que é a armadilha já registrada. Sem o
            # `tipo`, não se aprendeu nada com esta página.
            if not imovel or not imovel.get("tipo"):
                continue

            campos = {}
            if not atual.get("incluso") and imovel.get("incluso_no_aluguel"):
                campos["incluso no aluguel"] = imovel["incluso_no_aluguel"]
            if not atual.get("escada") and imovel.get("lances_de_escada"):
                campos["lances de escada"] = imovel["lances_de_escada"]
            if not campos:
                continue

            mudancas.append({"codigo": cod, **campos})
            if escrever:
                _gravar(conn, cod, campos)
        return mudancas
    finally:
        if fechar:
            conn.close()


def _gravar(conn, codigo, campos):
    """COMPLEMENTA o `extras`, nunca o substitui.

    `extras || jsonb` funde as chaves: o que já estava lá continua. Trocar o
    objeto inteiro apagaria "aceita permuta", "aceita financiamento" e o resto
    que a importação de agosto deixou -- e a regra 1 do projeto é não apagar.
    """
    import json
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE imoveis "
            "   SET extras = coalesce(extras,'{}'::jsonb) || %s::jsonb, "
            "       sincronizado_em = now() "
            " WHERE codigo::text = %s",
            (json.dumps(campos, ensure_ascii=False), str(codigo)))
    conn.commit()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--escrever", action="store_true",
                   help="grava de verdade. Sem isto, só mostra o que faria.")
    p.add_argument("--todos", action="store_true",
                   help="o catálogo inteiro, não só a locação no mercado.")
    p.add_argument("--codigo")
    args = p.parse_args()

    feitas = preencher(escrever=args.escrever, todos=args.todos,
                       codigo=args.codigo)
    for m in feitas:
        if m.get("erro"):
            print(f"  {m['codigo']}: ERRO {m['erro']}")
            continue
        partes = []
        if "incluso no aluguel" in m:
            partes.append(f"incluso={m['incluso no aluguel']!r}")
        if "lances de escada" in m:
            partes.append(f"escada={m['lances de escada']!r}")
        print(f"  {m['codigo']}: " + "  ".join(partes))
    total = len([m for m in feitas if not m.get("erro")])
    if args.escrever:
        print(f"\n{total} imóveis atualizados.")
    else:
        print(f"\n(simulação -- {total} imóveis seriam atualizados. "
              "use --escrever)")
