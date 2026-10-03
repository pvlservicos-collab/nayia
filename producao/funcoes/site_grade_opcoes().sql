CREATE OR REPLACE FUNCTION public.site_grade_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'grupos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', g.id_grupo, 'nome', g.nome, 'apelido', g.apelido,
                                  'ativo', g.ativo, 'venda', g.aceita_venda, 'locacao', g.aceita_locacao,
                                  'so_condominio', g.so_condominio, 'so_comercial', g.so_comercial,
                                  -- 280: o que a tela precisa para mostrar o post como ele chega neste grupo
                                  'todas_fotos', g.todas_fotos, 'venda_minima', g.venda_minima,
                                  'aluguel_minimo', g.aluguel_minimo, 'lotado', coalesce(g.apelido = 'lotado', false))
                                ORDER BY g.nome) FROM grupos g), '[]'::jsonb),
    'destinos', coalesce((SELECT jsonb_agg(jsonb_build_object('apelido', d.apelido, 'grupos', d.nomes) ORDER BY d.apelido)
                            FROM (SELECT g.apelido, array_agg(g.nome ORDER BY g.nome) AS nomes FROM grupos g
                                   WHERE g.ativo AND coalesce(g.apelido, '') NOT IN ('', 'lotado') GROUP BY g.apelido) d), '[]'::jsonb));
$function$;
