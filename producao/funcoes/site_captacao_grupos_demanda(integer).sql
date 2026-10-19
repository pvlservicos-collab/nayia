CREATE OR REPLACE FUNCTION public.site_captacao_grupos_demanda(p_dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH base AS (
    SELECT coalesce((SELECT j.card FROM privado.grupo_pedido_junto j WHERE j.pedido_id = q.id), q.id) AS id, q.faixa,
           coalesce(q.local->>'operacao', q.ficha->>'operacao') AS operacao,
           nullif(q.ficha->>'quartos', '')::int AS quartos,
           nullif(q.ficha->>'preco_max', '')::numeric AS teto,
           coalesce((SELECT array_agg(DISTINCT z) FROM (
                       SELECT jsonb_array_elements_text(coalesce(q.local->'bairros', '[]'::jsonb)) AS z
                       UNION SELECT jsonb_array_elements_text(coalesce(q.local->'condominios', '[]'::jsonb))) s), ARRAY['(sem lugar)']) AS lugares
      FROM privado.grupo_pedido q
     WHERE q.fonte = 'grupo' AND NOT privado.grupo_e_nosso(q.grupo_id, q.grupo_nome)          -- 418
       AND q.enviada_em >= now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 365))
  ), linhas AS (
    SELECT b.id, b.faixa, coalesce(b.operacao, '(não disse)') AS operacao, lugar, b.quartos,
           CASE WHEN b.teto IS NULL THEN '(sem valor)'
                WHEN coalesce(b.operacao, CASE WHEN b.teto < 30000 THEN 'aluguel' ELSE 'venda' END) = 'aluguel' THEN
                  CASE WHEN b.teto <= 1500 THEN 'até 1.500' WHEN b.teto <= 2500 THEN '1.500 a 2.500' WHEN b.teto <= 4000 THEN '2.500 a 4.000'
                       WHEN b.teto <= 6000 THEN '4.000 a 6.000' ELSE 'acima de 6.000' END
                ELSE CASE WHEN b.teto <= 300000 THEN 'até 300 mil' WHEN b.teto <= 500000 THEN '300 a 500 mil' WHEN b.teto <= 800000 THEN '500 a 800 mil'
                          WHEN b.teto <= 1500000 THEN '800 mil a 1,5 mi' ELSE 'acima de 1,5 mi' END END AS faixa_de_preco
      FROM base b, unnest(b.lugares) AS lugar
  )
  SELECT jsonb_build_object(
    'dias', least(greatest(coalesce(p_dias, 30), 1), 365),
    'pedidos', (SELECT count(DISTINCT id) FROM base),
    'sem_imovel', (SELECT count(DISTINCT id) FROM base WHERE faixa = 'sem_match'),
    'linhas', coalesce((SELECT jsonb_agg(jsonb_build_object('operacao', g.operacao, 'lugar', g.lugar, 'quartos', g.quartos,
                                                             'preco', g.faixa_de_preco, 'pedidos', g.n, 'sem_imovel', g.sem)
                                         ORDER BY g.sem DESC, g.n DESC, g.lugar)
                          FROM (SELECT l.operacao, l.lugar, l.quartos, l.faixa_de_preco, count(DISTINCT l.id) AS n,
                                       count(DISTINCT l.id) FILTER (WHERE l.faixa = 'sem_match') AS sem
                                  FROM linhas l GROUP BY 1, 2, 3, 4 ORDER BY 6 DESC, 5 DESC LIMIT 60) g), '[]'::jsonb));
$function$;
