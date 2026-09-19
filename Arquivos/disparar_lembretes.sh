#!/bin/bash
# Wrapper de cron para disparar_lembretes.py, no mesmo molde do
# disparar_grade.sh -- cron nao carrega .env sozinho, e "set -a" faz o que
# o arquivo define virar variavel exportada.
#
# Roda de minuto em minuto. O script e SILENCIOSO quando nao ha lembrete
# devido, entao o log so cresce quando algo aconteceu de verdade.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/disparar_lembretes.py" --enviar 2>&1)" || {
    codigo=$?
    echo "[$(date "$CARIMBO")] ERRO (saida $codigo)" >&2
    echo "$SAIDA" >&2
    exit "$codigo"
}

# So escreve no log quando houve lembrete. 1.440 execucoes por dia com
# "nada a fazer" tornariam o log ilegivel.
if [ -n "$SAIDA" ]; then
    echo "[$(date "$CARIMBO")] $SAIDA"
fi

# BATIMENTO. O alarme (`alarme_crons.py`) olha a data deste arquivo: cron
# que morre nao avisa ninguem, e em 02/09 a grade ficou 18 horas parada
# porque o wrapper perdeu o bit de execucao. `touch` e uma syscall e roda
# a cada minuto -- abrir banco so para dizer "estou vivo" custaria mais
# que o trabalho.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_disparar_lembretes"
