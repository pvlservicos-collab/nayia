"""
Refaz a lista de corretores que a NAI pode atender, a partir dos grupos.

PEDIDO DO TEL (18/09/2026): "pega todos os contatos dos grupos que eu estou e
salva como corretores ... voce so vai responder essas pessoas ... e ela vai
atualizar semanalmente os contatos dos grupos como sendo os unicos contatos
que ela tem permissao para falar."

O QUE FAZ: le da Z-API os grupos do numero da Nay (o mesmo que o publicador usa
para postar) e os participantes de cada um, e entrega tudo a
`nai_sincronizar_grupos()` no banco. Quem decide quem entra, quem sai e quais
grupos contam e o banco (`nai_grupo_corretor.incluir`) -- este script so le.

Cada participante vem com TELEFONE e LID. Os dois vao para o banco: a mensagem
que o corretor manda as vezes chega so com o LID, e sem o par gravado ela nao
casaria com ninguem (foi exatamente o que deixou 216 mensagens do Tel orfas na
captacao, em 17/09).

A TRAVA QUE IMPORTA -- LEITURA PELA METADE NAO TIRA NINGUEM DA LISTA:
  * se QUALQUER grupo falhou na leitura, a sincronizacao so ADICIONA;
  * se a lista nova ficou com menos da metade de quem podia falar antes,
    idem -- isso e mais provavel ser a Z-API devolvendo pouco do que metade
    dos corretores terem saido dos grupos numa semana.
Uma lista que cresce errado e inofensiva; uma que encolhe errado cala a Nay.

Simulacao por padrao, como tudo no projeto. So grava com --escrever.

Uso:
    python sincronizar_grupos_corretores.py              # so mostra
    python sincronizar_grupos_corretores.py --escrever   # grava
"""
import argparse
import json
import os
import sys
import time

import requests

from db import conectar

PAUSA_ENTRE_GRUPOS = 1.2  # regra do projeto: nao martelar a API
FRACAO_MINIMA = 0.5       # abaixo disso de quem podia falar, nao revoga


def env(nome):
    valor = os.environ.get(nome)
    if not valor:
        raise RuntimeError(f"{nome} nao configurada no ambiente (.env).")
    return valor


def zapi(caminho):
    base = (f"https://api.z-api.io/instances/{env('ZAPI_INSTANCIA')}"
            f"/token/{env('ZAPI_TOKEN')}")
    r = requests.get(base + caminho,
                     headers={"Client-Token": env("ZAPI_CLIENT_TOKEN")},
                     timeout=30)
    r.raise_for_status()
    return r.json()


def ler_grupos():
    """Todos os grupos do numero, paginando ate a pagina vir vazia."""
    grupos, pagina = [], 1
    while True:
        lote = zapi(f"/groups?page={pagina}&pageSize=100")
        if not isinstance(lote, list):
            raise RuntimeError(f"resposta inesperada em /groups: {str(lote)[:200]}")
        if not lote:
            return grupos
        grupos.extend(lote)
        if len(lote) < 100:
            return grupos
        pagina += 1


def ler_membros(grupo_id):
    meta = zapi(f"/group-metadata/{grupo_id}")
    if not isinstance(meta, dict) or "participants" not in meta:
        raise RuntimeError(f"sem participantes: {str(meta)[:200]}")
    return [{"phone": str(p.get("phone") or ""),
             "lid": str(p.get("lid") or "").replace("@lid", "")}
            for p in meta["participants"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--escrever", action="store_true",
                    help="grava no banco (sem isto, so mostra)")
    args = ap.parse_args()

    status = zapi("/status")
    if not status.get("connected"):
        # Nada a fazer com o numero fora do ar -- e nada a revogar tambem.
        print(f"Z-API desconectada, nada sincronizado: {status}", file=sys.stderr)
        return 2

    grupos = ler_grupos()
    pacote, falhas = [], []
    for g in grupos:
        gid, nome = g.get("phone"), g.get("name") or ""
        if not gid:
            continue
        try:
            membros = ler_membros(gid)
            pacote.append({"grupo_id": gid, "nome": nome, "membros": membros})
        except Exception as e:  # um grupo ruim nao derruba os outros
            falhas.append(f"{nome} ({gid}): {e}")
        time.sleep(PAUSA_ENTRE_GRUPOS)

    conn = conectar()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) AS n FROM corretores WHERE pode_falar AND ativo")
            antes = cur.fetchone()["n"]
            cur.execute("SELECT grupo_id FROM nai_grupo_corretor WHERE NOT incluir")
            fora = {r["grupo_id"] for r in cur.fetchall()}

        unicos = {m["phone"] for g in pacote if g["grupo_id"] not in fora
                  for m in g["membros"] if m["phone"]}

        revogar = not falhas
        motivo = ""
        if falhas:
            motivo = f"{len(falhas)} grupo(s) nao foram lidos"
        elif antes and len(unicos) < antes * FRACAO_MINIMA:
            revogar, motivo = False, (f"a lista nova ({len(unicos)}) tem menos da "
                                      f"metade de quem podia falar ({antes})")

        print(f"grupos lidos: {len(pacote)} de {len(grupos)}"
              f" | fora da lista: {len(fora)}"
              f" | membros unicos nos grupos incluidos: {len(unicos)}"
              f" | podiam falar antes: {antes}")
        if falhas:
            print("FALHAS:\n  " + "\n  ".join(falhas))
        if not revogar:
            print(f"NAO VAI TIRAR NINGUEM DA LISTA: {motivo}. So adiciona.")

        if not args.escrever:
            print("(simulacao -- nada gravado; rode com --escrever)")
            return 0

        with conn.cursor() as cur:
            cur.execute("SELECT nai_sincronizar_grupos(%s::jsonb, %s) AS r",
                        (json.dumps(pacote), revogar))
            resultado = cur.fetchone()["r"]
        conn.commit()
        print("gravado:", json.dumps(resultado, ensure_ascii=False))
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
