-- Testes da 340 (rodam dentro do ensaio, antes do ROLLBACK). Cada consulta é feita COM O PAPEL que a faz de verdade.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
GRANT ALL ON _t TO nay_site_escrita, nay_disparo;

-- um imóvel qualquer do catálogo e um lead qualquer da campanha, para as consultas terem com o que rodar
-- (o telefone fica numa variável do psql e não é impresso)
SELECT (SELECT min(codigo) FROM imoveis) AS cod,
       (SELECT telefone FROM captacao_leads WHERE captacao_lead_por_contato(telefone) = id ORDER BY id LIMIT 1) AS fone \gset

-- 1. o papel que grava o cadastro do CRM consegue a pontuação (o último comando da rota)
SET ROLE nay_site_escrita;
INSERT INTO _t SELECT 'site (escrita) lê a pontuação do imóvel', 'true', (nai_imovel_pontos(:cod) ? 'pct')::text;
RESET ROLE;

-- 2. o papel do CRM faz a consulta de pararNayDaCaptacao.ts, letra por letra
SET ROLE nay_disparo;
INSERT INTO _t SELECT 'CRM acha o lead pelo telefone', 'true',
  (SELECT count(*) = 1 FROM (SELECT l.id, l.humano_assumiu_em IS NOT NULL AS parada FROM captacao_leads l
                              WHERE l.id = captacao_lead_por_contato(:'fone'::text)) x)::text;
INSERT INTO _t SELECT 'CRM: quem não é da campanha não dá erro, só não acha', '0',
  (SELECT count(*) FROM captacao_leads l WHERE l.id = captacao_lead_por_contato('5592000000340'))::text;
RESET ROLE;

-- 3. o resto da tabela continua fechado para o CRM
CREATE FUNCTION pg_temp.negado(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'deixou';
EXCEPTION WHEN insufficient_privilege THEN
  RETURN 'negado';
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.negado(text) TO nay_disparo;
SET ROLE nay_disparo;
INSERT INTO _t SELECT 'CRM não lê o telefone direto da tabela', 'negado', pg_temp.negado('SELECT telefone FROM captacao_leads LIMIT 1');
INSERT INTO _t SELECT 'CRM não lê a linha inteira', 'negado', pg_temp.negado('SELECT * FROM captacao_leads LIMIT 1');
INSERT INTO _t SELECT 'CRM não escreve na tabela', 'negado',
  pg_temp.negado('UPDATE captacao_leads SET humano_assumiu_em = humano_assumiu_em WHERE false');
RESET ROLE;

INSERT INTO _t SELECT 'permissão: site (escrita) executa nai_imovel_pontos', 'true',
  has_function_privilege('nay_site_escrita', 'public.nai_imovel_pontos(integer)', 'EXECUTE')::text;
INSERT INTO _t SELECT 'permissão: CRM não ganhou a tabela inteira', 'false',
  has_table_privilege('nay_disparo', 'public.captacao_leads', 'SELECT')::text;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '340: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '340: % testes, todos certos', m;
END $$;
