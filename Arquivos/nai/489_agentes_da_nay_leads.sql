-- 489 (Pedro, 24/10/2026): A ARQUITETURA DE AGENTES DA NAY LEADS (o WhatsApp 8595), medida de ponta a ponta.
-- "Separa o atendimento da Nay Lead em vários agentes: 1 mestre que aciona os outros, 1 que atende e tira dúvidas,
-- 1 que escolhe imóveis, 1 de busca, 1 que organiza a visita, 1 de revisão" e "quero uma legenda de cores para cada
-- agente visível no card do lead ... uma opção ao lado da agenda, Arquitetura, com cada etapa num fluxograma ... um
-- histórico de atendimento em cada card do lead, em tags, cada agente que ativou, incluindo se um humano assumiu ...
-- de um jeito bem metrificável, para ser escalável".
--
--   privado.agente           o registro: chave, nome, cor (a legenda do CRM), ordem, o que faz, tipo, modelo
--   privado.agente_evento    uma linha por ativação: lead, turno, ação, decisão, confiança, ms, tokens, custo, modo
--   olx_config 'agentes'     nao | sombra | sim (sombra: o mestre e o veto decidem e gravam, mas nada muda no envio)
--   privado.agente_linha_do_tempo(desde, chave8)   os eventos gravados + o que os outros já registram (passos da busca,
--                            visitas, fila de perguntas, mensagens da equipe), numa linha do tempo só
--   crm_agentes(), crm_agentes_do_lead(telefone, limite), crm_agentes_painel(horas)   as leituras do CRM
-- Agente novo = uma linha em privado.agente e um registrar() no código: o CRM mostra sozinho.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS privado.agente (
  chave      text PRIMARY KEY,
  nome       text NOT NULL,
  cor        text NOT NULL,
  ordem      integer NOT NULL DEFAULT 0,
  descricao  text NOT NULL DEFAULT '',
  canal      text NOT NULL DEFAULT 'leads',
  tipo       text NOT NULL DEFAULT 'ia' CHECK (tipo IN ('ia', 'codigo', 'gente')),
  modelo     text,
  ligado     boolean NOT NULL DEFAULT true,
  criado_em  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO privado.agente (chave, nome, cor, ordem, descricao, tipo, modelo) VALUES
  ('mestre',      'Mestre',      '#7C3AED', 1, 'Lê a mensagem nova e escolhe o caminho: perguntas fechadas ao JEV (quer imóvel? dúvida? visita? fotos? é com a equipe? só agradeceu?)', 'ia', 'typesafe/jev-1.13'),
  ('atendimento', 'Atendimento', '#16A34A', 2, 'A voz da Nay: o único que escreve ao cliente, com só as regras do caminho que o mestre escolheu', 'ia', 'gpt-6-luna'),
  ('imoveis',     'Imóveis',     '#EA580C', 3, 'Escolhe o que mandar: a busca na nossa base e o veto do JEV ("este imóvel serve para o pedido?") antes de cada card', 'ia', 'typesafe/jev-1.13'),
  ('busca',       'Busca',       '#0891B2', 4, 'Procura fora da base quando o perfil exato não existe: grupos de corretores, anunciantes da OLX e corretores parceiros', 'codigo', NULL),
  ('visita',      'Visita',      '#DB2777', 5, 'Confirma com o cliente, chama o Diego ou o corretor, fala com o proprietário e lembra antes', 'codigo', NULL),
  ('revisao',     'Revisão',     '#CA8A04', 6, 'O que a Nay não sabe vai ao agente de correção (Claude) e, sem resposta, ao PV do Tel', 'ia', 'claude'),
  ('corretores',  'Corretores',  '#4F46E5', 7, 'A Nay Corretores: o corretor que escreve no 8595 tem o imóvel dele cadastrado como parceiro', 'ia', 'gpt-6-luna'),
  ('humano',      'Humano',      '#374151', 8, 'Alguém da equipe escreveu ou assumiu a conversa', 'gente', NULL)
ON CONFLICT (chave) DO UPDATE SET nome = EXCLUDED.nome, cor = EXCLUDED.cor, ordem = EXCLUDED.ordem,
  descricao = EXCLUDED.descricao, tipo = EXCLUDED.tipo, modelo = EXCLUDED.modelo;

CREATE TABLE IF NOT EXISTS privado.agente_evento (
  id              bigserial PRIMARY KEY,
  canal           text NOT NULL DEFAULT 'leads',
  lead_id         bigint,
  chave8          text,
  agente          text NOT NULL REFERENCES privado.agente (chave),
  acao            text NOT NULL,
  turno           text,
  decisao         jsonb NOT NULL DEFAULT '{}'::jsonb,
  confianca       numeric(6, 4),
  ms              integer,
  tokens_entrada  integer,
  tokens_cache    integer,
  tokens_saida    integer,
  custo_usd       numeric(14, 8),
  modelo          text,
  modo            text NOT NULL DEFAULT 'real' CHECK (modo IN ('real', 'sombra', 'replay')),
  erro            text,
  em              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS agente_evento_chave8_em ON privado.agente_evento (chave8, em DESC);
CREATE INDEX IF NOT EXISTS agente_evento_agente_em ON privado.agente_evento (agente, em);
CREATE INDEX IF NOT EXISTS agente_evento_modo_em ON privado.agente_evento (modo, em);
CREATE INDEX IF NOT EXISTS agente_evento_turno ON privado.agente_evento (turno) WHERE turno IS NOT NULL;

-- a chave começa DESLIGADA: liga depois do replay (sombra / sim)
INSERT INTO privado.olx_config (chave, valor) VALUES ('agentes', 'nao') ON CONFLICT (chave) DO NOTHING;

-- A LINHA DO TEMPO: o que foi gravado em agente_evento + o que já fica registrado nos outros lugares (sem mexer neles).
CREATE OR REPLACE FUNCTION privado.agente_linha_do_tempo(p_desde timestamptz, p_chave8 text DEFAULT NULL)
RETURNS TABLE (em timestamptz, chave8 text, agente text, acao text, detalhe text, modo text, ms integer,
               custo_usd numeric, tokens integer, erro text)
LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $$
  -- 1) os eventos gravados pelos agentes (mestre, atendimento, imóveis, ações)
  SELECT e.em, e.chave8, e.agente, e.acao,
         coalesce(e.decisao->>'resumo', e.decisao->>'motivo', ''), e.modo, e.ms, e.custo_usd,
         coalesce(e.tokens_entrada, 0) + coalesce(e.tokens_saida, 0), e.erro
    FROM privado.agente_evento e
   WHERE e.em >= p_desde AND e.modo IN ('real', 'sombra') AND (p_chave8 IS NULL OR e.chave8 = p_chave8)
  UNION ALL
  -- 2) a busca de fundo (olx/buscas.py): grupos, OLX e corretores são a Busca; a base e a oferta são Imóveis
  SELECT p.em, right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8),
         CASE WHEN p.lugar IN ('grupos', 'olx', 'corretor') THEN 'busca' ELSE 'imoveis' END,
         'busca_' || p.lugar, left(p.texto, 160), 'real', NULL::integer, NULL::numeric, NULL::integer, NULL::text
    FROM privado.busca_cliente_passo p
    JOIN privado.busca_cliente b ON b.id = p.busca
    JOIN privado.olx_lead_whatsapp w ON w.id = b.lead
   WHERE p.em >= p_desde AND p.lugar IN ('grupos', 'olx', 'corretor', 'base', 'oferta')
     AND (p_chave8 IS NULL OR right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) = p_chave8)
  UNION ALL
  -- 3) a visita (olx/visita.py): pedida, confirmada pelo cliente, confirmada
  SELECT x.quando_ev, right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8), 'visita', x.acao,
         'imóvel ' || coalesce(v.codigo::text, '?') || ', ' || coalesce(to_char(v.quando, 'DD/MM HH24:MI'), 'sem horário')
         || ' (' || coalesce(v.estado, '') || ')', 'real', NULL, NULL, NULL, NULL
    FROM privado.olx_visita v
    JOIN privado.olx_lead_whatsapp w ON w.id = v.lead
    CROSS JOIN LATERAL (VALUES (v.criado_em, 'visita_pedida'), (v.cliente_confirmou_em, 'visita_cliente_confirmou'),
                               (v.confirmada_em, 'visita_confirmada')) AS x (quando_ev, acao)
   WHERE x.quando_ev IS NOT NULL AND x.quando_ev >= p_desde
     AND (p_chave8 IS NULL OR right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) = p_chave8)
  UNION ALL
  -- 4) a revisão: a dúvida que foi à fila (agente de correção e, sem resposta, o Tel)
  SELECT f.criada_em, right(regexp_replace(coalesce(f.chave, ''), '\D', '', 'g'), 8), 'revisao',
         'duvida_' || coalesce(f.estado, ''), left(coalesce(f.pergunta, ''), 160), 'real', NULL, NULL, NULL, NULL
    FROM public.pergunta_fila f
   WHERE f.criada_em >= p_desde AND f.linha = 'captacao'
     AND (p_chave8 IS NULL OR right(regexp_replace(coalesce(f.chave, ''), '\D', '', 'g'), 8) = p_chave8)
  UNION ALL
  -- 5) gente da equipe escrevendo por este número (uma marca por hora; o que a Nay manda não conta)
  SELECT min(m.criada_em), right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8), 'humano', 'equipe_escreveu',
         count(*) || ' mensagem(ns) da equipe', 'real', NULL, NULL, NULL, NULL
    FROM public.captacao_mensagens m
   WHERE m.criada_em >= p_desde AND m.direcao = 'enviada' AND coalesce(btrim(m.texto), '') <> ''
     AND coalesce(m.origem, '') NOT IN ('resposta', 'disparo')
     AND NOT EXISTS (SELECT 1 FROM privado.olx_cliente_enviada c WHERE c.message_id = m.message_id)
     AND EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp w2
                  WHERE right(regexp_replace(coalesce(w2.telefone, ''), '\D', '', 'g'), 8)
                        = right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8))
     AND (p_chave8 IS NULL OR right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = p_chave8)
   GROUP BY right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8), date_trunc('hour', m.criada_em)
