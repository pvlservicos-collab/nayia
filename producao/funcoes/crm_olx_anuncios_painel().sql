CREATE OR REPLACE FUNCTION public.crm_olx_anuncios_painel()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH c AS MATERIALIZED (SELECT * FROM olx_anuncios_candidatos()),
  j AS (SELECT c.*, a.estado, a.id AS anuncio_id FROM c LEFT JOIN privado.olx_anuncio a ON a.codigo = c.codigo AND a.negocio = c.negocio)
  SELECT jsonb_build_object(
    'config', (SELECT jsonb_object_agg(k.chave, k.valor) FROM privado.olx_config k),
    'contagem', jsonb_build_object(
      'imoveis', (SELECT count(DISTINCT codigo) FROM c),
      'prontos', (SELECT count(*) FROM j WHERE (m->>'ok')::boolean AND coalesce(estado, 'removido') IN ('removido', 'erro', 'recusado')),
      'faltando_dados', (SELECT count(*) FROM j WHERE NOT (m->>'ok')::boolean),
      'enviados', (SELECT count(*) FROM privado.olx_anuncio WHERE estado = 'enviado'),
      'publicados', (SELECT count(*) FROM privado.olx_anuncio WHERE estado = 'publicado'),
      'recusados', (SELECT count(*) FROM privado.olx_anuncio WHERE estado IN ('recusado', 'erro')),
      'removidos', (SELECT count(*) FROM privado.olx_anuncio WHERE estado IN ('removido', 'removendo'))),
    'falta', coalesce((SELECT jsonb_agg(jsonb_build_object('motivo', f.motivo, 'n', f.n, 'codigos', f.codigos) ORDER BY f.n DESC)
                         FROM (SELECT regexp_replace(t.motivo, '\s*\(.*$', '') AS motivo, count(*) AS n,
                                      (array_agg(DISTINCT j.codigo ORDER BY j.codigo DESC))[1:40] AS codigos
                                 FROM j, jsonb_array_elements_text(j.m->'falta') t(motivo)
                                WHERE NOT (j.m->>'ok')::boolean GROUP BY 1) f), '[]'::jsonb),
    'nossos', coalesce((SELECT jsonb_agg(jsonb_build_object(
                           'ad_id', a.ad_id, 'codigo', a.codigo, 'negocio', a.negocio, 'conta', a.conta, 'estado', a.estado,
                           'titulo', a.conteudo->>'subject', 'preco', a.conteudo->'price', 'list_id', a.list_id, 'url', a.url,
                           'olx_status', a.olx_status, 'mensagem', a.mensagem, 'enviado_em', a.enviado_em, 'publicado_em', a.publicado_em)
                           ORDER BY a.atualizado_em DESC)
                          FROM (SELECT * FROM privado.olx_anuncio ORDER BY atualizado_em DESC LIMIT 300) a), '[]'::jsonb),
    'proximos', coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', p.codigo, 'negocio', p.negocio, 'titulo', p.m->>'titulo',
                                                             'preco', p.m->'preco', 'fotos', p.m->'fotos') ORDER BY p.codigo DESC)
                            FROM (SELECT * FROM j WHERE (m->>'ok')::boolean AND coalesce(estado, 'removido') IN ('removido', 'erro', 'recusado')
                                   ORDER BY codigo DESC LIMIT 40) p), '[]'::jsonb));
$function$;
