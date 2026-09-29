-- =====================================================================
-- 163 — A CAPTAÇÃO PELO NÚMERO DA Z-API, COM SEGURANÇA (28/09/2026)
--
-- Pedro: "quero implementar a captação também pelo número de captação do
-- jeito que era antes, com bastante segurança para o número não cair, e
-- também deixando a Nay de captação ativa nesse número" (92 8595-6408,
-- instância 3F8E05).
--
-- O QUE DERRUBOU O NÚMERO EM 17/09 (memória captacao-o-teto-conta-so-disparos):
--   * o teto contava só o PRIMEIRO disparo de cada dono; o volume real era ~4x
--     (15/09: 81 mensagens da API + 161 digitadas pela equipe = 242);
--   * o sinal veio um dia antes e ninguém viu: 16/09, 36 disparos e 3 respostas
--     (8%) -- num dia normal respondiam de 38% a 74% em 24 h.
--
-- O QUE MUDA:
--   1. TETOS DO VOLUME REAL, além do teto de disparos: mensagens da API por dia
--      (disparo + resposta + lembrete) e o total do número contando a equipe.
--      Estourou qualquer um, o disparo espera o dia seguinte. A resposta a quem
--      escreveu continua saindo.
--   2. AQUECIMENTO: o teto de disparos do dia é o MENOR entre o freio
--      (limite_dia) e a rampa -- começa em rampa_inicio no dia em que religa e
--      soma rampa_passo por dia até rampa_maximo. Sem rampa_desde, teto zero.
--   3. DISJUNTOR que PAUSA SOZINHO (e o fluxo avisa o Tel no Telegram):
--      a) resposta: dos últimos 10 disparos feitos de 3 a 48 h atrás, menos de
--         disjuntor_resposta_min % responderam -- o sinal de 16/09;
--      b) entrega: os últimos disjuntor_sem_entrega disparos, 30 min depois,
--         sem o "entregue" da Z-API (webhook de status);
--      c) desconexão: a Z-API avisou que o número caiu.
--      Pausar zera a rampa: religar recomeça devagar.
--   4. RELIGAR, POR QUALQUER CAMINHO (tela, SQL): tirar a pausa marca o dia da
--      rampa e apaga o motivo do disjuntor.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

-- a entrega, pelo webhook de status da Z-API
ALTER TABLE captacao_mensagens
  ADD COLUMN IF NOT EXISTS entregue_em timestamptz,
  ADD COLUMN IF NOT EXISTS lida_em timestamptz;
CREATE INDEX IF NOT EXISTS captacao_mensagens_message_id_idx
  ON captacao_mensagens (message_id) WHERE message_id IS NOT NULL;

INSERT INTO captacao_config (chave, valor, nota) VALUES
  ('rampa_inicio', '5', 'Disparos no dia em que a campanha religa (aquecimento do número).'),
  ('rampa_passo', '2', 'Quantos disparos a mais por dia, até o máximo da rampa.'),
  ('rampa_maximo', '15', 'Máximo de disparos por dia depois do aquecimento.'),
  ('rampa_desde', '', 'Dia em que a campanha religou; a rampa conta daqui. Vazio = teto zero. Tirar a pausa preenche; o disjuntor apaga.'),
  ('limite_api_dia', '60', 'Mensagens da API por dia neste número (disparo + resposta + lembrete). Passou, o disparo espera o dia seguinte.'),
  ('limite_total_dia', '150', 'Mensagens por dia neste número contando as digitadas pela equipe. Passou, o disparo espera o dia seguinte.'),
  ('disjuntor_resposta_min', '20', '% mínimo de resposta dos últimos 10 disparos (de 3 a 48 h atrás). Abaixo disso a campanha pausa sozinha.'),
  ('disjuntor_sem_entrega', '5', 'Disparos seguidos sem confirmação de entrega 30 min depois que pausam a campanha sozinha.')
ON CONFLICT (chave) DO NOTHING;

