CREATE OR REPLACE FUNCTION public.nai_e_so_bairro(p text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM (SELECT DISTINCT lower(unaccent(btrim(bairro))) b FROM imoveis WHERE coalesce(btrim(bairro), '') <> '') x
                  WHERE x.b = lower(unaccent(btrim(regexp_replace(coalesce(p, ''), '^\s*(no|na|em|bairro|o|a)\s+', '', 'i'), E' \t\n.,!?'))));
$function$;
