#!/bin/sh
# CAPTAÇÃO SEM O AGENTE VELHO, DE MADRUGADA (Pedro, 31/10/2026: "tire tudo do n8n"; plano, etapa 1).
# Roda na VPS da captação (srv1877774) uma vez, pelo /etc/cron.d/captacao-sem-agente-madrugada, e se apaga.
# O patch é /root/patch_captacao_sem_agente.py (ver o cabeçalho). Também desativa "Nay - escalar (captacao)", que só
# o agente velho chamava. Mesmas travas do captacao_imagem_madrugada.sh de 03/10: só entre 1h e 5h de Manaus,
# backup antes, o patch para se uma âncora não bater, e se o fluxo não voltar ativo devolve o backup.
LOG=/root/captacao_sem_agente_madrugada.log
FLUXO=CjsUJefRYcQIIi1F
ESCALAR=NayEscCaptacao01
TS=$(date +%Y%m%d_%H%M)
BK=/root/backups-n8n-captacao/bk_${TS}_antes_sem_agente.json
NOVO=/root/captacao_sem_agente.json
exec >> "$LOG" 2>&1
echo "=== $(TZ=America/Manaus date '+%d/%m %H:%M') Manaus: começando"
rm -f "$NOVO"
rm -f /etc/cron.d/captacao-sem-agente-madrugada   # uma vez só

H=$(TZ=America/Manaus date +%H)
if [ "${AGORA:-}" = "1" ]; then echo "AGORA=1: rodando fora da janela ($H h), por ordem"
elif [ "$H" -lt 1 ] || [ "$H" -ge 5 ]; then echo "fora da madrugada ($H h): não fiz nada"; exit 0; fi

N8N=n8n-captacao
docker ps --format '{{.Names}}' | grep -qx "$N8N" || { echo "container $N8N não está de pé: desisti"; exit 1; }

mkdir -p /root/backups-n8n-captacao
docker exec $N8N n8n export:workflow --id=$FLUXO --output=/tmp/bk_sem_agente.json >/dev/null 2>&1
docker cp $N8N:/tmp/bk_sem_agente.json "$BK" || { echo "backup falhou: desisti"; exit 1; }
python3 /root/patch_captacao_sem_agente.py "$BK" "$NOVO" || { echo "patch não aplicou: nada mudou"; exit 1; }

ATIVOS=$(docker exec $N8N n8n list:workflow --active=true --onlyId 2>/dev/null | grep -E '^[A-Za-z0-9]+$' | grep -vx "$ESCALAR")
QUANTOS=$(echo "$ATIVOS" | grep -c .)
echo "ficam ativos ($QUANTOS): $(echo $ATIVOS | tr '\n' ' ')"
echo "$ATIVOS" | grep -qx "$FLUXO" || { echo "o fluxo da captação não está ativo agora: desisti"; exit 1; }

importar() {
  docker cp "$1" $N8N:/tmp/importar.json
  docker exec $N8N n8n import:workflow --input=/tmp/importar.json
  docker exec $N8N n8n update:workflow --id=$ESCALAR --active=false >/dev/null 2>&1 || echo "não desativou $ESCALAR"
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

echo "importando o fluxo da captação sem o agente velho"
if importar "$NOVO"; then
  echo "OK: captação sem o agente velho (backup em $BK)"
  docker logs --since 4m $N8N 2>&1 | grep "Activated workflow"
else
  echo "FALHOU a volta do fluxo: devolvendo o backup"
  if importar "$BK"; then echo "backup devolvido, fluxo ativo (como antes)"; else echo "ATENÇÃO: nem o backup voltou -- olhar o n8n da captação"; fi
  exit 1
fi
