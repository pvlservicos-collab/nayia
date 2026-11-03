CREATE OR REPLACE FUNCTION public.site_links_organicos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'codigo', l.codigo, 'canal', l.canal, 'nome', l.nome, 'mensagem', l.mensagem, 'marca', l.marca,
           'utm_source', l.utm_source, 'utm_medium', l.utm_medium, 'utm_campaign', l.utm_campaign, 'ativo', l.ativo,
           'criado_em', l.criado_em,
           'cliques_7d', (SELECT count(*) FROM privado.link_organico_clique c WHERE c.codigo = l.codigo AND c.em > now() - interval '7 days'),
           'cliques_30d', (SELECT count(*) FROM privado.link_organico_clique c WHERE c.codigo = l.codigo AND c.em > now() - interval '30 days'),
           'cliques', (SELECT count(*) FROM privado.link_organico_clique c WHERE c.codigo = l.codigo),
           'leads_7d', (SELECT count(*) FROM privado.link_organico_lead d WHERE d.codigo = l.codigo AND d.primeira_em > now() - interval '7 days'),
           'leads_30d', (SELECT count(*) FROM privado.link_organico_lead d WHERE d.codigo = l.codigo AND d.primeira_em > now() - interval '30 days'),
           'leads', (SELECT count(*) FROM privado.link_organico_lead d WHERE d.codigo = l.codigo),
           'ultimos', coalesce((SELECT jsonb_agg(jsonb_build_object(
                          'em', d.primeira_em, 'final', right(d.telefone8, 4),
                          'nome', (SELECT coalesce(nullif(btrim(w.nome), ''), '') FROM privado.olx_lead_whatsapp w
                                    WHERE right(regexp_replace(w.telefone, '\D', '', 'g'), 8) = d.telefone8
                                    ORDER BY w.atualizado_em DESC LIMIT 1),
                          'etapa', (SELECT w.etapa FROM privado.olx_lead_whatsapp w
                                     WHERE right(regexp_replace(w.telefone, '\D', '', 'g'), 8) = d.telefone8
                                     ORDER BY w.atualizado_em DESC LIMIT 1)) ORDER BY d.primeira_em DESC)
                                  FROM (SELECT * FROM privado.link_organico_lead x WHERE x.codigo = l.codigo
                                         ORDER BY x.primeira_em DESC LIMIT 8) d), '[]'::jsonb))
           ORDER BY l.ativo DESC, l.canal, l.nome), '[]'::jsonb)
    FROM privado.link_organico l
$function$;
