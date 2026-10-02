#!/bin/bash
# Prompt 01 do pacote (segurança e backup): levantamento antes de mexer. SÓ LEITURA.
# Uso: bash p01_levantar.sh   (como root, em qualquer das duas VPS)
sec() { echo; echo "=== $* ==="; }

sec "host e hora"; hostname; date

sec "sshd: arquivos e valores efetivos"
ls -la /etc/ssh/sshd_config.d/ 2>/dev/null
grep -n -i -E '^\s*(Include|PasswordAuthentication|PermitRootLogin|MaxAuthTries|X11Forwarding|KbdInteractiveAuthentication|UsePAM)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
sshd -T 2>/dev/null | grep -i -E '^(passwordauthentication|permitrootlogin|maxauthtries|x11forwarding|kbdinteractiveauthentication|pubkeyauthentication)'
systemctl is-active ssh ssh.socket 2>&1 | tr '\n' ' '; echo
awk '{print $1, $NF}' /root/.ssh/authorized_keys

sec "pacotes"
for p in fail2ban ufw rclone gnupg sqlite3 rsync; do
  printf '%s: ' "$p"; dpkg-query -W -f='${Status} ${Version}\n' "$p" 2>/dev/null || echo "nao instalado"
done

sec "ufw e iptables INPUT"
ufw status verbose 2>&1 | head -5
iptables -S INPUT | head -10
grep -E '^(DEFAULT_FORWARD_POLICY|IPV6)' /etc/default/ufw

sec "sub-redes docker"
for n in $(docker network ls -q); do
  docker network inspect "$n" --format '{{.Name}} {{.Driver}} {{range .IPAM.Config}}{{.Subnet}} gw={{.Gateway}} {{end}}'
done
ip -br addr | grep -E 'docker|br-|tailscale|eth'

sec "quem escuta"
ss -tlnpu | awk 'NR==1 || /LISTEN|UNCONN/' | awk '{print $1, $5, $7}' | sort -u

sec "tuneis cloudflare"
for c in $(docker ps -a --format '{{.Names}}' | grep -i tunnel); do
  echo "$c: $(docker inspect "$c" --format '{{.HostConfig.RestartPolicy.Name}} | {{join .Config.Cmd " "}} | compose={{index .Config.Labels "com.docker.compose.project.working_dir"}}')"
  docker logs "$c" 2>&1 | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1
  echo "  pedidos nas ultimas 24 h (linhas de log): $(docker logs --since 24h "$c" 2>&1 | wc -l)"
done

sec "publicador (VPS1): bind"
grep -n -E "0\.0\.0\.0|\.run\(|host *=|port *=|PORTA|HOST" /root/nay-publicador/servidor.py 2>/dev/null | head -12

sec "imobiliaria (VPS2)"
if [ -d /root/imobiliaria ]; then
  ls -la /root/imobiliaria | head -40
  [ -f /root/imobiliaria/package.json ] && grep -v -i -E 'token|secret|senha|key' /root/imobiliaria/package.json | head -30
  echo "--- cabecalho do server.js"; head -40 /root/imobiliaria/server.js | grep -v -i -E 'token|secret|senha|password|apikey|api_key'
  echo "--- rotas"; grep -n -o -E "(app|router)\.(get|post|put|delete|use)\(['\"][^'\"]+['\"]" /root/imobiliaria/server.js | head -40
  echo "--- processo"; ps -eo pid,user,lstart,cmd | grep -E 'imobiliaria|server\.js' | grep -v grep
  echo "--- como sobe"; systemctl list-units --type=service --all 2>/dev/null | grep -i -E 'imobili|node' ; crontab -l 2>/dev/null | grep -i imobili; (command -v pm2 >/dev/null && pm2 ls 2>/dev/null | head -10)
  echo "--- git"; (cd /root/imobiliaria && git log --oneline 2>/dev/null | head -3; git remote -v 2>/dev/null | sed -E 's#//[^@]*@#//***@#')
  echo "--- quem aponta para a 8080"; grep -rn -E '8080' /root/*/Caddyfile /docker/*/Caddyfile /etc/caddy 2>/dev/null | head; docker ps --format '{{.Names}}' | while read c; do docker inspect "$c" --format '{{range .Mounts}}{{.Source}} {{end}}' | tr ' ' '\n' | grep -i caddyfile; done
fi

sec "scripts de backup"
ls -la /root/nay-publicador/scripts/backup*.sh /root/backup*.sh /root/scripts/backup*.sh 2>/dev/null
crontab -l | grep -i -E 'backup'
ls /etc/cron.d/ ; grep -l -i backup /etc/cron.d/* 2>/dev/null

sec "espaco"
df -h / | tail -1
