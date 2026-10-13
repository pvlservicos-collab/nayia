#!/bin/bash
# Roda na VPS1 (pelo publicar.sh vps1): acrescenta ao compose da API do site as duas variáveis da ponte dos Hermes.
# Só ACRESCENTA, depois da linha do NAY_CORE_PAINEL_TOKEN, e deixa a cópia do que estava (.bk-AAAAMMDD-HHMM).
set -euo pipefail
f=/docker/nay-site-api/docker-compose.yml
if grep -q "HERMES_PAINEL_URL" "$f"; then
  echo "o compose já tem as linhas da ponte"
else
  cp -p "$f" "$f.bk-$(date +%Y%m%d-%H%M)"
  python3 - "$f" <<'EOF'
import sys
f = sys.argv[1]
linhas = open(f, encoding="utf-8").read().split("\n")
i = next(n for n, l in enumerate(linhas) if "NAY_CORE_PAINEL_TOKEN=" in l)
recuo = linhas[i][:len(linhas[i]) - len(linhas[i].lstrip())]
linhas[i + 1:i + 1] = [
    recuo + "# Painel dos Hermes (13/10): a ponte que roda na VPS2, alcancada pelo Tailscale, com segredo de maquina",
    recuo + "# (nay-agentes/hermes-painel). O segredo mora so no .env daqui.",
    recuo + "- HERMES_PAINEL_URL=http://100.113.222.11:8650",
    recuo + "- HERMES_PAINEL_TOKEN=${HERMES_PAINEL_TOKEN:-}",
]
open(f, "w", encoding="utf-8").write("\n".join(linhas))
EOF
  echo "linhas acrescentadas ao compose:"
  grep -n "HERMES_PAINEL" "$f" | sed -E 's/(TOKEN=).*/\1<variável do .env>/'
fi
cd /docker/nay-site-api && docker compose config -q && echo "compose válido"
