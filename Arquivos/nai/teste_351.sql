-- Testes da 351 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
INSERT INTO _t SELECT 'dez listas, corretores primeiro', 'corretores,corretores,corretores,donos,donos,donos,donos,donos,donos,donos',
  (SELECT string_agg(grupo, ',' ORDER BY (grupo = 'donos'), n) FROM site_publicos_disparo());
INSERT INTO _t SELECT 'quem falou nos últimos 60 dias saiu de todas', 'true', (SELECT (sum(falaram) > 100)::text FROM site_publicos_disparo());
INSERT INTO _t SELECT 'a captação (quase todos responderam) ficou pequena', 'true', (SELECT (total < 200)::text FROM site_publicos_disparo() WHERE n = 9);
INSERT INTO _t SELECT 'disparados nunca passa do total', '0', (SELECT count(*)::text FROM site_publicos_disparo() WHERE disparados > total);
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT n, grupo, nome, total, disparados, falaram FROM site_publicos_disparo();
DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '351: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '351: % testes, todos certos', m;
END $$;
