#!/bin/bash
# Cópia diária do banco da Nay -- que até 02/09/2026 NÃO EXISTIA.
#
# O QUE ISTO PROTEGE: o `naydb` mora num único volume de Docker
# (`postgres_nay_pgdata`) num único servidor (srv1894338). Dentro dele estão
# coisas que NÃO se recuperam raspando o site de novo: as 3.652 mensagens de
# corretor, o histórico de conversa da Nay (`nay_memoria`), as regras, as
# pendências e o que o Tel já respondeu, os 1.053 corretores, os grupos, as
# captações. O catálogo em si a varredura reconstrói; o resto, não.
#
# Havia backup do n8n em /root/backups-n8n (os fluxos, em JSON) e NENHUM do
# banco -- nem dump, nem cron. Levantado quando o Tel perguntou "onde está o
# banco de dados?".
#
# POR QUE `pg_dump -Fc` E NÃO SQL PURO: o formato comprimido restaura tabela
# por tabela (`pg_restore -t`), que é o que se quer numa emergência de verdade
# -- quase sempre o problema é UMA tabela, não o banco inteiro.
#
# POR QUE CONFERIR O DUMP DEPOIS: arquivo de 0 byte gravado com sucesso é o
# mesmo silêncio do JPEG cinza de 49 KB que a OLX devolve num 404. Aqui o
# `pg_restore --list` lê o dump de volta e conta as tabelas; se não vier o que
# se espera, o arquivo é descartado e o backup ANTERIOR fica de pé.
#
# Restaurar (o comando que ninguém lembra na hora):
#   docker exec -i nay-postgres pg_restore -U nay -d naydb --clean --if-exists \
#     < /root/backups-banco/naydb-AAAAMMDD.dump
#   # uma tabela só:
#   ... pg_restore -U nay -d naydb -t pendencias < arquivo.dump
#   # DEPOIS DO RESTORE, SEMPRE (achado no teste de 30/09): dois índices por
#   # expressão e a mv_vocabulario_nomes usam funções que chamam outras sem o
#   # schema, e o pg_restore roda com search_path vazio -- eles FALHAM (3 erros,
#   # o resto volta inteiro). Recriar com search_path=public:
#   docker exec -i nay-postgres sh -c "pg_restore -f - -I corretores_chave_idx #     -I mensagens_chave_recebida" < arquivo.dump #     | sed "s/set_config(.search_path., .., false)/set_config('search_path', 'public', false)/" #     | docker exec -i nay-postgres psql -U nay -d naydb -v ON_ERROR_STOP=1
#   docker exec nay-postgres psql -U nay -d naydb -c "SET search_path=public" #     -c "REFRESH MATERIALIZED VIEW mv_vocabulario_nomes"
#   # o CRM: igual, com -d crmdb e o arquivo crmdb-AAAAMMDD-HHMM.dump
#
# O CRM TAMBÉM (30/09/2026). O `crmdb` mora no MESMO container (`nay-postgres`)
# e até hoje ficava de fora: os leads, as conversas espelhadas, os funis e as
# marcas do CRM só existiam no volume. Entrevista de 29/09, pergunta 54.
# Cada banco tem o seu arquivo (naydb-*.dump, crmdb-*.dump), a sua conferência
# e a sua retenção. Se um falhar, o batimento NÃO é tocado e o alarme avisa.
set -euo pipefail

PROJETO=${PROJETO:-/root/nay-publicador}
DESTINO=${DESTINO:-/root/backups-banco}
DIAS_PARA_GUARDAR=14
# banco:mínimo de tabelas com dado. Menos que isto é dump truncado: o naydb
# tinha 24 MB e ~40 tabelas em 02/09; o crmdb tinha 42 tabelas em 30/09.
BANCOS="naydb:25 crmdb:20"

export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

mkdir -p "$DESTINO"
RESUMO=""

for par in $BANCOS; do
    BANCO=${par%%:*}
    MINIMO_TABELAS=${par##*:}
    ARQUIVO="$DESTINO/$BANCO-$(date +%Y%m%d-%H%M).dump"

    if ! docker exec nay-postgres pg_dump -U nay -d "$BANCO" -Fc > "$ARQUIVO" 2>/tmp/backup_banco.erro; then
        echo "[$(date "$CARIMBO")] ERRO no pg_dump de $BANCO:" >&2
        cat /tmp/backup_banco.erro >&2
        rm -f "$ARQUIVO"
        exit 1
    fi

    # O dump tem que ser LEGÍVEL, não só existir.
    tabelas=$(docker exec -i nay-postgres pg_restore --list < "$ARQUIVO" 2>/dev/null               | grep -c 'TABLE DATA' || true)
    if [ "${tabelas:-0}" -lt "$MINIMO_TABELAS" ]; then
        echo "[$(date "$CARIMBO")] ERRO: dump de $BANCO com só ${tabelas:-0} tabelas (esperado >= $MINIMO_TABELAS). Descartado; o backup anterior continua valendo." >&2
        rm -f "$ARQUIVO"
        exit 1
    fi

    # Só apaga o velho DEPOIS de o novo ter passado na conferência -- senão um
    # backup quebrado leva junto os bons.
    find "$DESTINO" -name "$BANCO-*.dump" -mtime "+$DIAS_PARA_GUARDAR" -delete
    RESUMO="$RESUMO $BANCO: $tabelas tabelas, $(du -h "$ARQUIVO" | cut -f1);"
done

# BATIMENTO, lido pelo `alarme_crons.py`: cron que morre não avisa ninguém, e
# backup que parou é a única falha que só se descobre no dia em que ele faria
# falta.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_backup_banco"

echo "[$(date "$CARIMBO")] backup OK --$RESUMO $(ls "$DESTINO" | wc -l) arquivo(s) guardado(s)"
