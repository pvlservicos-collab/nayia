#!/bin/bash
# Roda NA VPS1: autoriza a chave pública da VPS2 ($1 = "ssh-ed25519 AAAA... comentário") com uma única permissão,
# escrever /docker/nay-site-web/public/admin/dados/agentes2.json (é assim que a página Agentes recebe a VPS2).
# Remove a linha anterior marcada nay-agentes-vps2 antes de escrever a nova. Uso: ssh nay-srv1894338 'bash -s' -- "$PUB" < este
set -eu
PUB="$1"
A=~/.ssh/authorized_keys
cp "$A" "$A.bak_nay_agentes"
grep -v 'nay-agentes-vps2' "$A" > "$A.novo"
[ -s "$A.novo" ] && [ -n "$(tail -c 1 "$A.novo")" ] && echo >> "$A.novo"
TIPO=$(echo "$PUB" | awk '{print $1}')
CHAVE=$(echo "$PUB" | awk '{print $2}')
printf 'command="cat > /docker/nay-site-web/public/admin/dados/agentes2.json",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty %s %s nay-agentes-vps2\n' "$TIPO" "$CHAVE" >> "$A.novo"
mv "$A.novo" "$A"
chmod 600 "$A"
awk '{print NR, NF, substr($1,1,14), $NF}' "$A"
