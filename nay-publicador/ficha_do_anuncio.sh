#!/bin/bash
# Wrapper de cron do ficha_do_anuncio.py (191, 29/09/2026): a ficha completa de
# cada anuncio do site, que a Nay consulta antes de responder sobre um imovel.
# A cada 3 horas; pausa de 1,5 s entre anuncios. So escreve no log se deu erro.
set -euo pipefail
cd /root/nay-publicador
set -a; . ./.env; set +a
export TZ='America/Manaus'
.venv/bin/python ficha_do_anuncio.py --todos --escrever --silencioso
mkdir -p logs && touch logs/.batimento_ficha_do_anuncio
