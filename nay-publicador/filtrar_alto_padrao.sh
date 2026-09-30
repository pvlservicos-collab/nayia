#!/bin/bash
# Colhe, de quem pede para entrar no grupo Alto Padrão, por onde ele anuncia.
# Roda a cada minuto, como os outros crons. Silencioso quando não há nada.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'

"$PROJETO/.venv/bin/python" "$PROJETO/filtrar_alto_padrao.py" --escrever

# BATIMENTO. Este cron manda mensagem para corretor que está chegando; se
# morresse, o sintoma seria o Tel simplesmente não receber Instagram nenhum --
# indistinguível de "ninguém respondeu". A varredura ficou 5 dias parada por
# exatamente essa confusão, e o alarme mora FORA do wrapper de propósito.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_filtrar_alto_padrao"
