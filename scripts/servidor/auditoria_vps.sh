#!/bin/bash
# Auditoria do pacote de 02/10: o que está de fato implementado nas VPS. SÓ LEITURA.
# Uso: bash auditoria_vps.sh   (como root, em qualquer das duas VPS; cada seção só fala do que existe ali)
sec() { echo; echo "=== $* ==="; }
SQLITE3=/usr/local/lib/node_modules/n8n/node_modules/.pnpm/sqlite3@5.1.7/node_modules/sqlite3

sec "host"; hostname; date -u '+%F %T UTC'; uptime -p; uptime -s

if [ -d /docker/nay-core ]; then
  sec "A1 git do nay-core"
  cd /docker/nay-core && git remote -v | sed -E 's#//[^@/]+@#//***@#' | head -2
  echo "status (linhas): $(git status --porcelain | wc -l)"; git status --porcelain | head -5
  git log -1 --format='%h %ad %s' --date=iso
  sec "A9 containers do nay-core"
  for c in nay-core nay-core-worker nay-core-enviador; do
    docker inspect "$c" --format '{{.Name}} estado={{.State.Status}} saude={{if .State.Health}}{{.State.Health.Status}}{{else}}sem healthcheck{{end}} restart={{.HostConfig.RestartPolicy.Name}} desde={{.State.StartedAt}}' 2>/dev/null || echo "$c: não existe"
  done
  echo "MODO no .env: $(grep -E '^MODO=' .env | head -1 || true)$(grep -q '^MODO=' .env || echo '(sem a linha MODO: vale config/limites.yaml)')"
  docker exec nay-core curl -s http://127.0.0.1:8000/saude; echo
  sec "C2/C3 relatórios"
  ls -la relatorios | grep -E 'sombra|replay|classif' | awk '{print $5, $6, $7, $8, $9}'
fi

sec "E1 ssh"
sshd -T 2>/dev/null | grep -i -E '^(passwordauthentication|permitrootlogin|maxauthtries|x11forwarding) '
echo "fail2ban: $(systemctl is-active fail2ban 2>&1) / pacote: $(dpkg-query -W -f='${Status}' fail2ban 2>/dev/null || echo 'não instalado')"

sec "E2 firewall e quem escuta de fora"
ufw status verbose 2>&1 | head -3
ss -tlnp | awk 'NR>1 {print $4, $6}' | grep -v -E '127\.0\.0\.|\[::1\]|%lo' | sed -E 's/users:\(\("([^"]+)".*/\1/' | sort -u

sec "E3 túneis"
for c in nay-painel-tunnel nay-site-api-tunnel; do
  docker inspect "$c" --format '{{.Name}} estado={{.State.Status}} restart={{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || true
done

sec "E4 backups (o mais novo de cada)"
for p in /root/backups-banco/naydb-*.dump /root/backups-banco/crmdb-*.dump; do
  f=$(ls -t $p 2>/dev/null | head -1); [ -n "$f" ] && ls -la --time-style=long-iso "$f" | awk '{print $5, $6, $7, $8}'
done
echo "pastas em /srv/backups-nay-vps1: $(ls /srv/backups-nay-vps1 2>/dev/null | tr '\n' ' ')"
f=$(ls -d /srv/backups-nay-vps1/2* 2>/dev/null | tail -1); [ -n "$f" ] && ls -la --time-style=long-iso "$f" | awk 'NR>1 {print $5, $6, $7, $8}'
echo "rclone: $(command -v rclone || echo 'não instalado') | gpg de .env: $(ls /root/backups-para-fora/*/*.gpg /root/backup*/*.gpg 2>/dev/null | head -1 || true)$(ls /root/backups-para-fora/*/*.gpg 2>/dev/null | grep -q . || echo 'nenhum')"
echo "script que copia sqlite do n8n, mídia, fotos ou .env: $(grep -l -E 'database\.sqlite|crm/midia|nay-site-web/public|\.env' /root/nay-publicador/backup_*.sh /root/backup*.sh 2>/dev/null | tr '\n' ' ' || true)(vazio = nenhum)"
echo "script de backup próprio desta VPS: $(ls /root/backup*.sh /root/*/backup*.sh /etc/cron.d/*backup* 2>/dev/null | tr '\n' ' ')"
grep -h -i -E 'restaura|pg_restore' /root/infra-*/EXECUCAO.md 2>/dev/null | head -3

