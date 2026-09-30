#!/bin/bash
# Cron do detector de visitas: lê as mensagens dos corretores e põe na grade.
#
# SEPARADO do `alertar_visitas.sh` de propósito -- aquele é o APAGADOR (a
# primeira coisa que faz é tirar da tabela o que já passou). Escritor e
# apagador no mesmo processo significa visita mal-datada escrita e apagada no
# mesmo minuto, sem deixar rastro.
#
# `--escrever` é explícito: sem a flag o detector só simula (regra 4 do
# projeto), e um detector que escreve na agenda do dono não podia subir sem
# ter rodado em seco contra as mensagens reais.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'

CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

if "$PROJETO/.venv/bin/python" "$PROJETO/detectar_visitas.py" --escrever; then
    :
else
    codigo=$?
    echo "[$(date "$CARIMBO")] detectar_visitas -- ERRO (saída $codigo)" >&2
    exit "$codigo"
fi

# BATIMENTO. O `alarme_crons.py` olha a data deste arquivo: cron que morre não
# avisa ninguém, e em 02/09 a grade ficou 18 horas parada por causa disso.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_detectar_visitas"
