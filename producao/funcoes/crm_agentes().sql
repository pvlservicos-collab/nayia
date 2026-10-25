CREATE OR REPLACE FUNCTION public.crm_agentes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object(
    'modo', coalesce((SELECT valor FROM privado.olx_config WHERE chave = 'agentes'), 'nao'),
    'agentes', coalesce((SELECT jsonb_agg(jsonb_build_object('chave', a.chave, 'nome', a.nome, 'cor', a.cor,
                                 'descricao', a.descricao, 'tipo', a.tipo, 'modelo', a.modelo, 'ligado', a.ligado)
                                 ORDER BY a.ordem)
                         FROM privado.agente a WHERE a.canal = 'leads'), '[]'::jsonb))
$function$;
