CREATE OR REPLACE FUNCTION public.crm_zap_painel()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH c AS (SELECT * FROM cnm_imoveis() WHERE ok),
       n AS (SELECT codigo, count(*) AS leads, max(coalesce(criado_em, recebido_em)) AS ultimo
               FROM privado.zap_lead WHERE codigo IS NOT NULL GROUP BY codigo)
  SELECT jsonb_build_object(
    'xml', 'https://api.imobeasy.online/api/zap/imoveis.xml',
    'leadsUrl', 'https://api.imobeasy.online/api/zap/leads',
    'anuncios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'codigo', c.codigo, 'ok', true, 'falta', '[]'::jsonb,
                    'titulo', c.imovel->>'titulo', 'tipo', c.imovel->>'tipo',
                    'valor', (c.imovel->>'valor')::numeric, 'valorLocacao', (c.imovel->>'valor_locacao')::numeric,
                    'transacao', concat_ws('+', c.imovel->>'transacao', nullif(c.imovel->>'transacao2', '')),
                    'fotos', coalesce(jsonb_array_length(c.imovel->'fotos'), 0),
                    'foto', c.imovel->'fotos'->>0,
                    'leads', coalesce(n.leads, 0), 'ultimoLead', n.ultimo)
                  ORDER BY n.ultimo DESC NULLS LAST, c.codigo), '[]'::jsonb)
                  FROM c LEFT JOIN n ON n.codigo = c.codigo),
    'leads', (SELECT jsonb_build_object('total', count(*), 'pessoas', count(DISTINCT zap_chave(l)),
                                        'naoLidos', count(*) FILTER (WHERE lido_em IS NULL),
                                        'autenticados', count(*) FILTER (WHERE autenticado),
                                        'ultimoEm', max(recebido_em))
                FROM privado.zap_lead l),
    'senhaGuardada', EXISTS (SELECT 1 FROM privado.zap_config
                              WHERE chave = 'lead_segredo' AND nullif(btrim(coalesce(valor, '')), '') IS NOT NULL),
    -- a mesma leitura de zap_lead_para_a_nay (572): sem a chave, a Nay não chama
    'naySim', coalesce((SELECT lower(btrim(valor)) FROM privado.zap_config WHERE chave = 'nay_atende'), 'nao') = 'sim')
$function$;
