#!/bin/sh
# CAPTAÇÃO: FOTO SOZINHA NÃO PARA O ATENDIMENTO, DE MADRUGADA (Pedro, 03/10/2026).
# Roda na VPS da captação (srv1877774), uma vez, pelo /etc/cron.d/captacao-imagem-madrugada, e se apaga.
# O patch é /root/patch_captacao_imagem_continua.py (ver o cabeçalho dele): lote só de foto segue com a pergunta
# do cadastro sem comentar a foto, o Tel continua avisado, e a frase "não consigo ver a imagem" nunca sai.
#
# Travas: só entre 1h e 5h de Manaus (AGORA=1 dispensa, só com ordem de quem manda); backup antes; o patch
# para tudo se uma âncora não bater; e se o fluxo não voltar ativo, devolve o backup sozinho.
# O n8n parado ~40 s mata as esperas curtas em andamento: a mensagem fica 'Recebido' e o "Cron da fila parada"
# (2 min) responde.
LOG=/root/captacao_imagem_madrugada.log
FLUXO=CjsUJefRYcQIIi1F
TS=$(date +%Y%m%d_%H%M)
BK=/root/backups-n8n-captacao/bk_${TS}_antes_imagem_continua.json
NOVO=/root/captacao_imagem_continua.json
exec >> "$LOG" 2>&1
echo "=== $(TZ=America/Manaus date '+%d/%m %H:%M') Manaus: começando"
rm -f "$NOVO"
rm -f /etc/cron.d/captacao-imagem-madrugada   # uma vez só

H=$(TZ=America/Manaus date +%H)
if [ "${AGORA:-}" = "1" ]; then echo "AGORA=1: rodando fora da janela ($H h), por ordem"
elif [ "$H" -lt 1 ] || [ "$H" -ge 5 ]; then echo "fora da madrugada ($H h): não fiz nada"; exit 0; fi

N8N=n8n-captacao
docker ps --format '{{.Names}}' | grep -qx "$N8N" || { echo "container $N8N não está de pé: desisti"; exit 1; }

mkdir -p /root/backups-n8n-captacao
docker exec $N8N n8n export:workflow --id=$FLUXO --output=/tmp/bk_imagem.json >/dev/null 2>&1
docker cp $N8N:/tmp/bk_imagem.json "$BK" || { echo "backup falhou: desisti"; exit 1; }
python3 /root/patch_captacao_imagem_continua.py "$BK" "$NOVO" || { echo "patch não aplicou: nada mudou"; exit 1; }

ATIVOS=$(docker exec $N8N n8n list:workflow --active=true --onlyId 2>/dev/null | grep -E '^[A-Za-z0-9]+$')
QUANTOS=$(echo "$ATIVOS" | grep -c .)
echo "ativos agora ($QUANTOS): $(echo $ATIVOS | tr '\n' ' ')"
echo "$ATIVOS" | grep -qx "$FLUXO" || { echo "o fluxo da captação não está ativo agora: desisti (não ligo o que estava desligado)"; exit 1; }

importar() {
  docker cp "$1" $N8N:/tmp/importar.json
  docker exec $N8N n8n import:workflow --input=/tmp/importar.json
  for id in $ATIVOS; do
    docker exec $N8N n8n update:workflow --id=$id --active=true >/dev/null 2>&1 || echo "não religou $id"
  done
  docker stop -t 40 $N8N && docker start $N8N
  for i in $(seq 1 48); do
    sleep 5
    VOLTOU=$(docker logs --since 5m $N8N 2>&1 | grep -c "Activated workflow")
    if [ "$VOLTOU" -ge "$QUANTOS" ]; then return 0; fi
  done
  return 1
}

echo "importando o fluxo da captação com o patch"
if importar "$NOVO"; then
  echo "OK: captação ativa com a foto que não para o atendimento (backup em $BK)"
  docker logs --since 4m $N8N 2>&1 | grep "Activated workflow"
else
  echo "FALHOU a volta do fluxo: devolvendo o backup"
  if importar "$BK"; then echo "backup devolvido, fluxo ativo (como antes)"; else echo "ATENÇÃO: nem o backup voltou -- olhar o n8n da captação"; fi
  exit 1
fi
echo "=== fim $(TZ=America/Manaus date '+%H:%M')"
