#!/usr/bin/env python3
"""Os arquivos de `nai/` batem com as funções que estão rodando em produção?

POR QUE EXISTE (30/09): as 309 funções da NAI viviam SÓ NO BANCO -- nenhuma
tinha fonte no repositório. Foi por isso que o bug do `record "t"` sobreviveu
até derrubar a agenda por seis horas: ninguém podia ler, revisar nem comparar o
porteiro que decide tudo que a NAI manda.

MAS ARQUIVO DESPEJADO E ESQUECIDO É PIOR QUE ARQUIVO NENHUM. O CLAUDE.md
registra "cópia diverge sozinha" como o padrão de bug mais caro do projeto: o
dia em que alguém trocar a função no banco e não no arquivo, o arquivo passa a
mentir -- e mentira que se lê com confiança custa mais que ausência.

Então a extração só vale acompanhada disto. É o mesmo desenho da verificação
`deriva do nay_comando`, que já existe no `rodar_testes.sh`.

A COMPARAÇÃO É BYTE A BYTE, de propósito. Cada arquivo é exatamente o que
`pg_get_functiondef` devolve, mais o `;`. Nenhum cabeçalho meu, nenhuma
normalização, nada para "tolerar" -- porque toda tolerância é um buraco por
onde a deriva passa. O contexto de cada função mora DENTRO do corpo dela, em
comentário SQL, que é o único comentário que sobrevive no banco.

    .venv/bin/python conferir_deriva_nai.py
"""
import os
import re
import subprocess
import sys

PASTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nai")

CONSULTA = r"""
WITH f AS (
  SELECT p.oid, p.proname::text AS nome, p.pronargs,
         count(*) OVER (PARTITION BY p.proname) AS irmaos
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'nai%'
)
SELECT f.nome || CASE WHEN f.irmaos > 1 THEN '__' || f.pronargs || 'arg' ELSE '' END || '.sql',
       pg_get_functiondef(f.oid) || ';'
  FROM f ORDER BY 1;
"""


def do_banco():
    """{arquivo: corpo} do que está rodando AGORA.

    Roda pelo mesmo caminho que o `rodar_testes.sh --com-banco` usa: `psql`
    dentro do container. Separadores fora do ASCII imprimível porque corpo de
    função tem vírgula, ponto e vírgula, tabulação e quebra de linha à vontade.
    """
    sql = "/tmp/conferir_deriva_nai.sql"
    with open(sql, "w", encoding="utf-8") as f:
        f.write(CONSULTA)
    subprocess.run(["docker", "cp", sql, "nay-postgres:/tmp/cdn.sql"],
                   check=True, capture_output=True)
    saida = subprocess.run(
        ["docker", "exec", "nay-postgres", "psql", "-U", "nay", "-d", "naydb",
         "-q", "-A", "-t", "-F", "\x01", "-R", "\x02", "-f", "/tmp/cdn.sql"],
        check=True, capture_output=True, text=True).stdout
    vivo = {}
    for reg in saida.split("\x02"):
        if "\x01" not in reg:
            continue
        nome, corpo = reg.split("\x01", 1)
        vivo[nome.strip()] = corpo.strip()
    return vivo


def main():
    if not os.path.isdir(PASTA):
        print("FALHARAM: a pasta nai/ nao existe")
        return 1
    vivo = do_banco()
    # O `_triggers.sql` guarda `CREATE TRIGGER`, não função -- fora da conta.
    em_arquivo = {n: open(os.path.join(PASTA, n), encoding="utf-8").read().strip()
                  for n in sorted(os.listdir(PASTA))
                  if n.endswith(".sql") and not n.startswith("_")}

    so_no_banco = sorted(set(vivo) - set(em_arquivo))
    so_em_arquivo = sorted(set(em_arquivo) - set(vivo))
    diferentes = sorted(n for n in set(vivo) & set(em_arquivo)
                        if vivo[n] != em_arquivo[n])

    if not (so_no_banco or so_em_arquivo or diferentes):
        print(f"PASSARAM (as {len(vivo)} funcoes da NAI batem com a producao)")
        return 0

    if so_no_banco:
        print(f"FALHARAM: {len(so_no_banco)} funcao(oes) em producao SEM arquivo "
              "-- extraia com a consulta do cabecalho deste script:")
        for n in so_no_banco[:12]:
            print(f"    {n}")
    if so_em_arquivo:
        print(f"FALHARAM: {len(so_em_arquivo)} arquivo(s) de funcao que NAO EXISTE "
              "mais em producao -- foi renomeada ou removida:")
        for n in so_em_arquivo[:12]:
            print(f"    {n}")
    if diferentes:
        print(f"FALHARAM: {len(diferentes)} funcao(oes) DIVERGEM entre o arquivo e "
              "a producao. O arquivo esta mentindo:")
        for n in diferentes[:12]:
            print(f"    {n}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
