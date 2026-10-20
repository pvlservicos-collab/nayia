#!/bin/bash
# Publica o Agente Claude. Uso (Git Bash, na raiz do nayia): ./agente-claude/publicar.sh
#
# VPS2 (nay-srv1877774): /opt/agente-claude (agente.py, painel, mcp_agente.py), serviço agente-claude-painel (root),
#   /usr/local/sbin/claude-agente e a chave /root/.ssh/agente_claude_vps1 para chegar ao root da VPS1 pelo Tailscale.
# VPS1 (nay-srv1894338): /usr/local/sbin/claude-agente e a chave pública da VPS2 no authorized_keys do root,
#   presa ao endereço Tailscale da VPS2 (from=). Nada da Nay é tocado.
# Nas duas: /etc/agente-claude/claude.env (600) para o CLAUDE_CODE_OAUTH_TOKEN; nasce vazio, nunca é sobrescrito.
#
# Desfazer: VPS2 `systemctl disable --now agente-claude-painel`; VPS1 apagar a linha "agente-claude-vps2" do
#   /root/.ssh/authorized_keys; nas duas `rm /usr/local/sbin/claude-agente`.
set -euo pipefail
cd "$(dirname "$0")"
VPS2=nay-srv1877774
VPS1=nay-srv1894338
VPS2_TS=100.113.222.11
VPS1_TS=100.86.114.74
ARQS="agente.py painel.py painel.html mcp_agente.py regras.exemplo.json claude-agente agente-claude-painel.service"

# 1) VPS1: o executor e o arquivo do login
tr -d '\r' < claude-agente | ssh $VPS1 'install -m 750 /dev/stdin /usr/local/sbin/claude-agente
  install -d -m 700 /etc/agente-claude
  [ -e /etc/agente-claude/claude.env ] || ( umask 077; printf "# CLAUDE_CODE_OAUTH_TOKEN=  (claude setup-token)\n" > /etc/agente-claude/claude.env )
  echo "VPS1: claude-agente instalado"'

# 2) VPS2: arquivos, executor, chave para a VPS1, serviço
tar -c $ARQS | ssh $VPS2 'set -e
  rm -rf /root/agente-claude-fonte && mkdir -p /root/agente-claude-fonte && tar -x -C /root/agente-claude-fonte
  cd /root/agente-claude-fonte && sed -i "s/\r$//" *
  D=/opt/agente-claude
  # o usuário agclaude (20/10, primeira versão) sai: agora tudo roda como root
  if id agclaude >/dev/null 2>&1; then
    systemctl stop agente-claude-painel 2>/dev/null || true
    userdel agclaude; rm -rf $D/.local $D/.cache $D/.npm $D/.claude $D/.claude.json $D/.bash_logout $D/.bashrc $D/.profile $D/vazio $D/.env
    echo "VPS2: usuário agclaude removido"
  fi
  install -d -m 750 $D; chown -R root:root $D
  install -m 750 agente.py painel.py mcp_agente.py $D/
  install -m 640 painel.html regras.exemplo.json $D/
  ln -sfn agente.py $D/agente
  [ -f $D/regras.json ] || install -m 640 regras.exemplo.json $D/regras.json
  install -m 750 claude-agente /usr/local/sbin/claude-agente
  install -d -m 700 /etc/agente-claude
  [ -e /etc/agente-claude/claude.env ] || ( umask 077; printf "# CLAUDE_CODE_OAUTH_TOKEN=  (claude setup-token)\n" > /etc/agente-claude/claude.env )
  [ -f /root/.ssh/agente_claude_vps1 ] || ssh-keygen -q -t ed25519 -N "" -C agente-claude-vps2 -f /root/.ssh/agente_claude_vps1
  install -m 644 agente-claude-painel.service /etc/systemd/system/agente-claude-painel.service
  systemctl daemon-reload; systemctl enable agente-claude-painel >/dev/null 2>&1; systemctl restart agente-claude-painel
  echo "VPS2: painel $(systemctl is-active agente-claude-painel)"'

# 3) a chave pública da VPS2 entra no root da VPS1, só aceita vindo do Tailscale da VPS2
ssh $VPS2 'cat /root/.ssh/agente_claude_vps1.pub' | tr -d '\r' | ssh $VPS1 "set -e
  read -r chave
  grep -qF \"\$chave\" /root/.ssh/authorized_keys || { cp -p /root/.ssh/authorized_keys /root/.ssh/authorized_keys.bk-\$(date +%Y%m%d-%H%M); printf 'from=\"$VPS2_TS\" %s\n' \"\$chave\" >> /root/.ssh/authorized_keys; echo 'VPS1: chave da VPS2 autorizada'; }"
ssh $VPS2 "ssh-keygen -F $VPS1_TS >/dev/null || ssh-keyscan -t ed25519 $VPS1_TS 2>/dev/null >> /root/.ssh/known_hosts
  ssh -o BatchMode=yes -o ConnectTimeout=10 -i /root/.ssh/agente_claude_vps1 root@$VPS1_TS 'echo VPS2 chega na VPS1: \$(hostname)'"
