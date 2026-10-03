CREATE OR REPLACE FUNCTION public.crm_grupo_mensagens(p_grupo text, p_antes timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limite integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', m.message_id, 'de_mim', m.de_mim, 'remetente', m.remetente, 'remetente_nome', m.remetente_nome,
           'tipo', m.tipo, 'texto', m.texto, 'midia_url', m.midia_url, 'citado_id', m.citado_id, 'quando', m.enviada_em))
           ORDER BY m.enviada_em DESC), '[]'::jsonb)
    FROM (SELECT * FROM privado.grupo_conversa
           WHERE grupo_id = p_grupo AND (p_antes IS NULL OR enviada_em < p_antes)
           ORDER BY enviada_em DESC
           LIMIT greatest(1, least(coalesce(p_limite, 60), 200))) m;
$function$;
