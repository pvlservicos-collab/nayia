#!/bin/bash
# Sobe o código do nay-olx (nay-olx/olx/*.py) para /root/nay-olx no srv1894338 e reinicia o serviço nay-olx.
# Uso, na raiz do nayia: ./nay-olx/publicar.sh            (todos os olx/*.py)
#                        ./nay-olx/publicar.sh whatsapp.py (só os arquivos dados)
#
# AVISO E PERGUNTA (CLAUDE.md): antes de gravar por cima, cada arquivo do servidor tem de ser igual a uma versão que
# saiu daqui (um dos últimos 40 commits dele). Se não for, alguém mexeu lá: o script PARA, diz qual e nada sobe.
# Só com o "pode" do Pedro para aquele arquivo: NAY_SOBRESCREVER=sim.
# No servidor fica a cópia do que estava lá: olx/<arq>.bk-AAAAMMDD-HHMM. Desfazer = copiar a .bk de volta e
# `systemctl restart nay-olx`.
set -euo pipefail
cd "$(dirname "$0")"
SRV=nay-srv1894338
DEST=/root/nay-olx
if [ $# -gt 0 ]; then ARQS="$*"; else ARQS=$(cd olx && ls *.py | tr '\n' ' '); fi
md5() { tr -d '\r' | md5sum | cut -c1-32; }

parar=0
for f in $ARQS; do
  [ -f "olx/$f" ] || { echo "olx/$f não existe aqui"; exit 1; }
  srv=$(ssh -o ConnectTimeout=20 $SRV "f=$DEST/olx/$f; [ -f \$f ] && tr -d '\r' < \$f | md5sum | cut -c1-32 || echo novo")
  [ "$srv" = novo ] && continue
  [ "$srv" = "$(md5 < olx/$f)" ] && continue
  achou=0
  for c in $(git log -40 --format=%h -- "olx/$f"); do
    [ "$(git show "$c:nay-olx/olx/$f" 2>/dev/null | md5)" = "$srv" ] && { achou=1; break; }
  done
  if [ $achou = 0 ]; then
    echo "AVISO: olx/$f no servidor não é nenhuma versão que saiu daqui (alguém mexeu lá)."
    parar=1
  fi
done
if [ $parar = 1 ] && [ "${NAY_SOBRESCREVER:-}" != sim ]; then
  echo "NADA FOI PUBLICADO. Pergunte ao Pedro: o que está no servidor nesses arquivos seria apagado."
  exit 3
fi

d=$(date +%Y%m%d-%H%M)
ssh $SRV "cd $DEST/olx && for f in $ARQS; do [ -f \$f ] && cp -p \$f \$f.bk-$d; done; echo cópia de segurança: .bk-$d"
tar -c -C olx $ARQS | ssh $SRV "set -e; tar -x -C $DEST/olx; cd $DEST/olx && for f in $ARQS; do sed -i 's/\r\$//' \$f; done
  $DEST/.venv/bin/python -m py_compile $DEST/olx/*.py
  systemctl restart nay-olx; sleep 8; systemctl is-active nay-olx
  journalctl -u nay-olx -n 8 --no-pager | cut -c1-200"
