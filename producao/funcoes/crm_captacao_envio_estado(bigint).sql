CREATE OR REPLACE FUNCTION public.crm_captacao_envio_estado(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('id', id, 'estado', estado, 'codigos', codigos, 'enviados', enviados, 'resultado', resultado)
    FROM privado.captacao_envio_pedido WHERE id = p_id
$function$;
