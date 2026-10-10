CREATE OR REPLACE FUNCTION public.crm_grupos_conhecidos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ids AS (
    SELECT id_grupo AS id FROM grupos
    UNION SELECT grupo_id FROM nai_grupo_corretor
    UNION SELECT DISTINCT grupo_id FROM privado.grupo_conversa
  )
  SELECT coalesce(jsonb_object_agg(ids.id, jsonb_strip_nulls(jsonb_build_object(
           'disparo', g.ativo, 'apelido', g.apelido, 'limite_dia', g.limite_dia,
           'aceita_venda', g.aceita_venda, 'aceita_locacao', g.aceita_locacao,
           'corretores', gc.incluir, 'membros_vistos', gc.membros,
           'mensagens', (SELECT count(*) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id
                                   AND NOT (m.tipo = 'outro' AND m.texto IS NULL AND m.midia_url IS NULL)),
           'ultima_mensagem', (SELECT max(m.enviada_em) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id
                                   AND NOT (m.tipo = 'outro' AND m.texto IS NULL AND m.midia_url IS NULL))))), '{}'::jsonb)
    FROM ids
    LEFT JOIN grupos g ON g.id_grupo = ids.id
    LEFT JOIN nai_grupo_corretor gc ON gc.grupo_id = ids.id;
$function$;
