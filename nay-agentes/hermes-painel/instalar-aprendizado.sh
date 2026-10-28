#!/bin/bash
# Instala o Agente de Aprendizado (perfil `aprendizado` do Hermes) na VPS2. Roda LÁ, como root, pelo
# `publicar.sh aprendizado`. Pode rodar de novo.
#
# Pedro, 28/10/2026: "quero montar um agente do hermes focado em aprendizado, ele vai abrir esse site aqui
# https://tactiq.io/tools/youtube-transcript colar o link de um vídeo ... clicar em copiar e salvar essa transcrição
# ... em um documento de texto na raiz desse projeto, pode ser até uma pasta só com essas transcrições".
#   - navegador: o MESMO Chrome do Agente OLX, no PC do Pedro (túnel 127.0.0.1:9303). O tactiq barra Chrome sem janela
#     (reCAPTCHA, medido em 28/10), e é no PC que o arquivo tem de cair;
#   - ferramentas: as do olx + `transcricao` (mcp_transcricao.py), que clica em Copy e faz o Chrome do PC gravar o .txt
#     em transcricoes/ do nayia;
#   - não toca no perfil olx nem no hermes-gateway-olx; reinicia só a ponte, para ela ler o perfis.json novo.
# Desfazer: systemctl disable --now hermes-gateway-aprendizado; tirar "aprendizado" do perfis.json e rodar
# ./publicar.sh aprendizado de novo (ou o ./publicar.sh do olx).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
OPT=/opt/hermes-painel
ETC=/etc/hermes-painel
SD=/etc/systemd/system
PY=/usr/local/lib/hermes-agent/venv/bin/python
PERFIS_DIR=/root/.hermes/profiles
P=aprendizado
API=8646
CDP=9303

[ -x "$PY" ] || { echo "não achei o Python do Hermes em $PY"; exit 1; }
install -m 600 "$AQUI/perfis.json" "$ETC/perfis.json"
install -m 644 "$AQUI/mcp_transcricao.py" "$OPT/mcp_transcricao.py"

if [ ! -d "$PERFIS_DIR/$P" ]; then
  timeout 120 hermes profile create "$P" --no-alias --no-skills \
    --description "Agente de Aprendizado: salva transcrições de vídeos do YouTube (tactiq) no computador do Pedro." </dev/null 2>&1 | tail -3 | cut -c1-160
  [ -d "$PERFIS_DIR/$P" ] || { echo "o Hermes não criou o perfil $P"; exit 1; }
  echo "perfil $P criado"
fi
install -m 600 "$AQUI/alma-aprendizado.md" "$PERFIS_DIR/$P/SOUL.md"
"$PY" "$AQUI/configurar_perfil.py" "$PERFIS_DIR/$P"

if [ ! -s "$ETC/gateway-$P.env" ]; then
  ( umask 077; printf 'API_SERVER_KEY=%s\nAPI_SERVER_HOST=127.0.0.1\nAPI_SERVER_PORT=%s\nBROWSER_CDP_URL=http://127.0.0.1:%s\n' "$(openssl rand -hex 32)" "$API" "$CDP" > "$ETC/gateway-$P.env" )
fi
grep -q '^OPENAI_API_KEY=' "$ETC/gateway-telegram.env" 2>/dev/null || echo "ATENÇÃO: não achei a chave da OpenAI em $ETC/gateway-telegram.env; sem ela o agente não pensa"
cat > "$SD/hermes-gateway-$P.service" <<EOF
[Unit]
Description=Agente de Aprendizado (Hermes, perfil $P) do painel admin › Agentes
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
systemctl enable "hermes-gateway-$P.service" >/dev/null 2>&1
systemctl restart "hermes-gateway-$P.service"
systemctl restart hermes-painel.service
for i in $(seq 1 40); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$API/health" && break; sleep 1; done
echo "ponte: $(systemctl is-active hermes-painel) · aprendizado: $(systemctl is-active hermes-gateway-$P) (API em ~${i}s) · olx: $(systemctl is-active hermes-gateway-olx)"
