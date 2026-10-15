CREATE OR REPLACE FUNCTION public.crm_olx_metricas()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH anuncios AS (
    SELECT a.list_id, a.ad_id, a.codigo, a.negocio, a.conta, a.estado, a.olx_status, a.url,
           a.conteudo->>'subject' AS titulo, (a.conteudo->>'price')::numeric AS preco, a.publicado_em
      FROM privado.olx_anuncio a WHERE a.list_id IS NOT NULL
    UNION ALL
    SELECT DISTINCT ON (x.list_id) x.list_id, NULL, NULL, NULL, x.conta, NULL, NULL, 'https://www.olx.com.br/vi/' || x.list_id || '.htm',
           NULL, NULL, NULL
      FROM (SELECT list_id, conta FROM privado.olx_chat WHERE list_id IS NOT NULL
            UNION SELECT list_id, conta FROM privado.olx_lead WHERE list_id IS NOT NULL) x
     WHERE NOT EXISTS (SELECT 1 FROM privado.olx_anuncio a WHERE a.list_id = x.list_id)
  ), chat AS (
    SELECT h.list_id, count(DISTINCT h.id) AS conversas,
           count(m.id) FILTER (WHERE m.de = 'comprador') AS recebidas,
           count(m.id) FILTER (WHERE m.de = 'nos') AS enviadas,
           count(m.id) FILTER (WHERE m.de = 'nos' AND coalesce(m.enviada_por, '') ~* '^nay') AS da_nay,
           count(DISTINCT h.id) FILTER (WHERE h.ultima_de = 'comprador') AS sem_resposta,
           max(m.quando) FILTER (WHERE m.de = 'comprador') AS ultima_do_cliente,
           count(m.id) FILTER (WHERE m.de = 'comprador' AND m.quando > now() - interval '7 days') AS recebidas_7d
      FROM privado.olx_chat h LEFT JOIN privado.olx_chat_mensagem m ON m.chat = h.id
     WHERE h.list_id IS NOT NULL GROUP BY h.list_id
  ), lead AS (
    SELECT l.list_id, count(*) AS leads,
           count(*) FILTER (WHERE l.origem = 'whatsapp') AS leads_whatsapp,
           count(*) FILTER (WHERE l.origem = 'telefone') AS leads_telefone,
           count(*) FILTER (WHERE l.origem = 'chat') AS leads_chat,
           count(*) FILTER (WHERE l.origem NOT IN ('whatsapp', 'telefone', 'chat') OR l.origem IS NULL) AS leads_outros,
           max(l.recebido_em) AS ultimo_lead
      FROM privado.olx_lead l WHERE l.list_id IS NOT NULL GROUP BY l.list_id
  )
  SELECT jsonb_build_object(
    'linhas', coalesce(jsonb_agg(jsonb_build_object(
       'list_id', a.list_id, 'ad_id', a.ad_id, 'codigo', a.codigo, 'negocio', a.negocio, 'conta', a.conta,
       'situacao', coalesce(a.olx_status, a.estado), 'url', a.url, 'titulo', coalesce(a.titulo, i.tipo || coalesce(' em ' || i.bairro, '')),
       'preco', a.preco, 'publicado_em', a.publicado_em,
       'dias_no_ar', CASE WHEN a.publicado_em IS NOT NULL THEN greatest(0, (now()::date - (a.publicado_em AT TIME ZONE 'America/Manaus')::date)) END,
       'conversas', coalesce(c.conversas, 0), 'recebidas', coalesce(c.recebidas, 0), 'enviadas', coalesce(c.enviadas, 0),
       'da_nay', coalesce(c.da_nay, 0), 'sem_resposta', coalesce(c.sem_resposta, 0), 'recebidas_7d', coalesce(c.recebidas_7d, 0),
       'ultima_do_cliente', c.ultima_do_cliente,
       'leads', coalesce(l.leads, 0), 'leads_whatsapp', coalesce(l.leads_whatsapp, 0), 'leads_telefone', coalesce(l.leads_telefone, 0),
       'leads_chat', coalesce(l.leads_chat, 0), 'leads_outros', coalesce(l.leads_outros, 0), 'ultimo_lead', l.ultimo_lead,
       'imovel_status', i.status, 'bairro', i.bairro, 'tipo', i.tipo)
       ORDER BY coalesce(c.recebidas, 0) DESC, coalesce(l.leads, 0) DESC, a.publicado_em DESC NULLS LAST), '[]'::jsonb),
    'leads_ligados', EXISTS (SELECT 1 FROM privado.olx_config k WHERE k.chave = 'leads_config_id' AND k.valor <> ''),
    'atualizado_em', now())
    FROM anuncios a
    LEFT JOIN chat c ON c.list_id = a.list_id
    LEFT JOIN lead l ON l.list_id = a.list_id
    LEFT JOIN imoveis i ON i.codigo = a.codigo;
$function$;
