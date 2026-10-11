#!/bin/bash
# Mede os agentes da VPS1 e escreve o JSON que a página Agentes do admin lê (Pedro, 11/10/2026: "cada quadrado um
# agente que nós temos e seus usos, e seus usos da VPS por dia"). Roda pelo cron a cada 5 min (nay-agentes.cron).
# Só leitura: systemd, cgroups do docker, mtime dos logs das rotinas e contagens de hoje no naydb.
set -u
SAIDA=/docker/nay-site-web/public/admin/dados/agentes.json
AGORA=$(date +%s)
NPROC=$(nproc)
MEM_TOTAL=$(awk '/MemTotal/{print $2*1024}' /proc/meminfo)
MEM_LIVRE=$(awk '/MemAvailable/{print $2*1024}' /proc/meminfo)
CARGA=$(cut -d' ' -f1-3 /proc/loadavg)
DISCO=$(df -B1 / | awk 'NR==2{print "{\"usado\":"$3",\"total\":"$2"}"}')
UPTIME=$(awk '{print int($1)}' /proc/uptime)

# ---- serviços systemd: cpu acumulada, memória agora, desde quando, estado
servico() {   # nome
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

# ---- containers docker: cpu do cgroup (usec), memória do cgroup, desde quando
container() {   # nome
  local n=$1 id cg cpu mem desde ativo
  id=$(docker inspect -f '{{.Id}}' "$n" 2>/dev/null)
  if [ -z "$id" ]; then
    printf '{"id":"%s","tipo":"container","ativo":false,"cpu_s":0,"mem":0,"desde":0}' "$n"
    return
  fi
  cg=/sys/fs/cgroup/system.slice/docker-$id.scope
  cpu=$(awk '/usage_usec/{print $2}' "$cg/cpu.stat" 2>/dev/null)
  mem=$(cat "$cg/memory.current" 2>/dev/null)
  desde=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$n")" +%s)
  ativo=$(docker inspect -f '{{.State.Running}}' "$n")
  printf '{"id":"%s","tipo":"container","ativo":%s,"cpu_s":%s,"mem":%s,"desde":%s}' \
    "$n" "$ativo" "$(awk -v c="${cpu:-0}" 'BEGIN{printf "%.1f", c/1e6}')" "${mem:-0}" "$desde"
}

# ---- rotinas (cron): a última vez que o log mexeu
rotina() {   # id, arquivo de log
  local m
  m=$(stat -c %Y "$2" 2>/dev/null || echo 0)
  printf '{"id":"%s","tipo":"rotina","ultima":%s}' "$1" "$m"
}

# ---- o que cada um fez HOJE (Manaus), no banco
HOJE="date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'"
BANCO=$(docker exec nay-postgres psql -U nay -d naydb -tA -c "
SELECT json_build_object(
  'core_turnos', (SELECT count(*) FROM core_turno WHERE criado_em >= $HOJE),
  'core_saidas', (SELECT count(*) FROM core_saida WHERE criado_em >= $HOJE AND estado = 'enviado'),
  'core_cards',  (SELECT count(*) FROM core_saida WHERE criado_em >= $HOJE AND estado = 'enviado' AND motivo = 'card'),
  'captacao_enviadas', (SELECT count(*) FROM captacao_mensagens WHERE criada_em >= $HOJE AND direcao = 'enviada' AND status <> 'Falhou'),
  'captacao_recebidas', (SELECT count(*) FROM captacao_mensagens WHERE criada_em >= $HOJE AND direcao = 'recebida'),
  'captacao_disparos', (SELECT count(*) FROM captacao_mensagens WHERE criada_em >= $HOJE AND direcao = 'enviada' AND origem = 'disparo' AND status <> 'Falhou'),
  'grupos_lidas', (SELECT count(*) FROM privado.grupo_mensagem_lida WHERE lida_em >= $HOJE),
  'grupos_pedidos', (SELECT count(*) FROM privado.grupo_pedido WHERE extraido_em >= $HOJE),
  'publicador_posts', (SELECT count(*) FROM envios_lista_grupo WHERE enviado_em >= $HOJE),
  'velha_turnos', (SELECT count(*) FROM nai_turno WHERE criado_em >= $HOJE),
  'velha_envios', (SELECT count(*) FROM envios WHERE enviado_em >= $HOJE),
  'imoveis_ofertaveis', (SELECT count(*) FROM core_imovel_busca WHERE ofertavel),
  'banco_mb', (SELECT round(pg_database_size('naydb') / 1048576.0))
)" 2>/dev/null)
[ -n "$BANCO" ] || BANCO='{}'

L=/root/nay-publicador/logs
TMP=$(mktemp)
{
printf '{"medido_em":%s,"vps":{"nome":"VPS1 (srv1894338)","cpus":%s,"mem_total":%s,"mem_livre":%s,"carga":"%s","disco":%s},' \
  "$AGORA" "$NPROC" "$MEM_TOTAL" "$MEM_LIVRE" "$CARGA" "$DISCO"
printf '"hoje":%s,"itens":[' "$BANCO"
for s in nay-captacao nay-grupos nay-publicador nay-enviador-manual; do servico "$s"; printf ','; done
for c in nay-core nay-core-worker nay-core-treino nay-core-enviador nay-site-api nay-site-web crm-imobeasy n8n-viux-n8n-1 nay-painel nay-postgres; do
  container "$c"; printf ','
done
rotina catalogo "$L/sincronizar_catalogo.log"; printf ','
rotina ficha "$L/ficha_do_anuncio.log"; printf ','
rotina backup "$L/backup_banco.log"; printf ','
rotina backup_fora "$L/backup_para_fora.log"; printf ','
rotina geocodificar "$L/geocodificar_novos.log"; printf ','
rotina etapas_crm "$L/sincronizar_etapas_crm.log"; printf ','
rotina visitas "$L/detectar_visitas.log"; printf ','
rotina pendencias "$L/ciclo_pendencias.log"; printf ','
rotina grade "$L/disparar_grade.log"; printf ','
rotina avisar_saidas "$L/avisar_saidas.log"; printf ','
rotina vigia /var/log/vigia_whatsapp.log
printf ']}\n'
} > "$TMP"
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP"; then
  mv "$TMP" "$SAIDA" && chmod 644 "$SAIDA"      # o mktemp cria 0600 e o nginx não lia (403)
else
  echo "JSON inválido, mantido o anterior"; rm -f "$TMP"
fi
