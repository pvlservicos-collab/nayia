#!/bin/bash
# RASPAGEM DIÁRIA DA OLX (Pedro, 22/10/2026: "sim, raspe sozinho ... precisa pegar mais abrangência nas médias dos
# imóveis que temos hoje"). Roda NESTE computador (a OLX barra navegador de servidor): agendada no Windows de madrugada
# (tarefa "Nay - raspagem OLX").
#
#   1. liga o Chrome escondido do Agente OLX (porta 9377), se estava desligado
#   2. as 8 buscas da OLX, todas as faixas de preço, só profissionais (Arquivos/olx-scrape-diario/olx_scrape.js)
#   3. o detalhe (descrição = telefone) só dos anúncios que ainda não estão no cache (cache/detalhes.jsonl)
#   4. a carga nas MESMAS 16 listas do Scrap (pasta OLX; atualiza, nada é apagado; coletado_em = hoje)
#   5. desliga o Chrome, se fui eu que liguei
# A busca do cliente (nay-olx olx/buscas.py) procura nessa base (busca_olx_candidatos). Registro: raspagem.log.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
D="$RAIZ/Arquivos/olx-scrape-diario"
DIA="$D/dias/$(date +%Y-%m-%d)"
CACHE="$D/cache/detalhes.jsonl"
NAVEGADOR="$RAIZ/nay-agentes/hermes-painel/navegador-olx.ps1"
mkdir -p "$DIA" "$D/cache"
touch "$CACHE"
exec >> "$D/raspagem.log" 2>&1
echo "== $(date '+%d/%m/%Y %H:%M') começo"

no_ar() { curl -s -m 3 http://127.0.0.1:9377/json/version >/dev/null; }
liguei=0
if ! no_ar; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$NAVEGADOR")" ligar >/dev/null 2>&1 &
  for _ in $(seq 60); do no_ar && break; sleep 5; done
  no_ar || { echo "o Chrome do agente não subiu: nada feito"; exit 1; }
  liguei=1
fi

cd "$D"
r=0
node olx_scrape.js "$DIA" 100 0 || r=1
[ $r = 0 ] && { node detalhes_fetch.js "$DIA/todos.json" "$CACHE" 3 || r=2; }
[ $r = 0 ] && { python montar_carga.py "$DIA" "$DIA/carga.sql" "$CACHE" | head -1 || r=3; }
[ $r = 0 ] && { tr -d '\r' < "$DIA/carga.sql" | ssh -o ConnectTimeout=20 nay-srv1894338 \
                 "docker exec -i nay-postgres psql -U nay -d naydb -X -q -v ON_ERROR_STOP=1 -P pager=off" | tail -3 || r=4; }
# o dia guarda só o resumo (as listas brutas pesam ~6 MB por dia)
rm -f "$DIA"/*.json 2>/dev/null; [ -f "$DIA/carga.sql" ] && gzip -f "$DIA/carga.sql"

[ $liguei = 1 ] && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$NAVEGADOR")" desligar >/dev/null 2>&1
echo "== $(date '+%d/%m/%Y %H:%M') fim (código $r: 0 ok, 1 lista, 2 detalhe, 3 montar, 4 carga)"
exit $r
