CREATE OR REPLACE FUNCTION public.site_fotos_lista(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'codigo', p_codigo,
    'existe', EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo),
    'manual', EXISTS (SELECT 1 FROM imovel_fotos_manual WHERE codigo = p_codigo),
    'fotos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'url', f.url, 'ordem', f.ordem,
                                                           'capa', coalesce(f.e_capa, false),
                                                           'do_site_antigo', f.url ~ '^https://imobeasy\.com/')
                                        ORDER BY f.ordem NULLS LAST, f.id)
                         FROM imovel_fotos f WHERE f.codigo = p_codigo AND coalesce(f.url, '') <> ''), '[]'::jsonb));
$function$;
