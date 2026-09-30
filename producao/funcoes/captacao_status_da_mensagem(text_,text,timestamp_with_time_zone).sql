CREATE OR REPLACE FUNCTION public.captacao_status_da_mensagem(p_ids text[], p_status text, p_momento timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
AS $function$
  WITH u AS (
    UPDATE captacao_mensagens
       SET entregue_em = CASE WHEN upper(p_status) IN ('RECEIVED', 'READ', 'PLAYED')
                              THEN COALESCE(entregue_em, p_momento) ELSE entregue_em END,
           lida_em = CASE WHEN upper(p_status) IN ('READ', 'PLAYED')
                          THEN COALESCE(lida_em, p_momento) ELSE lida_em END
     WHERE message_id = ANY (p_ids) AND direcao = 'enviada'
    RETURNING 1)
  SELECT count(*)::int FROM u;
$function$;
