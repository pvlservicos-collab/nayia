#!/bin/bash
# O medidor da VPS2 (srv1877774): mesmos passos do medir_agentes.sh, com os agentes de lá, sem banco. Escreve
# agentes2.json e manda para a VPS1, onde o admin lê (a VPS2 alcança a VPS1 por ssh; o contrário não).
set -u
LOCAL=/root/nay-agentes/agentes2.json
# destino: /docker/nay-site-web/public/admin/dados/agentes2.json na VPS1 (fixo na chave)
AGORA=$(date +%s)
NPROC=$(nproc)
MEM_TOTAL=$(awk '/MemTotal/{print $2*1024}' /proc/meminfo)
MEM_LIVRE=$(awk '/MemAvailable/{print $2*1024}' /proc/meminfo)
CARGA=$(cut -d' ' -f1-3 /proc/loadavg)
DISCO=$(df -B1 / | awk 'NR==2{print "{\"usado\":"$3",\"total\":"$2"}"}')
UPTIME=$(awk '{print int($1)}' /proc/uptime)

servico() {
  local n=$1 cpu mem desde ativo reinicios
  cpu=$(systemctl show "$n" -p CPUUsageNSec --value)
  mem=$(systemctl show "$n" -p MemoryCurrent --value)
  desde=$(systemctl show "$n" -p ActiveEnterTimestampMonotonic --value)
  ativo=$(systemctl show "$n" -p ActiveState --value)
  reinicios=$(systemctl show "$n" -p NRestarts --value)
  local desde_s=$(( AGORA - UPTIME + ${desde:-0} / 1000000 ))
  printf '{"id":"%s","tipo":"servico","ativo":%s,"cpu_s":%s,"mem":%s,"desde":%s,"reinicios":%s}' \
    "$n" "$([ "$ativo" = active ] && echo true || echo false)" \
    "$(awk -v c="${cpu:-0}" 'BEGIN{printf "%.1f", c/1e9}')" "${mem:-0}" "$desde_s" "${reinicios:-0}"
}
container() {
  local n=$1 id cg cpu mem desde ativo
  id=$(docker inspect -f '{{.Id}}' "$n" 2>/dev/null)
  if [ -z "$id" ]; then printf '{"id":"%s","tipo":"container","ativo":false,"cpu_s":0,"mem":0,"desde":0}' "$n"; return; fi
  cg=/sys/fs/cgroup/system.slice/docker-$id.scope
  cpu=$(awk '/usage_usec/{print $2}' "$cg/cpu.stat" 2>/dev/null)
  mem=$(cat "$cg/memory.current" 2>/dev/null)
  desde=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$n")" +%s)
  ativo=$(docker inspect -f '{{.State.Running}}' "$n")
  printf '{"id":"%s","tipo":"container","ativo":%s,"cpu_s":%s,"mem":%s,"desde":%s}' \
    "$n" "$ativo" "$(awk -v c="${cpu:-0}" 'BEGIN{printf "%.1f", c/1e6}')" "${mem:-0}" "$desde"
}
rotina() { local m; m=$(stat -c %Y "$2" 2>/dev/null || echo 0); printf '{"id":"%s","tipo":"rotina","ultima":%s}' "$1" "$m"; }

TMP=$(mktemp)
{
printf '{"medido_em":%s,"vps":{"nome":"VPS2 (srv1877774)","cpus":%s,"mem_total":%s,"mem_livre":%s,"carga":"%s","disco":%s},"hoje":{},"itens":[' \
  "$AGORA" "$NPROC" "$MEM_TOTAL" "$MEM_LIVRE" "$CARGA" "$DISCO"
for s in hermes-gateway-corretores hermes-gateway-telegram lembretes; do servico "$s"; printf ','; done
for c in n8n-captacao evolution-api evolution-postgres portal-corretor portal-postgres financas caddy-captacao; do container "$c"; printf ','; done
rotina lembretes_envio /opt/lembretes/logs/cron.log; printf ','
rotina lembrete_groq /root/lembrete_groq.log; printf ','
rotina backup_financas /var/log/backup_financas.log; printf ','
rotina backups_vps1 /srv/backups-nay-vps1
printf ']}\n'
} > "$TMP"
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP"; then
  # a chave da VPS2 na VPS1 só pode fazer UMA coisa: escrever este arquivo (command= no authorized_keys)
  mv "$TMP" "$LOCAL" && ssh -o BatchMode=yes -o ConnectTimeout=15 nay-srv1894338 < "$LOCAL"
else
  echo "JSON inválido"; rm -f "$TMP"
fi