-- o teto de disparos de hoje: o menor entre o freio e a rampa
CREATE OR REPLACE FUNCTION captacao_teto_hoje() RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT GREATEST(0, LEAST(
    COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'limite_dia'), 0),
    CASE WHEN COALESCE((SELECT btrim(valor) FROM captacao_config WHERE chave = 'rampa_desde'), '') = '' THEN 0
         -- rampa marcada para um dia que ainda não chegou: hoje é zero
         WHEN (now() AT TIME ZONE 'America/Manaus')::date
              < (SELECT btrim(valor)::date FROM captacao_config WHERE chave = 'rampa_desde') THEN 0
         ELSE LEAST(
           COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'rampa_maximo'), 0),
           COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'rampa_inicio'), 0)
             + COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'rampa_passo'), 0)
               * GREATEST(0, (now() AT TIME ZONE 'America/Manaus')::date
                             - (SELECT btrim(valor)::date FROM captacao_config WHERE chave = 'rampa_desde')))
    END))
$$;

-- o disparo está liberado agora? E se não, por quê. A MESMA resposta para o
-- fluxo (Pegar lead novo) e para a tela do CRM.
CREATE OR REPLACE FUNCTION captacao_disparo_liberado()
RETURNS TABLE (liberado boolean, motivo text, disparos_hoje int, teto_hoje int,
               api_hoje int, limite_api int, total_hoje int, limite_total int)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  -- só o que saiu por ESTE número (o lead do número oficial não conta)
  SELECT count(*) FILTER (WHERE m.origem = 'disparo'),
         count(*) FILTER (WHERE m.origem <> 'humano'),
         count(*)
    INTO disparos_hoje, api_hoje, total_hoje
    FROM captacao_mensagens m
   WHERE m.direcao = 'enviada' AND m.status <> 'Falhou'
     AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.id = m.lead_id AND l.canal = 'oficial');
  teto_hoje    := captacao_teto_hoje();
  limite_api   := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'limite_api_dia'), 0);
  limite_total := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'limite_total_dia'), 0);
  motivo := CASE
    WHEN COALESCE((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') <> 'nao' THEN
      COALESCE('pausada pelo disjuntor: ' || NULLIF((SELECT valor FROM captacao_config WHERE chave = '_disjuntor'), ''), 'pausada')
    WHEN teto_hoje <= 0 THEN 'o teto de hoje é zero (rampa não começou ou limite_dia 0)'
    WHEN disparos_hoje >= teto_hoje THEN format('já saíram os %s disparos de hoje', teto_hoje)
    WHEN api_hoje >= limite_api THEN format('a API já mandou %s mensagens hoje (limite %s)', api_hoje, limite_api)
    WHEN total_hoje >= limite_total THEN format('o número já mandou %s mensagens hoje, contando a equipe (limite %s)', total_hoje, limite_total)
    WHEN COALESCE((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim') <> 'sim'
         AND NOT captacao_no_horario(now()) THEN 'fora do horário'
    ELSE NULL END;
  liberado := motivo IS NULL;
  RETURN NEXT;
END $$;

-- pausa, anota o motivo e zera a rampa (religar recomeça devagar)
CREATE OR REPLACE FUNCTION captacao_desarmar(p_motivo text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO captacao_config (chave, valor, nota) VALUES
    ('captacao_pausada', 'sim', NULL),
    ('_disjuntor', p_motivo, 'Por que a campanha pausou sozinha. Religar apaga.'),
    ('_disjuntor_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'), 'Quando o disjuntor pausou.'),
    ('rampa_desde', '', NULL)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
$$;

-- o vigia: roda de 2 em 2 minutos (no fluxo). Devolve o motivo SÓ quando
-- acabou de desarmar -- é o que o fluxo manda para o Tel.
CREATE OR REPLACE FUNCTION captacao_vigiar() RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_pct   int := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'disjuntor_resposta_min'), 20);
  v_max   int := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'disjuntor_sem_entrega'), 5);
  v_n     int;
  v_resp  int;
  v_sem   int;
  v_vistos int;
  v_motivo text;
