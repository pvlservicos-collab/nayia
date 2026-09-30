CREATE OR REPLACE FUNCTION public.nai_lugar_citado(p_texto text)
 RETURNS TABLE(tipo text, nome text, bairros text[], expressao text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH t AS (SELECT nai_lugar_normal(p_texto) AS n)
  SELECT 'conjunto', c.nome, ARRAY[c.bairro], c.expressao FROM nai_lugar_conjunto c, t
   WHERE c.ativo AND t.n <> '' AND t.n ~ c.expressao
  UNION ALL
  SELECT 'avenida', a.nome, a.bairros, a.expressao FROM nai_lugar_avenida a, t
   WHERE a.ativo AND t.n <> '' AND t.n ~ a.expressao;
$function$;
