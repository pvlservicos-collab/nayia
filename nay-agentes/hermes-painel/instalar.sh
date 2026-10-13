#!/bin/bash
# Instala o painel dos Hermes na VPS2 (srv1877774). Roda LÁ, como root, pelo publicar.sh. Pode rodar de novo: o que já
# existe (segredos, cópia do Chrome) fica como está. Pedro, 13/10/2026.
#
# O que cria (tudo novo, nada do Hermes é editado):
#   /opt/hermes-painel/                 a ponte (ponte.py) e uma cópia do Chrome que o Hermes já tinha baixado
#   /etc/hermes-painel/                 perfis.json e os segredos (ponte.env, gateway-<perfil>.env), só root lê
#   hermes-painel.service               a ponte, só no endereço do Tailscale
#   hermes-chrome-<perfil>.service      o Chrome do perfil (usuário sem privilégio, teto de memória)
#   hermes-chrome-<perfil>-porta.socket a porta que acorda o Chrome na primeira ligação e o desliga após 20 min parado
#   hermes-gateway-<perfil>.service.d/painel.conf   liga a API local do Hermes e aponta o navegador dele para o Chrome
# Desfazer: ./instalar.sh desfazer
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
OPT=/opt/hermes-painel
ETC=/etc/hermes-painel
SD=/etc/systemd/system
PY=/usr/local/lib/hermes-agent/venv/bin/python
CHROME_ORIGEM=/root/.cache/ms-playwright/chromium-1208/chrome-linux64
# perfil  porta-da-API  porta-do-navegador  porta-interna-do-Chrome
PERFIS="telegram:8642:9301:9311 corretores:8643:9302:9312"

if [ "${1:-}" = desfazer ]; then
  for linha in $PERFIS; do
    p=${linha%%:*}
    systemctl disable --now "hermes-chrome-$p-porta.socket" 2>/dev/null || true
    systemctl stop "hermes-chrome-$p-porta.service" "hermes-chrome-$p.service" 2>/dev/null || true
    rm -f "$SD/hermes-chrome-$p.service" "$SD/hermes-chrome-$p-porta.service" "$SD/hermes-chrome-$p-porta.socket"
    rm -f "$SD/hermes-gateway-$p.service.d/painel.conf"; rmdir "$SD/hermes-gateway-$p.service.d" 2>/dev/null || true
  done
  systemctl disable --now hermes-painel.service 2>/dev/null || true
  rm -f "$SD/hermes-painel.service"
  systemctl daemon-reload
  echo "Desfeito. Ficaram /opt/hermes-painel, /etc/hermes-painel e /var/lib/hermes-chrome (apague à mão se quiser)."
  echo "Os gateways continuam com a API ligada até serem reiniciados."
  exit 0
fi

TS_IP=$(tailscale ip -4 | head -1)
[ -n "$TS_IP" ] || { echo "sem endereço do Tailscale: a ponte só sobe nele"; exit 1; }
[ -x "$PY" ] || { echo "não achei o Python do Hermes em $PY"; exit 1; }

mkdir -p "$OPT" "$ETC"
chmod 755 "$OPT"; chmod 700 "$ETC"
install -m 644 "$AQUI/ponte.py" "$OPT/ponte.py"
install -m 600 "$AQUI/perfis.json" "$ETC/perfis.json"

# O Chrome: cópia do que o Playwright do Hermes instalou. O serviço roda com usuário sem privilégio, que não entra em /root.
if [ ! -x "$OPT/chrome/chrome" ]; then
  [ -x "$CHROME_ORIGEM/chrome" ] || { echo "não achei o Chrome em $CHROME_ORIGEM"; exit 1; }
  cp -dR --preserve=mode,timestamps "$CHROME_ORIGEM" "$OPT/chrome"
  chmod -R u=rwX,go=rX "$OPT/chrome"
  echo "Chrome copiado para $OPT/chrome ($(du -sh "$OPT/chrome" | cut -f1))"
fi

# Segredos: nascem aqui e não são impressos.
if [ ! -s "$ETC/ponte.env" ]; then
  ( umask 077; printf 'PAINEL_TOKEN=%s\nPAINEL_HOST=%s\nPAINEL_PORTA=8650\n' "$(openssl rand -hex 32)" "$TS_IP" > "$ETC/ponte.env" )
  echo "segredo da ponte criado"
fi
sed -i "s/^PAINEL_HOST=.*/PAINEL_HOST=$TS_IP/" "$ETC/ponte.env"

cat > "$SD/hermes-painel.service" <<EOF
[Unit]
Description=Ponte do painel dos Hermes (admin › Agentes do site imobeasy.online)
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

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
for linha in $PERFIS; do
  IFS=: read -r p api cdp interna <<< "$linha"

  # --- o Chrome do perfil: usuário dinâmico (sem privilégio), pasta própria que guarda os logins, teto de memória
  cat > "$SD/hermes-chrome-$p.service" <<EOF
