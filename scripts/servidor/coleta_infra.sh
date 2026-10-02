#!/bin/bash
# COLETA DE INFRAESTRUTURA, SÓ LEITURA (Pedro, 02/10/2026).
# Não reinicia nada, não muda config, não roda apt nem docker rm/prune. A única
# coisa que escreve é a pasta do próprio relatório: /root/infra-<data>/bruto/.
# Serve nas duas VPS: o que não existe numa delas sai como "NAO HA".
# Segredos não entram: de variável de ambiente só sai o NOME (e o valor apenas
# dos limites e da poda do n8n); labels do Traefik saem com usuário/senha redigidos.
# Uso: bash coleta_infra.sh        (como root)
export LC_ALL=C
D=/root/infra-$(TZ=America/Manaus date +%F)
B=$D/bruto
mkdir -p "$B"
N8N=$(docker ps --format '{{.Names}}' | grep -i n8n | head -1)
PG=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
SQLITE3=/usr/local/lib/node_modules/n8n/node_modules/.pnpm/sqlite3@5.1.7/node_modules/sqlite3
mascara() { sed -E 's/(sk-|eyJ)[A-Za-z0-9._-]{12,}/<REDIGIDO>/g; s/([Pp]assword|PASSWORD|[Tt]oken|TOKEN|[Ss]ecret|SECRET|[Ss]enha|CHAVE|KEY)=[^ ,"]+/\1=<REDIGIDO>/g; s/(basicauth\.users=)[^ ,"]+/\1<REDIGIDO>/g; s/\b55[0-9]{6,7}([0-9]{4})\b/[tel ...\1]/g'; }
sec() { echo; echo "##### $1"; }

# ---------------------------------------------------------------- 1. MÁQUINA
{
sec "hostname / data"; hostname; date; TZ=America/Manaus date '+Manaus: %F %T'
sec "nproc"; nproc
sec "free -h"; free -h
sec "swapon --show"; swapon --show || true; [ -z "$(swapon --show)" ] && echo "(sem swap)"
sec "df -h"; df -h -x tmpfs -x devtmpfs -x overlay
sec "df -i"; df -i -x tmpfs -x devtmpfs -x overlay
sec "uptime"; uptime
sec "loadavg"; cat /proc/loadavg
sec "pressure"; for f in cpu memory io; do echo "-- $f"; cat /proc/pressure/$f 2>/dev/null || echo "NAO HA"; done
sec "oom no dmesg"; dmesg -T 2>/dev/null | grep -i -E "oom|killed process" | tail -20; echo "total: $(dmesg -T 2>/dev/null | grep -c -i -E 'oom|killed process')"
sec "sysstat"; systemctl is-active sysstat 2>/dev/null; ls -la /var/log/sysstat 2>/dev/null | tail -12
} > "$B/01-maquina.txt" 2>&1

# sar: por dia, a média e o pico (com a hora) de CPU, memória e carga
{
for f in $(ls -t /var/log/sysstat/sa[0-9]* 2>/dev/null | head -8 | tac); do
  dia=$(sar -u -f "$f" 2>/dev/null | head -1 | awk '{print $4}')
  echo "== $dia ($(basename "$f"))"
  sar -u -f "$f" 2>/dev/null | awk '$1 ~ /^[0-9][0-9]:/ && $NF ~ /^[0-9.]+$/ && $2 == "all" {u = 100 - $NF; s += u; n++; if (u > m) {m = u; h = $1}} END {if (n) printf "  CPU   media %.1f%%  pico %.1f%% as %s (UTC)  amostras %d\n", s/n, m, h, n}'
  sar -r -f "$f" 2>/dev/null | awk '$1 ~ /^[0-9][0-9]:/ && $5 ~ /^[0-9.]+$/ {s += $5; n++; if ($5 > m) {m = $5; h = $1}} END {if (n) printf "  MEM   media %.1f%% usada  pico %.1f%% as %s (UTC)\n", s/n, m, h}'
  sar -q -f "$f" 2>/dev/null | awk '$1 ~ /^[0-9][0-9]:/ && $4 ~ /^[0-9.]+$/ {s += $4; n++; if ($4 > m) {m = $4; h = $1}} END {if (n) printf "  LOAD1 media %.2f  pico %.2f as %s (UTC)\n", s/n, m, h}'
  sar -S -f "$f" 2>/dev/null | awk '$1 ~ /^[0-9][0-9]:/ && $4 ~ /^[0-9.]+$/ {if ($4 > m) {m = $4; h = $1}} END {if (h) printf "  SWAP  pico %.1f%% usado as %s (UTC)\n", m, h}'
done
echo; echo "== hoje, por hora (CPU %usada, UTC)"
sar -u 2>/dev/null | awk '$1 ~ /^[0-9][0-9]:/ && $2 == "all" {split($1, t, ":"); s[t[1]] += 100 - $NF; n[t[1]]++; if (100 - $NF > m[t[1]]) m[t[1]] = 100 - $NF} END {for (h in s) printf "  %sh  media %.1f%%  pico %.1f%%\n", h, s[h]/n[h], m[h]}' | sort
} > "$B/01-sar.txt" 2>&1

