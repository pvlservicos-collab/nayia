-- 230 (30/09/2026): o filtro de Zona do site (Admin > Imóveis) lê bairro_zona.
-- Só leitura, para o mesmo papel que já lê as listas de conjunto e avenida (207).
BEGIN;
SET LOCAL lock_timeout = '3s';
GRANT SELECT ON bairro_zona TO nay_site_leitura;
COMMIT;