BEGIN
  IF COALESCE((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') <> 'nao' THEN
    RETURN NULL;
  END IF;

  -- a) RESPOSTA: o sinal de 16/09
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM captacao_mensagens r
                                         WHERE r.lead_id = d.lead_id AND r.direcao = 'recebida'
                                           AND r.criada_em > d.criada_em))
    INTO v_n, v_resp
    FROM (SELECT m.lead_id, m.criada_em FROM captacao_mensagens m
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status = 'Enviado'
             AND m.criada_em BETWEEN now() - interval '48 hours' AND now() - interval '3 hours'
           ORDER BY m.criada_em DESC LIMIT 10) d;
  IF v_n >= 10 AND v_resp * 100 < v_pct * v_n THEN
    v_motivo := format('só %s dos últimos %s disparos tiveram resposta (mínimo %s%%) -- sinal de número restrito, como em 16/09',
                       v_resp, v_n, v_pct);
  END IF;

  -- b) ENTREGA: só vale com o aviso de entrega da Z-API chegando (webhook de status)
  IF v_motivo IS NULL AND EXISTS (SELECT 1 FROM captacao_mensagens WHERE entregue_em > now() - interval '7 days') THEN
    SELECT count(*) FILTER (WHERE u.entregue_em IS NULL), count(*)
      INTO v_sem, v_vistos
      FROM (SELECT m.entregue_em FROM captacao_mensagens m
             WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status = 'Enviado'
               AND m.message_id IS NOT NULL
               AND m.criada_em BETWEEN now() - interval '48 hours' AND now() - interval '30 minutes'
             ORDER BY m.criada_em DESC LIMIT v_max) u;
    IF v_vistos >= v_max AND v_sem = v_vistos THEN
      v_motivo := format('os últimos %s disparos não foram entregues (30 min depois) -- sinal de número restrito', v_sem);
    END IF;
  END IF;

  IF v_motivo IS NULL THEN
    RETURN NULL;
  END IF;
  PERFORM captacao_desarmar(v_motivo);
  RETURN v_motivo;
END $$;

-- o aviso de status da Z-API (SENT / RECEIVED / READ / PLAYED)
CREATE OR REPLACE FUNCTION captacao_status_da_mensagem(p_ids text[], p_status text, p_momento timestamptz)
RETURNS int LANGUAGE sql AS $$
  WITH u AS (
    UPDATE captacao_mensagens
       SET entregue_em = CASE WHEN upper(p_status) IN ('RECEIVED', 'READ', 'PLAYED')
                              THEN COALESCE(entregue_em, p_momento) ELSE entregue_em END,
           lida_em = CASE WHEN upper(p_status) IN ('READ', 'PLAYED')
                          THEN COALESCE(lida_em, p_momento) ELSE lida_em END
     WHERE message_id = ANY (p_ids) AND direcao = 'enviada'
    RETURNING 1)
  SELECT count(*)::int FROM u;
$$;

-- a Z-API avisou que o número desconectou
CREATE OR REPLACE FUNCTION captacao_desconectou(p_erro text) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM captacao_desarmar('a Z-API avisou que o número desconectou'
                            || COALESCE(' (' || NULLIF(btrim(p_erro), '') || ')', ''));
  RETURN (SELECT valor FROM captacao_config WHERE chave = '_disjuntor');
END $$;

-- religar, venha de onde vier: marca o dia da rampa e apaga o motivo do disjuntor
CREATE OR REPLACE FUNCTION captacao_config_religou() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE captacao_config
     SET valor = to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD')
   WHERE chave = 'rampa_desde' AND COALESCE(btrim(valor), '') = '';
  UPDATE captacao_config SET valor = '' WHERE chave = '_disjuntor' AND COALESCE(valor, '') <> '';
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS captacao_config_religou ON captacao_config;
CREATE TRIGGER captacao_config_religou
  AFTER UPDATE ON captacao_config
  FOR EACH ROW
  WHEN (NEW.chave = 'captacao_pausada' AND NEW.valor = 'nao' AND OLD.valor IS DISTINCT FROM NEW.valor)
  EXECUTE FUNCTION captacao_config_religou();

-- a tela do CRM lê o estado (a role de escrita do site já lê captacao_config)
GRANT EXECUTE ON FUNCTION captacao_disparo_liberado() TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION captacao_teto_hoje() TO nay_site_escrita;
GRANT SELECT (entregue_em, lida_em) ON captacao_mensagens TO nay_site_escrita;

COMMIT;
