CREATE OR REPLACE FUNCTION public.site_mudancas(p_estado text, p_codigo integer, p_limite integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- p_codigo: o histórico de UM imóvel (com as confirmações). Sem ele: a tela Mudanças recentes
  -- (p_estado = 'revisar' | 'revisadas'), sem as confirmações, que não têm o que revisar.
  SELECT jsonb_build_object(
    'contagem', (SELECT jsonb_build_object('revisar', count(*) FILTER (WHERE m.revisado_em IS NULL),
                                           'revisadas', count(*) FILTER (WHERE m.revisado_em IS NOT NULL))
                   FROM privado.imovel_mudanca m WHERE m.tipo <> 'confirmacao'),
    'itens', coalesce((
      SELECT jsonb_agg(x.j ORDER BY x.id DESC)
        FROM (SELECT m.id, jsonb_build_object(
                       'id', m.id, 'codigo', m.codigo, 'tipo', m.tipo, 'origem', m.origem, 'dono', m.dono,
                       'dito_em', m.dito_em, 'criado_em', m.criado_em, 'mensagens', m.mensagens, 'campos', m.campos,
                       'notas', to_jsonb(m.notas), 'revisado_em', m.revisado_em, 'revisado_por', m.revisado_por,
                       'desfeito_em', m.desfeito_em, 'desfeito_por', m.desfeito_por, 'desfeito_campos', to_jsonb(m.desfeito_campos),
                       'imovel', jsonb_build_object('tipo', i.tipo, 'condominio', i.condominio_nome, 'bairro', i.bairro,
                                   'status', i.status, 'valor_aluguel', i.valor_aluguel, 'valor_venda', i.valor_venda,
                                   'publicado_no_site', i.publicado_no_site,
                                   'vencimento', (SELECT max(c.vencimento) FROM contratos_locacao c WHERE c.codigo = m.codigo::text))) AS j
                FROM privado.imovel_mudanca m
                LEFT JOIN imoveis i ON i.codigo = m.codigo
               WHERE (p_codigo IS NULL OR m.codigo = p_codigo)
                 AND (p_codigo IS NOT NULL OR m.tipo <> 'confirmacao')
                 AND (p_codigo IS NOT NULL OR p_estado IS NULL
                      OR (p_estado = 'revisar' AND m.revisado_em IS NULL)
                      OR (p_estado = 'revisadas' AND m.revisado_em IS NOT NULL))
               ORDER BY m.id DESC
               LIMIT greatest(1, least(coalesce(p_limite, 300), 1000))) x), '[]'::jsonb));
$function$;
