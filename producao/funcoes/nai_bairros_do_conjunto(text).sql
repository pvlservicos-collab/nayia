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
