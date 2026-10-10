CREATE OR REPLACE FUNCTION public.site_captacao_grupos_apelidos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object(
    'apelidos', coalesce((SELECT jsonb_agg(jsonb_build_object('apelido', a.apelido, 'tipo', a.tipo, 'oficial', a.oficial, 'obs', a.obs)
                                           ORDER BY a.tipo, a.apelido) FROM privado.grupo_apelido a), '[]'::jsonb),
    'bairros', coalesce((SELECT jsonb_agg(b ORDER BY b) FROM (SELECT DISTINCT btrim(i.bairro) AS b FROM imoveis i
                          WHERE nullif(btrim(i.bairro), '') IS NOT NULL) x), '[]'::jsonb),
    'condominios', coalesce((SELECT jsonb_agg(n ORDER BY n) FROM (SELECT DISTINCT btrim(c.nome) AS n FROM condominios c
                              WHERE nullif(btrim(c.nome), '') IS NOT NULL) y), '[]'::jsonb));
$function$;
