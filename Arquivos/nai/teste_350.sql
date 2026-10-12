-- Testes da 350 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
INSERT INTO _t SELECT 'nenhuma observação preenchida por nós', '0', (SELECT count(*)::text FROM imoveis WHERE observacao IS NOT NULL);
INSERT INTO _t SELECT 'o OBS do anúncio continua na ficha (2944)', 'true', (SELECT (coalesce(observacoes, '') ILIKE '%geladeira%')::text FROM imovel_ficha WHERE codigo = 2944);
INSERT INTO _t SELECT 'o card do 2944 não leva mais a lista de móveis', 'false', (SELECT (texto_pronto ILIKE '%geladeira%')::text FROM nai_card_do_banco(2944));
INSERT INTO _t SELECT 'dez listas', '10', (SELECT count(*)::text FROM site_publicos_disparo());
INSERT INTO _t SELECT 'a captação tem os leads todos e os enviados', 'true',
  (SELECT (total = (SELECT count(*) FROM captacao_leads WHERE coalesce(telefone_chave, '') <> '') AND disparados >= 300)::text FROM site_publicos_disparo() WHERE n = 9);
INSERT INTO _t SELECT 'a retomada tem os 91', 'true', (SELECT (total BETWEEN 80 AND 100)::text FROM site_publicos_disparo() WHERE n = 10);
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT n, nome, total, disparados FROM site_publicos_disparo() WHERE n >= 9;
DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '350: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '350: % testes, todos certos', m;
END $$;
