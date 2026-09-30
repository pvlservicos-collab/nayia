CREATE OR REPLACE FUNCTION public.crm_fechamento_do_contato(p_telefone text)
 RETURNS TABLE(fechamento_id bigint, tipo text, iniciado_em timestamp with time zone, concluido_em timestamp with time zone, checklist_tipo text, checklist_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT f.id, f.tipo, f.iniciado_em, f.concluido_em, ck.tipo, ck.criado_em
    FROM crm_pessoas(ARRAY[p_telefone]) pe
    -- o aberto primeiro; senão, o último
    LEFT JOIN LATERAL (SELECT * FROM nai_fechamento f WHERE f.contato_id = ANY (pe.ids)
                        ORDER BY (f.concluido_em IS NULL) DESC, f.id DESC LIMIT 1) f ON true
    -- o último checklist que a Nay mandou (nai_enviar_checklist_para, motivo 'checklist')
    LEFT JOIN LATERAL (SELECT s.criado_em,
                              CASE WHEN s.texto ~* 'venda|vendedor|comprador' THEN 'venda' ELSE 'locacao' END AS tipo
                         FROM nai_saida s
                        WHERE s.contato_id = ANY (pe.ids) AND s.motivo = 'checklist'
                          AND s.estado IN ('enviado', 'enviando', 'simulado')
                        ORDER BY s.criado_em DESC LIMIT 1) ck ON true
   LIMIT 1;
$function$;
