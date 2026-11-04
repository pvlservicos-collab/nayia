CREATE OR REPLACE FUNCTION public.campanha_no_bairro(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN b = '' THEN ''
              WHEN lower(unaccent(split_part(b, ' ', 1))) IN ('ponta', 'cidade', 'compensa', 'cachoeirinha', 'gloria', 'raiz',
                         'redencao', 'paz', 'praca', 'chapada', 'alvorada', 'nova', 'colonia', 'vila', 'betania', 'zona', 'santa',
                         'uniao', 'nossa', 'lagoa')
              THEN 'na ' || b ELSE 'no ' || b END
    FROM (SELECT btrim(coalesce(bairro, '')) AS b FROM imoveis WHERE codigo = p_codigo) x
$function$;
