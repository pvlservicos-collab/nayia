CREATE OR REPLACE FUNCTION public.site_whats_modelos_notas()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'notas', coalesce((SELECT jsonb_object_agg(nome || '|' || idioma, jsonb_build_object('etiquetas', to_jsonb(etiquetas), 'observacao', observacao, 'atualizado_em', atualizado_em))
                         FROM whats_modelo_nota), '{}'::jsonb),
    'etiquetas', (SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) FROM (SELECT DISTINCT unnest(etiquetas) e FROM whats_modelo_nota) x)
  )
$function$;
