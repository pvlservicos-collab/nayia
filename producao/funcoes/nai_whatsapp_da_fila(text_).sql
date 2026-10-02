CREATE OR REPLACE FUNCTION public.nai_whatsapp_da_fila(p_ids text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object('tipo', s.tipo, 'telefone', s.telefone_final,
                            'texto', coalesce(s.resposta->>'texto_final', s.texto), 'imagem', s.imagem_url)
    FROM nai_saida s
   WHERE s.criado_em > now() - interval '4 days'
     AND (s.message_id = ANY (p_ids) OR s.resposta->>'zaapId' = ANY (p_ids) OR s.resposta->>'messageId' = ANY (p_ids))
   ORDER BY s.id DESC
   LIMIT 1;
$function$;
