#!/bin/bash
# COMPLEMENTO DA COLETA DE INFRA (só leitura, como a principal): o que a primeira
# passada deixou em aberto. Grava em /root/infra-<data>/bruto/2x-*.txt.
export LC_ALL=C
D=/root/infra-$(TZ=America/Manaus date +%F); B=$D/bruto; mkdir -p "$B"
N8N=$(docker ps --format '{{.Names}}' | grep -i n8n | head -1)
PG=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
SQLITE3=/usr/local/lib/node_modules/n8n/node_modules/.pnpm/sqlite3@5.1.7/node_modules/sqlite3
mascara() { sed -E 's/(sk-|eyJ)[A-Za-z0-9._-]{12,}/<REDIGIDO>/g; s/([Pp]assword|PASSWORD|[Tt]oken|TOKEN|[Ss]ecret|SECRET|[Ss]enha|SENHA|CHAVE|KEY|SEGREDO)[A-Z_]*=[^ ,"]+/\1=<REDIGIDO>/g; s/\b55[0-9]{6,7}([0-9]{4})\b/[tel ...\1]/g'; }
sec() { echo; echo "##### $1"; }

{
sec "containers: restart, limites, OOM, health"
for c in $(docker ps -a --format '{{.Names}}'); do
  docker inspect "$c" --format '{{.Name}} | restart={{.HostConfig.RestartPolicy.Name}} | mem_limite={{.HostConfig.Memory}} | cpus={{.HostConfig.NanoCpus}} | oom_killed={{.State.OOMKilled}} | reinicios={{.RestartCount}} | iniciado={{.State.StartedAt}} | rede={{.HostConfig.NetworkMode}} | log={{.HostConfig.LogConfig.Type}}'
  echo "    health: $(docker inspect "$c" --format '{{json .State.Health}}' | cut -c1-60 | sed 's/^null$/sem healthcheck/; s/{"Status":"\([a-z]*\)".*/\1/') | usuario: $(docker inspect "$c" --format '{{.Config.User}}' | sed 's/^$/root (padrao)/') | privilegiado: $(docker inspect "$c" --format '{{.HostConfig.Privileged}}')"
done
} > "$B/23-containers.txt" 2>&1

{
sec "/var/lib por pasta"; du -sh /var/lib/* 2>/dev/null | sort -h | tail -8
sec "/var/lib/containerd"; du -sh /var/lib/containerd/* 2>/dev/null | sort -h | tail -5
sec "/tmp: os maiores"; du -sh /tmp/* 2>/dev/null | sort -h | tail -12; echo "-- por prefixo de nome"; ls /tmp | sed -E 's/[-_.][A-Za-z0-9]{6,}$//; s/[0-9]{6,}.*//' | sort | uniq -c | sort -rn | head -10; echo "-- mais antigo e mais novo"; ls -lt --time-style=+%F /tmp | awk 'NR > 1 {print $6}' | sort | sed -n '1p;$p'
sec "/root/backups-n8n: os maiores"; du -sh /root/backups-n8n/* 2>/dev/null | sort -h | tail -8; echo "arquivos: $(find /root/backups-n8n -type f | wc -l)"
sec "/root/backups: por tipo"; find /root/backups -maxdepth 1 -printf '%f\n' | sed -E 's/[-_][0-9]{8}.*//' | sort | uniq -c | sort -rn | head -8; du -sh /root/backups
} > "$B/22-disco.txt" 2>&1

{
sec "falhas de login (btmp anterior)"; echo "linhas em btmp.1: $(lastb -f /var/log/btmp.1 2>/dev/null | grep -c .)"; lastb -f /var/log/btmp.1 2>/dev/null | sed -n '$p'; echo "-- por usuario tentado"; lastb -f /var/log/btmp.1 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -6; echo "-- IPs distintos: $(lastb -i -f /var/log/btmp.1 2>/dev/null | awk '{print $3}' | sort -u | wc -l)"
sec "auth.log: 7 dias"; for f in /var/log/auth.log /var/log/auth.log.1; do echo "$f: Failed password=$(grep -c 'Failed password' $f) | Invalid user=$(grep -c 'Invalid user' $f) | Accepted password=$(grep -c 'Accepted password' $f) | Accepted publickey=$(grep -c 'Accepted publickey' $f) | primeira linha: $(head -1 $f | cut -c1-19)"; done
sec "logins aceitos por IP (auth.log atual)"; grep -h 'Accepted' /var/log/auth.log /var/log/auth.log.1 | awk '{print $7, $9, $11}' | sed -E 's/([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+/\1.x.x/' | sort | uniq -c | sort -rn | head -8
sec "quem esta logado agora"; who | sed -E 's/([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+/\1.x.x/'
} > "$B/25-ssh.txt" 2>&1

