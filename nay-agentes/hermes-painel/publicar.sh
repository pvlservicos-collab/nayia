#!/bin/bash
# Publica o painel dos agentes de site (admin › Agentes). Uso (Git Bash, na raiz do nayia):
#   ./nay-agentes/hermes-painel/publicar.sh        VPS2: instala/atualiza a ponte e o agente OLX (perfil, alma, config, serviço)
#   ./nay-agentes/hermes-painel/publicar.sh vps1   VPS1, só na primeira vez: põe no compose da API do site o endereço da
#                                                  ponte e leva o segredo para o .env de lá (de servidor para servidor, sem imprimir)
#   ./scripts/nay site admin/agentes.html assets/js/agentes.js assets/js/hermes-painel.js assets/css/hermes-painel.css
#                                                  a rota /admin/api/hermes (reconstrói a API) e a tela
# Depois: mudou a ponte, a alma ou o config do agente → o primeiro comando. Mudou só a tela → ./scripts/nay estatico <arquivos>.
# O navegador do agente OLX não se publica: é o navegador-olx.bat, que roda no computador de quem usa.
set -euo pipefail
cd "$(dirname "$0")"
VPS2=nay-srv1877774
VPS1=nay-srv1894338
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
tar -cz ponte.py perfis.json instalar.sh alma-olx.md configurar_perfil.py | ssh -o ConnectTimeout=20 $VPS2 'rm -rf /root/hermes-painel-fonte && mkdir -p /root/hermes-painel-fonte && tar -xz -C /root/hermes-painel-fonte && sed -i "s/\r$//" /root/hermes-painel-fonte/* && bash /root/hermes-painel-fonte/instalar.sh'
