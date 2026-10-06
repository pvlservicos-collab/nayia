#!/bin/bash
# Wrapper de cron para geocodificar_imoveis.py, no molde dos outros (cron nao
# carrega .env sozinho; "set -a" exporta o que o arquivo define).
#
# O MAPA SE ATUALIZA SOZINHO (Pedro, 06/10/2026: "o mapa nao esta atualizando
# com os imoveis do site novo, precisa atualizar certinho"). Ate aqui o ponto
# de cada imovel (imovel_geo) so entrava em rodada feita a mao: os 20 imoveis
# cadastrados pelo site novo desde 29/09 ficaram uma semana fora do mapa.
#
# Roda de hora em hora: so localiza quem ainda NAO tem ponto (o script ja e
# assim), e o Nominatim aceita 1 consulta por segundo -- meia duzia de imoveis
# novos por dia sao segundos. Os bairros ao redor (imovel_bairro_ao_redor) sao
# refeitos so quando entrou imovel novo, porque esse passo reescreve a tabela
# inteira (~26 mil linhas, uns 30 s).
#
# O flock do cron impede duas rodadas ao mesmo tempo.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'
echo "== $(date '+%Y-%m-%dT%H:%M:%S%z')"

SAIDA=$(.venv/bin/python geocodificar_imoveis.py imoveis 2>&1) || { echo "$SAIDA"; echo "FALHOU: imoveis"; exit 1; }
echo "$SAIDA"

# Sem ninguem localizado nesta rodada (ha imoveis antigos sem endereco que ficam
# "para localizar" para sempre e saem como 'sem'), os bairros ao redor ficam como estao.
if echo "$SAIDA" | grep -q "^fim: {'condominio': 0, 'rua': 0, 'bairro': 0,"; then
  exit 0
fi
.venv/bin/python geocodificar_imoveis.py ao-redor 2>&1 || { echo "FALHOU: ao-redor"; exit 1; }
