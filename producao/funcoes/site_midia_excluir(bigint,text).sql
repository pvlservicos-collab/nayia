CREATE OR REPLACE FUNCTION public.site_midia_excluir(p_id bigint, p_quem text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- some da tela, fica no banco (excluido_em); as peças presas a uma demanda excluída ficam soltas, não somem
  WITH x AS (UPDATE midia_item SET excluido_em = now(), atualizado_por = left(p_quem, 80) WHERE id = p_id AND excluido_em IS NULL RETURNING id)
  SELECT jsonb_build_object('excluidos', (SELECT count(*) FROM x))
$function$;
