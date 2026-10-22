CREATE OR REPLACE FUNCTION public.blog_artigo_credito_da_capa()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- a capa mudou e ninguém mandou o crédito da nova: o crédito era da foto antiga
  IF NEW.capa_url IS DISTINCT FROM OLD.capa_url AND NEW.capa_credito IS NOT DISTINCT FROM OLD.capa_credito THEN
    NEW.capa_credito := NULL;
  END IF;
  RETURN NEW;
END $function$;
