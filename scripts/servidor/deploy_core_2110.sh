#!/bin/bash
# Deploy do nay-core de 21/10 (card com as perguntas mais feitas + follow-ups da visita), na VPS srv1894338.
# Os consertos que o chat Nay fez direto aqui em 20/10 22h já estão no commit 7380706 do pacote, iguais linha a linha;
# eles vão para um stash (e já há cópia em /root/backups-nay-core/consertos-do-chat-nay-20261020-2200.patch).
set -e
cd /docker/nay-core
[ "$(git diff -- nay/ templates/ | md5sum | cut -c1-32)" = "fde18c0b3e8877fcdc9804864b006152" ] \
  || { echo "PARE: alguém mexeu no código desde a cópia; nada foi feito"; exit 1; }
git stash push -m "consertos do chat Nay 20/10 22h (iguais ao commit 7380706)" -- \
  nay/acoes/buscar.py nay/acoes/enviar_imovel.py nay/acoes/executar.py nay/cerebro/catalogo.py \
  nay/estado/pedido.py nay/validador/validar.py templates/card.md
git fetch -q /root/nay-core-2110.bundle nova-nay:refs/remotes/bundle/nova-nay
git merge --ff-only bundle/nova-nay
git log --oneline -3
make deploy
docker ps --format '{{.Names}} {{.Status}}' | grep nay-core
