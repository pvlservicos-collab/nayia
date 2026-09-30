CREATE OR REPLACE FUNCTION public.nay_bairro_e_perto(p_a text, p_b text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    EXISTS (
      SELECT 1 FROM unnest(coalesce(nay_bairros_proximos(p_a), ARRAY[]::text[])) x
       WHERE nay_normalizar_lugar(x, true) = nay_normalizar_lugar(coalesce(p_b,''), true)
    ), false);
$function$;