if docker ps --format '{{.Names}}' | grep -q '^nay-postgres$'; then
  sec "E5 postgres: erros nas últimas 24 h e na última hora"
  L=$(docker logs --since 24h nay-postgres 2>&1)
  for p in 'nai_fone_br(text) does not exist' 'is not assigned yet' 'permission denied' 'lead_activities_zapi_msgid_unique'; do
    echo "$p: 24h=$(echo "$L" | grep -c -F "$p") | última hora=$(docker logs --since 60m nay-postgres 2>&1 | grep -c -F "$p")"
  done
  echo "$L" | grep -F 'permission denied' | sed -E 's/.*(permission denied.*)/\1/' | sort | uniq -c | sort -rn | head -4
  docker exec nay-postgres psql -U nay -d naydb -Atc "SHOW log_min_duration_statement"
fi

sec "E6 crontab"
echo "ligar_nay_20260928: $(crontab -l 2>/dev/null | grep -c ligar_nay_20260928) linha(s)"
echo "linhas que jogam a saída em /dev/null:"
{ crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null; } | grep -v '^#' | grep '/dev/null' | sed -E 's/^([^ ]+ +){5}//' | cut -c1-110 | head -12
echo "alarme_crons: $({ crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null; } | grep -v '^#' | grep -i alarme_crons | cut -c1-120 || true)"

sec "E7 imagens, limite de memória e healthcheck"
docker ps --format '{{.Names}}' | while read -r c; do
  docker inspect "$c" --format '{{.Name}} imagem={{.Config.Image}} mem={{.HostConfig.Memory}} saude={{if .State.Health}}sim{{else}}não{{end}}'
done

sec "E8 reinício e pacotes"
echo "reboot-required: $([ -f /var/run/reboot-required ] && echo SIM || echo não) | kernel rodando: $(uname -r)"
echo "pacotes a atualizar: $(apt list --upgradable 2>/dev/null | grep -c upgradable)"

sec "E9 limpeza"
echo "/tmp: $(du -sh /tmp 2>/dev/null | cut -f1) | cópias do sqlite em /tmp: $(ls /tmp/*.sqlite 2>/dev/null | wc -l)"
docker system df 2>/dev/null | awk 'NR==1 || /Build/'
journalctl --disk-usage 2>/dev/null | tail -1

N8N=$(docker ps --format '{{.Names}}' | grep -E 'n8n' | head -1)
if [ -n "$N8N" ]; then
  sec "E10/F3 n8n ($N8N)"
  docker exec "$N8N" printenv | grep -E '^(EXECUTIONS_DATA_MAX_AGE|EXECUTIONS_DATA_PRUNE_MAX_COUNT|N8N_CONCURRENCY_PRODUCTION_LIMIT)='
  docker exec "$N8N" sh -c 'ls -la /home/node/.n8n/database.sqlite' | awk '{print "sqlite:", $5, "bytes"}'
  docker exec -i -e SQLITE3_PATH=$SQLITE3 "$N8N" node - <<'JS' 2>&1
const s = require(process.env.SQLITE3_PATH);
const db = new s.Database("/home/node/.n8n/database.sqlite", s.OPEN_READONLY);
db.all(`SELECT count(*) AS execucoes,
               round(avg((julianday(startedAt) - julianday(createdAt)) * 86400), 1) AS espera_media_s,
               round(max((julianday(startedAt) - julianday(createdAt)) * 86400), 0) AS espera_max_s,
               sum(CASE WHEN (julianday(startedAt) - julianday(createdAt)) * 86400 > 60 THEN 1 ELSE 0 END) AS mais_de_1_min
          FROM execution_entity WHERE startedAt IS NOT NULL AND createdAt > datetime('now', '-24 hours')`,
  (e, r) => { console.log("fila nas últimas 24 h:", e ? e.message : JSON.stringify(r[0]));
    db.all("SELECT name, active FROM workflow_entity ORDER BY active DESC, name", (e2, w) => {
      console.log("fluxos:", e2 ? e2.message : w.map(x => (x.active ? "[ATIVO] " : "[parado] ") + x.name).join(" | ")); db.close(); }); });
JS
fi

if docker ps -a --format '{{.Names}}' | grep -q '^portal-corretor$'; then
  sec "F1 portal do corretor"
  docker inspect portal-corretor --format 'estado={{.State.Status}} saude={{if .State.Health}}{{.State.Health.Status}}{{else}}sem{{end}} desde={{.State.StartedAt}}'
  docker inspect evolution-api --format 'evolution-api estado={{.State.Status}}' 2>/dev/null
  for h in app.imobeasy.online; do echo "$h -> $(curl -s -m 10 -o /dev/null -w '%{http_code}' https://$h/)"; done
  d=$(docker inspect portal-corretor --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'); echo "pasta: $d"
  ls "$d" 2>/dev/null | head -20 | tr '\n' ' '; echo
  grep -rhoE "(href|to)=\"/[a-z0-9/_-]+\"" "$d" --include=*.html --include=*.tsx --include=*.jsx --include=*.ejs --include=*.js 2>/dev/null | grep -v node_modules | sort | uniq -c | sort -rn | head -15
fi
