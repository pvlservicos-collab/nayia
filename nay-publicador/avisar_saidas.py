#!/usr/bin/env python3
"""Avisa no grupo Easy os imóveis que saíram do mercado, venham por onde vierem.

POR QUE EXISTE (Tel, 28/09): ele mandou `alugado 5737` pelo número da Imob
Easy, a Nay respondeu "Tirei do ar (alugado): 5737 — Amazonas Flat" e **não
avisou no grupo IMÓVEIS PARA ANUNCIAR EASY**. Os corretores que pegaram aquele
anúncio para divulgar continuam divulgando um imóvel que não existe mais.

A CAUSA: existem dois caminhos para "o imóvel saiu", e só um avisava.

  publicador (`_liberar_vaga`)    tira das vagas, marca indisponível, cancela
                                  lembretes e entregas, E AVISA NO EASY
  NAI (`nai_comando_tel`, 22/09)  marca indisponível e sabe DESFAZER
                                  (`DISPONIVEL 5737`) -- mas não fala com grupo

`alugado 5737` casa `nai_e_comando_imovel`, então fica na NAI -- e o aviso,
que mora só do outro lado, nunca acontecia.

ESTE CRON FECHA OS DOIS: o gatilho do banco (`aviso_de_saida.sql`) enfileira
quando `disponivel` vai para false, por QUALQUER caminho -- inclusive um
UPDATE feito à mão no psql. Aqui só se lê a fila e se manda.

O TEXTO É O MESMO do comando na mão (`_avisar_easy_que_saiu`), chamado de lá.
Duas redações do mesmo aviso divergiriam na primeira edição.

    .venv/bin/python avisar_saidas.py            # simula
    .venv/bin/python avisar_saidas.py --enviar
"""
import argparse

import db
from publicador import _avisar_easy_que_saiu


def saidas_a_avisar(conn, horas=6):
    with conn.cursor() as cur:
        cur.execute("SELECT codigo, motivo FROM nay_saidas_a_avisar(%s)", (horas,))
        return cur.fetchall()


def avisar(conexao=None, enviar=False, horas=6, avisar_um=None):
    """Manda o aviso de cada saída pendente. Devolve o que fez."""
    avisar_um = avisar_um or _avisar_easy_que_saiu
    fechar = conexao is None
    conn = conexao or db.conectar()
    feitos = []
    try:
        for linha in saidas_a_avisar(conn, horas):
            codigo, motivo = linha["codigo"], linha["motivo"]
            if not enviar:
                feitos.append((codigo, motivo, "(simulação)"))
                continue

            # RESERVA ANTES DE MANDAR, mesma lição do `postar_easy`: entre
            # "vi que devia" e "avisei" cabe outra rodada do cron -- ele roda
            # de minuto em minuto -- e o grupo receberia duas vezes.
            with conn.cursor() as cur:
                cur.execute("SELECT nay_reservar_aviso_de_saida(%s) AS ok", (codigo,))
                reservou = (cur.fetchone() or {}).get("ok")
            conn.commit()
            if not reservou:
                continue

            try:
                resposta = _avisar_easy_que_saiu(codigo, conn, motivo) \
                    if avisar_um is _avisar_easy_que_saiu else avisar_um(codigo, conn, motivo)
            except Exception as exc:
                resposta = f"erro: {exc}"

            # DEVOLVE À FILA SÓ QUANDO NADA SAIU. Se parte foi para o grupo,
            # devolver faria o aviso sair duas vezes -- e grupo não desfaz.
            if str(resposta).startswith("NÃO consegui") or str(resposta).startswith("erro:"):
                with conn.cursor() as cur:
                    cur.execute("SELECT nay_devolver_aviso_de_saida(%s, %s)",
                                (codigo, str(resposta)[:200]))
                conn.commit()
            feitos.append((codigo, motivo, resposta))
        return feitos
    finally:
        if fechar:
            conn.close()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--enviar", action="store_true",
                   help="manda de verdade. Sem isto, só mostra o que faria.")
    p.add_argument("--horas", type=int, default=6,
                   help="quanto para trás olhar (padrão 6)")
    args = p.parse_args()
    for codigo, motivo, resposta in avisar(enviar=args.enviar, horas=args.horas):
        print(f"  {codigo} ({motivo}): {resposta}")
