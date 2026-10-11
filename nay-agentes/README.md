# nay-agentes

A página **Agentes** do admin do site (`admin/agentes.html`) mostra um quadrado por agente que a Nay tem na VPS1,
com o que ele faz e quanto da VPS usa por dia. Quem mede é `medir_agentes.sh`, pelo cron de 5 em 5 minutos
(`/etc/cron.d/nay-agentes`), escrevendo `/docker/nay-site-web/public/admin/dados/agentes.json`. Só leitura.

- Serviço systemd: CPU acumulada (`CPUUsageNSec`), memória, desde quando está no ar, reinícios.
- Container: CPU e memória do cgroup, desde quando.
- Rotina (cron): a última vez que o log mexeu.
- "Hoje" (Manaus): contagens no naydb (turnos do núcleo, mensagens da captação, pedidos dos grupos, posts...).

"Uso da VPS por dia" = CPU acumulada dividida pelo tempo no ar (média desde que subiu); a página mostra em
"minutos de CPU por dia" e "% de 1 CPU". Memória é a de agora.

Publicar: `./nay-agentes/publicar.sh` (copia os dois arquivos, instala o cron e mede uma vez).
