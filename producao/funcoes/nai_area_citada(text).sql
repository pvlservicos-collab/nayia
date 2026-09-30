CREATE OR REPLACE FUNCTION public.nai_area_citada(p_texto text)
 RETURNS TABLE(area text, bairro text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT b.area, b.bairro
    FROM bairro_area b
   WHERE position(btrim(regexp_replace(lower(unaccent(b.area)), '[^a-z0-9]+', ' ', 'g'))
                  IN regexp_replace(lower(unaccent(coalesce(p_texto,''))), '[^a-z0-9]+', ' ', 'g')) > 0;
$function$;
