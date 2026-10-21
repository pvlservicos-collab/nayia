#!/bin/bash
# Sobe o código da Nay de captação (nay-captacao/captacao/*.py e ferramentas.json) para /root/nay-captacao no
# srv1894338 e reinicia o serviço nay-captacao. Uso, na raiz do nayia: ./nay-captacao/publicar.sh
#
# AVISO E PERGUNTA (CLAUDE.md): antes de gravar por cima, cada arquivo do servidor tem de ser igual a uma versão que
# saiu daqui (um dos últimos 40 commits dele). Se não for, alguém mexeu lá: o script PARA, diz qual e nada sobe.
# Só com o "pode" do Pedro para aquele arquivo: NAY_SOBRESCREVER=sim.
# No servidor fica a cópia do que estava lá: captacao/<arq>.bk-AAAAMMDD-HHMM. Desfazer = copiar a .bk de volta e
# `systemctl restart nay-captacao`.
set -euo pipefail
cd "$(dirname "$0")"
SRV=nay-srv1894338
DEST=/root/nay-captacao
ARQS=$(cd captacao && ls *.py ferramentas.json)
md5() { tr -d '\r' | md5sum | cut -c1-32; }

parar=0
for f in $ARQS; do
  srv=$(ssh -o ConnectTimeout=20 $SRV "f=$DEST/captacao/$f; [ -f \$f ] && tr -d '\r' < \$f | md5sum | cut -c1-32 || echo novo")
  [ "$srv" = novo ] && continue
  [ "$srv" = "$(md5 < captacao/$f)" ] && continue
  achou=0
  for c in $(git log -40 --format=%h -- "captacao/$f"); do
    [ "$(git show "$c:nay-captacao/captacao/$f" 2>/dev/null | md5)" = "$srv" ] && { achou=1; break; }
  done
  if [ $achou = 0 ]; then
    echo "AVISO: captacao/$f no servidor não é nenhuma versão que saiu daqui (alguém mexeu lá)."
    parar=1
  fi
done
if [ $parar = 1 ] && [ "${NAY_SOBRESCREVER:-}" != sim ]; then
  echo "NADA FOI PUBLICADO. Pergunte ao Pedro: o que está no servidor nesses arquivos seria apagado."
  exit 3
fi

d=$(date +%Y%m%d-%H%M)
ssh $SRV "cd $DEST/captacao && for f in $ARQS; do [ -f \$f ] && cp -p \$f \$f.bk-$d; done; echo cópia de segurança: .bk-$d"
tar -c -C captacao $ARQS | ssh $SRV "set -e; tar -x -C $DEST/captacao; cd $DEST/captacao && for f in $ARQS; do sed -i 's/\r\$//' \$f; done
  $DEST/.venv/bin/python -m py_compile $DEST/captacao/*.py
  systemctl restart nay-captacao; sleep 8; systemctl is-active nay-captacao
  journalctl -u nay-captacao -n 8 --no-pager | cut -c1-200"
