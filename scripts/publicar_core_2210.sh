#!/bin/bash
# Sobe na Nay nova (nay-core, srv1894338) o conserto da Ana Claudia (22/10: o número solto que é um dos códigos da lista
# na frente é o código; "casa do parque dez 5721" recebia "Qual deles?"), JUNTO com as 14 edições que o chat Nay fez
# direto na VPS de 21/10 20:02 a 22/10 11:17 de Manaus (sem commit lá; deploy dele às 11:19).
#   Uso, na raiz do nayia: ./scripts/publicar_core_2210.sh
#
# O ramo junta-servidor-2210 do C:\Users\pedro\nay-core é: 0cfbc09 (o que está no servidor) + 159af42 (as edições do
# servidor, copiadas iguais: md5 do `git diff --binary` 318226e9...) + 6e5dfe7 (o conserto).
#
# AVISO E PERGUNTA (CLAUDE.md, "nunca substituir o que o chat editou na VPS"): se o servidor não estiver mais em 0cfbc09
# ou alguém tiver mexido de novo depois da cópia, o script PARA e nada é feito. As edições ficam também em
# /root/backups-nay-core/consertos-chat-nay-ate-20261022-1117.patch e num git stash.
# Desfazer: no servidor, `cd /docker/nay-core && git reset --hard 0cfbc09 && git stash pop && make deploy`.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210
ESPERADO=318226e96a29930247c4625164b49a1f
B=$(mktemp -d)/nay-core-junta-2210.bundle

git -C "$CORE" bundle create "$B" 0cfbc09..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2210.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 0cfbc09 ] || { echo 'PARE: o servidor não está mais em 0cfbc09; nada foi feito'; exit 1; }
  [ \"\$(git diff --binary | md5sum | cut -c1-32)\" = $ESPERADO ] \
    || { echo 'PARE: alguém mexeu de novo no código depois da cópia; nada foi feito'; exit 1; }
  mkdir -p /root/backups-nay-core
  git diff --binary > /root/backups-nay-core/consertos-chat-nay-ate-20261022-1117.patch
  git stash push -m 'edições do chat Nay até 22/10 11:17 (iguais ao commit 159af42)'
  git fetch -q /root/nay-core-junta-2210.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -3
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
