CREATE OR REPLACE FUNCTION public.cnm_chave(l privado.cnm_lead)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN length(coalesce(l.telefone, '')) >= 8 THEN 't' || right(l.telefone, 8)
              WHEN nullif(btrim(coalesce(l.email, '')), '') IS NOT NULL THEN 'e' || lower(btrim(l.email))
              ELSE 'l' || l.lead_id END
$function$;
