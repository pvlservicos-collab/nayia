CREATE OR REPLACE FUNCTION public.nai_chave_som(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(
                   regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z]', '', 'g'),
                 'ph', 'f', 'g'),
               '(qu|q|c|k)', 'k', 'g'),
             '(ss|z|x)', 's', 'g'),
           '(y|h|w)', 'i', 'g'),
         '(.)\1+', '\1', 'g');
$function$;
