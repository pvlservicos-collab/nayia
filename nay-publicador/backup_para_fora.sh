#!/bin/bash
# Cópia diária PARA FORA desta VPS (30/09/2026).
#
# O QUE ISTO RESOLVE: até hoje o dump do banco ficava no MESMO disco da MESMA
# VPS (/root/backups-banco). Perder o disco era perder o banco e os backups
# juntos. Entrevista de 29/09, pergunta 54.
#
# O QUE VAI, todo dia, para a srv1877774 (pelo Tailscale): o dump do dia do
# naydb e do crmdb (feitos por backup_banco.sh às 23:05) -- as conversas da
# Nay e do CRM e o resto do banco, ~14 MB. O n8n NÃO vai: o Tel pediu cópia
# leve (30/09), e o sqlite dele tem ~165 MB por dia, quase tudo histórico de
# execuções. Os fluxos do n8n continuam só com os JSON exportados à mão.
#
# A CHAVE SÓ GRAVA. Do lado de lá ela é `rrsync -wo -no-del`, presa em
# /srv/backups-nay-vps1 e só aceita conexão do IP do Tailscale desta VPS: não
# lê, não apaga, não abre shell. Se esta VPS for invadida, quem entrar não
# consegue apagar os backups de lá. A limpeza dos antigos roda LÁ, num cron
# próprio (14 dias).
#
# Restaurar: copiar o .dump de volta e seguir o cabeçalho de backup_banco.sh
# (inclusive o passo de depois do restore).
set -euo pipefail

PROJETO=${PROJETO:-/root/nay-publicador}
BANCO_BK=${BANCO_BK:-/root/backups-banco}
LOCAL=${LOCAL:-/root/backups-para-fora}
DESTINO_HOST=root@100.113.222.11
CHAVE=/root/.ssh/backup_para_vps2
PASTA=${PASTA:-$(TZ=America/Manaus date +%Y%m%d)}

export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'
falha() { echo "[$(date "$CARIMBO")] ERRO: $*" >&2; exit 1; }

mkdir -p "$LOCAL/$PASTA"
chmod 700 "$LOCAL"

# 1. Os dumps do banco: os mais novos de cada um, e só se forem de menos de 26 h.
for b in naydb crmdb; do
    d=$(ls -t "$BANCO_BK"/$b-*.dump 2>/dev/null | head -1 || true)
    [ -n "$d" ] || falha "nenhum dump de $b em $BANCO_BK"
    [ -n "$(find "$d" -mmin -1560)" ] || falha "o dump mais novo de $b ($d) tem mais de 26 h"
    cp "$d" "$LOCAL/$PASTA/"
done

chmod 600 "$LOCAL/$PASTA"/*

# 2. Para fora. Sem --delete (a chave nem deixa): lá, só acrescenta.
rsync -a -e "ssh -i $CHAVE -o BatchMode=yes -o ConnectTimeout=20" \
      "$LOCAL/$PASTA/" "$DESTINO_HOST:$PASTA/" || falha "rsync para a srv1877774"

# 3. Aqui fica só a pasta de hoje (os dumps originais continuam em $BANCO_BK).
find "$LOCAL" -mindepth 1 -maxdepth 1 -type d ! -name "$PASTA" -exec rm -rf {} +

mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_backup_para_fora"
echo "[$(date "$CARIMBO")] copia para fora OK -- $PASTA: $(ls "$LOCAL/$PASTA" | wc -l) arquivos, $(du -sh "$LOCAL/$PASTA" | cut -f1)"
