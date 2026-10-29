CREATE OR REPLACE FUNCTION public.crm_lead_busca_ativa(p_telefone text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH f AS (SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) AS f8),
  l AS (SELECT w.id FROM privado.olx_lead_whatsapp w, f
         WHERE f.f8 <> '' AND right(regexp_replace(w.telefone, '\D', '', 'g'), 8) = f.f8
         ORDER BY w.atualizado_em DESC LIMIT 1),
  b AS (SELECT c.* FROM privado.busca_cliente c JOIN l ON c.lead = l.id)
  SELECT jsonb_build_object(
           'id', b.id, 'estado', b.estado, 'motivo', b.motivo, 'teste', b.teste, 'filtros', b.filtros,
           'ativada_em', b.ativada_em, 'cliente_avisado_em', b.cliente_avisado_em, 'atualizado_em', b.atualizado_em,
           'grupos', b.grupos, 'olx', b.olx, 'ofertas', b.ofertas,
           'corretores', coalesce((SELECT jsonb_agg(jsonb_build_object('nome', c.nome, 'telefone', c.telefone, 'estado', c.estado,
                                                                        'codigo', c.codigo, 'origem', c.origem, 'em', c.atualizado_em)
                                                     ORDER BY c.atualizado_em DESC)
                                     FROM privado.busca_corretor c WHERE c.busca = b.id), '[]'::jsonb),
           'passos', coalesce((SELECT jsonb_agg(jsonb_build_object('em', p.em, 'lugar', p.lugar, 'texto', p.texto) ORDER BY p.em DESC, p.id DESC)
                                 FROM (SELECT * FROM privado.busca_cliente_passo WHERE busca = b.id ORDER BY em DESC, id DESC LIMIT 60) p),
                              '[]'::jsonb))
    FROM b
$function$;
