#!/bin/bash
# Roda TODAS as suites de uma vez: Python, JavaScript e SQL.
#
# POR QUE EXISTE: as suites .sql (como teste_valor_nao_e_codigo.sql) nao
# rodavam por nada automatico -- so quando alguem lembrava de copiar para o
# container. Suite que ninguem roda e documentacao, nao teste.
#
# As de SQL precisam do banco, entao so rodam com --com-banco, no servidor
# (ou de uma maquina com acesso ao container).
#
#   ./rodar_testes.sh                 # Python + JavaScript
#   ./rodar_testes.sh --com-banco     # e tambem as de SQL, no servidor
set -uo pipefail

cd "$(dirname "$0")"
PY=".venv/bin/python"
[ -x "$PY" ] || PY="python3"

ok=0
ruim=0

rodar() {
    printf '%-38s ' "$1"
    if saida="$(eval "$2" 2>&1)"; then
        echo "$saida" | tail -1
        ok=$((ok + 1))
    else
        echo "FALHOU"
        echo "$saida" | tail -6 | sed 's/^/        /'
        ruim=$((ruim + 1))
    fi
}

# O ARQUIVO E A PRODUCAO NAO PODEM DIVERGIR. `comando_descartar_resposta.sql`
# se declara "o corpo inteiro de nay_comando como esta em producao" e traz o
# passo de deploy no cabecalho -- entao um arquivo velho, rodado por quem for
# fazer o ajuste seguinte, apaga a correcao anterior em silencio. Foi o que
# quase aconteceu com a confirmacao do RESPOSTA (01/09).
#
# E uma FUNCAO, e nao um texto passado ao `rodar`: o `rodar` usa `eval`, e ali
# o `$nayfn$` do delimitador seria expandido como variavel e sumiria.
# O REGRAS-E-BUGS.md nao pode divergir do banco. A Parte 1 dele e gerada da
# tabela `regras`, que e a mesma fonte do prompt da Nay -- documento parado
# vira uma segunda copia da regra, e cópia diverge sozinha (a gramatica de
# comando chegou a ter QUATRO copias, uma errada).
# TODO WRAPPER DE CRON PRECISA DO BIT DE EXECUCAO -- e no git, nao so no
# disco. Em 02/09 o `disparar_grade.sh` estava 100644 enquanto os outros
# estavam 100755; um `git reset --hard` no servidor imps o modo errado e o
# cron passou a falhar com "Permission denied" a cada minuto. A grade ficou
# 18 HORAS parada, com 754 linhas de erro num log que ninguem le.
checar_modo_de_execucao() {
    ruins="$(git ls-files -s -- '*.sh' | awk '$1 != "100755" { print $4 }')"
    if [ -z "$ruins" ]; then
        echo "PASSARAM (todos os .sh executaveis no git)"
        return 0
    fi
    echo "FALHARAM: sem bit de execucao no git: $ruins"
    echo "  conserte com: git update-index --chmod=+x <arquivo>"
    return 1
}

checar_regras_e_bugs() {
    # As outras suites .py sao unitarias e nao tocam o banco; esta le a
    # tabela `regras`. O .env fica dentro de subshell para nao vazar
    # credencial para o resto do runner.
    saida="$( ( [ -f .env ] && { set -a; . ./.env; set +a; }
               $PY gerar_regras_e_bugs.py ) 2>&1 )" || { echo "$saida"; return 1; }
    case "$saida" in
      *"já está em dia"*) echo "PASSARAM ($saida)"; return 0 ;;
      *) echo "FALHARAM: $saida"; echo "  rode: $PY gerar_regras_e_bugs.py --escrever"; return 1 ;;
    esac
}

checar_deriva_do_comando() {
    docker exec nay-postgres psql -U nay -d naydb -tAc \
        "SELECT prosrc FROM pg_proc WHERE proname='nay_comando'" > /tmp/comando_vivo.txt || return 1
    sed -n '/^LANGUAGE plpgsql AS [$]nayfn[$]/,/^[$]nayfn[$];/p' comando_descartar_resposta.sql \
        | sed '1d;$d' > /tmp/comando_arq.txt
    if [ ! -s /tmp/comando_arq.txt ]; then
        echo "FALHARAM: nao achei o corpo de nay_comando no arquivo"
        return 1
    fi
    # Linha em branco e espaco no fim nao sao deriva: o gerador e o psql
    # discordam em UMA quebra de linha no comeco do corpo, e isso acusaria
    # divergencia todo dia. O que importa e o TEXTO.
    limpar() { sed -e 's/[[:space:]]*$//' "$1" | grep -v '^$'; }
    limpar /tmp/comando_vivo.txt > /tmp/comando_vivo_limpo.txt
    limpar /tmp/comando_arq.txt  > /tmp/comando_arq_limpo.txt
    if diff -q /tmp/comando_vivo_limpo.txt /tmp/comando_arq_limpo.txt >/dev/null; then
        echo "PASSARAM (o arquivo bate com a producao)"
        return 0
    fi
    echo "FALHARAM: comando_descartar_resposta.sql divergiu da producao"
    diff /tmp/comando_vivo_limpo.txt /tmp/comando_arq_limpo.txt | head -12
    return 1
}

rodar "bit de execucao dos .sh" "checar_modo_de_execucao"

for t in teste_*.py; do
    [ -e "$t" ] || continue
    rodar "$t" "$PY '$t'"
done

# `node` existe no Mac; no servidor ele mora dentro do container do n8n --
# que e onde essas regex rodam de verdade. Preferir o container quando ele
# estiver disponivel prova contra o mesmo motor da producao.
if command -v node >/dev/null 2>&1; then
    NODE="node"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^n8n-viux-n8n-1$'; then
    NODE="container"
else
    NODE=""
fi

for t in teste_*.js; do
    [ -e "$t" ] || continue
    case "$NODE" in
      node)
        rodar "$t" "node '$t'" ;;
      container)
        rodar "$t" "docker cp '$t' n8n-viux-n8n-1:/tmp/ >/dev/null \
                    && docker cp casos_comando_envio.json n8n-viux-n8n-1:/tmp/ >/dev/null 2>&1; \
                    docker exec n8n-viux-n8n-1 node /tmp/'$t'" ;;
      *)
        printf '%-38s %s\n' "$t" "(pulado: sem node e sem container)" ;;
    esac
done

if [ "${1:-}" = "--com-banco" ]; then
    rodar "deriva do nay_comando" "checar_deriva_do_comando"
    rodar "REGRAS-E-BUGS.md em dia" "checar_regras_e_bugs"

    for t in teste_*.sql; do
        [ -e "$t" ] || continue
        # As suites SQL imprimem "TODOS OS N CASOS PASSARAM" ou "N FALHARAM".
        # `psql` sai com 0 mesmo quando o teste falha, entao o veredito vem
        # do texto -- e um grep por FALHARAM decide.
        rodar "$t" "docker cp '$t' nay-postgres:/tmp/t.sql >/dev/null \
                    && docker exec nay-postgres psql -U nay -d naydb -tA -f /tmp/t.sql \
                       | grep -E 'PASSARAM|FALHARAM' \
                    | grep -qv FALHARAM \
                    && docker exec nay-postgres psql -U nay -d naydb -tA -f /tmp/t.sql \
                       | grep -E 'PASSARAM|FALHARAM'"
    done
fi

echo
if [ "$ruim" -eq 0 ]; then
    echo "TODAS AS $ok SUITES PASSARAM"
else
    echo "$ruim de $((ok + ruim)) suites FALHARAM"
fi
exit "$ruim"
