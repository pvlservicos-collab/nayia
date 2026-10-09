CREATE OR REPLACE FUNCTION public.condominio_nome_nucleo(p_nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nullif(btrim(regexp_replace(lower(nay_sem_acento(coalesce(p_nome, ''))),
           '^((condominio|residencial|edificio|cond\.?|res\.?|ed\.?)\s+)+|(\s+(residencial|condominio))+$', '', 'g')), '');
$function$;
