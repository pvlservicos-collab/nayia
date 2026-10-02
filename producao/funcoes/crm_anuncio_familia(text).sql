CREATE OR REPLACE FUNCTION public.crm_anuncio_familia(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN t = '' THEN NULL
    WHEN t ~ 'lote|terreno|chacara|sitio|fazenda' THEN 'terreno'
    WHEN t ~ 'apart|apto|flat|cobertura|kitnet|kitinete|studio|loft|duplex' THEN 'apartamento'
    WHEN t ~ 'casa|sobrado' THEN 'casa'
    WHEN t ~ 'sala|loja|ponto|galpao|deposito|predio|comercial|andar' THEN 'comercial'
    END
  FROM (SELECT nay_sem_acento(lower(coalesce(p, ''))) AS t) x;
$function$;
