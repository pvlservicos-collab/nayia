#!/bin/bash
# Sobe na Nay nova o conserto da conversa da Estefânia (23/10): "Conquista Marina" não é o tipo marina, e "Qual valor e
# fotos" depois das fotos responde o valor (cf31f40), por cima do 0030f2c que está no servidor.
#   Uso, na raiz do nayia: ./scripts/publicar_core_2310.sh
# AVISO E PERGUNTA: se o servidor não estiver em 0030f2c ou tiver qualquer edição sem commit, PARA e nada é feito.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210c
B=$(mktemp -d)/nay-core-2310.bundle
git -C "$CORE" bundle create "$B" 0030f2c..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-2310.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 0030f2c ] || { echo 'PARE: o servidor não está em 0030f2c; nada foi feito'; exit 1; }
  [ -z \"\$(git status --short | grep -v '^??')\" ] || { echo 'PARE: há edição sem commit no servidor; nada foi feito'; exit 1; }
  git fetch -q /root/nay-core-2310.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -2
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
