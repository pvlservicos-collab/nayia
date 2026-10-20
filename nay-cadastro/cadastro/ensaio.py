"""Ensaia uma leva sem gravar nem enviar nada: o que ela leria do texto, o condomínio que acharia e as perguntas.

Uso (servidor): .venv/bin/python -m cadastro.ensaio "texto do anúncio" ["resposta à 1ª pergunta" ...]
As respostas seguem as perguntas na ordem; o banco só é LIDO (condomínio, corretores), numa transação desfeita.
"""
from __future__ import annotations

import json
import sys

from cadastro import banco, campos, condominio, modelo
from cadastro import ficha as fichas
from cadastro import leva as levas


def main(args: list[str]) -> None:
    texto, respostas = args[0], args[1:]
    conn = banco.conectar(autocommit=False)
    try:
        saida = modelo.ler_leva(texto, 0)
        ficha = fichas.do_modelo(saida)
        fones = levas.fones_do_texto(texto)
        papel = "corretor" if fones and banco.uma(conn, banco.E_CORRETOR, (fones[0],))["sim"] else ficha.get("_papel")
        if ficha.get("condominio"):
            cands = banco.linhas(conn, banco.CONDOMINIO, (ficha["condominio"], ficha.get("bairro")))
            o_que, cond = condominio.escolher(cands)
            print(f"condomínio «{ficha['condominio']}»: {o_que}", cond and f"-> {cond['id']} {cond['nome']}")
            if o_que == "ligar":
                ficha = condominio.ligar(ficha, cond)
            elif o_que == "confirmar":
                ficha["_condo_candidato"] = {"id": cond["id"], "nome": cond["nome"], "bairro": cond.get("bairro")}
        print("é imóvel:", saida.get("e_imovel"), "| telefones:", fones, "| papel:", papel)
        print("ficha:", json.dumps(ficha, ensure_ascii=False))
        ctx = {"papel_conhecido": bool(papel)}
        print("perguntas:", campos.faltam(ficha, ctx))
        for resposta in respostas:
            falta = campos.faltam(ficha, ctx)
            if not falta:
                break
            chave = falta[0]
            pergunta = campos.POR_CHAVE[chave].texto(ficha)
            r = modelo.ler_resposta(pergunta, chave, resposta, ", ".join(campos.resumo_do_que_tem(ficha)))
            ficha = fichas.juntar(ficha, fichas.do_modelo(r))
            ficha["_feitas"] = [*(ficha.get("_feitas") or []), chave]
            print(f"\nNAY: {pergunta}\nELE: {resposta}\n  -> {json.dumps(fichas.do_modelo(r), ensure_ascii=False)}"
                  f" (respondeu={r['respondeu']}, nao_sabe={r['nao_sabe']}, fora={r['fora_do_assunto']})")
        print("\nfaltam:", campos.faltam(ficha, ctx), "| sem resposta:", campos.ficou_sem(ficha, ctx))
        print("corpo do site:", json.dumps(fichas.para_o_site(ficha), ensure_ascii=False))
    finally:
        conn.rollback()
        conn.close()


if __name__ == "__main__":
    main(sys.argv[1:])
