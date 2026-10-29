"""28/10/2026 (511, Tel: "não conseguimos ver a mensagem que foi no grupo"): os pedidos de busca que já foram aos grupos
não guardavam o texto (desde agora guardam, buscas.grupos_volta). Este preenche os antigos com mensagem_de_grupo dos
filtros da busca (os de hoje; quem mudou o perfil depois do post vê o pedido de agora). Roda UMA vez, à mão:

    cd /root/nay-olx && set -a && . ./.env && set +a && .venv/bin/python texto_dos_pedidos_2810.py [--ensaio]
"""
import argparse
import json

from olx import banco, buscas


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ensaio", action="store_true")
    a = ap.parse_args()
    conn = banco.conectar()
    n = 0
    for b in banco.linhas(conn, "SELECT id, filtros, grupos FROM privado.busca_cliente WHERE grupos <> '[]'::jsonb"):
        itens = list(b["grupos"] or [])
        faltam = [x for x in itens if x.get("mid") and not x.get("texto")]
        if not faltam:
            continue
        texto = buscas.mensagem_de_grupo(b["filtros"] or {})
        for x in faltam:
            x["texto"] = texto
        n += len(faltam)
        print(f"busca {b['id']}: {len(faltam)} pedido(s)")
        if not a.ensaio:
            banco.um(conn, "UPDATE privado.busca_cliente SET grupos = %s::jsonb WHERE id = %s",
                     (json.dumps(itens, ensure_ascii=False), b["id"]))
    if a.ensaio:
        conn.rollback()
    else:
        conn.commit()
    print(f"{n} pedido(s) com o texto{' (ensaio: nada gravado)' if a.ensaio else ''}")


if __name__ == "__main__":
    main()
