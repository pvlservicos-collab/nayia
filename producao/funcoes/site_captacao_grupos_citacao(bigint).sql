CREATE OR REPLACE FUNCTION public.site_captacao_grupos_citacao(p_saida bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('grupo', q.grupo_id, 'message_id', q.ref, 'pedido', q.id)
    FROM nai_saida s
    JOIN privado.grupo_pedido_mensagem m ON m.turno_id = s.turno_id
    JOIN privado.grupo_pedido q ON q.id = m.pedido_id
   WHERE s.id = p_saida AND s.motivo = 'captacao_ativa_negociacao' AND s.tipo = 'texto'
     -- 381: desligada. Com o privateAnswer a Z-API mandou a negociação NO GRUPO (15/10 e 16/10): sem citação, vai no privado
     AND coalesce(nai_cfg('negociacao_citar_no_grupo'), 'nao') = 'sim'
     AND q.fonte = 'grupo' AND q.grupo_id LIKE '%-group' AND nullif(btrim(q.ref), '') IS NOT NULL
     -- só mensagem que veio da Z-API tem id que ela reconhece (a importada da conversa exportada não tem)
     -- e nunca mensagem NOSSA: com ela a Z-API ignora o privateAnswer e a resposta cairia no grupo
     AND EXISTS (SELECT 1 FROM privado.grupo_conversa c WHERE c.message_id = q.ref AND NOT c.de_mim)
   LIMIT 1
$function$;
