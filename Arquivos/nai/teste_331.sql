\timing on
SELECT jsonb_pretty(crm_captacao_disparo_oficial());
SET ROLE nay_disparo;
SELECT (crm_captacao_disparo_oficial()->'listas'->1->>'faltam') AS faltam_retomada_como_crm;
RESET ROLE;
