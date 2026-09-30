CREATE OR REPLACE FUNCTION public.nay_chave_condominio(p_nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(
           regexp_replace(nay_normalizar_lugar(coalesce(p_nome,''), true),
             '\m(condominio|cond|residencial|resid|edificio|ed|apartamento|apto|'
             || 'parque|torre|bloco)\M', ' ', 'g'),
           '\s+', ' ', 'g'));
$function$;
