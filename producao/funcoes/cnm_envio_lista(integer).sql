CREATE OR REPLACE FUNCTION public.cnm_envio_lista(p_dias integer DEFAULT 60)
 RETURNS TABLE(codigo integer, candidato boolean, ok boolean, falta jsonb, tipo text, bairro text, condominio text, condo_recente boolean, condo_ano integer, quartos integer, suites integer, vagas integer, area numeric, valor_venda numeric, valor_aluguel numeric, status text, fotos integer, capa text, parceiro boolean, enviados integer, em_grupos integer, visitas integer, buscados integer, imovel jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH janela AS (SELECT now() - make_interval(days => greatest(p_dias, 1)) AS desde),
  env AS (
    SELECT x.codigo, count(DISTINCT x.pessoa || '|' || x.dia) AS n
      FROM (SELECT e.codigo, right(regexp_replace(e.chave, '\D', '', 'g'), 8) AS pessoa, e.dia::text AS dia
              FROM imovel_enviado_no_dia e, janela j WHERE e.dia >= (j.desde AT TIME ZONE 'America/Manaus')::date
            UNION ALL
            SELECT o.codigo, right(l.telefone, 8), (o.enviado_em AT TIME ZONE 'America/Manaus')::date::text
              FROM olx_cliente_enviada o JOIN olx_lead_whatsapp l ON l.id = o.lead, janela j
             WHERE o.tipo = 'card' AND o.codigo IS NOT NULL AND o.enviado_em >= j.desde
            UNION ALL
            SELECT c.codigo, right(regexp_replace(c.chave, '\D', '', 'g'), 8), (c.enviado_em AT TIME ZONE 'America/Manaus')::date::text
              FROM core_envio_imovel c, janela j WHERE c.enviado_em >= j.desde) x
     GROUP BY x.codigo),
  grp AS (
    SELECT g.codigo::int AS codigo, count(*) AS n
      FROM envios g, janela j
     WHERE g.enviado_em >= j.desde AND g.codigo ~ '^[0-9]{1,6}$' AND g.destino = 'grupo'
     GROUP BY 1),
  vis AS (
    SELECT x.codigo, count(*) AS n
      FROM (SELECT v.codigo FROM nai_visita v, janela j
             WHERE coalesce(v.quando, v.quando_sugerido) >= j.desde AND v.estado NOT IN ('cancelada', 'expirada')
            UNION ALL
            SELECT o.codigo FROM olx_visita o, janela j
             WHERE o.quando >= j.desde AND o.estado NOT IN ('cancelada', 'expirada')) x
     GROUP BY x.codigo),
  pedidos AS (
    SELECT x.codigo, count(DISTINCT x.pessoa) AS n
      FROM (SELECT l.codigo, right(l.telefone, 8) AS pessoa FROM olx_lead_whatsapp l, janela j
             WHERE l.codigo IS NOT NULL AND l.criado_em >= j.desde
            UNION ALL
            SELECT m.cod::int, right(regexp_replace(t.telefone, '\D', '', 'g'), 8)
              FROM (SELECT telefone, criada_em, texto FROM mensagens WHERE direcao = 'recebida'
                    UNION ALL SELECT telefone, criada_em, texto FROM captacao_mensagens WHERE direcao = 'recebida') t,
                   janela j,
                   LATERAL (SELECT (regexp_matches(t.texto, '(?:imobeasy\.(?:com|online)/imovel/|c[oó]digo[: ]+)([0-9]{3,5})', 'gi'))[1] AS cod) m
             WHERE t.criada_em >= j.desde AND t.texto IS NOT NULL
            UNION ALL
            SELECT c, right(regexp_replace(me.telefone, '\D', '', 'g'), 8)
              FROM me_envia me, janela j, LATERAL unnest(me.codigos) AS c WHERE me.criado_em >= j.desde) x
     GROUP BY x.codigo)
  SELECT i.codigo,
         (i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false)
            AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false)
            AND (coalesce(i.valor_venda, 0) > 0 OR coalesce(i.valor_aluguel, 0) > 0)) AS candidato,
         coalesce((m.m->>'ok')::boolean, false), m.m->'falta',
         i.tipo, i.bairro, i.condominio_nome,
         coalesce((SELECT bool_or(p.recente) FROM condominio_proximo p WHERE p.condo_id = i.condo_id), false),
         (SELECT max(p.ano) FROM condominio_proximo p WHERE p.condo_id = i.condo_id),
         i.quartos, i.suites, i.vagas, coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)),
         nullif(i.valor_venda, 0), nullif(i.valor_aluguel, 0), i.status,
         (SELECT count(*)::int FROM imovel_fotos f WHERE f.codigo = i.codigo),
         (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo AND f.url ~* '^https://'
           ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1),
         coalesce(i.e_parceiro, false),
         coalesce(env.n, 0)::int, coalesce(grp.n, 0)::int, coalesce(vis.n, 0)::int, coalesce(pedidos.n, 0)::int,
         m.m->'imovel'
    FROM imoveis i
    LEFT JOIN env ON env.codigo = i.codigo
    LEFT JOIN grp ON grp.codigo = i.codigo
    LEFT JOIN vis ON vis.codigo = i.codigo
    LEFT JOIN pedidos ON pedidos.codigo = i.codigo
    LEFT JOIN LATERAL (
        SELECT CASE WHEN i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false)
                         AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false)
                         AND (coalesce(i.valor_venda, 0) > 0 OR coalesce(i.valor_aluguel, 0) > 0)
                    THEN cnm_imovel_montar(i.codigo) END AS m) m ON true
   WHERE i.status <> 'Excluído'
     AND (m.m IS NOT NULL OR coalesce(env.n, 0) + coalesce(vis.n, 0) + coalesce(pedidos.n, 0) > 0)
   ORDER BY i.codigo;
$function$;
