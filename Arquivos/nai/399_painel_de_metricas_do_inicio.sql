-- 399: o PAINEL DE MÉTRICAS da aba Início do admin do site
--
-- Pedro, 16/10/2026: "quero um grande painel dashboard de métricas, focado em analisar o desempenho por dia, por
-- semana, por mês ... pessoas que falamos por dia, conversões por dia (Parceria e Captação = visitas agendadas;
-- Captação também imóveis novos) ... visitas agendadas, imóveis mandados pela Nay por dia, média de imóvel por
-- corretor ... negócios fechados da aba Fechamento ... pessoas vindas da OLX e quantas visitaram ... métricas dos
-- disparos: enviados, responderam, atualizaram o status do imóvel".
--
-- site_painel_metricas(de, ate, grao) devolve tudo de uma vez, só CONTAGEM (nenhum telefone sai daqui):
--   periodos[]           o começo de cada dia/semana/mês do intervalo (em Manaus)
--   serie.<métrica>[]    um número por período, alinhado com periodos
--   totais.<métrica>     o número do intervalo inteiro (pessoa distinta conta uma vez, não a soma dos dias)
--   coortes_disparo[]    por dia de disparo e linha: enviados -> responderam -> mudaram/confirmaram o status
--   funil_olx            clientes da OLX no intervalo -> receberam imóvel -> pediram visita -> confirmada -> visitaram
--   top_imoveis[]        os códigos que mais saíram para corretor/cliente
--   fechamentos[]        os da aba Fechamento que começaram ou terminaram no intervalo
-- "Pessoas que falamos" por linha mora no banco do CRM: a API do site busca em /api/metrics/pessoas-por-linha.
-- Os números internos (nossas linhas, equipe, Tel, testes) ficam fora: site_painel_internos().
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.site_painel_internos()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- os 8 últimos dígitos de quem é DE CASA: as três linhas, a equipe, o Tel e os números de teste
  SELECT coalesce(array_agg(DISTINCT x ORDER BY x) FILTER (WHERE length(x) = 8), '{}')
    FROM (SELECT right(regexp_replace(coalesce(t, ''), '\D', '', 'g'), 8) AS x
            FROM (SELECT unnest(ARRAY['94453618', '85956408', '84560874']) AS t   -- Parceria, Captação, Oficial
                  UNION ALL SELECT telefone FROM equipe
                  UNION ALL SELECT unnest(string_to_array(valor, ',')) FROM nai_config
                             WHERE chave IN ('tel_telefone', 'numeros_teste', 'comando_telefones')
                  UNION ALL SELECT unnest(string_to_array(valor, ',')) FROM captacao_config
                             WHERE chave IN ('telefone_teste', 'python_telefones')
                  UNION ALL SELECT unnest(string_to_array(valor, ',')) FROM privado.olx_config
                             WHERE chave = 'whatsapp_teste') a) b;
$function$;

