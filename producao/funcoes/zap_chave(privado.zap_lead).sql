CREATE OR REPLACE FUNCTION public.zap_chave(l privado.zap_lead)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN length(coalesce(l.telefone, '')) >= 8 THEN 't' || right(l.telefone, 8)
              WHEN nullif(btrim(coalesce(l.email, '')), '') IS NOT NULL THEN 'e' || lower(btrim(l.email))
              ELSE 'l' || l.id END
$function$;
