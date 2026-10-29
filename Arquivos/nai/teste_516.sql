-- 516: ensaio (tudo desfeito)
SET ROLE nay_disparo;
SELECT count(*) AS pares, count(DISTINCT cliente) AS leads, count(DISTINCT contato) AS contatos FROM crm_contatos_relacionados();
SELECT * FROM crm_contatos_relacionados() ORDER BY em DESC LIMIT 5;
RESET ROLE;
