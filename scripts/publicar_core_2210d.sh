#!/bin/bash
# Sobe na Nay nova (nay-core, srv1894338) a ficha que busca mais antes de perguntar ao Tel (22/10, Everton no 5727: o
# andar pelo admin antigo, a unidade 1101 -> 11, e o que o Tel já respondeu sobre o imóvel), JUNTO com as 10 edições
# feitas direto na VPS de 22/10 16:48 a 18:00 de Manaus (sem commit lá; deploy delas às 18:01). Precisa da nayia 472.
#   Uso, na raiz do nayia: ./scripts/publicar_core_2210d.sh
#
# O ramo junta-servidor-2210c do C:\Users\pedro\nay-core é: 992c906 (o que está no servidor) + e871540 (as edições do
# servidor, copiadas iguais: md5 do `git diff --binary` 83ff378e...) + 5e88e28 (a ficha).
#
# AVISO E PERGUNTA (CLAUDE.md, "nunca substituir o que o chat editou na VPS"): se o servidor não estiver mais em 992c906
# ou alguém tiver mexido de novo depois da cópia, o script PARA e nada é feito. As edições ficam também em
# /root/backups-nay-core/consertos-chat-nay-ate-20261022-1800.patch e num git stash.
# Desfazer: no servidor, `cd /docker/nay-core && git reset --hard 992c906 && git stash pop && make deploy`.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210c
ESPERADO=83ff378eb27b70acc8c3c8a3a4c230d2
B=$(mktemp -d)/nay-core-junta-2210d.bundle

git -C "$CORE" bundle create "$B" 992c906..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2210d.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 992c906 ] || { echo 'PARE: o servidor não está mais em 992c906; nada foi feito'; exit 1; }
  [ \"\$(git diff --binary | md5sum | cut -c1-32)\" = $ESPERADO ] \
    || { echo 'PARE: alguém mexeu de novo no código depois da cópia; nada foi feito'; exit 1; }
  mkdir -p /root/backups-nay-core
  git diff --binary > /root/backups-nay-core/consertos-chat-nay-ate-20261022-1800.patch
  git stash push -m 'edições do chat Nay até 22/10 18:00 (iguais ao commit e871540)'
  git fetch -q /root/nay-core-junta-2210d.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -3
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