CREATE OR REPLACE FUNCTION public.site_painel_metricas(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date,
                                                       p_grao text DEFAULT 'dia'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_grao text := CASE lower(coalesce(p_grao, 'dia')) WHEN 'semana' THEN 'week' WHEN 'mes' THEN 'month' ELSE 'day' END;
  v_hoje date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_ate  date := least(coalesce(p_ate, v_hoje), v_hoje);
  v_de   date := greatest(least(coalesce(p_de, v_ate - 29), v_ate), v_ate - 400);
  v_ini  timestamptz;
  v_fim  timestamptz;
  v_int  text[] := site_painel_internos();
  v_nomes text[] := ARRAY[
    'visitas', 'visitas_nay', 'visitas_crm', 'visitas_confirmadas', 'visitas_marcadas_para',
    'visitas_olx', 'visitas_olx_confirmadas',
    'enviados', 'enviados_nay', 'enviados_equipe', 'destinatarios', 'enviados_captacao', 'destinatarios_captacao',
    'grupo_posts', 'grupo_imoveis',
    'imoveis_novos', 'imoveis_novos_site', 'imoveis_novos_olx', 'imoveis_novos_crm', 'imoveis_novos_outros',
    'fech_iniciados', 'fech_concluidos',
    'olx_leads', 'olx_whatsapp', 'organicos', 'olx_anuncios', 'olx_chats_donos',
    'disparos', 'disparos_oficial', 'disparos_zapi', 'responderam', 'responderam_oficial', 'responderam_zapi',
    'status_mudou', 'status_confirmado', 'status_oficial', 'status_zapi', 'status_outros',
    'pedidos_grupo', 'pedidos_grupo_atendidos', 'perguntas', 'perguntas_respondidas'];
  v jsonb;
BEGIN
  -- semana começa na segunda e mês no dia 1: o primeiro período não sai pela metade
  v_de  := date_trunc(v_grao, v_de::timestamp)::date;
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := (v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus';

  WITH ev(m, t, k) AS MATERIALIZED (
  -- PARCERIA: as visitas (a conversão da Parceria); quem marcou: a Nay ou alguém pelo CRM
  SELECT x.m, x.t, 'v' || v.id
    FROM nai_visita v
   CROSS JOIN LATERAL (VALUES ('visitas', v.criado_em),
                              (CASE WHEN v.criada_no_crm_por IS NULL THEN 'visitas_nay' ELSE 'visitas_crm' END, v.criado_em),
                              -- confirmada: pelo corretor, aprovada pela equipe ou confirmada no fim do fluxo
                              ('visitas_confirmadas', coalesce(v.confirmada_em, v.confirmada_corretor_em, v.aprovada_em)),
                              ('visitas_marcadas_para', CASE WHEN v.estado NOT IN ('cancelada', 'expirada') THEN v.quando END)) x(m, t)
   WHERE v.excluida_em IS NULL AND x.t >= v_ini AND x.t < v_fim
  -- PARCERIA: imóvel que saiu (card ou foto) para alguém: pela Nay (nay-core e a NAI velha) ou pela equipe
  UNION ALL
  SELECT x.m, s.enviado_em, x.k
    FROM (SELECT CASE WHEN papel_destino = 'entrega' THEN 'enviados_equipe' ELSE 'enviados_nay' END AS quem,
                 chave_destino, codigo, enviado_em
            FROM nai_saida
           WHERE estado = 'enviado' AND codigo IS NOT NULL AND enviado_em >= v_ini AND enviado_em < v_fim
          UNION ALL
          SELECT 'enviados_nay', chave_destino, codigo, enviado_em
            FROM core_saida
           WHERE estado = 'enviado' AND codigo IS NOT NULL AND enviado_em >= v_ini AND enviado_em < v_fim) s
   CROSS JOIN LATERAL (VALUES (s.quem, s.chave_destino || '|' || s.codigo),
                              ('enviados', s.chave_destino || '|' || s.codigo),
                              ('destinatarios', s.chave_destino)) x(m, k)
   WHERE right(regexp_replace(s.chave_destino, '\D', '', 'g'), 8) <> ALL (v_int)
  -- CAPTAÇÃO (8595): imóvel que a Nay do WhatsApp mandou para cliente da OLX/orgânico
  UNION ALL
  SELECT x.m, e.enviado_em, x.k
    FROM privado.olx_cliente_enviada e
    JOIN privado.olx_lead_whatsapp w ON w.id = e.lead
   CROSS JOIN LATERAL (VALUES ('enviados_captacao', e.lead || '|' || e.codigo),
                              ('destinatarios_captacao', e.lead::text)) x(m, k)
   WHERE e.tipo = 'card' AND e.codigo IS NOT NULL AND e.enviado_em >= v_ini AND e.enviado_em < v_fim
     AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  -- GRUPOS: os posts de imóvel nos grupos de corretores
  UNION ALL
  SELECT x.m, e.enviado_em, x.k
    FROM envios e
   CROSS JOIN LATERAL (VALUES ('grupo_posts', 'e' || e.id), ('grupo_imoveis', e.codigo::text)) x(m, k)
   WHERE e.destino = 'grupo' AND e.enviado_em >= v_ini AND e.enviado_em < v_fim
  -- IMÓVEIS NOVOS no cadastro (a carga da planilha do site antigo de 26/09 não é imóvel novo)
  UNION ALL
  SELECT x.m, i.criado_em, i.codigo::text
    FROM imoveis i
   CROSS JOIN LATERAL (VALUES ('imoveis_novos'),
                              ('imoveis_novos_' || CASE WHEN i.origem IN ('site', 'olx', 'crm') THEN i.origem ELSE 'outros' END)) x(m)
   WHERE i.origem IS DISTINCT FROM 'planilha_site_antigo_20260926' AND i.criado_em >= v_ini AND i.criado_em < v_fim
  -- FECHAMENTO: os da aba Fechamento
  UNION ALL
  SELECT x.m, x.t, 'f' || f.id
    FROM nai_fechamento f
   CROSS JOIN LATERAL (VALUES ('fech_iniciados', f.iniciado_em), ('fech_concluidos', f.concluido_em)) x(m, t)
   WHERE x.t >= v_ini AND x.t < v_fim
  -- OLX: os leads que a OLX manda, os que chegaram ao WhatsApp (e os orgânicos), as visitas, os anúncios e os
  -- chats com proprietários
  UNION ALL
  SELECT 'olx_leads', o.recebido_em, coalesce(nullif(right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8), ''), 'ol' || o.id)
    FROM privado.olx_lead o
   WHERE o.recebido_em >= v_ini AND o.recebido_em < v_fim
     AND right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT CASE WHEN w.origem = 'organico' THEN 'organicos' ELSE 'olx_whatsapp' END, w.criado_em, 'w' || w.id
    FROM privado.olx_lead_whatsapp w
   WHERE w.criado_em >= v_ini AND w.criado_em < v_fim
     AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT x.m, x.t, 'ov' || ov.id
    FROM privado.olx_visita ov
    JOIN privado.olx_lead_whatsapp w ON w.id = ov.lead
   CROSS JOIN LATERAL (VALUES ('visitas_olx', ov.criado_em), ('visitas_olx_confirmadas', ov.confirmada_em)) x(m, t)
   WHERE x.t >= v_ini AND x.t < v_fim
     AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT 'olx_anuncios', a.publicado_em, 'a' || a.id
    FROM privado.olx_anuncio a WHERE a.publicado_em >= v_ini AND a.publicado_em < v_fim
  UNION ALL
  SELECT 'olx_chats_donos', c.criado_em, 'c' || c.id
    FROM privado.olx_chat c WHERE c.criado_em >= v_ini AND c.criado_em < v_fim
  -- DISPAROS para proprietários: o que saiu (pela oficial ou pela Z-API), quem respondeu e quem mudou/confirmou o status
  UNION ALL
  SELECT x.m, m.criada_em, 'cm' || m.id
    FROM captacao_mensagens m
   CROSS JOIN LATERAL (VALUES ('disparos'),
                              (CASE WHEN m.message_id LIKE 'wamid.%' THEN 'disparos_oficial' ELSE 'disparos_zapi' END)) x(m)
   WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND coalesce(m.status, '') !~* '^(falhou|nao entregue|não entregue)'
     AND m.criada_em >= v_ini AND m.criada_em < v_fim
  UNION ALL
  -- por número: o canal de hoje do dono (oficial ou Z-API); a mudança sem dono ligado fica em "outros"
  SELECT x.m, l.respondeu_em, 'cl' || l.id
    FROM captacao_leads l
   CROSS JOIN LATERAL (VALUES ('responderam'),
                              (CASE WHEN l.canal = 'oficial' THEN 'responderam_oficial' ELSE 'responderam_zapi' END)) x(m)
   WHERE l.respondeu_em >= v_ini AND l.respondeu_em < v_fim
     AND right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT x.m, mu.criado_em, 'im' || mu.id
    FROM privado.imovel_mudanca mu
    LEFT JOIN captacao_leads l ON l.id = mu.lead_id
   CROSS JOIN LATERAL (VALUES (CASE WHEN mu.tipo = 'mudanca' THEN 'status_mudou' ELSE 'status_confirmado' END),
                              (CASE WHEN l.id IS NULL THEN 'status_outros' WHEN l.canal = 'oficial' THEN 'status_oficial'
                                    ELSE 'status_zapi' END)) x(m)
   WHERE mu.tipo IN ('mudanca', 'confirmacao') AND mu.desfeito_em IS NULL
     AND mu.criado_em >= v_ini AND mu.criado_em < v_fim
  -- GRUPOS: os pedidos de imóvel que os corretores fazem nos grupos (o mesmo pedido em vários grupos conta uma vez)
  UNION ALL
  SELECT x.m, g.enviada_em, x.k
    FROM privado.grupo_pedido g
    LEFT JOIN LATERAL (SELECT j.card FROM privado.grupo_pedido_junto j WHERE j.pedido_id = g.id LIMIT 1) j ON true
   CROSS JOIN LATERAL (VALUES ('pedidos_grupo', 'gp' || coalesce(j.card, g.id)),
                              ('pedidos_grupo_atendidos', CASE WHEN g.estado = 'enviado' THEN 'gp' || coalesce(j.card, g.id) END)) x(m, k)
   WHERE g.fonte = 'grupo' AND g.enviada_em >= v_ini AND g.enviada_em < v_fim AND x.k IS NOT NULL
  -- A FILA DE PERGUNTAS ao Tel (a limpeza que ele fez em 16/10, "zerada pelo Tel", não conta)
  UNION ALL
  SELECT x.m, x.t, 'pf' || p.id
    FROM pergunta_fila p
   CROSS JOIN LATERAL (VALUES ('perguntas', p.criada_em), ('perguntas_respondidas', p.respondida_em)) x(m, t)
   WHERE coalesce(p.detalhe, '') !~* '^zerada' AND x.t >= v_ini AND x.t < v_fim
  ), per AS (
    SELECT generate_series(v_de::timestamp, v_ate::timestamp, ('1 ' || v_grao)::interval)::date AS p
  ), agg AS (
    SELECT m, date_trunc(v_grao, t AT TIME ZONE 'America/Manaus')::date AS p, count(DISTINCT k) AS n
      FROM ev GROUP BY 1, 2
  ), nomes AS (
    SELECT unnest(v_nomes) AS m UNION SELECT DISTINCT m FROM ev
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate,
    'grao', CASE v_grao WHEN 'week' THEN 'semana' WHEN 'month' THEN 'mes' ELSE 'dia' END,
    'gerado_em', now(),
    'periodos', (SELECT jsonb_agg(p ORDER BY p) FROM per),
    'internos', to_jsonb(v_int),
    'serie', (SELECT jsonb_object_agg(n.m, (SELECT jsonb_agg(coalesce(a.n, 0) ORDER BY per.p)
                                              FROM per LEFT JOIN agg a ON a.m = n.m AND a.p = per.p))
                FROM nomes n),
    'totais', (SELECT jsonb_object_agg(n.m, coalesce(t.n, 0))
                 FROM nomes n LEFT JOIN (SELECT m, count(DISTINCT k) AS n FROM ev GROUP BY m) t ON t.m = n.m),
    -- os códigos que mais saíram (Parceria e Captação), com o que o imóvel é
    'top_imoveis', (
    SELECT coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'vezes', c.vezes, 'tipo', i.tipo, 'bairro', i.bairro,
                                                 'condominio', i.condominio_nome, 'venda', i.valor_venda, 'aluguel', i.valor_aluguel)
                              ORDER BY c.vezes DESC, c.codigo), '[]'::jsonb)
      FROM (SELECT split_part(k, '|', 2)::int AS codigo, count(DISTINCT k) AS vezes   -- vezes = pessoas que receberam
              FROM ev WHERE m IN ('enviados', 'enviados_captacao') AND split_part(k, '|', 2) ~ '^\d+$'
             GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 10) c
      LEFT JOIN imoveis i ON i.codigo = c.codigo)
  ) INTO v;

  -- cada DIA de disparo, por linha, seguido: quem recebeu naquele dia, quem respondeu em até 7 dias depois daquele
  -- disparo e quem mudou ou confirmou o status do imóvel depois dele (o dono que recebeu em dois dias conta nos dois)
  v := v || jsonb_build_object('coortes_disparo', (
    WITH d AS (
      SELECT m.lead_id, (m.criada_em AT TIME ZONE 'America/Manaus')::date AS dia, min(m.criada_em) AS quando,
             bool_or(m.message_id LIKE 'wamid.%') AS oficial
        FROM captacao_mensagens m
       WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.lead_id IS NOT NULL
         AND coalesce(m.status, '') !~* '^(falhou|nao entregue|não entregue)'
         AND m.criada_em >= v_ini AND m.criada_em < v_fim
       GROUP BY 1, 2
    ), d2 AS (
      SELECT d.*, right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) AS p8
        FROM d JOIN captacao_leads l ON l.id = d.lead_id
    ), r AS MATERIALIZED (       -- o que os donos escreveram (o telefone limpo uma vez só)
      SELECT lead_id, right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) AS p8, criada_em
        FROM captacao_mensagens
       WHERE direcao = 'recebida' AND criada_em >= v_ini AND criada_em < v_fim + interval '7 days'
    )
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.dia DESC, c.linha), '[]'::jsonb)
      FROM (SELECT d2.dia, CASE WHEN d2.oficial THEN 'oficial' ELSE 'captacao' END AS linha,
                   count(*) AS enviados,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM r
                                                   WHERE (r.lead_id = d2.lead_id OR r.p8 = d2.p8)
                                                     AND r.criada_em > d2.quando AND r.criada_em < d2.quando + interval '7 days')) AS responderam,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.imovel_mudanca mu
                                                   WHERE mu.lead_id = d2.lead_id AND mu.tipo = 'mudanca'
                                                     AND mu.desfeito_em IS NULL AND mu.criado_em >= d2.quando)) AS mudaram,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.imovel_mudanca mu
                                                   WHERE mu.lead_id = d2.lead_id AND mu.tipo IN ('mudanca', 'confirmacao')
                                                     AND mu.desfeito_em IS NULL AND mu.criado_em >= d2.quando)) AS atualizaram
              FROM d2
             WHERE d2.p8 <> ALL (v_int)
             GROUP BY 1, 2) c));

  -- OLX: dos clientes que a OLX trouxe ao WhatsApp no intervalo, quantos chegaram a cada passo
  v := v || jsonb_build_object('funil_olx', (
    WITH w AS (
      SELECT w.id, w.origem
        FROM privado.olx_lead_whatsapp w
       WHERE w.criado_em >= v_ini AND w.criado_em < v_fim
         AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
    )
    SELECT jsonb_build_object(
      'leads_olx', (SELECT count(DISTINCT coalesce(nullif(right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8), ''), 'ol' || o.id))
                      FROM privado.olx_lead o WHERE o.recebido_em >= v_ini AND o.recebido_em < v_fim
                       AND right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)),
      'no_whatsapp', count(*) FILTER (WHERE w.origem <> 'organico'),
      'organicos', count(*) FILTER (WHERE w.origem = 'organico'),
      'receberam_imovel', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.lead = w.id AND e.tipo = 'card')),
      'pediram_visita', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_visita ov WHERE ov.lead = w.id)),
      'visita_confirmada', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_visita ov WHERE ov.lead = w.id
                                                            AND (ov.confirmada_em IS NOT NULL OR ov.estado = 'confirmada'))),
      'visitaram', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_visita ov WHERE ov.lead = w.id
                                                    AND (ov.confirmada_em IS NOT NULL OR ov.estado = 'confirmada') AND ov.quando < now())))
      FROM w));

  -- a aba Fechamento: os que começaram ou terminaram no intervalo (só o primeiro nome do cliente)
  v := v || jsonb_build_object('fechamentos', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id', f.id, 'tipo', f.tipo, 'iniciado_em', f.iniciado_em, 'concluido_em', f.concluido_em,
             'nome', nullif(split_part(btrim(coalesce(c.nome_completo, c.nome_whatsapp, '')), ' ', 1), ''),
             'dias', CASE WHEN f.concluido_em IS NOT NULL THEN round(extract(epoch FROM f.concluido_em - f.iniciado_em) / 86400.0, 1) END)
           ORDER BY coalesce(f.concluido_em, f.iniciado_em) DESC), '[]'::jsonb)
      FROM nai_fechamento f
      LEFT JOIN nai_contato c ON c.id = f.contato_id
     WHERE (f.iniciado_em >= v_ini AND f.iniciado_em < v_fim) OR (f.concluido_em >= v_ini AND f.concluido_em < v_fim)));

  RETURN v;
END
$function$;

REVOKE ALL ON FUNCTION public.site_painel_internos(), public.site_painel_metricas(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_painel_metricas(date, date, text) TO nay_site_escrita, nay_site_leitura;
COMMIT;
