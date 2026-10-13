#!/bin/bash
# Roda na VPS2 (pelo publicar.sh telegram-luna): o Hermes Telegram passa a usar o mesmo modelo do Corretores
# (gpt-5.6-luna, direto na OpenAI). Motivo: o modelo antigo dele (tencent/hy3:free, pela Nous) está sem login e ele
# não respondia a nada desde pelo menos 04/10. Pedro, 13/10: "fique a vontade para trocar".
# O que muda: 3 linhas do bloco `model` do config.yaml do perfil telegram (cópia do que estava fica ao lado) e a chave
# da OpenAI, copiada do .env do perfil corretores para /etc/hermes-painel/gateway-telegram.env (o .env do perfil
# telegram não muda). Nada da chave é impresso.
set -euo pipefail
P=/root/.hermes/profiles
quando=$(date +%Y%m%d-%H%M%S)
cp -p $P/telegram/config.yaml $P/telegram/config.yaml.antes-do-painel-$quando
echo "cópia: config.yaml.antes-do-painel-$quando"
hermes --profile telegram config set model.default gpt-5.6-luna 2>&1 | tail -1 | cut -c1-160
hermes --profile telegram config set model.provider custom 2>&1 | tail -1 | cut -c1-160
hermes --profile telegram config set model.base_url https://api.openai.com/v1 2>&1 | tail -1 | cut -c1-160
echo "bloco model agora:"; awk '/^model:/{f=1;print;next} f&&/^[^ ]/{f=0} f{print}' $P/telegram/config.yaml
f=/etc/hermes-painel/gateway-telegram.env
if ! grep -q '^OPENAI_API_KEY=' "$f"; then
  cp -p "$f" "$f.antes-$quando"
  linha=$(grep -m1 -E '^OPENAI_API_KEY=.{20,}' $P/corretores/.env)
  [ -n "$linha" ] || { echo "não achei a chave no perfil corretores"; exit 1; }
  [ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" = '\n' ] || echo >> "$f"
  printf '%s\n' "$linha" >> "$f"
  echo "chave da OpenAI copiada do perfil corretores para $f"
fi
systemctl restart hermes-gateway-telegram
for i in $(seq 1 40); do curl -s -m 2 -o /dev/null http://127.0.0.1:8642/health && break; sleep 1; done
echo "gateway telegram: $(systemctl is-active hermes-gateway-telegram) · API respondeu depois de ~${i}s"
# uma pergunta curta, pela ponte, para ver se ele voltou a pensar
. /etc/hermes-painel/ponte.env
B="http://$PAINEL_HOST:$PAINEL_PORTA/agentes/telegram"
c() { curl -s -m 60 -H "X-Painel-Token: $PAINEL_TOKEN" -H "Content-Type: application/json" "$@"; }
run=$(c -X POST "$B/enviar" -d '{"texto":"Teste do painel. Responda apenas com a palavra: funcionando"}' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("run",""))')
for i in $(seq 1 30); do
  sleep 2
  s=$(c "$B/pulso?run=$run")
  echo "$s" | python3 -c 'import json,sys; r=json.load(sys.stdin)["run"]; sys.exit(0 if r["vivo"] else 1)' || break
done
echo "$s" | python3 -c 'import json,sys; r=json.load(sys.stdin)["run"]; print("resposta do Hermes Telegram:", r["status"], "|", (r["saida"] or r["erro"] or "")[:200])'
