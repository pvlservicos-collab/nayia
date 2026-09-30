#!/bin/bash
# Wrapper de cron para entregar_pendentes.py, no molde do
# disparar_lembretes.sh. Silencioso quando nao ha divida.
set -euo pipefail
PROJETO=/root/nay-publicador
cd "$PROJETO"
set -a
. ./.env
set +a
export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'
SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/entregar_pendentes.py" --enviar 2>&1)" || {
    codigo=$?
    echo "[$(date "$CARIMBO")] ERRO (saida $codigo)" >&2
    echo "$SAIDA" >&2
    exit "$codigo"
}
if [ -n "$SAIDA" ]; then echo "[$(date "$CARIMBO")] $SAIDA"; fi

# BATIMENTO. O alarme (`alarme_crons.py`) olha a data deste arquivo: cron
# que morre nao avisa ninguem, e em 02/09 a grade ficou 18 horas parada
# porque o wrapper perdeu o bit de execucao. `touch` e uma syscall e roda
# a cada minuto -- abrir banco so para dizer "estou vivo" custaria mais
# que o trabalho.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_entregar_pendentes"
