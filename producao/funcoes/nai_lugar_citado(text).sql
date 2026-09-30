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