# ------------------------------------------------------------------ 2. DISCO
{
sec "du -xh --max-depth=2 / (os 40 maiores)"; du -xh --max-depth=2 / 2>/dev/null | sort -h | tail -40
sec "/var/lib/docker por subpasta"; du -sh /var/lib/docker/* 2>/dev/null | sort -h
sec "/root por pasta"; du -sh /root/* /root/.[a-zA-Z]* 2>/dev/null | sort -h | tail -30
sec "/docker por pasta"; du -sh /docker/* 2>/dev/null | sort -h
sec "/tmp"; du -sh /tmp 2>/dev/null; ls /tmp | wc -l
sec "/var/log"; du -sh /var/log 2>/dev/null; du -sh /var/log/* 2>/dev/null | sort -h | tail -12
sec "backups (pastas com 'backup' no nome)"; find / -xdev -maxdepth 4 -type d -iname '*backup*' 2>/dev/null | while read p; do printf '%s\t%s\t%s arquivos\tmais novo: %s\n' "$(du -sh "$p" 2>/dev/null | cut -f1)" "$p" "$(find "$p" -type f 2>/dev/null | wc -l)" "$(find "$p" -type f -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | tail -1)"; done
sec "docker system df"; docker system df
sec "docker system df -v: imagens"; docker system df -v 2>/dev/null | sed -n '/^Images space usage/,/^Containers space usage/p' | head -60
sec "docker system df -v: volumes"; docker system df -v 2>/dev/null | sed -n '/^Local Volumes space usage/,/^Build cache usage/p' | head -50
sec "imagens sem container"; docker images -f dangling=true -q | wc -l; docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' | head -40
sec "sqlite do n8n ($N8N)"; docker exec "$N8N" sh -c 'ls -la /home/node/.n8n/ | grep -i -E "sqlite|config"' 2>&1; TZ=America/Manaus date '+medido em %F %T Manaus'
} > "$B/02-disco.txt" 2>&1

# ------------------------------------------------------------- 3. CONTAINERS
{
sec "docker ps -a"; docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
sec "inspect por container"
for c in $(docker ps -a --format '{{.Names}}'); do
  docker inspect "$c" --format '{{.Name}} | restart={{.HostConfig.RestartPolicy.Name}} | mem_limite={{.HostConfig.Memory}} | cpus={{.HostConfig.NanoCpus}} | oom_killed={{.State.OOMKilled}} | reinicios={{.RestartCount}} | iniciado={{.State.StartedAt}} | health={{if .State.Health}}{{.State.Health.Status}}{{else}}sem healthcheck{{end}} | rede={{.HostConfig.NetworkMode}} | log={{.HostConfig.LogConfig.Type}}{{range $k, $v := .HostConfig.LogConfig.Config}} {{$k}}={{$v}}{{end}}'
  docker inspect "$c" --format '   portas: {{range $p, $b := .NetworkSettings.Ports}}{{$p}}->{{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}; {{end}}'
done
sec "docker stats --no-stream"; docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}'
} > "$B/03-containers.txt" 2>&1

# ----------------------------------------------------------------- 4. PORTAS
{
sec "ss -tlnpu"; ss -tlnpu 2>/dev/null | awk 'NR == 1 || /LISTEN|UNCONN/' | sed -E 's/users:\(\("([^"]+)".*/\1/' | sort -u
sec "ufw"; ufw status verbose 2>&1 | head -40
sec "iptables -S (INPUT, DOCKER-USER, politicas)"; iptables -S 2>/dev/null | grep -E '^-P|INPUT|DOCKER-USER' | head -40
sec "regras de DNAT do docker (o que o docker publica)"; iptables -t nat -S DOCKER 2>/dev/null | grep DNAT | head -30
} > "$B/04-portas.txt" 2>&1

