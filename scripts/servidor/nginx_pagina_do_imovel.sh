#!/bin/bash
# Ensina o nginx do site a servir a página do imóvel em /imovel/<código>-<nome> (02/10/2026).
# Guarda a configuração de antes, acrescenta UM bloco, testa (nginx -t) e só então recarrega.
# Se o teste falhar, devolve a configuração de antes. Rodar de novo não duplica o bloco.
# Uso (VPS1, root): bash nginx_pagina_do_imovel.sh
set -euo pipefail
CONF=/docker/nay-site-web/nginx-default.conf
if grep -q 'location \^~ /imovel/' "$CONF"; then echo "o bloco /imovel/ já está lá"; exit 0; fi
cp -a "$CONF" "$CONF.bk_$(date +%Y%m%d_%H%M)_antes_pagina_do_imovel"
python3 - "$CONF" <<'PY'
import io, sys
p = sys.argv[1]
t = io.open(p, encoding="utf-8").read()
ancora = "    location ~* \\.(?:html|js|css)$ {"
assert t.count(ancora) == 1, "não achei a âncora no nginx-default.conf"
bloco = (
    "    # A PÁGINA DO IMÓVEL (Pedro, 02/10/2026): /imovel/5717-apartamento-... serve\n"
    "    # sempre imovel.html; o código é lido do endereço pelo script da página.\n"
    "    location ^~ /imovel/ {\n"
    "        add_header Cache-Control \"no-cache, must-revalidate\" always;\n"
    "        try_files /imovel.html =404;\n"
    "    }\n\n")
io.open(p, "w", encoding="utf-8", newline="\n").write(t.replace(ancora, bloco + ancora))
PY
if docker exec nay-site-web nginx -t 2>&1 | tail -2; then
  docker exec nay-site-web nginx -s reload && echo "nginx recarregado"
else
  echo "nginx -t FALHOU: devolvendo a configuração de antes"
  cp -a "$(ls -t $CONF.bk_*_antes_pagina_do_imovel | head -1)" "$CONF"
  exit 1
fi
