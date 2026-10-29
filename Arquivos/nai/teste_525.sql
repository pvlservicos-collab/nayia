-- 525: ensaio (tudo desfeito)
SET ROLE nay_disparo;
SELECT count(*) AS proprietarios FROM crm_proprietarios_fone8();
SELECT count(*) FILTER (WHERE length(f) <> 8) AS fora_do_formato FROM crm_proprietarios_fone8() f;
RESET ROLE;
