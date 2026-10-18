CREATE OR REPLACE FUNCTION public.blog_slug(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nullif(btrim(regexp_replace(regexp_replace(lower(unaccent(coalesce(p, ''))), '[^a-z0-9]+', '-', 'g'), '-{2,}', '-', 'g'), '-'), '')
$function$;
