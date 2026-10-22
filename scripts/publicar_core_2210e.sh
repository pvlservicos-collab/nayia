#!/bin/bash
# Segundo passo do publicar_core_2210d.sh: aquele parou no make deploy (test_limites_de_tamanho: a função ficha com 61
# linhas) DEPOIS de levar o servidor para 5e88e28 (as edições da VPS estão no commit e871540 e no stash). Este traz o
# commit que encurta o comentário da função ficha (61 > 60 linhas) e roda o make deploy (os testes antes dos contêineres).
#   Uso, na raiz do nayia: ./scripts/publicar_core_2210c.sh
# AVISO E PERGUNTA: se o servidor não estiver em 5e88e28 ou tiver qualquer edição sem commit, PARA e nada é feito.
set -euo pipefail
CORE=/c/Users/pedro/nay-core
RAMO=junta-servidor-2210c
B=$(mktemp -d)/nay-core-junta-2210e.bundle
git -C "$CORE" bundle create "$B" 5e88e28..$RAMO
scp -q "$B" nay-srv1894338:/root/nay-core-junta-2210e.bundle
ssh nay-srv1894338 "set -e; cd /docker/nay-core
  [ \"\$(git rev-parse --short HEAD)\" = 5e88e28 ] || { echo 'PARE: o servidor não está em 5e88e28; nada foi feito'; exit 1; }
  [ -z \"\$(git status --short | grep -v '^??')\" ] || { echo 'PARE: há edição sem commit no servidor; nada foi feito'; exit 1; }
  git fetch -q /root/nay-core-junta-2210e.bundle $RAMO:refs/remotes/bundle/$RAMO
  git merge --ff-only bundle/$RAMO
  git log --oneline -2
  make deploy
  docker ps --format '{{.Names}} {{.Status}}' | grep nay-core"
