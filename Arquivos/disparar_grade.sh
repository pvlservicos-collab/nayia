#!/bin/bash
# Doc 29, Etapa B: wrapper de cron pro disparar_grade.py.
#
# Cron não carrega .env sozinho -- mesmo problema resolvido no systemd
# de servidor.py (ali via EnvironmentFile=; cron não tem equivalente).
# "set -a" faz tudo que ". .env" define virar variável de ambiente
# exportada automaticamente, sem precisar declarar uma por uma.
#
# Marca início/fim com timestamp: sem isso, o log ficaria vazio tanto
# numa execução bem-sucedida sem vaga pra disparar quanto numa
# execução que o cron nunca chegou a chamar -- e não teria como
# distinguir os dois só olhando o arquivo.
#
# Onde a saída vai (arquivo, rotação) não é decisão deste script --
# fica inteiramente na linha de crontab que chama isto, via
# redirecionamento. Este script não sabe nem precisa saber onde o log
# mora.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

# Sem isto, os timestamps deste script saem em UTC (fuso do cron), não
# na hora de Manaus -- confunde a leitura do log, 4h a mais do horário
# real. Só afeta as chamadas de date abaixo; disparar_grade.py decide
# o disparo com seu próprio ZoneInfo("America/Manaus"), independente
# da TZ do shell, então isto não muda nada lá.
export TZ='America/Manaus'

CARIMBO='+%Y-%m-%dT%H:%M:%S%z'  # formato POSIX -- não usa "date -Is" (GNU-only, sem garantia de existir em toda imagem)

echo "[$(date "$CARIMBO")] início"
if "$PROJETO/.venv/bin/python" "$PROJETO/disparar_grade.py"; then
    echo "[$(date "$CARIMBO")] fim -- OK"
else
    codigo=$?
    echo "[$(date "$CARIMBO")] fim -- ERRO (saída $codigo)" >&2
    exit "$codigo"
fi

# BATIMENTO. O alarme (`alarme_crons.py`) olha a data deste arquivo: cron
# que morre nao avisa ninguem, e em 02/09 a grade ficou 18 horas parada
# porque o wrapper perdeu o bit de execucao. `touch` e uma syscall e roda
# a cada minuto -- abrir banco so para dizer "estou vivo" custaria mais
# que o trabalho.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_disparar_grade"
