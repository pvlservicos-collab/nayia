#!/bin/bash
# Cron da etapa da Nay -> tag do lead no CRM (sincronizar_etapas_crm.py). Silencioso sem nada.
set -euo pipefail
PROJETO=/root/nay-publicador
cd "$PROJETO"
set -a; . ./.env; set +a
SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/sincronizar_etapas_crm.py" 2>&1)" || { echo "[$(date "+%F %T")] ERRO"; echo "$SAIDA"; exit 1; }
if [ -n "$SAIDA" ]; then echo "[$(date "+%F %T")] $SAIDA"; fi
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_sincronizar_etapas_crm"
