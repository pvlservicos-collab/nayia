CREATE OR REPLACE FUNCTION public.nay_endereco_sem_numero(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT NULLIF(btrim(regexp_replace(
    regexp_replace(coalesce(p_texto,''),
      -- número de porta: vírgula/nº/traço e o número, no FIM do endereço.
      -- Preso ao fim de propósito: "KM 09 da AM 70" e "Av. das Torres 4"
      -- têm número no meio e são nome de via, não porta.
      '\s*(,|-|–|n[°º]?\.?|numero)\s*[0-9]{1,6}[a-z]?\s*$', '', 'gi'),
    '\s+', ' ', 'g'), ' ,-'), '');
$function$;