# -------------------------------------------------------------------- 5. SSH
{
sec "sshd -T"; sshd -T 2>/dev/null | grep -i -E '^(passwordauthentication|permitrootlogin|pubkeyauthentication|port|kbdinteractiveauthentication|challengeresponseauthentication|permitemptypasswords|maxauthtries|allowusers|x11forwarding) '
sec "authorized_keys do root (so tipo e comentario)"; awk '{print NR": "$1" ... "$3" "$4}' /root/.ssh/authorized_keys 2>/dev/null; echo "total: $(grep -c . /root/.ssh/authorized_keys 2>/dev/null)"
sec "fail2ban"; systemctl is-active fail2ban 2>&1; command -v fail2ban-client >/dev/null && fail2ban-client status 2>&1 | head -8 || echo "fail2ban NAO instalado"
sec "last -n 30"; last -n 30 -i 2>/dev/null | head -32
sec "lastb (falhas)"; echo "total no arquivo atual: $(lastb 2>/dev/null | grep -c .)"; lastb -i 2>/dev/null | head -12; echo "-- por IP (os 10 que mais tentaram)"; lastb -i 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -10; echo "-- por usuario"; lastb 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -8
sec "usuarios com shell"; grep -v -E '(nologin|false|sync|halt|shutdown)$' /etc/passwd | cut -d: -f1,3,7
} > "$B/05-ssh.txt" 2>&1

# ----------------------------------------------------------- 6. ATUALIZAÇÕES
{
sec "apt upgradable"; echo "pacotes: $(apt list --upgradable 2>/dev/null | grep -c upgradable)"; apt list --upgradable 2>/dev/null | grep -i -E 'security|linux-image|openssh|docker|openssl|libc6' | head -15
sec "reboot-required"; ls -la /var/run/reboot-required 2>&1; cat /var/run/reboot-required.pkgs 2>/dev/null | head
sec "kernel"; echo "rodando: $(uname -r)"; echo "instalados:"; dpkg -l 'linux-image-[0-9]*' 2>/dev/null | awk '/^ii/ {print "  "$2" "$3}'
sec "os"; grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
sec "docker"; docker version --format 'cliente {{.Client.Version}} / servidor {{.Server.Version}}'; docker compose version 2>&1 | head -1
sec "ultimo apt upgrade"; grep -h -B1 -A3 -E 'Commandline: .*(upgrade|dist-upgrade|unattended)' /var/log/apt/history.log 2>/dev/null | tail -12; zgrep -h -E '^Start-Date|Commandline' /var/log/apt/history.log* 2>/dev/null | paste - - | grep -i -E 'upgrade' | sort | tail -3; echo "unattended-upgrades: $(systemctl is-enabled unattended-upgrades 2>&1) / $(systemctl is-active unattended-upgrades 2>&1)"; ls -la /var/log/unattended-upgrades/ 2>/dev/null | tail -4
} > "$B/06-atualizacoes.txt" 2>&1

