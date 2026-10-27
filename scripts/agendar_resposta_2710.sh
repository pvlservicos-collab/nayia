#!/bin/bash
# 27/10/2026 (Pedro): as respostas que a Nay Leads deixou para trás saem às 09:00 de Manaus de 27/10 (13:00 UTC; o
# servidor está em UTC). Sobe nay-olx/resposta_2710.py e cria /etc/cron.d/nay-leads-resposta-2710, que roda uma vez,
# grava em /root/nay-olx/resposta_2710.log e se apaga. Desistir antes da hora: ssh ... rm /etc/cron.d/nay-leads-resposta-2710
# Uso, na raiz do nayia: ./scripts/agendar_resposta_2710.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SRV=nay-srv1894338
ssh -o ConnectTimeout=20 $SRV "[ -e /root/nay-olx/resposta_2710.py ] && { echo 'já existe /root/nay-olx/resposta_2710.py: parei'; exit 3; } || true"
tr -d '\r' < nay-olx/resposta_2710.py | ssh $SRV "cat > /root/nay-olx/resposta_2710.py"
ssh $SRV "cat > /etc/cron.d/nay-leads-resposta-2710 <<'EOF'
0 13 27 10 * root cd /root/nay-olx && set -a && . ./.env && set +a && TZ=America/Manaus .venv/bin/python resposta_2710.py >> /root/nay-olx/resposta_2710.log 2>&1; rm -f /etc/cron.d/nay-leads-resposta-2710
EOF
chmod 644 /etc/cron.d/nay-leads-resposta-2710; cat /etc/cron.d/nay-leads-resposta-2710; date -u"
