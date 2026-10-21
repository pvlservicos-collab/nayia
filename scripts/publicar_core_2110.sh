#!/bin/bash
# Sobe na Nay nova (nay-core, srv1894338) o card com as perguntas mais feitas (andar baixo/médio/alto ou lances de
# escada, incluso no aluguel) e os follow-ups da visita (commit 82ad546 de 21/10), JUNTO com os consertos que o chat Nay
# do painel fez direto na VPS até 21/10 11:13 de Manaus (20 arquivos, sem commit lá).
#   Uso, na raiz do nayia: ./scripts/publicar_core_2110.sh
#
# O ramo junta-servidor-2110 do C:\Users\pedro\nay-core é: c637b5e (o que está no servidor) + 1ff4d4a (os consertos do
# chat Nay, copiados iguais do /docker/nay-core: md5 do diff bc78d7b9...) + 0cfbc09 (o card, o 82ad546 por cima).
# A suíte inteira passou nesse ramo em 21/10.
#
# AVISO E PERGUNTA (CLAUDE.md, "nunca substituir o que o chat editou na VPS"): se o servidor não estiver mais em c637b5e
# ou o chat Nay tiver mexido de novo depois da cópia, o script PARA e nada é feito. Os consertos do chat ficam também em
# /root/backups-nay-core/consertos-chat-nay-ate-20261021-1113.patch e num git stash.
# Desfazer: no servidor, `cd /docker/nay-core && git reset --hard c637b5e && git stash pop && make deploy`.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2110
ESPERADO=bc78d7b994840fa4f8fe93e98b595ab3
B=$(mktemp -d)/nay-core-junta-2110.bundle

git -C "$CORE" bundle create "$B" c637b5e..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2110.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = c637b5e ] || { echo 'PARE: o servidor não está mais em c637b5e; nada foi feito'; exit 1; }
  [ \"\$(git diff -- nay templates config tests | md5sum | cut -c1-32)\" = $ESPERADO ] \
    || { echo 'PARE: o chat Nay mexeu de novo no código depois da cópia; nada foi feito'; exit 1; }
  mkdir -p /root/backups-nay-core
  git diff --binary > /root/backups-nay-core/consertos-chat-nay-ate-20261021-1113.patch
  git stash push -m 'consertos do chat Nay até 21/10 11:13 (iguais ao commit 1ff4d4a)' -- nay templates config tests
  git fetch -q /root/nay-core-junta-2110.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -3
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