# ------------------------------------------------------------ 7. TRAEFIK/TLS
{
sec "labels traefik de cada container"
for c in $(docker ps --format '{{.Names}}'); do
  l=$(docker inspect "$c" --format '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' | grep -i '^traefik' | mascara)
  [ -n "$l" ] && { echo "--- $c"; echo "$l"; }
done
sec "config estatica do traefik"; T=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1); docker inspect "$T" --format '{{range .Args}}{{.}}{{"\n"}}{{end}}' 2>/dev/null | mascara; docker inspect "$T" --format 'portas: {{range $p, $b := .NetworkSettings.Ports}}{{$p}}->{{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}; {{end}}' 2>/dev/null
sec "arquivos dinamicos"; ls -la /docker/traefik/dynamic/ 2>/dev/null; for f in /docker/traefik/dynamic/*.yml; do echo "--- $f"; grep -E 'rule:|service:|middlewares|priority|url:' "$f" 2>/dev/null | mascara; done
sec "certificados (validade)"
for h in $(for c in $(docker ps --format '{{.Names}}'); do docker inspect "$c" --format '{{range $k, $v := .Config.Labels}}{{$v}}{{"\n"}}{{end}}'; done | grep -o 'Host(`[^`]*`)' | sed 's/Host(`//; s/`)//' | sort -u); do
  fim=$(echo | timeout 12 openssl s_client -servername "$h" -connect "$h:443" 2>/dev/null | openssl x509 -noout -enddate -issuer 2>/dev/null | tr '\n' ' ')
  echo "$h | ${fim:-NAO RESPONDEU}"
done
sec "cloudflared"
for c in $(docker ps --format '{{.Names}}' | grep -i -E 'tunnel|cloudflared'); do
  echo "--- $c: $(docker inspect "$c" --format '{{join .Config.Cmd " "}}' | sed -E 's/(--token|eyJ)[^ ]*/<token>/g')"
  docker logs --tail 500 "$c" 2>&1 | grep -o -E 'https://[a-z0-9.-]+trycloudflare\.com' | sort -u | tail -2
done
systemctl is-active cloudflared 2>&1 | head -1
} > "$B/07-traefik.txt" 2>&1

