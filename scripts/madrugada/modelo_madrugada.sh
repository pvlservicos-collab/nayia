#!/bin/sh
# TODOS OS NÓS DO n8n NO gpt-6-luna, DE MADRUGADA (Pedro, 01/10/2026).
# Mesmo procedimento do espelho e da foto: roda uma vez pelo
# /etc/cron.d/modelo-madrugada e se apaga.
#
# Serve nas DUAS VPS: ele descobre o container do n8n e troca o modelo de TODOS
# os fluxos de uma vez (export --all -> patch -> import). Na VPS da Nay espera a
# Nay parar; na VPS da captação não há o que esperar (o disparo é de 30 em 30
# min e o import leva segundos), então a trava da fila é dispensada quando a
# tabela `mensagens` não existe ali.
#
# Travas: só entre 1h e 5h de Manaus; backup antes; e se os fluxos não voltarem
# ativos, devolve o backup sozinho.
LOG=/root/modelo_madrugada.log
MODELO=gpt-6-luna
TS=$(date +%Y%m%d_%H%M)
BK=/root/backups-n8n/bk_${TS}_antes_modelo.json
NOVO=/root/n8n_modelo_novo.json
NOVO2=/root/n8n_modelo_e_imagem.json
exec >> "$LOG" 2>&1
echo "=== $(TZ=America/Manaus date '+%d/%m %H:%M') Manaus: começando ($MODELO)"
rm -f "$NOVO" "$NOVO2"   # sobra de tentativa anterior não entra no import
rm -f /etc/cron.d/modelo-madrugada   # uma vez só

H=$(TZ=America/Manaus date +%H)
if [ "$H" -lt 1 ] || [ "$H" -ge 5 ]; then echo "fora da madrugada ($H h): não fiz nada"; exit 0; fi

N8N=$(docker ps --format '{{.Names}}' | grep -i n8n | head -1)
if [ -z "$N8N" ]; then echo "não achei o container do n8n: desisti"; exit 1; fi
echo "container: $N8N"

# a Nay parada? (só onde existe a fila dela)
if docker exec nay-postgres psql -U nay -d naydb -At -c "SELECT 1 FROM mensagens LIMIT 1" >/dev/null 2>&1; then
  sql() { docker exec nay-postgres psql -U nay -d naydb -At -c "$1"; }
  for i in $(seq 1 60); do
    RECENTES=$(sql "SELECT count(*) FROM mensagens WHERE criada_em > now() - interval '3 min'")
    FILA=$(sql "SELECT count(*) FROM mensagens WHERE status = 'Recebido' AND criada_em > now() - interval '1 day'")
    if [ "$RECENTES" = "0" ] && [ "$FILA" = "0" ]; then break; fi
    echo "movimento (recentes=$RECENTES fila=$FILA), espero 1 min"
    sleep 60
  done
  if [ "$RECENTES" != "0" ] || [ "$FILA" != "0" ]; then echo "a Nay não parou em 60 min: desisti, nada mudou"; exit 1; fi
else
  echo "sem a fila da Nay aqui (VPS da captação): sigo sem esperar"
fi

mkdir -p /root/backups-n8n
docker exec $N8N n8n export:workflow --all --output=/tmp/bk_modelo.json >/dev/null 2>&1
docker cp $N8N:/tmp/bk_modelo.json "$BK" || { echo "backup falhou: desisti"; exit 1; }
python3 /root/patch_modelo_n8n.py "$BK" "$NOVO" "$MODELO" || { echo "patch do modelo falhou (ou não havia o que trocar): nada mudou"; exit 1; }

# a Nay não lê mais imagem (Pedro, 01/10). Onde não há o ramo, o script diz
# "nada a fazer" e sai 0; se uma âncora não bater, ele para tudo.
python3 /root/patch_sem_ler_imagem.py "$NOVO" "$NOVO2" || { echo "patch da imagem falhou: nada mudou"; exit 1; }
if [ -f "$NOVO2" ]; then NOVO="$NOVO2"; fi

# QUEM ESTAVA ATIVO: o import desativa os fluxos, e sem religar um por um a Nay
# fica muda. Guardo os ids ANTES de qualquer coisa.
ATIVOS=$(docker exec $N8N n8n list:workflow --active=true --onlyId 2>/dev/null | grep -E '^[A-Za-z0-9]+$')
QUANTOS=$(echo "$ATIVOS" | grep -c .)
echo "ativos agora ($QUANTOS): $(echo $ATIVOS | tr '
' ' ')"
if [ "$QUANTOS" -lt 1 ]; then echo "não consegui listar os ativos: desisti"; exit 1; fi

importar() {
  docker cp "$1" $N8N:/tmp/importar.json
  docker exec $N8N n8n import:workflow --input=/tmp/importar.json
  for id in $ATIVOS; do
    docker exec $N8N n8n update:workflow --id=$id --active=true >/dev/null 2>&1 || echo "não religou $id"
  done
  docker stop -t 40 $N8N && docker start $N8N
  # espera voltar: tantos "Activated workflow" quantos estavam ativos
  for i in $(seq 1 48); do
    sleep 5
    VOLTOU=$(docker logs --since 5m $N8N 2>&1 | grep -c "Activated workflow")
    if [ "$VOLTOU" -ge "$QUANTOS" ]; then return 0; fi
  done
  return 1
}

echo "importando os fluxos com o modelo novo"
if importar "$NOVO"; then
  echo "OK: fluxos ativos com $MODELO (backup em $BK)"
  docker logs --since 4m $N8N 2>&1 | grep "Activated workflow"
else
  echo "FALHOU a volta dos fluxos: devolvendo o backup"
  if importar "$BK"; then echo "backup devolvido, fluxos ativos (como antes)"; else echo "ATENÇÃO: nem o backup voltou -- olhar o n8n"; fi
  exit 1
fi
echo "=== fim $(TZ=America/Manaus date '+%H:%M')"
