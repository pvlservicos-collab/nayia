CREATE OR REPLACE FUNCTION public.nay_esquecer_imovel(p_codigo text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  DELETE FROM imovel_conhecimento
   WHERE codigo = NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