# --------------------------------------------------------------- 8. POSTGRES
if [ -n "$PG" ]; then
{
q() { docker exec -e PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=60000' "$PG" psql -U nay -d "${2:-naydb}" -X -A -F ' | ' -P pager=off -c "$1" 2>&1; }
sec "versao e parametros"; q "SELECT version()"; q "SELECT name, setting, unit FROM pg_settings WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','max_connections','effective_cache_size','max_wal_size','checkpoint_timeout','autovacuum','log_min_duration_statement','random_page_cost','jit','shared_preload_libraries') ORDER BY 1"
sec "conexoes por banco e aplicacao"; q "SELECT datname, coalesce(nullif(application_name,''),'(sem nome)') app, usename, state, count(*) n, host(client_addr) origem FROM pg_stat_activity WHERE datname IS NOT NULL GROUP BY 1,2,3,4,6 ORDER BY 5 DESC LIMIT 30"; q "SELECT count(*) conexoes_agora, (SELECT setting FROM pg_settings WHERE name='max_connections') maximo FROM pg_stat_activity"
sec "pg_stat_statements"; q "SELECT extname, extversion FROM pg_extension ORDER BY 1"; q "SELECT round(total_exec_time::numeric/1000,1) total_s, calls, round(mean_exec_time::numeric,1) media_ms, round(max_exec_time::numeric,1) max_ms, left(regexp_replace(query, E'\\\\s+', ' ', 'g'), 110) consulta FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5" | mascara
sec "tamanho por banco"; q "SELECT datname, pg_size_pretty(pg_database_size(datname)) tamanho FROM pg_database WHERE NOT datistemplate ORDER BY pg_database_size(datname) DESC"
for db in naydb crmdb; do
  sec "$db: 15 maiores tabelas"; q "SELECT schemaname||'.'||relname tabela, pg_size_pretty(pg_total_relation_size(relid)) total, n_live_tup vivas, n_dead_tup mortas, CASE WHEN n_live_tup > 0 THEN round(100.0*n_dead_tup/n_live_tup,1) END pct_mortas, to_char(last_autovacuum,'DD/MM HH24:MI') autovacuum, to_char(last_autoanalyze,'DD/MM HH24:MI') autoanalyze FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 15" "$db"
done
sec "vacuum das 4 tabelas"; q "SELECT relname, n_live_tup, n_dead_tup, to_char(last_autovacuum,'DD/MM HH24:MI') autovacuum, to_char(last_autoanalyze,'DD/MM HH24:MI') autoanalyze, to_char(last_vacuum,'DD/MM HH24:MI') vacuum_manual, autovacuum_count FROM pg_stat_user_tables WHERE relname IN ('nai_turno','nai_saida','mensagens','nai_memoria') ORDER BY 1"
sec "logs do postgres, 7 dias"; L=$(docker logs --since 168h "$PG" 2>&1); echo "linhas: $(echo "$L" | wc -l)"; echo "ERROR: $(echo "$L" | grep -c 'ERROR:')"; echo "FATAL: $(echo "$L" | grep -c 'FATAL:')"; echo "checkpoints too frequently: $(echo "$L" | grep -c -i 'checkpoints are occurring too frequently')"; echo "deadlock: $(echo "$L" | grep -c -i 'deadlock detected')"; echo "canceling statement: $(echo "$L" | grep -c -i 'canceling statement')"; echo "-- os 12 erros mais repetidos"; echo "$L" | grep 'ERROR:' | sed -E 's/^.*ERROR: +//; s/[0-9]{4,}/N/g; s/"[^"]{0,60}"/"X"/g' | cut -c1-110 | sort | uniq -c | sort -rn | head -12
} > "$B/08-postgres.txt" 2>&1
else echo "sem postgres nesta VPS" > "$B/08-postgres.txt"; fi

# -------------------------------------------------------------------- 9. N8N
{
sec "container"; echo "$N8N"
sec "variaveis (so nomes)"; docker exec "$N8N" printenv 2>/dev/null | cut -d= -f1 | sort -u | tr '\n' ' '; echo
sec "limites e poda (com valor)"; docker exec "$N8N" printenv 2>/dev/null | grep -E '^(EXECUTIONS_|N8N_CONCURRENCY|N8N_RUNNERS|DB_SQLITE|DB_TYPE|N8N_DEFAULT_BINARY_DATA_MODE|N8N_PAYLOAD_SIZE_MAX|NODE_OPTIONS|GENERIC_TIMEZONE|TZ|N8N_VERSION|N8N_LOG_LEVEL|QUEUE_|N8N_METRICS)' | sort
sec "versao"; docker exec "$N8N" n8n --version 2>&1 | tail -1
sec "sqlite e WAL"; docker exec "$N8N" sh -c 'ls -la /home/node/.n8n/ | grep -i -E "sqlite|config|binary"; du -sh /home/node/.n8n 2>/dev/null'
sec "execucoes por status e workflows"
docker exec -i -e SQLITE3_PATH=$SQLITE3 "$N8N" node - <<'JS' 2>&1
const s = require(process.env.SQLITE3_PATH);
const db = new s.Database("/home/node/.n8n/database.sqlite", s.OPEN_READONLY);
const q = (sql) => new Promise((ok) => db.all(sql, [], (e, r) => ok(e ? [{ erro: e.message }] : r)));
(async () => {
  console.log("por status:", JSON.stringify(await q("SELECT status, count(*) n FROM execution_entity GROUP BY 1 ORDER BY 2 DESC")));
  console.log("total e datas:", JSON.stringify(await q("SELECT count(*) n, min(startedAt) de, max(startedAt) ate FROM execution_entity")));
  console.log("por dia (7 dias):", JSON.stringify(await q("SELECT substr(startedAt,1,10) dia, count(*) n, sum(status='error') erros FROM execution_entity WHERE startedAt > datetime('now','-7 days') GROUP BY 1 ORDER BY 1")));
  console.log("workflows:", JSON.stringify(await q("SELECT count(*) total, sum(active) ativos FROM workflow_entity")));
  console.log("ativos:", JSON.stringify(await q("SELECT name FROM workflow_entity WHERE active = 1 ORDER BY 1")));
  console.log("erros por fluxo (7 dias):", JSON.stringify(await q("SELECT w.name, count(*) n FROM execution_entity e JOIN workflow_entity w ON w.id = e.workflowId WHERE e.status = 'error' AND e.startedAt > datetime('now','-7 days') GROUP BY 1 ORDER BY 2 DESC")));
  console.log("tamanho por tabela:", JSON.stringify(await q("SELECT name, round(sum(pgsize)/1048576.0,1) mb FROM dbstat GROUP BY 1 ORDER BY 2 DESC LIMIT 6")));
})();
JS
sec "logs 72h, contagem por tipo"; L=$(docker logs --since 72h "$N8N" 2>&1); echo "linhas: $(echo "$L" | wc -l)"; for p in 'error' 'warn' 'memory' 'sqlite_busy' 'timeout' 'ECONNRESET' 'rate limit' 'heap'; do echo "$p: $(echo "$L" | grep -c -i "$p")"; done; echo "-- as 10 mensagens de erro mais repetidas"; echo "$L" | grep -i 'error' | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?//; s/[0-9]{4,}/N/g' | cut -c1-120 | sort | uniq -c | sort -rn | head -10 | mascara
} > "$B/09-n8n.txt" 2>&1

# ------------------------------------------------------- 10. SERVIÇOS E CRONS
{
sec "servicos rodando"; systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}' | tr '\n' ' '; echo
sec "servicos que nao sao do sistema base"; systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}' | grep -v -E '^(systemd|dbus|cron|ssh|rsyslog|getty|serial-getty|user@|polkit|networkd|unattended|multipathd|udisks|ModemManager|snapd|packagekit|upower|irqbalance|accounts-daemon|qemu-guest|chrony|fwupd|thermald|atd|sysstat)' | while read u; do echo "$u | usuario=$(systemctl show -p User --value "$u") | $(systemctl show -p ExecStart --value "$u" | sed -E 's/.*argv\[\]=([^;]+);.*/\1/' | cut -c1-110 | mascara)"; done
sec "servicos com falha"; systemctl --failed --no-pager --no-legend | head
sec "crontab do root"; crontab -l 2>/dev/null | grep -v -E '^\s*(#|$)' | mascara
sec "/etc/cron.d"; for f in /etc/cron.d/*; do echo "--- $f"; grep -v -E '^\s*(#|$|SHELL|PATH|MAILTO)' "$f" | mascara; done
sec "execucoes do cron nos ultimos 7 dias (journal), por comando"; journalctl -u cron --since '7 days ago' --no-pager 2>/dev/null | grep 'CMD' | sed -E 's/^([A-Z][a-z]{2} +[0-9]+ [0-9:]+).*CMD \((.*)\)$/\1\t\2/' | awk -F'\t' '{c = substr($2, 1, 90); n[c]++; u[c] = $1} END {for (k in n) printf "%6d vezes | ultima %s | %s\n", n[k], u[k], k}' | sort -rn | mascara
sec "erros do cron no journal (7 dias)"; journalctl -u cron --since '7 days ago' --no-pager 2>/dev/null | grep -i -E 'error|fail|bad|no mta' | cut -c1-160 | sort | uniq -c | sort -rn | head -8
sec "logs que os crons escrevem (tamanho, ultima escrita, ultimas linhas com erro)"
for f in $( (crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null) | grep -o -E '>>? *[^ ;&|]+\.(log|txt|md)' | sed -E 's/>>? *//' | grep -v '\$' | sort -u); do
  [ -f "$f" ] && echo "$f | $(du -h "$f" | cut -f1) | ultima escrita $(date -r "$f" '+%F %H:%M') | linhas com erro: $(grep -c -i -E 'error|erro|falh|traceback' "$f" 2>/dev/null)" || echo "$f | NAO EXISTE"
