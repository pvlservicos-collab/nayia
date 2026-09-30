#!/bin/bash
# CATALOGAR NA HORA O QUE FOI POSTADO (Tel, 14/09/2026).
#
# O que aconteceu: o publicador postou o 5737 nos grupos (ele lê o anúncio AO
# VIVO), um corretor marcou o card e pediu fotos -- e a Nay, que lê a TABELA,
# não tinha o imóvel: a varredura das 21h20 veio antes do anúncio existir, e a
# próxima seria só às 22h17. Resultado: "de qual imóvel o Sr. quer as fotos?"
# para um imóvel que ela mesma tinha identificado.
#
# O que isto faz: a cada 2 minutos, olha se existe código POSTADO (envios dos
# últimos 3 dias) ou CITADO por corretor que não está no catálogo. Só quando
# existe, roda a varredura curta (página 1 de venda e de aluguel, onde entram
# os anúncios novos) e os mesmos passos da varredura de hora em hora: fotos,
# tipo e o preenchimento dos dados do anúncio. Sem nada faltando, não toca no
# site. Varredura parcial NUNCA despublica (proteção do sincronizar_catalogo).
set -u
exec 9>/tmp/catalogar_postados.lock
flock -n 9 || exit 0

PROJETO=/root/nay-publicador
cd "$PROJETO" || exit 1
set -a; . ./.env; set +a
export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

FALTAM=$(docker exec nay-postgres psql -U nay -d naydb -tAc "
  SELECT coalesce(string_agg(DISTINCT c, ' '), '') FROM (
    SELECT e.codigo AS c FROM envios e
     WHERE e.enviado_em > now() - interval '3 days' AND e.codigo ~ '^[0-9]{3,5}$'
    UNION ALL
    SELECT nay_imovel_da_citacao(m.citado_id) FROM mensagens m
     WHERE m.criada_em > now() - interval '1 day' AND m.citado_id IS NOT NULL
  ) x
  WHERE c IS NOT NULL AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = c)")

[ -z "$FALTAM" ] && exit 0

echo "[$(date "$CARIMBO")] postado/citado sem catálogo: $FALTAM -- catalogando"
.venv/bin/python sincronizar_catalogo.py --paginas-venda 1 --paginas-aluguel 1 --escrever --silencioso 2>&1 | sed 's/^/  /'
.venv/bin/python varrer_fotos.py --escrever --silencioso 2>&1 | sed 's/^/  /'
.venv/bin/python varrer_tipos.py --escrever --silencioso 2>&1 | sed 's/^/  /'
for c in $FALTAM; do
  python3 preencher_do_anuncio.py --codigo "$c" --escrever 2>&1 | grep -v "^imóveis a olhar" | sed 's/^/  /'
done

AINDA=$(docker exec nay-postgres psql -U nay -d naydb -tAc "
  SELECT coalesce(string_agg(c, ' '), '') FROM unnest(string_to_array('$FALTAM', ' ')) c
   WHERE NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = c)")
if [ -n "$AINDA" ]; then
  echo "[$(date "$CARIMBO")] ainda fora do catálogo (não está na página 1 do site?): $AINDA"
fi
