#!/bin/bash
# Wrapper de cron do sincronizar_grupos_corretores.py -- TODA SEGUNDA, 06:10
# de Manaus, antes do expediente: a semana comeca com a lista de corretores
# refeita a partir dos grupos (pedido do Tel, 18/09/2026).
#
# Mesmo molde dos outros: cron nao carrega .env sozinho, e "set -a" faz o que
# o arquivo define virar variavel exportada.
#
# O BATIMENTO SO BATE QUANDO DEU CERTO. E ele que o alarme_crons.py mede, com
# folga de 8 dias: se a sincronizacao falhar (Z-API fora, erro no banco), o
# arquivo envelhece e o Tel recebe o aviso. Log ninguem le -- e uma lista que
# para de ser atualizada nao da sintoma nenhum, so vai ignorando corretor novo.
set -uo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

if SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/sincronizar_grupos_corretores.py" --escrever 2>&1)"; then
    echo "[$(date "$CARIMBO")] $SAIDA"
    mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_sincronizar_grupos_corretores"
else
    codigo=$?
    echo "[$(date "$CARIMBO")] ERRO (saida $codigo)" >&2
    echo "$SAIDA" >&2
    exit "$codigo"
fi
