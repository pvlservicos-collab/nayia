CREATE OR REPLACE FUNCTION public.crm_olx_scrap_leads(p_q text, p_fones text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'atualizado_em' DESC), '[]'::jsonb) FROM (
    SELECT DISTINCT ON (l.telefone) jsonb_build_object(
             'lead', l.id, 'nome', l.nome, 'telefone', l.telefone, 'busca', b.id, 'estado', b.estado,
             'filtros', b.filtros, 'atualizado_em', b.atualizado_em) AS x
      FROM privado.busca_cliente b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
     WHERE (nullif(btrim(p_q), '') IS NOT NULL AND l.nome ILIKE '%' || btrim(p_q) || '%')
        OR right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = ANY (p_fones)
        OR (length(regexp_replace(coalesce(p_q, ''), '\D', '', 'g')) >= 6
            AND regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g') LIKE '%' || regexp_replace(p_q, '\D', '', 'g') || '%')
     ORDER BY l.telefone, b.atualizado_em DESC
     LIMIT 12) y;
$function$;
