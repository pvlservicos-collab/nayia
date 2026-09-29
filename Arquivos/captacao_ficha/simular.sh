#!/bin/sh
# SIMULADOR DA CONVERSA DA CAPTAÇÃO (28/09/2026) -- roda DENTRO do container do
# n8n: as credenciais saem decifradas só para /tmp/sim (umask 077) e a pasta é
# apagada no fim. O modelo, o prompt e o SQL das ferramentas são os de verdade;
# o banco roda numa transação desfeita no fim. Nenhuma mensagem sai.
#
#   sh simular.sh disponivel outro bagunca          (com o prompt VIVO do banco)
#   PROMPT=/root/n8n-captacao/novo.txt sh simular.sh disponivel   (texto novo, antes de gravar)
#
# Cenários: os roteiros de falas do dono em simular_captacao.js (CENARIOS).
set -e
C=n8n-captacao
AQUI=$(dirname "$0")
docker exec -u root $C rm -rf /tmp/sim
docker exec $C sh -c 'umask 077; mkdir -p /tmp/sim'
for id in iR8sKG7vjnpQSWio CzrQhGemsCI4hLUh; do
  docker exec $C sh -c "umask 077; n8n export:credentials --id=$id --decrypted --output=/tmp/sim/$id.json >/dev/null 2>&1"
done
docker exec $C sh -c 'umask 077; n8n export:workflow --id=CjsUJefRYcQIIi1F --output=/tmp/sim/fluxo.json >/dev/null 2>&1'
docker exec -i $C sh -c 'umask 077; cat > /tmp/sim/simular.js' < "$AQUI/simular_captacao.js"
ARQ=""
if [ -n "$PROMPT" ]; then
  docker exec -i $C sh -c 'umask 077; cat > /tmp/sim/prompt.txt' < "$PROMPT"
  ARQ=/tmp/sim/prompt.txt
fi
for c in "$@"; do
  docker exec $C node /tmp/sim/simular.js "$c" $ARQ || true
done
docker exec -u root $C rm -rf /tmp/sim
docker exec $C sh -c 'test ! -e /tmp/sim && echo "(credenciais apagadas do container)"'
