#!/bin/bash
# Sobe o complemento do cadastro (22/10) ao /root/nay-cadastro: confere o servidor contra o histórico daqui (aviso e
# pergunta), guarda .bk, testa a importação no venv de lá e reinicia o serviço.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SRV=nay-srv1894338
lf() { tr -d '\r'; }
eval "$(sed -n '/^conferir_servidor() {/,/^}/p;/^subir() {/,/^}/p' "$RAIZ/scripts/nay")"
ARQS="cadastro/leva.py cadastro/no_grupo.py"
conferir_servidor nay-cadastro /root/nay-cadastro $ARQS
for f in $ARQS; do subir nay-cadastro /root/nay-cadastro "$f"; done
ssh -o ConnectTimeout=20 $SRV 'cd /root/nay-cadastro && sed -i "s/\r$//" cadastro/leva.py cadastro/no_grupo.py && .venv/bin/python -c "from cadastro import no_grupo, leva; print(\"importa ok\", leva.parece_anuncio(\"64m2\", {}))" && systemctl restart nay-cadastro && sleep 4 && systemctl is-active nay-cadastro && journalctl -u nay-cadastro --since "-1 min" --no-pager | tail -5'
