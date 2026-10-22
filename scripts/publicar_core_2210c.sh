#!/bin/bash
# Segundo passo do publicar_core_2210b.sh: aquele parou no make deploy (test_limites_de_tamanho: ficha.py com 324
# linhas) DEPOIS de levar o servidor para 5215c61 (as edições da VPS estão no commit e4b6ffd e no stash). Este traz o
# commit que tira a energia para nay/cerebro/energia.py e roda o make deploy (os testes antes dos contêineres).
#   Uso, na raiz do nayia: ./scripts/publicar_core_2210c.sh
# AVISO E PERGUNTA: se o servidor não estiver em 5215c61 ou tiver qualquer edição sem commit, PARA e nada é feito.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210b
B=$(mktemp -d)/nay-core-junta-2210c.bundle
git -C "$CORE" bundle create "$B" 5215c61..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2210c.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 5215c61 ] || { echo 'PARE: o servidor não está em 5215c61; nada foi feito'; exit 1; }
  [ -z \"\$(git status --short | grep -v '^??')\" ] || { echo 'PARE: há edição sem commit no servidor; nada foi feito'; exit 1; }
  git fetch -q /root/nay-core-junta-2210c.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -2
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
