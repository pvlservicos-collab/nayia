#!/bin/bash
# Instala o Hermes do Claude (perfil `claude`) na VPS2. Roda LÁ, como root, pelo `publicar.sh claude`. Pode rodar de novo.
#
# Pedro, 20/10/2026: "vc vai criar outro hermes só para isso fora da olx, esse hermes só vai falar comigo". Ele manda ao
# Claude, na hora marcada, as regras do painel agentes.imobeasy.online (agente-claude/ no repo). Só fala pela tela
# admin › Agentes (API local, sem Telegram nem WhatsApp). Ferramentas: memória, agenda e a `agente` (mcp_agente.py);
# sem terminal. Não toca no perfil olx nem no hermes-gateway-olx; reinicia só a ponte, para ela ler o perfis.json novo.
# Desfazer: systemctl disable --now hermes-gateway-claude; tirar "claude" do perfis.json e reinstalar.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
ETC=/etc/hermes-painel
SD=/etc/systemd/system
PY=/usr/local/lib/hermes-agent/venv/bin/python
PERFIS_DIR=/root/.hermes/profiles
P=claude
API=8645

[ -x "$PY" ] || { echo "não achei o Python do Hermes em $PY"; exit 1; }
[ -f /opt/agente-claude/mcp_agente.py ] || { echo "falta o Agente Claude: rode antes ./agente-claude/publicar.sh"; exit 1; }
install -m 600 "$AQUI/perfis.json" "$ETC/perfis.json"

if [ ! -d "$PERFIS_DIR/$P" ]; then
  timeout 120 hermes profile create "$P" --no-alias --no-skills \
    --description "Hermes do Claude: manda ao Claude, na hora marcada, as regras do painel agentes.imobeasy.online. Só fala com o Pedro." </dev/null 2>&1 | tail -3 | cut -c1-160
  [ -d "$PERFIS_DIR/$P" ] || { echo "o Hermes não criou o perfil $P"; exit 1; }
  echo "perfil $P criado"
fi
install -m 600 "$AQUI/alma-claude.md" "$PERFIS_DIR/$P/SOUL.md"
"$PY" "$AQUI/configurar_perfil.py" "$PERFIS_DIR/$P"

if [ ! -s "$ETC/gateway-$P.env" ]; then
  ( umask 077; printf 'API_SERVER_KEY=%s\nAPI_SERVER_HOST=127.0.0.1\nAPI_SERVER_PORT=%s\n' "$(openssl rand -hex 32)" "$API" > "$ETC/gateway-$P.env" )
fi
cat > "$SD/hermes-gateway-$P.service" <<EOF
[Unit]
Description=Hermes do Claude (perfil $P) do painel admin › Agentes
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=-$ETC/gateway-telegram.env
EnvironmentFile=$ETC/gateway-$P.env
ExecStart=$PY -m hermes_cli.main --profile $P gateway run
WorkingDirectory=$PERFIS_DIR/$P
Restart=always
RestartSec=5
RestartForceExitStatus=75
RestartPreventExitStatus=78
KillMode=mixed
KillSignal=SIGTERM
ExecStopPost=-$PY -m gateway.cgroup_cleanup
TimeoutStopSec=60
MemoryMax=600M
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SD/hermes-gateway-$P.service"
systemctl daemon-reload
systemctl enable "hermes-gateway-$P.service" >/dev/null 2>&1
systemctl restart "hermes-gateway-$P.service"
systemctl restart hermes-painel.service
for i in $(seq 1 40); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$API/health" && break; sleep 1; done
echo "ponte: $(systemctl is-active hermes-painel) · hermes do claude: $(systemctl is-active hermes-gateway-$P) (API em ~${i}s) · olx: $(systemctl is-active hermes-gateway-olx)"
