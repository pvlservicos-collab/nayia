CREATE OR REPLACE FUNCTION public.cnm_envio_selecao()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('ids', to_jsonb(s.ids), 'destaques', to_jsonb(s.destaques),
                            'atualizado_em', s.atualizado_em, 'atualizado_por', s.atualizado_por)
    FROM cnm_envio_selecao s WHERE s.id = 1;
$function$;
