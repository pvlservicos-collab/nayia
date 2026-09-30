CREATE OR REPLACE FUNCTION public.crm_telefone_do_lid(p_lid text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT coalesce(
    (SELECT nai_fone_br(i.telefone)
       FROM identidade_lid i
      WHERE regexp_replace(i.lid, '\D', '', 'g') = regexp_replace(coalesce(p_lid, ''), '\D', '', 'g')
        AND coalesce(i.telefone, '') <> ''
      ORDER BY i.criado_em DESC NULLS LAST
      LIMIT 1),
    -- 171: a captação aprende o LID de cada dono que responde
    (SELECT nai_fone_br(l.telefone)
       FROM captacao_leads l
      WHERE regexp_replace(coalesce(l.chat_lid, ''), '\D', '', 'g') = regexp_replace(coalesce(p_lid, ''), '\D', '', 'g')
        AND regexp_replace(coalesce(p_lid, ''), '\D', '', 'g') <> ''
        AND coalesce(l.telefone, '') <> ''
      ORDER BY l.atualizado_em DESC NULLS LAST
      LIMIT 1))
$function$;
