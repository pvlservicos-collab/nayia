#!/bin/bash
# Cron de alertas da agenda de visitas.
# Roda a cada minuto, como os outros crons.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'

"$PROJETO/.venv/bin/python" "$PROJETO/alertar_visitas.py"

# BATIMENTO, que faltava desde 11/09. Este cron manda cinco tipos de mensagem
# para o WhatsApp do Tel -- briefing da manhã, véspera, lembrete de 90 min,
# cobrança de 1 hora -- e se morresse ninguém saberia: o sintoma seria a
# agenda simplesmente parar de avisar, que é indistinguível de "não havia
# visita nenhuma". Foi essa exata confusão que deixou a grade 18 horas parada
# em 02/09.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_alertar_visitas"
