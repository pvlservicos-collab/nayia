CREATE OR REPLACE FUNCTION public.crm_cnm_painel()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH c AS (SELECT * FROM cnm_imoveis()),
       n AS (SELECT codigo, count(*) AS leads, max(coalesce(criado_no_portal, recebido_em)) AS ultimo
               FROM privado.cnm_lead WHERE codigo IS NOT NULL GROUP BY codigo)
  SELECT jsonb_build_object(
    'xml', 'https://api.imobeasy.online/api/chavesnamao/imoveis.xml',
    'leadsUrl', 'https://api.imobeasy.online/api/chavesnamao/leads',
    'vao', (SELECT count(*) FROM c WHERE ok),
    'ficam', (SELECT count(*) FROM c WHERE NOT ok),
    'anuncios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'codigo', c.codigo, 'ok', c.ok, 'falta', c.falta,
                    'titulo', c.imovel->>'titulo', 'tipo', c.imovel->>'tipo',
                    'valor', (c.imovel->>'valor')::numeric, 'valorLocacao', (c.imovel->>'valor_locacao')::numeric,
                    'transacao', concat_ws('+', c.imovel->>'transacao', nullif(c.imovel->>'transacao2', '')),
                    'fotos', coalesce(jsonb_array_length(c.imovel->'fotos'), 0),
                    'foto', c.imovel->'fotos'->>0,
                    'leads', coalesce(n.leads, 0), 'ultimoLead', n.ultimo)
                  ORDER BY c.ok, n.ultimo DESC NULLS LAST, c.codigo), '[]'::jsonb)
                  FROM c LEFT JOIN n ON n.codigo = c.codigo),
    'leads', (SELECT jsonb_build_object('total', count(*), 'pessoas', count(DISTINCT cnm_chave(l)),
                                        'naoLidos', count(*) FILTER (WHERE lido_em IS NULL),
                                        'autenticados', count(*) FILTER (WHERE autenticado),
                                        'ultimoEm', max(recebido_em))
                FROM privado.cnm_lead l),
    'senhaGuardada', (SELECT count(*) = 2 FROM privado.cnm_config
                       WHERE chave IN ('lead_email', 'lead_token') AND nullif(btrim(coalesce(valor, '')), '') IS NOT NULL))
$function$;
