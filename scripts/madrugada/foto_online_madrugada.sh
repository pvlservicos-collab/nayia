#!/bin/sh
# AS FOTOS DO SITE NOVO PASSANDO NA CONFERÊNCIA, DE MADRUGADA (01/10/2026).
# Mesmo procedimento do espelho-madrugada (/root/espelho_madrugada.sh, 29/09):
# roda uma vez pelo /etc/cron.d/foto-online-madrugada e se apaga.
#
# O que muda: só o nó "Conferir cabeçalho" do fluxo NaiAtendLocacao1
# (/root/patch_foto_online_n8n.py) -- passa a aceitar a foto que mora em
# imobeasy.online/fotos/<codigo>/ e em fotos-captacao/olx/<codigo>/, conferindo
# o código no caminho. Eram 18 imóveis com a foto barrada como foto_sem_codigo.
#
# Travas: só entre 1h e 5h de Manaus; só com a Nay parada (nada em 3 min e nada
# "Recebido" na fila) -- espera até 60 min; backup antes; e se os fluxos não
# voltarem ativos, devolve o backup sozinho.
LOG=/root/foto_online_madrugada.log
WF=NaiAtendLocacao1
N8N=n8n-viux-n8n-1
TS=$(date +%Y%m%d_%H%M)
BK=/root/backups-n8n/bk_${TS}_antes_foto_online.json
NOVO=/root/nai_foto_online.json
exec >> "$LOG" 2>&1
echo "=== $(TZ=America/Manaus date '+%d/%m %H:%M') Manaus: começando"
rm -f /etc/cron.d/foto-online-madrugada   # uma vez só

H=$(TZ=America/Manaus date +%H)
if [ "$H" -lt 1 ] || [ "$H" -ge 5 ]; then echo "fora da madrugada ($H h): não fiz nada"; exit 0; fi

sql() { docker exec nay-postgres psql -U nay -d naydb -At -c "$1"; }

# a Nay parada?
for i in $(seq 1 60); do
  RECENTES=$(sql "SELECT count(*) FROM mensagens WHERE criada_em > now() - interval '3 min'")
  FILA=$(sql "SELECT count(*) FROM mensagens WHERE status = 'Recebido' AND criada_em > now() - interval '1 day'")
  if [ "$RECENTES" = "0" ] && [ "$FILA" = "0" ]; then break; fi
  echo "movimento (recentes=$RECENTES fila=$FILA), espero 1 min"
  sleep 60
done
if [ "$RECENTES" != "0" ] || [ "$FILA" != "0" ]; then echo "a Nay não parou em 60 min: desisti, nada mudou"; exit 1; fi

# backup e patch (o patch é sobre o fluxo VIVO, nunca sobre um JSON do repositório)
mkdir -p /root/backups-n8n
docker exec $N8N n8n export:workflow --id=$WF --output=/tmp/bk_foto.json >/dev/null 2>&1
docker cp $N8N:/tmp/bk_foto.json "$BK" || { echo "backup falhou: desisti"; exit 1; }
python3 /root/patch_foto_online_n8n.py "$BK" "$NOVO" || { echo "patch falhou: desisti, nada mudou"; exit 1; }

importar() {
  docker cp "$1" $N8N:/tmp/importar.json
  docker exec $N8N n8n import:workflow --input=/tmp/importar.json
  docker exec $N8N n8n update:workflow --id=$WF --active=true
  docker stop -t 40 $N8N && docker start $N8N
  # espera os fluxos voltarem (até 3 min): o import derruba o webhook
  for i in $(seq 1 36); do
    sleep 5
    L=$(docker logs --since 4m $N8N 2>&1)
    if echo "$L" | grep -q "Activated workflow \"NAI atendimento locação\"" && echo "$L" | grep -q "Activated workflow \"Nay- recebe mensagem\""; then return 0; fi
  done
  return 1
}

echo "importando o fluxo com a conferência nova"
if importar "$NOVO"; then
  echo "OK: fluxos ativos com a foto do site novo liberada (backup em $BK)"
  docker logs --since 4m $N8N 2>&1 | grep "Activated workflow"
else
  echo "FALHOU a volta dos fluxos: devolvendo o backup"
  if importar "$BK"; then echo "backup devolvido, fluxos ativos (como antes)"; else echo "ATENÇÃO: nem o backup voltou -- olhar o n8n"; fi
  exit 1
fi
echo "=== fim $(TZ=America/Manaus date '+%H:%M')"
