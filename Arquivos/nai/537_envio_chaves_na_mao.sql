-- 537 (Pedro, 30/10/2026): página "Envio para Chaves na Mão" no admin do site: escolher os imóveis (400 no plano, 20 em
-- destaque) e ver as métricas dos últimos 2 meses para decidir. Só leitura; nada do banco muda.
--
--   cnm_envio_lista(p_dias)   um imóvel por linha: o que ele tem + enviados, visitas e buscas na janela + se entra no feed
--                             do portal (cnm_imovel_montar: ok/falta). Entram os imóveis que o feed considera (nossos,
--                             Disponíveis, no site, com valor) e, para a métrica, os que tiveram movimento.
--   cnm_envio_demanda(p_dias) o perfil do que os leads pediram na janela (aluguel x venda, preço, bairros, tipos e
--                             condomínio recente x antigo)
--
-- DE ONDE SAI CADA NÚMERO (a janela é de p_dias dias, 60 por padrão):
--   enviados   pessoas x dia distintos que receberam o imóvel: imovel_enviado_no_dia (a Nay da Parceria), cartões do
--              8595 (privado.olx_cliente_enviada) e core_envio_imovel (nay-core); em grupos: envios (separado)
--   visitas    nai_visita (fora cancelada/expirada) + privado.olx_visita (fora cancelada/expirada)
--   buscados   pessoas distintas que pediram ESSE imóvel: o anúncio por onde o lead da OLX chegou
--              (olx_lead_whatsapp.codigo), "Código: NNNN" ou o link do site nas mensagens que RECEBEMOS (Parceria e
--              Leads) e os pedidos da página "me envia" (privado.me_envia)
BEGIN;

CREATE OR REPLACE FUNCTION public.cnm_envio_lista(p_dias integer DEFAULT 60)
 RETURNS TABLE(codigo integer, candidato boolean, ok boolean, falta jsonb, tipo text, bairro text, condominio text,
               condo_recente boolean, condo_ano integer, quartos integer, suites integer, vagas integer, area numeric,
               valor_venda numeric, valor_aluguel numeric, status text, fotos integer, capa text, parceiro boolean,
               enviados integer, em_grupos integer, visitas integer, buscados integer, imovel jsonb)
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

REVOKE ALL ON FUNCTION public.cnm_envio_lista(integer), public.cnm_envio_demanda(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cnm_envio_lista(integer), public.cnm_envio_demanda(integer) TO nay_site_leitura, nay_site_escrita;

COMMIT;