{
sec "o que escuta na 8080 e na 8090"; ss -tlnp 2>/dev/null | grep -E ':(8080|8090)\s' | sed -E 's/users:\(\("([^"]+)",pid=([0-9]+).*/\1 pid=\2/'
for p in $(ss -tlnp 2>/dev/null | grep -E ':(8080|8090)\s' | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u); do echo "pid $p: $(tr '\0' ' ' < /proc/$p/cmdline) | usuario $(stat -c %U /proc/$p) | desde $(ps -o lstart= -p $p)"; done
sec "publicador (8080): rotas e protecao"; grep -n -E '@app\.(route|get|post)|def _?(autent|auth|senha|token|protegid)|Authorization|x-[a-z-]*(token|segredo|senha)|host=|app\.run' /root/nay-publicador/servidor.py 2>/dev/null | cut -c1-160 | mascara | head -40
sec "publicador: respostas sem credencial (de dentro)"; for r in / /api /saude /health /status /painel /api/status /api/fila /api/grupos /api/envios /api/config; do printf '%-14s %s\n' "$r" "$(curl -s -o /dev/null -m 6 -w '%{http_code} %{size_download}b' http://127.0.0.1:8080$r)"; done
sec "baixador (8090): rotas"; grep -n -E '@app\.(route|get|post)|Authorization|token|host=' /root/baixador-imagens/servidor.py 2>/dev/null | cut -c1-140 | mascara | head -15
sec "n8n: exige login?"; curl -s -o /dev/null -m 8 -w 'https://n8n.imobeasy.online/ -> %{http_code}\n' https://n8n.imobeasy.online/; curl -s -m 8 https://n8n.imobeasy.online/rest/settings 2>/dev/null | grep -o '"userManagement":{[^}]*}' | cut -c1-200; curl -s -o /dev/null -m 8 -w '/rest/workflows sem sessao -> %{http_code}\n' https://n8n.imobeasy.online/rest/workflows
sec "site: /admin e /admin/api sem senha"; curl -s -o /dev/null -m 8 -w 'imobeasy.online/admin/ -> %{http_code}\n' https://imobeasy.online/admin/; curl -s -o /dev/null -m 8 -w 'api.imobeasy.online/api/tabelas -> %{http_code} %{size_download}b\n' https://api.imobeasy.online/api/tabelas; curl -s -o /dev/null -m 8 -w 'crm.imobeasy.online/ -> %{http_code}\n' https://crm.imobeasy.online/; curl -s -o /dev/null -m 8 -w 'fotos.imobeasy.online/ -> %{http_code}\n' https://fotos.imobeasy.online/
sec "tuneis trycloudflare: abertos sem senha?"; for u in https://nurses-suppliers-court-doors.trycloudflare.com/api/tabelas https://carpet-cold-enquiries-stream.trycloudflare.com/; do curl -s -o /dev/null -m 10 -w "$u -> %{http_code} %{size_download}b\n" "$u"; done
} > "$B/24-exposicao.txt" 2>&1

{
sec "n8n: execucoes 'new' por idade"
docker exec -i -e SQLITE3_PATH=$SQLITE3 "$N8N" node - <<'JS' 2>&1
const s = require(process.env.SQLITE3_PATH);
const db = new s.Database("/home/node/.n8n/database.sqlite", s.OPEN_READONLY);
const q = (sql) => new Promise((ok) => db.all(sql, [], (e, r) => ok(e ? [{ erro: e.message }] : r)));
(async () => {
  console.log("new por fluxo:", JSON.stringify(await q("SELECT w.name, count(*) n, min(e.createdAt) mais_antiga, max(e.createdAt) mais_nova FROM execution_entity e LEFT JOIN workflow_entity w ON w.id = e.workflowId WHERE e.status = 'new' GROUP BY 1 ORDER BY 2 DESC")));
  console.log("por status e modo:", JSON.stringify(await q("SELECT status, mode, count(*) n FROM execution_entity GROUP BY 1, 2 ORDER BY 3 DESC")));
  console.log("duracao (s) das concluidas, por fluxo:", JSON.stringify(await q("SELECT w.name, count(*) n, round(avg((julianday(e.stoppedAt) - julianday(e.startedAt)) * 86400), 1) media, round(max((julianday(e.stoppedAt) - julianday(e.startedAt)) * 86400), 1) maxima FROM execution_entity e JOIN workflow_entity w ON w.id = e.workflowId WHERE e.status = 'success' AND e.stoppedAt IS NOT NULL GROUP BY 1 ORDER BY 2 DESC")));
  console.log("espera na fila (s) = startedAt - createdAt:", JSON.stringify(await q("SELECT round(avg((julianday(startedAt) - julianday(createdAt)) * 86400), 1) media, round(max((julianday(startedAt) - julianday(createdAt)) * 86400), 1) maxima, sum((julianday(startedAt) - julianday(createdAt)) * 86400 > 60) acima_de_1min FROM execution_entity WHERE startedAt IS NOT NULL")));
})();
JS
} > "$B/29-n8n.txt" 2>&1

