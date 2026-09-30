-- 231 (30/09/2026): CONJUNTO QUE TAMBÉM É NOME DE BAIRRO NO CATÁLOGO.
-- Pedro: "eu não pedi só zona como filtro e sim os conjuntos, ex.: Parque das
-- Laranjeiras, que fica no bairro Parque das Laranjeiras / Flores". No catálogo há
-- imóvel com bairro "Parque das Laranjeiras" (além de "Flores"); o conjunto só
-- puxava Flores. Agora o conjunto vale para o bairro dele E para o bairro do
-- catálogo que tem o mesmo nome -- na Nay (nai_lugar_citado), em imovel_lugar
-- e no site (a lista de bairros do conjunto sai daqui).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_bairros_do_conjunto(p_nome text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  -- 231: o bairro do conjunto + o bairro do catálogo de mesmo nome
  SELECT array_agg(DISTINCT b ORDER BY b) FROM (
    SELECT c.bairro AS b FROM nai_lugar_conjunto c WHERE c.nome = p_nome
    UNION
    SELECT i.bairro FROM nai_lugar_conjunto c JOIN imoveis i ON nai_lugar_normal(i.bairro) ~ c.expressao
     WHERE c.nome = p_nome AND coalesce(btrim(i.bairro), '') <> ''
  ) x;
$function$;

CREATE OR REPLACE FUNCTION public.nai_lugar_citado(p_texto text)
 RETURNS TABLE(tipo text, nome text, bairros text[], expressao text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH t AS (SELECT nai_lugar_normal(p_texto) AS n)
  SELECT 'conjunto', c.nome, nai_bairros_do_conjunto(c.nome), c.expressao FROM nai_lugar_conjunto c, t
   WHERE c.ativo AND t.n <> '' AND t.n ~ c.expressao   -- 231: os bairros do conjunto
  UNION ALL
  SELECT 'avenida', a.nome, a.bairros, a.expressao FROM nai_lugar_avenida a, t
   WHERE a.ativo AND t.n <> '' AND t.n ~ a.expressao
  -- 229: a ZONA ("zona leste", "zona centro-sul") vira os bairros dela (bairro_zona)
  UNION ALL
  SELECT 'zona', 'Zona ' || initcap(z.zona), array_agg(z.bairro ORDER BY z.bairro),
         '\mzona ' || replace(z.zona, '-', ' ') || '\M'
    FROM bairro_zona z, t
   WHERE t.n <> '' AND t.n ~ ('\mzona ' || replace(z.zona, '-', ' ') || '\M')
   GROUP BY z.zona;
$function$;

-- imovel_lugar: o imóvel cujo BAIRRO tem o nome do conjunto também é do conjunto
CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei %', p_fn, p_vezes, n; END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;
SELECT pg_temp.trocar('nai_relacionar_imovel_lugar(integer)',
$a$     WHERE (b.condo <> '' AND b.condo ~ cj.expressao)
        OR (b.rua <> '' AND cj.bn = b.bn AND b.rua ~ cj.expressao)$a$,
$b$     WHERE (b.condo <> '' AND b.condo ~ cj.expressao)
        OR (b.rua <> '' AND cj.bn = b.bn AND b.rua ~ cj.expressao)
        OR (b.bn <> '' AND b.bn ~ cj.expressao)   -- 231: o bairro tem o nome do conjunto$b$);
SELECT nai_relacionar_imovel_lugar(NULL) AS imoveis_ligados;
GRANT EXECUTE ON FUNCTION nai_bairros_do_conjunto(text) TO nay_site_leitura;

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'tem casa no parque das laranjeiras?', 'lugar', '{Flores,"Parque das Laranjeiras"}',
   'conjunto que também é bairro do catálogo puxa os dois');
COMMIT;
SELECT 'laranjeiras', count(*) FROM imovel_lugar WHERE 'Parque das Laranjeiras' = ANY (conjuntos);