$$;

-- CRM: a legenda (os agentes, as cores) e a chave
CREATE OR REPLACE FUNCTION public.crm_agentes()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $$
  SELECT jsonb_build_object(
    'modo', coalesce((SELECT valor FROM privado.olx_config WHERE chave = 'agentes'), 'nao'),
    'agentes', coalesce((SELECT jsonb_agg(jsonb_build_object('chave', a.chave, 'nome', a.nome, 'cor', a.cor,
                                 'descricao', a.descricao, 'tipo', a.tipo, 'modelo', a.modelo, 'ligado', a.ligado)
                                 ORDER BY a.ordem)
                         FROM privado.agente a WHERE a.canal = 'leads'), '[]'::jsonb))
$$;

-- CRM: o histórico do card (os agentes que ativaram, do mais recente para o mais antigo)
CREATE OR REPLACE FUNCTION public.crm_agentes_do_lead(p_telefone text, p_limite integer DEFAULT 60)
RETURNS TABLE (em timestamptz, agente text, nome text, cor text, acao text, detalhe text, modo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $$
  SELECT t.em, t.agente, a.nome, a.cor, t.acao, t.detalhe, t.modo
    FROM privado.agente_linha_do_tempo(now() - interval '60 days',
                                       right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)) t
    JOIN privado.agente a ON a.chave = t.agente
   WHERE length(right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)) = 8
   ORDER BY t.em DESC
   LIMIT greatest(1, least(coalesce(p_limite, 60), 300))
$$;

-- CRM: o painel da Arquitetura (cada agente no período: ativações, conversas, tempo, custo, erros; os caminhos do
-- mestre; o veto; e o último replay)
CREATE OR REPLACE FUNCTION public.crm_agentes_painel(p_horas integer DEFAULT 24)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $$
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
$$;

GRANT EXECUTE ON FUNCTION public.crm_agentes(), public.crm_agentes_do_lead(text, integer), public.crm_agentes_painel(integer)
  TO nay, nay_disparo;

COMMIT;