if [ -n "$PG" ]; then
{
L=$(docker logs --since 168h "$PG" 2>&1)
sec "nai_fone_br nao existe: quem chama"; echo "$L" | grep -A3 'function nai_fone_br(text) does not exist' | grep -E 'STATEMENT|CONTEXT|QUERY' | sed -E 's/[0-9]{9,}/N/g' | cut -c1-240 | sort | uniq -c | sort -rn | head -4
echo "-- por dia"; echo "$L" | grep 'function nai_fone_br(text) does not exist' | cut -c1-10 | sort | uniq -c
sec "permission denied: quem"; echo "$L" | grep -A2 'permission denied for table' | grep -E 'STATEMENT' | sed -E 's/[0-9]{6,}/N/g' | cut -c1-200 | sort | uniq -c | sort -rn | head -5; echo "-- por dia"; echo "$L" | grep 'permission denied for table' | cut -c1-10 | sort | uniq -c
sec "record nao atribuido: onde"; echo "$L" | grep -A2 'is not assigned yet' | grep -E 'CONTEXT' | cut -c1-200 | sort | uniq -c | sort -rn | head -3
sec "chave duplicada: qual"; echo "$L" | grep 'duplicate key value violates' | sed -E 's/^.*constraint //' | sort | uniq -c | sort -rn | head -5
sec "erros por dia"; echo "$L" | grep 'ERROR:' | cut -c1-10 | sort | uniq -c
sec "FATAL"; echo "$L" | grep 'FATAL:' | cut -c1-160 | mascara
sec "wal e checkpoints"; docker exec "$PG" psql -U nay -d naydb -X -A -F ' | ' -P pager=off -c "SELECT checkpoints_timed, checkpoints_req, buffers_checkpoint, buffers_backend, stats_reset::date FROM pg_stat_bgwriter" 2>&1 | head -4
sec "papeis do banco"; docker exec "$PG" psql -U nay -d naydb -X -A -F ' | ' -P pager=off -c "SELECT rolname, rolsuper, rolcanlogin, rolconnlimit FROM pg_roles WHERE rolname !~ '^pg_' ORDER BY 1" 2>&1
sec "pg_hba (regras, sem comentario)"; docker exec "$PG" sh -c "grep -v -E '^\s*(#|$)' /var/lib/postgresql/data/pg_hba.conf" 2>&1
sec "listen_addresses e ssl"; docker exec "$PG" psql -U nay -d naydb -X -A -F ' | ' -P pager=off -c "SELECT name, setting FROM pg_settings WHERE name IN ('listen_addresses','ssl','password_encryption','log_connections','log_statement')" 2>&1
} > "$B/28-postgres.txt" 2>&1
fi

{
sec "backup_banco.sh"; mascara < /root/nay-publicador/backup_banco.sh 2>/dev/null | grep -v '^\s*$' | cut -c1-170
sec "backup_para_fora.sh"; mascara < /root/nay-publicador/backup_para_fora.sh 2>/dev/null | grep -v '^\s*$' | cut -c1-170
sec "logs dos backups (ultimas linhas)"; tail -6 /root/nay-publicador/logs/backup_banco.log 2>/dev/null | mascara; echo ---; tail -8 /root/nay-publicador/logs/backup_para_fora.log 2>/dev/null | mascara
sec "batimentos dos crons"; ls -la --time-style='+%F %H:%M' /root/nay-publicador/logs/.batimento_* 2>/dev/null | awk '{print $6, $7, $8}'
sec "o que ha de backup de: midia do CRM, fotos, sqlite do n8n, .env"; grep -l -r -E 'midia|fotos-captacao|database\.sqlite|\.env' /root/nay-publicador/backup_*.sh /root/*.sh 2>/dev/null | head; echo "(lista acima = scripts que citam esses caminhos)"
sec "restauracao ja testada? (procura por pg_restore no historico e nos scripts)"; grep -c 'pg_restore' /root/.bash_history 2>/dev/null; grep -l 'pg_restore' /root/*.sh /root/nay-publicador/*.sh 2>/dev/null | head -5; grep 'pg_restore' /root/.bash_history 2>/dev/null | tail -3 | mascara | cut -c1-160
} > "$B/33-backups.txt" 2>&1
echo "complemento pronto"
