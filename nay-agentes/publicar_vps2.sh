#!/bin/bash
# Publica o medidor na VPS2: copia, instala o cron e mede uma vez (o JSON vai para a VPS1 pelo scp do próprio script).
set -e
cd "$(dirname "$0")"
tar -cz medir_vps2.sh nay-agentes-vps2.cron | ssh nay-srv1877774 'mkdir -p /root/nay-agentes && tar -xz -C /root/nay-agentes && chmod +x /root/nay-agentes/medir_vps2.sh && cp /root/nay-agentes/nay-agentes-vps2.cron /etc/cron.d/nay-agentes && /root/nay-agentes/medir_vps2.sh && ls -la /root/nay-agentes/agentes2.json'
ssh nay-srv1894338 'ls -la /docker/nay-site-web/public/admin/dados/agentes2.json'