done
} > "$B/10-servicos-crons.txt" 2>&1

# ------------------------------------------------------------------ 11. LOGS
{
sec "journal"; journalctl --disk-usage 2>&1
sec "logrotate cobre"; ls /etc/logrotate.d/ | tr '\n' ' '; echo
sec "daemon.json do docker"; cat /etc/docker/daemon.json 2>/dev/null || echo "NAO HA /etc/docker/daemon.json (log-driver padrao json-file, sem max-size)"
sec "logs json dos containers (maiores)"; for f in /var/lib/docker/containers/*/*-json.log; do n=$(docker inspect --format '{{.Name}}' "$(basename "$(dirname "$f")")" 2>/dev/null); echo "$(du -h "$f" | cut -f1) $n"; done | sort -h | tail -15
sec "logs dos projetos (arquivos .log acima de 5 MB)"; find /root /docker /var/log /opt /home -xdev -type f \( -name '*.log' -o -name '*.log.*' \) -size +5M 2>/dev/null -exec du -h {} + | sort -h | tail -20
} > "$B/11-logs.txt" 2>&1

# ------------------------------------------------------------------ 12. REDE
{
sec "tailscale"; tailscale status 2>&1 | sed -E 's/[a-z0-9._-]+@[a-z0-9.-]+/<conta>/g' | head -15
sec "quem acessa o 5432 pelo tailscale"; [ -n "$PG" ] && docker exec "$PG" psql -U nay -d naydb -X -A -F ' | ' -P pager=off -c "SELECT host(client_addr) origem, usename, datname, coalesce(nullif(application_name,''),'-') app, count(*) n FROM pg_stat_activity WHERE client_addr IS NOT NULL GROUP BY 1,2,3,4 ORDER BY 5 DESC" 2>&1
sec "vnstat"; command -v vnstat >/dev/null && vnstat --oneline 2>&1 | head -3 || echo "vnstat NAO instalado"
sec "/proc/net/dev (acumulado desde o boot)"; awk 'NR > 2 {gsub(":", "", $1); if ($2 + $10 > 0) printf "%-18s recebido %.1f GB  enviado %.1f GB\n", $1, $2/1073741824, $10/1073741824}' /proc/net/dev | grep -v -E '^(lo|veth|br-)' ; uptime -s
sec "latencia (curl -w)"; for u in https://api.openai.com/v1/models https://api.z-api.io/ https://imobeasy.com/ https://www.google.com/; do curl -s -o /dev/null -m 15 -w "$u | http %{http_code} | dns %{time_namelookup}s | conecta %{time_connect}s | tls %{time_appconnect}s | 1o byte %{time_starttransfer}s | total %{time_total}s\n" "$u"; done
} > "$B/12-rede.txt" 2>&1

# --------------------------------------------------------------- 13. BACKUPS
{
sec "o que parece backup no cron"; (crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null) | grep -i -E 'backup|dump|rsync|rclone|restic|borg|tar ' | mascara
sec "scripts de backup"; find /root /docker /opt /usr/local/bin -xdev -maxdepth 3 -type f \( -iname '*backup*' -o -iname '*dump*' \) 2>/dev/null | head -20
sec "dumps do postgres no disco"; find / -xdev -type f \( -name '*.dump' -o -name '*.sql.gz' -o -name '*.pgdump' -o -name '*dump*.sql' \) -size +1M 2>/dev/null -printf '%TY-%Tm-%Td %TH:%TM\t%s bytes\t%p\n' | sort | tail -15
sec "ferramentas de copia para fora"; for t in rclone restic borg aws gsutil rsync; do printf '%s: ' $t; command -v $t || echo "nao instalado"; done; ls -la /root/.config/rclone/ 2>/dev/null | head -3
sec "volumes do docker (onde mora o dado)"; docker volume ls --format '{{.Name}}' | while read v; do echo "$v | $(docker volume inspect "$v" --format '{{.Mountpoint}}') | $(du -sh "$(docker volume inspect "$v" --format '{{.Mountpoint}}')" 2>/dev/null | cut -f1)"; done
sec "binds dos containers (pastas do host com dado)"; for c in $(docker ps --format '{{.Names}}'); do docker inspect "$c" --format '{{.Name}}: {{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}; {{end}}' | cut -c1-400; done
sec "midia do CRM, armazem, uploads, fotos"; for p in /docker/crm/midia /docker/nay-site-web/public/fotos /docker/nay-site-web/public/fotos-captacao /docker/nay-site-web/public/uploads /docker/nay-publicador /root/armazem /docker/armazem; do [ -e "$p" ] && echo "$p | $(du -sh "$p" 2>/dev/null | cut -f1) | $(find "$p" -type f 2>/dev/null | wc -l) arquivos | mais novo $(find "$p" -type f -printf '%TY-%Tm-%Td\n' 2>/dev/null | sort | tail -1)" || echo "$p | NAO EXISTE"; done
sec ".env de cada projeto (so onde estao e a data)"; find /docker /root -xdev -maxdepth 4 -name '.env*' -type f 2>/dev/null -printf '%TY-%Tm-%Td\t%s bytes\t%p\n' | sort -k3
sec "fluxos do n8n exportados"; ls -la /root/backups-n8n* 2>/dev/null | tail -8
sec "backups de funcoes"; ls /root/backups-funcoes 2>/dev/null | wc -l; ls -t /root/backups-funcoes 2>/dev/null | head -3
} > "$B/13-backups.txt" 2>&1

echo "coleta pronta em $B: $(ls "$B" | wc -l) arquivos, $(du -sh "$B" | cut -f1)"
