#!/bin/bash
# Instala o painel dos agentes de site na VPS2 (srv1877774). Roda LÁ, como root, pelo publicar.sh. Pode rodar de novo.
#
# 13/10/2026, à noite (Pedro: "TIRA ESSES hermes de la não vou usar, se tiver alguma função neles rodando hoje para
# tudo, quero que crie um para acessar esse site aqui https://conta.olx.com.br/acesso"):
#   - os gateways hermes-gateway-telegram e hermes-gateway-corretores são PARADOS e desligados do boot (os perfis e os
#     arquivos deles ficam no disco, intactos; para voltar: systemctl enable --now hermes-gateway-<perfil>);
#   - nasce o perfil `olx` do Hermes, só com ferramentas de navegador, e o serviço hermes-gateway-olx;
#   - o navegador do agente OLX NÃO fica aqui: a OLX bloqueia navegador de servidor (Cloudflare, "you have been
#     blocked"). Ele usa um Chrome no computador do Pedro, que chega por um túnel ssh na porta 127.0.0.1:9303
#     (navegador-olx.bat). Aqui só existe a porta.
#
# O que fica na VPS2:
#   /opt/hermes-painel/ponte.py         a ponte (serviço hermes-painel), só no endereço do Tailscale
#   /etc/hermes-painel/                 perfis.json e os segredos (ponte.env, gateway-*.env), só root lê
#   /root/.hermes/profiles/olx/         o perfil do agente (SOUL.md e config.yaml vêm deste repositório)
#   hermes-gateway-olx.service          o agente
# Desfazer: ./instalar.sh desfazer
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
OPT=/opt/hermes-painel
ETC=/etc/hermes-painel
SD=/etc/systemd/system
PY=/usr/local/lib/hermes-agent/venv/bin/python
PERFIS_DIR=/root/.hermes/profiles
P=olx
API=8644
CDP=9303
APOSENTADOS="telegram corretores"

if [ "${1:-}" = desfazer ]; then
  systemctl disable --now "hermes-gateway-$P.service" hermes-painel.service 2>/dev/null || true
  rm -f "$SD/hermes-gateway-$P.service" "$SD/hermes-painel.service"
  systemctl daemon-reload
  echo "Desfeito. Ficaram /opt/hermes-painel, /etc/hermes-painel e o perfil $PERFIS_DIR/$P (apague à mão se quiser)."
  exit 0
fi

TS_IP=$(tailscale ip -4 | head -1)
[ -n "$TS_IP" ] || { echo "sem endereço do Tailscale: a ponte só sobe nele"; exit 1; }
[ -x "$PY" ] || { echo "não achei o Python do Hermes em $PY"; exit 1; }

mkdir -p "$OPT" "$ETC"
chmod 755 "$OPT"; chmod 700 "$ETC"
install -m 644 "$AQUI/ponte.py" "$OPT/ponte.py"
install -m 600 "$AQUI/perfis.json" "$ETC/perfis.json"

if [ ! -s "$ETC/ponte.env" ]; then
  ( umask 077; printf 'PAINEL_TOKEN=%s\nPAINEL_HOST=%s\nPAINEL_PORTA=8650\n' "$(openssl rand -hex 32)" "$TS_IP" > "$ETC/ponte.env" )
  echo "segredo da ponte criado"
fi
sed -i "s/^PAINEL_HOST=.*/PAINEL_HOST=$TS_IP/" "$ETC/ponte.env"

cat > "$SD/hermes-painel.service" <<EOF
[Unit]
Description=Ponte do painel dos agentes de site (admin › Agentes do site imobeasy.online)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=$ETC/ponte.env
ExecStart=$PY $OPT/ponte.py
Restart=always
RestartSec=5
MemoryMax=250M

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SD/hermes-painel.service"

# --- 1) os Hermes antigos: param e saem do boot. Nada deles é apagado.
for velho in $APOSENTADOS; do
  if [ "$(systemctl is-active "hermes-gateway-$velho" 2>/dev/null)" = active ] || [ "$(systemctl is-enabled "hermes-gateway-$velho" 2>/dev/null)" = enabled ]; then
    systemctl disable --now "hermes-gateway-$velho" >/dev/null 2>&1 || true
    echo "hermes-gateway-$velho: parado e fora do boot"
  fi
  systemctl disable --now "hermes-chrome-$velho-porta.socket" >/dev/null 2>&1 || true
  systemctl stop "hermes-chrome-$velho-porta.service" "hermes-chrome-$velho.service" >/dev/null 2>&1 || true
  # o que o painel tinha posto para eles (o Chrome na VPS e a API local) sai junto
  rm -f "$SD/hermes-chrome-$velho.service" "$SD/hermes-chrome-$velho-porta.service" "$SD/hermes-chrome-$velho-porta.socket"
  rm -f "$SD/hermes-gateway-$velho.service.d/painel.conf"; rmdir "$SD/hermes-gateway-$velho.service.d" 2>/dev/null || true
done

# --- 2) o perfil do agente OLX
if [ ! -d "$PERFIS_DIR/$P" ]; then
  timeout 120 hermes profile create "$P" --no-alias --no-skills \
    --description "Agente da conta da OLX da Imob Easy: trabalha pelo navegador, guiado pelo Pedro na tela Agentes do admin." </dev/null 2>&1 | tail -3 | cut -c1-160
  [ -d "$PERFIS_DIR/$P" ] || { echo "o Hermes não criou o perfil $P"; exit 1; }
  echo "perfil $P criado"
fi
install -m 600 "$AQUI/alma-olx.md" "$PERFIS_DIR/$P/SOUL.md"
"$PY" "$AQUI/configurar_perfil.py" "$PERFIS_DIR/$P"

# --- 3) o serviço do agente. A API local tem senha própria (nasce aqui, não é impressa). A chave da OpenAI é a que o
#        Pedro pôs em 13/10 em gateway-telegram.env: o serviço LÊ aquele arquivo, nada é copiado. As variáveis de
#        gateway-olx.env vêm depois e valem por cima (porta da API, navegador).
if [ ! -s "$ETC/gateway-$P.env" ]; then
  ( umask 077; printf 'API_SERVER_KEY=%s\nAPI_SERVER_HOST=127.0.0.1\nAPI_SERVER_PORT=%s\nBROWSER_CDP_URL=http://127.0.0.1:%s\n' "$(openssl rand -hex 32)" "$API" "$CDP" > "$ETC/gateway-$P.env" )
fi
grep -q '^OPENAI_API_KEY=' "$ETC/gateway-telegram.env" 2>/dev/null || echo "ATENÇÃO: não achei a chave da OpenAI em $ETC/gateway-telegram.env; sem ela o agente não pensa"
cat > "$SD/hermes-gateway-$P.service" <<EOF
[Unit]
Description=Agente OLX (Hermes, perfil $P) do painel admin › Agentes
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
MemoryMax=700M
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SD/hermes-gateway-$P.service"

systemctl daemon-reload
systemctl enable "hermes-gateway-$P.service" hermes-painel.service >/dev/null 2>&1
systemctl restart "hermes-gateway-$P.service"
systemctl restart hermes-painel.service
for i in $(seq 1 40); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$API/health" && break; sleep 1; done
echo "ponte: $(systemctl is-active hermes-painel.service) · agente $P: $(systemctl is-active "hermes-gateway-$P") (API respondeu em ~${i}s)"
for velho in $APOSENTADOS; do echo "hermes-gateway-$velho: $(systemctl is-active "hermes-gateway-$velho" 2>/dev/null || true) / $(systemctl is-enabled "hermes-gateway-$velho" 2>/dev/null || true)"; done
