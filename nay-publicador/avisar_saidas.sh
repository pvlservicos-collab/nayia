#!/bin/bash
# O aviso de ALUGADO/VENDIDO no grupo Easy, venha o comando por onde vier.
# Mesmo molde dos outros crons: flock na linha do crontab, .env carregado
# aqui (cron nao carrega sozinho), e silencio quando nao ha nada a fazer.
set -euo pipefail
PROJETO=/root/nay-publicador
CARIMBO="+%Y-%m-%dT%H:%M:%S%z"
cd "$PROJETO"
set -a
. ./.env
set +a
export TZ="America/Manaus"
SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/avisar_saidas.py" --enviar 2>&1)" || {
    echo "[$(date "$CARIMBO")] ERRO no avisar_saidas" >&2
    echo "$SAIDA" >&2
    exit 1
}
[ -n "$SAIDA" ] && echo "[$(date "$CARIMBO")] $SAIDA"
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_avisar_saidas"
exit 0
