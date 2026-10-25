CREATE OR REPLACE FUNCTION public.crm_agentes_painel(p_horas integer DEFAULT 24)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH t AS (SELECT * FROM privado.agente_linha_do_tempo(now() - make_interval(hours => greatest(1, least(coalesce(p_horas, 24), 24 * 90))))),
  por AS (
    SELECT a.chave, a.nome, a.cor, a.ordem, a.descricao, a.tipo, a.modelo,
           count(t.agente) FILTER (WHERE t.modo = 'real') AS ativacoes,
           count(t.agente) FILTER (WHERE t.modo = 'sombra') AS sombra,
           count(DISTINCT t.chave8) FILTER (WHERE t.modo = 'real') AS conversas,
           round(avg(t.ms))::integer AS ms_medio,
           round(coalesce(sum(t.custo_usd), 0), 4) AS custo_usd,
           coalesce(sum(t.tokens), 0) AS tokens,
           count(t.erro) AS erros,
           max(t.em) AS ultima
      FROM privado.agente a LEFT JOIN t ON t.agente = a.chave
     WHERE a.canal = 'leads'
     GROUP BY a.chave, a.nome, a.cor, a.ordem, a.descricao, a.tipo, a.modelo)
  SELECT jsonb_build_object(
    'horas', p_horas,
    'modo', coalesce((SELECT valor FROM privado.olx_config WHERE chave = 'agentes'), 'nao'),
    'agentes', coalesce((SELECT jsonb_agg(to_jsonb(por) ORDER BY por.ordem) FROM por), '[]'::jsonb),
    'caminhos', coalesce((SELECT jsonb_object_agg(r.rota, r.n) FROM (
        SELECT rota, count(*) AS n FROM privado.agente_evento e, jsonb_array_elements_text(coalesce(e.decisao->'rotas', '[]'::jsonb)) rota
         WHERE e.agente = 'mestre' AND e.modo IN ('real', 'sombra') AND e.em >= now() - make_interval(hours => p_horas)
         GROUP BY rota) r), '{}'::jsonb),
    'veto', jsonb_build_object(
        'passou', (SELECT count(*) FROM privado.agente_evento WHERE agente = 'imoveis' AND acao = 'veto_passou' AND em >= now() - make_interval(hours => p_horas)),
        'barrou', (SELECT count(*) FROM privado.agente_evento WHERE agente = 'imoveis' AND acao = 'veto_barrou' AND em >= now() - make_interval(hours => p_horas))),
    'replay', (SELECT jsonb_build_object('em', e.em, 'resumo', e.decisao) FROM privado.agente_evento e
                WHERE e.modo = 'replay' AND e.acao = 'replay_resumo' ORDER BY e.em DESC LIMIT 1))
$function$;
