CREATE OR REPLACE FUNCTION public.campanha_metricas(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH posts AS (
    SELECT grupo_nome, enviado_em FROM envios WHERE destino = 'grupo' AND codigo = p_codigo::text
    UNION ALL
    SELECT grupo_nome, enviado_em FROM envios_lista_grupo WHERE codigo = p_codigo
  ), pg AS (SELECT count(*) AS posts, count(DISTINCT grupo_nome) AS grupos FROM posts),
  memb AS (SELECT max(g.membros) AS maior FROM nai_grupo_corretor g WHERE g.nome IN (SELECT grupo_nome FROM posts)),
  cli AS (
    SELECT count(DISTINCT p) AS n FROM (
      SELECT right(regexp_replace(e.chave, '\D', '', 'g'), 8) AS p FROM imovel_enviado_no_dia e WHERE e.codigo = p_codigo
      UNION SELECT right(l.telefone, 8) FROM olx_cliente_enviada o JOIN olx_lead_whatsapp l ON l.id = o.lead
             WHERE o.codigo = p_codigo AND o.tipo = 'card'
      UNION SELECT right(regexp_replace(c.chave, '\D', '', 'g'), 8) FROM core_envio_imovel c WHERE c.codigo = p_codigo) x
  ), vis AS (
    SELECT count(*) FILTER (WHERE q > now() - interval '30 days') AS v30, count(*) AS vt FROM (
      SELECT coalesce(v.quando, v.quando_sugerido) AS q FROM nai_visita v
       WHERE v.codigo = p_codigo AND v.estado NOT IN ('cancelada', 'expirada')
      UNION ALL
      SELECT o.quando FROM olx_visita o WHERE o.codigo = p_codigo AND o.estado NOT IN ('cancelada', 'expirada')) x
  )
  SELECT jsonb_build_object(
           'codigo', p_codigo,
           'no_site', coalesce(i.publicado_no_site, false),
           'desde', i.criado_em::date,
           'chaves_na_mao', p_codigo = ANY (coalesce((SELECT s.ids FROM cnm_envio_selecao s WHERE s.id = 1), '{}')),
           'posts', pg.posts, 'grupos', pg.grupos, 'corretores', coalesce(memb.maior, 0),
           'clientes', cli.n, 'visitas_30d', vis.v30, 'visitas', vis.vt)
    FROM imoveis i, pg, memb, cli, vis
   WHERE i.codigo = p_codigo
$function$;
