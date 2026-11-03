CREATE OR REPLACE FUNCTION public.crm_grupos_da_busca()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', g.grupo_id, 'nome', g.nome, 'locacao', g.locacao, 'venda', g.venda)
                            ORDER BY g.nome), '[]'::jsonb)
    FROM privado.busca_grupo g WHERE g.ativo
$function$;
