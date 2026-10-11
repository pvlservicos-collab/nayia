-- Testes da 347 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
INSERT INTO _t SELECT 'nenhum lazer com item de segurança ou comodidade', '0',
  (SELECT count(*)::text FROM condominio_ficha f WHERE EXISTS (SELECT 1 FROM unnest(f.lazer) l
     WHERE lower(unaccent(l)) ~ '^(seguranca 24|guarita|portaria|condominio fechado|elevador|gas encanado|agua de poco|gerador)'));
INSERT INTO _t SELECT 'o item mudou de lista, não sumiu (9029)', 'true',
  (SELECT (EXISTS (SELECT 1 FROM unnest(f.seguranca) x WHERE x ILIKE 'seguran%24h') AND NOT EXISTS (SELECT 1 FROM unnest(f.lazer) x WHERE x ILIKE 'seguran%'))::text
     FROM condominio_ficha f JOIN imoveis i ON i.condo_id = f.condominio_id WHERE i.codigo = 9029);
INSERT INTO _t SELECT 'lazer de verdade continua (Maison Rochelle tem Piscina)', 'true',
  (SELECT ('Piscina' = ANY (f.lazer))::text FROM condominio_ficha f JOIN imoveis i ON i.condo_id = f.condominio_id WHERE i.codigo = 2944);
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '347: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '347: % testes, todos certos', m;
END $$;
