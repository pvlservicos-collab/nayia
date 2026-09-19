#!/bin/bash
# Wrapper de cron para ciclo_pendencias.py, no mesmo molde dos outros:
# cron nao carrega .env sozinho, e "set -a" faz o que o arquivo define
# virar variavel exportada.
#
# Roda de minuto em minuto como os irmaos, e e SILENCIOSO quando nao ha
# nada -- entao o log so cresce quando alguma coisa aconteceu de verdade.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/ciclo_pendencias.py" --enviar 2>&1)" || {
    codigo=$?
    echo "[$(date "$CARIMBO")] ERRO (saida $codigo)" >&2
    echo "$SAIDA" >&2
    exit "$codigo"
}

if [ -n "$SAIDA" ]; then
    echo "[$(date "$CARIMBO")] $SAIDA"
fi

# BATIMENTO. O alarme (`alarme_crons.py`) olha a data deste arquivo: cron
# que morre nao avisa ninguem, e em 02/09 a grade ficou 18 horas parada
# porque o wrapper perdeu o bit de execucao. `touch` e uma syscall e roda
# a cada minuto -- abrir banco so para dizer "estou vivo" custaria mais
# que o trabalho.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_ciclo_pendencias"
