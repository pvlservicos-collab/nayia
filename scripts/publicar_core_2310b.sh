#!/bin/bash
# Sobe na Nay nova o andar em faixa (23/10, Tel: "é andar baixo, médio ou alto ... ela tem que aceitar isso"), por cima do
# cf31f40 que está no servidor.
#   Uso, na raiz do nayia: ./scripts/publicar_core_2310b.sh
# AVISO E PERGUNTA: se o servidor não estiver em cf31f40 ou tiver qualquer edição sem commit, PARA e nada é feito.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210c
B=$(mktemp -d)/nay-core-2310b.bundle
git -C "$CORE" bundle create "$B" cf31f40..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-2310b.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = cf31f40 ] || { echo 'PARE: o servidor não está em cf31f40; nada foi feito'; exit 1; }
  [ -z \"\$(git status --short | grep -v '^??')\" ] || { echo 'PARE: há edição sem commit no servidor; nada foi feito'; exit 1; }
  git fetch -q /root/nay-core-2310b.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -2
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
