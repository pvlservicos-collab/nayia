#!/bin/bash
# Publica os medidores na VPS1 (agentes e uso de recursos): copia, instala o cron, mede uma vez e mostra o resumo do JSON.
set -e
cd "$(dirname "$0")"
tar -cz medir_agentes.sh medir_recursos.py nay-agentes.cron | ssh nay-srv1894338 'mkdir -p /root/nay-agentes && tar -xz -C /root/nay-agentes && chmod +x /root/nay-agentes/medir_agentes.sh && cp /root/nay-agentes/nay-agentes.cron /etc/cron.d/nay-agentes && /root/nay-agentes/medir_agentes.sh && python3 /root/nay-agentes/medir_recursos.py && python3 /root/nay-agentes/resumo.py'
