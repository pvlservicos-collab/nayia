CREATE OR REPLACE FUNCTION public.site_captacao_grupos_teste_lido(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT coalesce((SELECT jsonb_build_object('lido', true, 'pedidos', l.pedidos, 'motivo', l.motivo, 'erro', l.erro,
                                             'pontuado', NOT EXISTS (SELECT 1 FROM privado.grupo_pedido q
                                                                      WHERE q.fonte = 'teste' AND q.ref = p_id::text AND q.pontuado_em IS NULL))
                     FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'teste' AND l.ref = p_id::text),
                  jsonb_build_object('lido', false));
$function$;
