#!/bin/bash
# Ensaia conversas da Nay de captação com o código DAQUI, numa pasta à parte no servidor (/root/nay-captacao-ensaio).
# O serviço nay-captacao (que atende e dispara) não é tocado; cada conversa roda numa transação desfeita e nenhuma
# mensagem sai (captacao/ensaio.py). Usa o .env e o Python do serviço.
#   Uso, na raiz do nayia: ./nay-captacao/ensaiar.sh alugado_tem alugado_nao vendido_tem ...
set -euo pipefail
cd "$(dirname "$0")"
[ $# -gt 0 ] || { echo "diga os cenários (ver captacao/ensaio.py)"; exit 1; }
for c in "$@"; do [[ "$c" =~ ^[a-z_]+$ ]] || { echo "cenário inválido: $c"; exit 1; }; done
tar -c --exclude=__pycache__ captacao | ssh nay-srv1894338 "set -e
  rm -rf /root/nay-captacao-ensaio && mkdir -p /root/nay-captacao-ensaio && tar -x -C /root/nay-captacao-ensaio
  find /root/nay-captacao-ensaio -name '*.py' -exec sed -i 's/\r\$//' {} +
  cd /root/nay-captacao-ensaio && set -a && . /root/nay-captacao/.env && set +a
  for c in $*; do /root/nay-captacao/.venv/bin/python -m captacao.ensaio \$c; echo; done"
