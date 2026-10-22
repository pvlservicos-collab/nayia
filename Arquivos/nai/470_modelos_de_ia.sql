-- 470 -- MODELOS DE IA: o registro do uso, o preço, a escolha do modelo por nó e o que a página admin › Modelos lê
--
-- Pedro, 22/10/2026: "uma página nova no menu chamada Modelos, vai pegar toda a nossa tecnologia de integrações e fazer
-- uma conexão grande de nós, mostrando onde estão todos os modelos de IA e dando a opção de substituirmos esses modelos por
-- lá, e um contador de quanto estamos gastando em cada modelo, por nó de modelo ... e um painel no topo com os gastos por
-- período".
-- Antes: só o nay-core media o custo (core_trace.saida->>'custo', pelo preço de config/modelos.yaml); a captação e o
-- nay-olx jogavam fora o `usage` que a OpenAI devolve; o n8n não registra tokens.
-- - privado.ia_preco: o preço por milhão de tokens (US$), e por minuto no áudio;
-- - privado.ia_uso: uma linha por chamada (o nó, o modelo, os tokens, o custo); ia_uso_registrar() é o que os serviços
--   chamam (o custo sai do preço);
-- - privado.ia_no_modelo: o modelo escolhido para o nó (o que a página troca); ia_modelo_do_no(nó, padrão) é o que os
--   serviços leem antes de chamar. Só os nós que já leem daqui são trocáveis pela página (site_ia_modelo_trocar);
-- - site_ia_modelos(): os gastos e as chamadas por nó e por período (hoje, ontem, 7 dias, 30 dias, mês), juntando o
--   ia_uso e o core_trace do nay-core, e os turnos do n8n (só contagem: lá não há tokens).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.ia_preco (
  modelo        text PRIMARY KEY,
  entrada       numeric,           -- US$ por milhão de tokens de entrada
  entrada_cache numeric,           -- US$ por milhão de tokens de entrada em cache
  saida         numeric,           -- US$ por milhão de tokens de saída
  por_minuto    numeric,           -- US$ por minuto (áudio)
  fonte         text,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.ia_preco IS '470: preço dos modelos (US$) para o custo de ia_uso; o nay-core usa o de config/modelos.yaml.';
INSERT INTO privado.ia_preco (modelo, entrada, entrada_cache, saida, por_minuto, fonte) VALUES
  ('gpt-6-luna', 0.10, 0.01, 0.50, NULL, 'nay-core config/modelos.yaml, conferido em 30/09/2026'),
  ('gpt-4o-mini-transcribe', NULL, NULL, NULL, 0.003, 'nay-core config/modelos.yaml (12/10/2026)'),
  ('gpt-4o-transcribe', NULL, NULL, NULL, 0.006, 'nay-core config/modelos.yaml (12/10/2026)')
ON CONFLICT (modelo) DO NOTHING;

CREATE TABLE IF NOT EXISTS privado.ia_uso (
  id             bigserial PRIMARY KEY,
  no             text NOT NULL,
  modelo         text NOT NULL,
  tokens_entrada integer,
  tokens_cache   integer,
  tokens_saida   integer,
  custo_usd      numeric(14, 8),
  em             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ia_uso_no_em ON privado.ia_uso (no, em);
CREATE INDEX IF NOT EXISTS ia_uso_em ON privado.ia_uso (em);
COMMENT ON TABLE privado.ia_uso IS '470: uma linha por chamada de modelo dos serviços (captação, nay-olx): tokens e custo em US$.';

CREATE TABLE IF NOT EXISTS privado.ia_no_modelo (
  no          text PRIMARY KEY,
  modelo      text NOT NULL,
  trocado_por text,
  trocado_em  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.ia_no_modelo IS '470: o modelo escolhido para cada nó trocável (a página admin › Modelos); o serviço lê antes de chamar.';
INSERT INTO privado.ia_no_modelo (no, modelo, trocado_por) VALUES
  ('captacao.atender', 'gpt-6-luna', '470 (o que já rodava)'),
  ('olx.chat', 'gpt-6-luna', '470 (o que já rodava)'),
  ('olx.whatsapp', 'gpt-6-luna', '470 (o que já rodava)'),
  ('olx.parceiro', 'gpt-6-luna', '470 (o que já rodava)')
ON CONFLICT (no) DO NOTHING;

CREATE OR REPLACE FUNCTION public.ia_modelo_do_no(p_no text, p_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce((SELECT nullif(btrim(m.modelo), '') FROM privado.ia_no_modelo m WHERE m.no = p_no), p_padrao)
$function$;

CREATE OR REPLACE FUNCTION public.ia_uso_registrar(p_no text, p_modelo text, p_entrada integer, p_cache integer,
                                                   p_saida integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO privado.ia_uso (no, modelo, tokens_entrada, tokens_cache, tokens_saida, custo_usd)
  SELECT left(p_no, 60), left(p_modelo, 80), p_entrada, p_cache, p_saida,
         CASE WHEN p.modelo IS NULL OR p.entrada IS NULL THEN NULL
              ELSE (greatest(coalesce(p_entrada, 0) - coalesce(p_cache, 0), 0) * p.entrada
                    + coalesce(p_cache, 0) * coalesce(p.entrada_cache, p.entrada)
                    + coalesce(p_saida, 0) * coalesce(p.saida, 0)) / 1000000.0 END
    FROM (SELECT 1) x LEFT JOIN privado.ia_preco p ON p.modelo = p_modelo
$function$;

-- o nó de cada linha do core_trace (o nay-core grava o custo de cada chamada)
CREATE OR REPLACE FUNCTION public.ia_no_do_core(p_etapa text, p_modelo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_modelo ~* 'deepseek|openrouter' THEN 'core.reserva'
    WHEN p_modelo ~* 'jev' THEN 'core.jev'
    WHEN p_etapa = 'classificar' THEN 'core.classificador'
    WHEN p_etapa = 'responder_duvida' THEN 'core.duvida'
    WHEN p_etapa = 'comandos.instrucao' THEN 'core.instrucao'
    WHEN p_modelo ~* 'transcri' THEN 'core.transcricao'
    ELSE 'core.outro' END
$function$;

CREATE OR REPLACE FUNCTION public.site_ia_modelos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH dia AS (SELECT (now() AT TIME ZONE 'America/Manaus')::date AS hoje),
  uso AS MATERIALIZED (
    SELECT u.no, u.modelo, u.em, u.custo_usd AS custo FROM privado.ia_uso u WHERE u.em > now() - interval '62 days'
    UNION ALL
    SELECT ia_no_do_core(t.etapa, t.modelo), t.modelo, t.criado_em,
           CASE WHEN t.saida ? 'custo' AND (t.saida->>'custo') ~ '^[0-9.eE+-]+$' THEN (t.saida->>'custo')::numeric END
      FROM core_trace t WHERE t.modelo IS NOT NULL AND t.criado_em > now() - interval '62 days'
  ),
  -- o n8n (a Nay velha) não registra tokens: as chamadas são os turnos em que ela respondeu (uma resposta 'turno' na
  -- nai_saida), no agente do papel e na secretária, que passa por todo turno
  velha AS MATERIALIZED (
    SELECT t.papel, t.criado_em FROM nai_turno t
     WHERE t.papel IN ('corretor', 'proprietario', 'motoboy') AND t.criado_em > now() - interval '62 days'
       AND EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = t.id AND s.papel_destino = 'turno' AND s.tipo = 'texto')
  ),
  n8n AS MATERIALIZED (
    SELECT CASE v.papel WHEN 'corretor' THEN 'n8n.corretor' WHEN 'proprietario' THEN 'n8n.proprietario'
                        ELSE 'n8n.fernando' END AS no, NULL::text AS modelo, v.criado_em AS em, NULL::numeric AS custo
      FROM velha v
    UNION ALL
    SELECT 'n8n.secretaria', NULL, v.criado_em, NULL FROM velha v
  ),
  tudo AS (SELECT * FROM uso UNION ALL SELECT * FROM n8n),
  per AS (
    SELECT x.no, x.modelo, x.custo,
           (x.em AT TIME ZONE 'America/Manaus')::date AS d, d0.hoje
      FROM tudo x CROSS JOIN dia d0
  ),
  por_no AS (
    SELECT no,
           jsonb_build_object(
             'hoje',  round(coalesce(sum(custo) FILTER (WHERE d = hoje), 0), 6),
             'ontem', round(coalesce(sum(custo) FILTER (WHERE d = hoje - 1), 0), 6),
             'd7',    round(coalesce(sum(custo) FILTER (WHERE d > hoje - 7), 0), 6),
             'd30',   round(coalesce(sum(custo) FILTER (WHERE d > hoje - 30), 0), 6),
             'mes',   round(coalesce(sum(custo) FILTER (WHERE date_trunc('month', d) = date_trunc('month', hoje)), 0), 6)) AS gasto,
           jsonb_build_object(
             'hoje',  count(*) FILTER (WHERE d = hoje),
             'ontem', count(*) FILTER (WHERE d = hoje - 1),
             'd7',    count(*) FILTER (WHERE d > hoje - 7),
             'd30',   count(*) FILTER (WHERE d > hoje - 30),
             'mes',   count(*) FILTER (WHERE date_trunc('month', d) = date_trunc('month', hoje))) AS chamadas,
           bool_or(custo IS NOT NULL) AS medido,
           (array_agg(modelo ORDER BY modelo) FILTER (WHERE modelo IS NOT NULL))[1] AS modelo_visto
      FROM per GROUP BY no
  ),
  serie AS (
    SELECT jsonb_agg(jsonb_build_object('dia', to_char(g.d, 'YYYY-MM-DD'),
                                        'custo', round(coalesce((SELECT sum(p.custo) FROM per p WHERE p.d = g.d), 0), 6))
                     ORDER BY g.d) AS s
      FROM dia, generate_series(dia.hoje - 29, dia.hoje, interval '1 day') AS gs(t), LATERAL (SELECT gs.t::date AS d) g
  )
  SELECT jsonb_build_object(
    'gerado_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'nos', coalesce((SELECT jsonb_object_agg(no, jsonb_build_object('gasto', gasto, 'chamadas', chamadas, 'medido', medido,
                                                                     'modelo_visto', modelo_visto)) FROM por_no), '{}'::jsonb),
    'escolhidos', coalesce((SELECT jsonb_object_agg(m.no, jsonb_build_object('modelo', m.modelo, 'por', m.trocado_por,
                                                     'em', to_char(m.trocado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')))
                              FROM privado.ia_no_modelo m), '{}'::jsonb),
    'totais', jsonb_build_object(
       'hoje',  coalesce((SELECT round(sum(custo), 6) FROM per WHERE d = hoje), 0),
       'ontem', coalesce((SELECT round(sum(custo), 6) FROM per WHERE d = hoje - 1), 0),
       'd7',    coalesce((SELECT round(sum(custo), 6) FROM per WHERE d > hoje - 7), 0),
       'd30',   coalesce((SELECT round(sum(custo), 6) FROM per WHERE d > hoje - 30), 0),
       'mes',   coalesce((SELECT round(sum(custo), 6) FROM per WHERE date_trunc('month', d) = date_trunc('month', hoje)), 0)),
    'serie', (SELECT s FROM serie),
    'precos', coalesce((SELECT jsonb_object_agg(p.modelo, jsonb_build_object('entrada', p.entrada, 'entrada_cache', p.entrada_cache,
                                                  'saida', p.saida, 'por_minuto', p.por_minuto, 'fonte', p.fonte))
                          FROM privado.ia_preco p), '{}'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.site_ia_modelo_trocar(p_no text, p_modelo text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_antes text;
  v_mod   text := btrim(coalesce(p_modelo, ''));
BEGIN
  SELECT modelo INTO v_antes FROM privado.ia_no_modelo WHERE no = p_no;
  IF v_antes IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Este nó não é trocável pela página (o modelo dele mora no código ou no n8n).');
  END IF;
  IF v_mod !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{2,79}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Nome de modelo inválido: use o nome exato da API (ex.: gpt-6-luna).');
  END IF;
  UPDATE privado.ia_no_modelo SET modelo = v_mod, trocado_por = left(coalesce(nullif(btrim(p_quem), ''), 'admin'), 80),
         trocado_em = now() WHERE no = p_no;
  RETURN jsonb_build_object('ok', true, 'no', p_no, 'antes', v_antes, 'modelo', v_mod,
                            'aviso', 'O serviço usa o modelo novo na próxima chamada (até 1 minuto).');
END $function$;

GRANT EXECUTE ON FUNCTION public.ia_modelo_do_no(text, text) TO nay;
GRANT EXECUTE ON FUNCTION public.ia_uso_registrar(text, text, integer, integer, integer) TO nay;
GRANT EXECUTE ON FUNCTION public.site_ia_modelos() TO nay, nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_ia_modelo_trocar(text, text, text) TO nay, nay_site_escrita;

COMMIT;