[Unit]
Description=Chrome do Hermes $p (painel admin › Agentes)
StopWhenUnneeded=yes

[Service]
Type=simple
DynamicUser=yes
StateDirectory=hermes-chrome/$p
Environment=HOME=/var/lib/hermes-chrome/$p TZ=America/Manaus LANG=pt_BR.UTF-8
ExecStart=$OPT/chrome/chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --no-first-run --no-default-browser-check --disable-background-networking --disable-sync --disable-extensions --disable-breakpad --disable-features=Translate,MediaRouter --password-store=basic --lang=pt-BR --window-size=1366,911 "--user-agent=$UA" --remote-debugging-address=127.0.0.1 --remote-debugging-port=$interna --remote-allow-origins=* --user-data-dir=/var/lib/hermes-chrome/$p/perfil about:blank
ExecStartPost=/usr/bin/timeout 20 /bin/sh -c 'until curl -s -m 1 -o /dev/null http://127.0.0.1:$interna/json/version; do sleep 0.25; done'
MemoryHigh=900M
MemoryMax=1100M
CPUWeight=50
OOMPolicy=stop
Restart=no
TimeoutStopSec=10
EOF

  # --- a porta: a primeira ligação (do Hermes ou da ponte) sobe o Chrome; 20 min sem ligação, desliga os dois
  cat > "$SD/hermes-chrome-$p-porta.socket" <<EOF
[Unit]
Description=Porta do Chrome do Hermes $p (acorda o navegador na primeira ligação)

[Socket]
ListenStream=127.0.0.1:$cdp

[Install]
WantedBy=sockets.target
EOF
  cat > "$SD/hermes-chrome-$p-porta.service" <<EOF
[Unit]
Description=Repasse da porta $cdp para o Chrome do Hermes $p
Requires=hermes-chrome-$p.service
After=hermes-chrome-$p.service

[Service]
ExecStart=/usr/lib/systemd/systemd-socket-proxyd --exit-idle-time=20min 127.0.0.1:$interna
PrivateTmp=yes
EOF

  # --- o gateway do Hermes: API local com senha e o navegador apontado para o Chrome acima (drop-in, o .env dele não muda)
  if [ ! -s "$ETC/gateway-$p.env" ]; then
    ( umask 077; printf 'API_SERVER_KEY=%s\nAPI_SERVER_HOST=127.0.0.1\nAPI_SERVER_PORT=%s\nBROWSER_CDP_URL=http://127.0.0.1:%s\n' "$(openssl rand -hex 32)" "$api" "$cdp" > "$ETC/gateway-$p.env" )
  fi
  mkdir -p "$SD/hermes-gateway-$p.service.d"
  cat > "$SD/hermes-gateway-$p.service.d/painel.conf" <<EOF
# Painel dos Hermes (admin › Agentes, 13/10/2026): liga a API local (127.0.0.1:$api) e manda o navegador do agente
# para o Chrome do painel (porta $cdp). Desfazer: apagar este arquivo, systemctl daemon-reload, reiniciar o serviço.
[Service]
EnvironmentFile=$ETC/gateway-$p.env
EOF
  chmod 644 "$SD/hermes-chrome-$p.service" "$SD/hermes-chrome-$p-porta.socket" "$SD/hermes-chrome-$p-porta.service" "$SD/hermes-gateway-$p.service.d/painel.conf"
done
chmod 644 "$SD/hermes-painel.service"

systemctl daemon-reload
for linha in $PERFIS; do
  IFS=: read -r p api cdp interna <<< "$linha"
  systemctl enable --now "hermes-chrome-$p-porta.socket" >/dev/null 2>&1 || { echo "não consegui ligar a porta do Chrome de $p"; exit 1; }
  # só reinicia o gateway se ele estiver no ar e ainda sem a API (o processo de hoje nasceu antes do drop-in)
  pid=$(systemctl show "hermes-gateway-$p" -p MainPID --value)
  if [ "${pid:-0}" != 0 ] && ! tr '\0' '\n' < "/proc/$pid/environ" | grep -q '^API_SERVER_KEY='; then
    echo "reiniciando hermes-gateway-$p para ligar a API local..."
    systemctl restart "hermes-gateway-$p"
  fi
done
systemctl enable hermes-painel.service >/dev/null 2>&1
systemctl restart hermes-painel.service
sleep 2
systemctl is-active hermes-painel.service | sed 's/^/ponte: /'
for linha in $PERFIS; do
  IFS=: read -r p api cdp interna <<< "$linha"
  printf 'gateway %s: %s · porta do navegador: %s\n' "$p" "$(systemctl is-active "hermes-gateway-$p")" "$(systemctl is-active "hermes-chrome-$p-porta.socket")"
done
