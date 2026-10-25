-- 490: O REGISTRO DE FLUXOS DA NAY LEADS (Pedro, 25/10/2026: "deixe lá onde tem o fluxo um registro de fluxos, onde a
-- nay passou e quais ferramentas passou, tipo um log de traços").
-- Cada turno (a mensagem do cliente até a resposta) já grava os passos em privado.agente_evento com o mesmo `turno`
-- (489). Aqui:
--   o agente 'fluxo'            as portas e as ferramentas do código (a mensagem que chega, as travas, a busca na base,
--                               o envio); cinza, fora do fluxograma e fora do histórico do card
--   crm_agentes_tracos(...)     os turnos mais recentes, cada um com os passos em ordem (agente, ferramenta, resumo, ms,
--                               tokens, custo, erro e o detalhe), para a aba Arquitetura do CRM
--   crm_agentes_do_lead         igual à 489, sem os passos do 'fluxo' (o card mostra os agentes, não as portas)
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

INSERT INTO privado.agente (chave, nome, cor, ordem, descricao, tipo, modelo) VALUES
  ('fluxo', 'Fluxo', '#64748B', 9, 'As portas e as ferramentas do código: a mensagem que chega, as travas (a equipe na conversa, só agradeceu, o limite), a busca na base e o envio', 'codigo', NULL)
ON CONFLICT (chave) DO UPDATE SET nome = EXCLUDED.nome, cor = EXCLUDED.cor, ordem = EXCLUDED.ordem,
  descricao = EXCLUDED.descricao, tipo = EXCLUDED.tipo, modelo = EXCLUDED.modelo;

CREATE INDEX IF NOT EXISTS agente_evento_em ON privado.agente_evento (em DESC);

CREATE OR REPLACE FUNCTION public.crm_agentes_tracos(p_limite integer DEFAULT 40, p_antes bigint DEFAULT NULL,
                                                     p_telefone text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.crm_agentes_do_lead(p_telefone text, p_limite integer DEFAULT 60)
RETURNS TABLE (em timestamptz, agente text, nome text, cor text, acao text, detalhe text, modo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $$
  SELECT t.em, t.agente, a.nome, a.cor, t.acao, t.detalhe, t.modo
    FROM privado.agente_linha_do_tempo(now() - interval '60 days',
                                       right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)) t
    JOIN privado.agente a ON a.chave = t.agente
   WHERE length(right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)) = 8
     AND t.agente <> 'fluxo'
   ORDER BY t.em DESC
   LIMIT greatest(1, least(coalesce(p_limite, 60), 300))
$$;

GRANT EXECUTE ON FUNCTION public.crm_agentes_tracos(integer, bigint, text) TO nay, nay_disparo;

COMMIT;
