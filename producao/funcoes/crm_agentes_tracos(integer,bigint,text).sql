CREATE OR REPLACE FUNCTION public.crm_agentes_tracos(p_limite integer DEFAULT 40, p_antes bigint DEFAULT NULL::bigint, p_telefone text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH f AS (SELECT nullif(right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8), '') AS c8),
  ev AS (
    SELECT e.*, coalesce(e.turno, 'e' || e.id) AS t
      FROM privado.agente_evento e, f
     WHERE e.modo IN ('real', 'sombra') AND e.em > now() - interval '30 days'
       AND (f.c8 IS NULL OR e.chave8 = f.c8)),
  tur AS (
    SELECT t, min(id) AS primeiro, min(em) AS inicio, max(em) AS fim, max(lead_id) AS lead_id, max(chave8) AS chave8,
           count(*) AS passos, count(erro) AS erros, sum(custo_usd) AS custo,
           sum(coalesce(tokens_entrada, 0) + coalesce(tokens_saida, 0)) AS tokens
      FROM ev
     GROUP BY t
    HAVING p_antes IS NULL OR min(id) < p_antes
     ORDER BY min(id) DESC
     LIMIT greatest(1, least(coalesce(p_limite, 40), 200)))
  SELECT jsonb_build_object('turnos', coalesce(jsonb_agg(jsonb_build_object(
      'turno', tur.t, 'primeiro', tur.primeiro, 'inicio', tur.inicio, 'fim', tur.fim,
      'duracao_ms', round(extract(epoch FROM tur.fim - tur.inicio) * 1000)::integer,
      'lead', tur.lead_id, 'chave8', tur.chave8, 'nome', w.nome, 'telefone', w.telefone, 'origem', w.origem,
      'etapa', w.etapa, 'erros', tur.erros, 'tokens', tur.tokens, 'custo_usd', round(coalesce(tur.custo, 0), 6),
      'passos', (SELECT jsonb_agg(jsonb_build_object(
                    'id', e.id, 'em', e.em, 'agente', e.agente, 'nome', a.nome, 'cor', a.cor, 'acao', e.acao,
                    'resumo', coalesce(e.decisao->>'resumo', e.decisao->>'motivo', ''), 'ms', e.ms,
                    'tokens', coalesce(e.tokens_entrada, 0) + coalesce(e.tokens_saida, 0), 'custo_usd', e.custo_usd,
                    'modelo', e.modelo, 'modo', e.modo, 'erro', e.erro, 'detalhe', e.decisao) ORDER BY e.id)
                   FROM ev e JOIN privado.agente a ON a.chave = e.agente WHERE e.t = tur.t))
    ORDER BY tur.primeiro DESC), '[]'::jsonb))
  FROM tur LEFT JOIN privado.olx_lead_whatsapp w ON w.id = tur.lead_id
$function$;
