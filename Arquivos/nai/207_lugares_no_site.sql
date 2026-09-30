-- 207 (Pedro, 30/09/2026): "quero essas listas de filtros lá no nosso site,
-- para pesquisar por conjunto ou avenida". A lista de imóveis do admin lê as
-- mesmas tabelas da Nay (206) pela API do site, que entra como nay_site_leitura.
BEGIN;
SET LOCAL lock_timeout = '3s';
GRANT SELECT ON nai_lugar_conjunto, nai_lugar_avenida TO nay_site_leitura, nay_leitura;
COMMIT;
