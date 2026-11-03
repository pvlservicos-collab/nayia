CREATE OR REPLACE FUNCTION public.site_midias()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'hoje', (now() AT TIME ZONE 'America/Manaus')::date,
    'itens', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'canal', m.canal, 'tipo', m.tipo, 'titulo', m.titulo, 'descricao', m.descricao, 'formato', m.formato,
        'quem', m.quem, 'status', m.status, 'prioridade', m.prioridade, 'data', m.data, 'demanda_id', m.demanda_id,
        'origem', m.origem, 'link', m.link, 'atualizado_em', m.atualizado_em, 'atualizado_por', m.atualizado_por)
        ORDER BY m.data NULLS LAST, m.id)
      FROM midia_item m WHERE m.excluido_em IS NULL), '[]'::jsonb))
$function$;
