#!/usr/bin/env bash
# A FOTO DAS ETIQUETAS DE UMA LINHA DO CRM (426; Pedro, 20/10/2026): copia, do CRM (crmdb) para o banco da Nay (naydb,
# privado.relatorio_etiquetas_*), quem está em cada etiqueta da linha. Só lê o CRM. Roda NO SERVIDOR:
#   ssh nay-srv1894338 'bash -s' < scripts/foto_etiquetas_leads.sh [linha] [observação]
# linha: whatsapp_zapi_captacao (padrão, o WhatsApp Leads) | whatsapp_zapi | whatsapp_cloud_official
set -euo pipefail
TIPO="${1:-whatsapp_zapi_captacao}"
OBS="${2:-foto das etiquetas antes de as abas virarem as etapas}"
case "$TIPO" in whatsapp_zapi_captacao|whatsapp_zapi|whatsapp_cloud_official) ;; *) echo "linha inválida"; exit 1;; esac
ARQ=$(mktemp)
docker exec nay-postgres psql -U nay -d crmdb -v ON_ERROR_STOP=1 -Atc "COPY (
  SELECT t.name, l.id::text, coalesce(nullif(l.custom_attributes->>'apelido', ''), l.title), l.phone, l.last_activity_at, l.created_at
    FROM leads l JOIN integrations i ON i.id = l.integration_id
    JOIN lead_tags lt ON lt.lead_id = l.id JOIN tags t ON t.id = lt.tag_id
   WHERE i.type = '$TIPO' AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false) AND t.name NOT LIKE 'Nay:%'
) TO STDOUT WITH CSV" > "$ARQ"
echo "linhas lidas do CRM: $(wc -l < "$ARQ")"
{
  echo "BEGIN;"
  echo "CREATE TEMP TABLE _c (etiqueta text, lead_id text, nome text, telefone text, ultima timestamptz, criado timestamptz) ON COMMIT DROP;"
  echo "COPY _c FROM STDIN WITH CSV;"
  cat "$ARQ"
  echo '\.'
  echo "WITH f AS (INSERT INTO privado.relatorio_etiquetas_foto (linha, observacao) VALUES ('$TIPO', \$o\$$OBS\$o\$) RETURNING id)
        INSERT INTO privado.relatorio_etiquetas_contato (foto_id, etiqueta, lead_id, nome, telefone, ultima_atividade, criado_no_crm)
        SELECT f.id, c.etiqueta, c.lead_id, c.nome, c.telefone, c.ultima, c.criado FROM _c c, f ON CONFLICT DO NOTHING;"
  echo "SELECT id, linha, (SELECT count(*) FROM privado.relatorio_etiquetas_contato WHERE foto_id = f.id) AS contatos_por_etiqueta FROM privado.relatorio_etiquetas_foto f ORDER BY id DESC LIMIT 1;"
  echo "COMMIT;"
} | docker exec -i nay-postgres psql -U nay -d naydb -v ON_ERROR_STOP=1 -q
rm -f "$ARQ"
