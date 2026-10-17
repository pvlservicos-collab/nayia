-- 402: o placar das listas (disparados, responderam) e quem falta, com o tempo limite do site
SET ROLE nay_site_escrita;
SET statement_timeout = '8s';
EXPLAIN (ANALYZE, SUMMARY ON, TIMING OFF, COSTS OFF) SELECT * FROM site_publicos_disparo();
SELECT n, total, disparados, responderam, round(100.0 * responderam / nullif(disparados, 0)) AS pct FROM site_publicos_disparo();
RESET ROLE;
