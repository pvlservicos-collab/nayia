#!/bin/bash
# 508 (Pedro, 28/10/2026): os avisos à equipe saem do grupo Altarquia e vão às Notificações do CRM; no grupo só visita.
# Uso, na raiz do nayia: ./scripts/publicar_avisos_508.sh
# Cada etapa PARA se o servidor tiver algo que não saiu daqui (os publicar.sh e o nay crm conferem sozinhos).
set -euo pipefail
cd "$(dirname "$0")/.."
SRV=nay-srv1894338
S=/c/Users/pedro/AppData/Local/Temp/claude/c--Users-pedro-Desktop-TEL-SOBREIRA-Nay-IA/89358e30-039e-42ec-a23e-fcb910561c17/scratchpad

echo "== 0. testes da OLX e da captação no servidor (numa cópia em /tmp, sem tocar no que roda)"
tar -c --exclude=__pycache__ nay-olx/olx nay-olx/tests nay-captacao/captacao nay-captacao/tests \
  | ssh $SRV "set -e; rm -rf /tmp/ensaio-508; mkdir -p /tmp/ensaio-508; tar -x -C /tmp/ensaio-508
    cd /tmp/ensaio-508/nay-olx && /root/nay-olx/.venv/bin/python -m unittest discover -s tests -q 2>&1 | tail -3
    cd /tmp/ensaio-508/nay-captacao && /root/nay-captacao/.venv/bin/python -m unittest discover -s tests -q 2>&1 | tail -3"

echo "== 1. banco: a 508"
./scripts/nay aplicar Arquivos/nai/508_avisos_da_equipe_no_crm.sql

echo "== 2. CRM"
./scripts/nay crm "src/lib/avisosDaNay.ts" "src/app/api/cron/espelho-nay/route.ts" "src/app/api/notifications/route.ts" \
  "src/hooks/useNotifications.ts" "src/app/(authenticated)/notifications/page.tsx"

echo "== 3. Nay da OLX"
./nay-olx/publicar.sh grupo.py whatsapp.py buscas.py parceiro.py chat.py

echo "== 4. Nay de captação"
./nay-captacao/publicar.sh

echo "== 5. regras do agente da Nay (servidor 2)"
scp -q "$S/agente_avisos_508.py" nay-srv1877774:/root/agente_avisos_508.py
ssh nay-srv1877774 "python3 /root/agente_avisos_508.py"

echo "== pronto. Conferir: ./scripts/nay q \"SELECT id, fonte, tipo, titulo FROM crm_avisos_da_equipe(0)\""
