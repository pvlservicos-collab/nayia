-- Testes da 349 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
INSERT INTO _t SELECT 'oito listas, na ordem', '1,2,3,4,5,6,7,8', (SELECT string_agg(n::text, ',' ORDER BY n) FROM site_publicos_disparo());
INSERT INTO _t SELECT 'disparados nunca passa do total', '0', (SELECT count(*)::text FROM site_publicos_disparo() WHERE disparados > total);
INSERT INTO _t SELECT 'corretores dos grupos é a maior e tem mais de mil', 'true', (SELECT (total > 1000)::text FROM site_publicos_disparo() WHERE n = 1);
INSERT INTO _t SELECT 'o papel do site executa', 'true', has_function_privilege('nay_site_escrita', 'public.site_publicos_disparo()', 'EXECUTE')::text;
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT * FROM site_publicos_disparo();
DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '349: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '349: % testes, todos certos', m;
END $$;
