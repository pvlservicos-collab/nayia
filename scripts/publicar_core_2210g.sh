#!/bin/bash
# Sobe na Nay nova a regra fixa da mobília (22/10, Tel: no mobiliado "só aluga todo mobiliado", o proprietário raramente
# tira os móveis): energia.py vira respostas_fixas.py (commits até a mobília pelo cadastro), por cima do 7b5ab46 que está no servidor.
#   Uso, na raiz do nayia: ./scripts/publicar_core_2210f.sh
# AVISO E PERGUNTA: se o servidor não estiver em 7b5ab46 ou tiver qualquer edição sem commit, PARA e nada é feito.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210c
B=$(mktemp -d)/nay-core-junta-2210g.bundle
git -C "$CORE" bundle create "$B" 7b5ab46..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2210g.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 7b5ab46 ] || { echo 'PARE: o servidor não está em 7b5ab46; nada foi feito'; exit 1; }
  [ -z \"\$(git status --short | grep -v '^??')\" ] || { echo 'PARE: há edição sem commit no servidor; nada foi feito'; exit 1; }
  git fetch -q /root/nay-core-junta-2210g.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -2
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
