CREATE OR REPLACE FUNCTION public.cnm_envio_demanda(p_dias integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH f AS (
    SELECT l.id, l.filtros AS f,
           CASE WHEN l.filtros->>'finalidade' ~* '^loc' THEN 'locacao' WHEN l.filtros->>'finalidade' ~* '^vend' THEN 'venda' END AS fin,
           CASE WHEN (l.filtros->>'teto') ~ '^[0-9.]+$' THEN (l.filtros->>'teto')::numeric END AS teto
      FROM olx_lead_whatsapp l
     WHERE l.criado_em >= now() - make_interval(days => greatest(p_dias, 1)) AND l.filtros <> '{}'::jsonb),
  rec AS (SELECT nay_sem_acento(lower(p.nome)) AS nome, p.recente FROM condominio_proximo p),
  cond AS (
    SELECT f.id, c.nome_pedido, coalesce((SELECT bool_or(r.recente) FROM rec r
                WHERE r.nome <> '' AND (nay_sem_acento(lower(c.nome_pedido)) LIKE '%' || r.nome || '%'
                                     OR r.nome LIKE '%' || nay_sem_acento(lower(c.nome_pedido)) || '%')), NULL) AS recente
      FROM f, LATERAL (SELECT trim(x) AS nome_pedido FROM unnest(
              ARRAY[f.f->>'condominio'] || ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(f.f->'referencias') = 'array' THEN f.f->'referencias' ELSE '[]'::jsonb END))) x
             WHERE trim(x) <> '') c)
  SELECT jsonb_build_object(
    'dias', p_dias,
    'pedidos', (SELECT count(*) FROM f),
    'locacao', (SELECT count(*) FROM f WHERE fin = 'locacao'),
    'venda', (SELECT count(*) FROM f WHERE fin = 'venda'),
    'teto_medio_locacao', (SELECT round(avg(teto)) FROM f WHERE fin = 'locacao' AND teto > 0),
    'teto_medio_venda', (SELECT round(avg(teto)) FROM f WHERE fin = 'venda' AND teto > 0),
    'tipos', (SELECT coalesce(jsonb_agg(jsonb_build_object('tipo', t, 'n', n) ORDER BY n DESC), '[]'::jsonb)
                FROM (SELECT coalesce(nullif(f.f->>'tipo', ''), 'sem tipo') t, count(*) n FROM f GROUP BY 1) q),
    'bairros', (SELECT coalesce(jsonb_agg(jsonb_build_object('bairro', b, 'n', n) ORDER BY n DESC), '[]'::jsonb)
                  FROM (SELECT b, count(*) n FROM f, LATERAL jsonb_array_elements_text(
                          CASE WHEN jsonb_typeof(f.f->'bairros') = 'array' THEN f.f->'bairros' ELSE '[]'::jsonb END) b
                         GROUP BY b ORDER BY 2 DESC LIMIT 15) q),
    'condominios', (SELECT coalesce(jsonb_agg(jsonb_build_object('nome', nome_pedido, 'n', n, 'recente', recente) ORDER BY n DESC), '[]'::jsonb)
                      FROM (SELECT nome_pedido, count(DISTINCT id) n, bool_or(recente) recente FROM cond GROUP BY nome_pedido ORDER BY 2 DESC LIMIT 15) q),
    'em_condominio_recente', (SELECT count(DISTINCT id) FROM cond WHERE recente),
    'em_condominio_antigo', (SELECT count(DISTINCT id) FROM cond WHERE recente IS NOT TRUE AND id NOT IN (SELECT id FROM cond WHERE recente))
  );
$function$;
