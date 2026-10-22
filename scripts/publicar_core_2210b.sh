#!/bin/bash
# Sobe na Nay nova (nay-core, srv1894338) o conserto da Ana Claudia (22/10: o número solto que é um dos códigos da lista
# na frente é o código; "casa do parque dez 5721" recebia "Qual deles?") e a regra da energia (o locatário paga, pelo
# consumo; só energia solar do imóvel não), JUNTO com as 20 edições feitas direto na VPS de 21/10 20:02 a 22/10 13:09
# de Manaus (sem commit lá; deploy delas às 13:10). Substitui o publicar_core_2210.sh, que parou porque o servidor mudou.
#   Uso, na raiz do nayia: ./scripts/publicar_core_2210b.sh
#
# O ramo junta-servidor-2210b do C:\Users\pedro\nay-core é: 0cfbc09 (o que está no servidor) + e4b6ffd (as edições do
# servidor, copiadas iguais: md5 do `git diff --binary` b6de1e40...) + 654decc (Ana Claudia) + 5215c61 (energia).
#
# AVISO E PERGUNTA (CLAUDE.md, "nunca substituir o que o chat editou na VPS"): se o servidor não estiver mais em 0cfbc09
# ou alguém tiver mexido de novo depois da cópia, o script PARA e nada é feito. As edições ficam também em
# /root/backups-nay-core/consertos-chat-nay-ate-20261022-1309.patch e num git stash.
# Desfazer: no servidor, `cd /docker/nay-core && git reset --hard 0cfbc09 && git stash pop && make deploy`.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210b
ESPERADO=b6de1e4049cb2aa0df4f5943f6d224ca
B=$(mktemp -d)/nay-core-junta-2210b.bundle

git -C "$CORE" bundle create "$B" 0cfbc09..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2210b.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 0cfbc09 ] || { echo 'PARE: o servidor não está mais em 0cfbc09; nada foi feito'; exit 1; }
  [ \"\$(git diff --binary | md5sum | cut -c1-32)\" = $ESPERADO ] \
    || { echo 'PARE: alguém mexeu de novo no código depois da cópia; nada foi feito'; exit 1; }
  mkdir -p /root/backups-nay-core
  git diff --binary > /root/backups-nay-core/consertos-chat-nay-ate-20261022-1309.patch
  git stash push -m 'edições do chat Nay até 22/10 13:09 (iguais ao commit e4b6ffd)'
  git fetch -q /root/nay-core-junta-2210b.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -3
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
