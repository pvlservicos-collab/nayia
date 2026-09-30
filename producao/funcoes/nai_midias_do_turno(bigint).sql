CREATE OR REPLACE FUNCTION public.nai_midias_do_turno(p_turno bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  -- 233: todas as mensagens do turno (não só a última da rajada: pergunta 2 da
  -- entrevista, 118 de 181 nunca eram lidas), com o link e a legenda
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'tipo', m.origem, 'url', m.midia_url, 'message_id', m.message_id,
           'legenda', nullif(btrim(coalesce(m.texto, '')), '')) ORDER BY m.id), '[]'::jsonb)
    FROM nai_turno t JOIN mensagens m ON m.id = ANY (coalesce(t.msg_ids, '{}'))
   WHERE t.id = p_turno AND m.origem IN ('imagem', 'documento', 'video') AND coalesce(m.midia_url, '') <> '';
$function$;
