#!/bin/bash
# Publica o painel dos Hermes (admin › Agentes). Uso (Git Bash, na raiz do nayia), nesta ordem na primeira vez:
#   ./nay-agentes/hermes-painel/publicar.sh        VPS2: instala/atualiza a ponte, o Chrome de cada perfil e a API local dos Hermes
#   ./nay-agentes/hermes-painel/publicar.sh vps1   VPS1: põe no compose da API do site o endereço da ponte e leva o segredo
#                                                  para o .env de lá (de servidor para servidor, sem imprimir)
#   ./scripts/nay site admin/agentes.html assets/js/agentes.js assets/js/hermes-painel.js assets/css/hermes-painel.css
#                                                  a rota /admin/api/hermes (reconstrói a API) e a tela
# Depois, para mudar só a ponte: o primeiro comando. Para mudar só a tela: ./scripts/nay estatico <arquivos>.
#   ./nay-agentes/hermes-painel/publicar.sh telegram-luna   VPS2: troca o modelo do Hermes Telegram para o luna
#                                                  (copia a chave da OpenAI do perfil corretores; ver telegram_luna.sh)
set -euo pipefail
cd "$(dirname "$0")"
VPS2=nay-srv1877774
VPS1=nay-srv1894338
if [ "${1:-}" = telegram-luna ]; then
  tr -d '' < telegram_luna.sh | ssh -o ConnectTimeout=20 $VPS2 'bash -s'
  exit 0
fi
if [ "${1:-}" = vps1 ]; then
  tr -d '\r' < vps1_compose.sh | ssh -o ConnectTimeout=20 $VPS1 'bash -s'
  # o segredo passa de uma VPS para a outra por dentro do cano; nada dele aparece na tela
  ssh -o ConnectTimeout=20 $VPS2 "grep '^PAINEL_TOKEN=' /etc/hermes-painel/ponte.env" | tr -d '\r' \
    | ssh -o ConnectTimeout=20 $VPS1 'read -r linha; v=${linha#PAINEL_TOKEN=}; [ ${#v} -ge 32 ] || { echo "segredo vazio"; exit 1; }
        f=/docker/nay-site-api/.env; cp -p "$f" "$f.bk-$(date +%Y%m%d-%H%M)"
        [ "$(tail -c1 "$f" | od -An -c | tr -d " ")" = "\\n" ] || echo >> "$f"
        if grep -q "^HERMES_PAINEL_TOKEN=" "$f"; then sed -i "s/^HERMES_PAINEL_TOKEN=.*/HERMES_PAINEL_TOKEN=$v/" "$f"; else printf "HERMES_PAINEL_TOKEN=%s\n" "$v" >> "$f"; fi
        echo "segredo gravado no .env da API do site ($(grep -c "^HERMES_PAINEL_TOKEN=" "$f") linha)"'
  echo "Falta reconstruir a API para ela ler as variáveis: ./scripts/nay site admin/agentes.html ..."
  exit 0
fi
tar -cz ponte.py perfis.json instalar.sh | ssh -o ConnectTimeout=20 $VPS2 'rm -rf /root/hermes-painel-fonte && mkdir -p /root/hermes-painel-fonte && tar -xz -C /root/hermes-painel-fonte && sed -i "s/\r$//" /root/hermes-painel-fonte/* && bash /root/hermes-painel-fonte/instalar.sh'
