CREATE OR REPLACE FUNCTION public.nai_vocabulario_atualizar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  REFRESH MATERIALIZED VIEW mv_vocabulario_nomes;
  SELECT count(*) INTO n FROM mv_vocabulario_nomes;
  RETURN n;
END;
$function$
;
