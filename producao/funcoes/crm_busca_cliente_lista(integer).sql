CREATE OR REPLACE FUNCTION public.crm_busca_cliente_lista(p_dias integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'atualizado_em' DESC), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
             'id', b.id, 'lead', b.lead, 'estado', b.estado, 'motivo', b.motivo, 'teste', b.teste, 'filtros', b.filtros,
             'nome', l.nome, 'telefone', l.telefone, 'origem', l.origem, 'etapa', l.etapa, 'codigo', l.codigo,
             'criado_em', b.criado_em, 'atualizado_em', b.atualizado_em, 'ativada_em', b.ativada_em,
             'cliente_avisado_em', b.cliente_avisado_em, 'base_em', b.base_em, 'base_qtd', b.base_qtd,
             'grupos', b.grupos, 'grupos_em', b.grupos_em, 'olx', b.olx, 'olx_em', b.olx_em,
             'ofertas', b.ofertas, 'ofertado_em', b.ofertado_em,
             'passos', coalesce((SELECT jsonb_agg(jsonb_build_object('em', p.em, 'lugar', p.lugar, 'texto', p.texto) ORDER BY p.id)
                                  FROM (SELECT * FROM privado.busca_cliente_passo p WHERE p.busca = b.id ORDER BY p.id DESC LIMIT 40) p), '[]'::jsonb)) AS x
      FROM privado.busca_cliente b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
     WHERE b.atualizado_em > now() - make_interval(days => greatest(p_dias, 1))) y;
$function$;
