CREATE OR REPLACE FUNCTION public.nay_condominio_de_verdade(p_tipo text, p_condominio text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN coalesce(btrim(p_condominio),'') = '' THEN NULL
    -- igual ao tipo: é rótulo, não nome
    WHEN lower(btrim(p_condominio)) = lower(btrim(coalesce(p_tipo,''))) THEN NULL
    -- e as palavras de tipo sozinhas, que também aparecem no campo
    WHEN lower(btrim(p_condominio)) ~
         '^(apartamento|casa|casas|lote|loja|loja/ponto|sala|sala/andar|predio|prédio|terreno|kitnet|flat|cobertura|chacara|chácara|sobrado|galpao|galpão)$'
      THEN NULL
    WHEN btrim(p_condominio) ILIKE '%identificado%' THEN NULL
    ELSE btrim(p_condominio)
  END;
$function$;
