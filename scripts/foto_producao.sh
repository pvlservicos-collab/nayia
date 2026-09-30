#!/bin/bash
# Foto da produção: regera producao/ a partir do servidor, SÓ LEITURA.
#   banco   funções vivas do schema public, nai_config, nai_prompt (sessão read-only)
#   n8n     fluxos ativos, do sqlite aberto em OPEN_READONLY (segredos apagados no servidor)
#   cron    crontab do root e /etc/cron.d
#   n8n env só os NOMES das variáveis do container (o valor não sai do servidor)
# Uso (Windows, Git Bash, na raiz do nayia): ./scripts/foto_producao.sh
# Depois de aplicar qualquer mudança em produção: rode e commite.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SRV=nay-srv1894338
BRUTO="$RAIZ/producao/.bruto"
SQLITE3=/usr/local/lib/node_modules/n8n/node_modules/.pnpm/sqlite3@5.1.7/node_modules/sqlite3
rm -rf "$BRUTO" && mkdir -p "$BRUTO"

ssh -o ConnectTimeout=20 "$SRV" "docker exec -i -e PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=120000' nay-postgres psql -U nay -d naydb -X -A -t -q -v ON_ERROR_STOP=1" \
  < "$RAIZ/scripts/foto_banco.sql" > "$BRUTO/banco.json"
ssh -o ConnectTimeout=20 "$SRV" "docker exec -i -e SQLITE3_PATH=$SQLITE3 n8n-viux-n8n-1 node -" \
  < "$RAIZ/scripts/foto_n8n.js" > "$BRUTO/workflows.json"
ssh -o ConnectTimeout=20 "$SRV" 'crontab -l; for f in /etc/cron.d/*; do echo "### $f"; cat "$f"; done' > "$BRUTO/cron.txt"
ssh -o ConnectTimeout=20 "$SRV" "docker exec n8n-viux-n8n-1 printenv | cut -d= -f1 | sort -u" > "$BRUTO/n8n_env.txt"

PYTHONIOENCODING=utf-8 python "$RAIZ/scripts/foto_producao.py" "$BRUTO" "$RAIZ/producao"
rm -rf "$BRUTO"
