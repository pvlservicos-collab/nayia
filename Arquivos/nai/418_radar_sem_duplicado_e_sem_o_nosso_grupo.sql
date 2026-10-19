-- 418: O RADAR (Grupos › Captação ativa) SEM DUPLICADO E SEM O NOSSO GRUPO (Pedro, 19/10/2026)
--
-- Pedro: "coloca daquela forma que a mesma busca em vários grupos apareça aqui só uma vez, ainda tem pedidos duplicados,
-- e outra ele está filtrando buscas de imóveis do grupo da imob easy, tem que tirar o nosso grupo".
--
-- 1. A junção da 380 só juntava o MESMO número. Ficavam dois cards: a Greyce Jane com o mesmo texto por dois números
--    (13/10 10:58 e 11:00), a Karla Amorim e a Juliana Pinheiro com o mesmo pedido palavra por palavra, a Tania e o
--    Cristian (0,97). Agora o texto igual (semelhança >= 0,85, texto com 30+ letras, mesma operação e tipo quando ditos,
--    até 72 h antes) de OUTRO número entra no card que já existe. Os cards dos últimos 10 dias são juntados de novo.
-- 2. privado.grupo_fora: os nossos grupos, que o leitor não lê e o radar, a demanda e o painel não contam.
--    Começa com o "BUSCA E OFERTA IMOB EASY 1⃣" e o "Altarquia Imob easy AI a sinistra do mercado" (o da equipe).
--    Tirar um da lista = DELETE da linha; voltar = INSERT.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.grupo_fora (
  grupo_id    text,
  grupo_nome  text,
  motivo      text NOT NULL,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  CHECK (grupo_id IS NOT NULL OR grupo_nome IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS grupo_fora_id ON privado.grupo_fora (grupo_id) WHERE grupo_id IS NOT NULL;
COMMENT ON TABLE privado.grupo_fora IS '418: grupos que não são o mercado (os nossos): o leitor da captação ativa não lê, o radar/demanda/painel não contam.';

INSERT INTO privado.grupo_fora (grupo_id, grupo_nome, motivo)
SELECT v.id, v.nome, v.motivo FROM (VALUES
  ('559291005912-1563982274', 'BUSCA E OFERTA IMOB EASY 1⃣', 'o grupo da Imob Easy (Pedro, 19/10)'),
  ('120363410110464366-group', 'Altarquia Imob easy AI a sinistra do mercado', 'o grupo da equipe (Pedro, 19/10)')) v(id, nome, motivo)
 WHERE NOT EXISTS (SELECT 1 FROM privado.grupo_fora f WHERE f.grupo_id = v.id);

CREATE OR REPLACE FUNCTION privado.grupo_e_nosso(p_grupo_id text, p_grupo_nome text)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  -- a conversa exportada (337) não tem o id do grupo: vale o nome
  SELECT EXISTS (SELECT 1 FROM privado.grupo_fora f
                  WHERE (p_grupo_id IS NOT NULL AND f.grupo_id = p_grupo_id)
                     OR (nullif(btrim(p_grupo_nome), '') IS NOT NULL AND lower(btrim(f.grupo_nome)) = lower(btrim(p_grupo_nome))))
$f$;

-- o card de OUTRO número com o mesmo texto (o mais antigo dos parecidos), para um pedido já em grupo_pedido_junto ou não
CREATE OR REPLACE FUNCTION privado.grupo_pedido_card_de_outro(p_pedido bigint)
RETURNS TABLE (card bigint, sem numeric) LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  WITH q AS (
    SELECT p.id, p.fonte, p.enviada_em, nullif(p.ficha->>'operacao', '') AS op, nullif(p.ficha->>'tipo', '') AS tipo,
           nullif(right(regexp_replace(coalesce(p.remetente, ''), '\D', '', 'g'), 8), '') AS quem,
           privado.grupo_texto_normal(p.texto) AS nt,
           (SELECT j.card FROM privado.grupo_pedido_junto j WHERE j.pedido_id = p.id) AS meu_card
      FROM privado.grupo_pedido p WHERE p.id = p_pedido)
  SELECT j.card, round(similarity(j.nt, q.nt)::numeric, 2)
    FROM q JOIN privado.grupo_pedido_junto j
      ON j.fonte = q.fonte AND j.pedido_id <> q.id AND j.card IS DISTINCT FROM q.meu_card
     AND j.quem IS DISTINCT FROM q.quem
     AND j.enviada_em BETWEEN q.enviada_em - interval '72 hours' AND q.enviada_em
     AND (j.operacao IS NULL OR q.op IS NULL OR j.operacao = q.op)
     AND (j.tipo IS NULL OR q.tipo IS NULL OR j.tipo = q.tipo)
   WHERE q.fonte <> 'teste' AND length(q.nt) >= 30 AND length(j.nt) >= 30 AND similarity(j.nt, q.nt) >= 0.85
   ORDER BY similarity(j.nt, q.nt) DESC, j.enviada_em, j.card
   LIMIT 1
$f$;

CREATE OR REPLACE FUNCTION privado.grupo_pedido_juntar_novos(p_dias integer DEFAULT 30)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q        record;
  v_card   bigint;
  v_motivo text;
  v_sem    numeric;
  v_n      int := 0;
BEGIN
  -- uma por vez: a lista, o rejeitar e o enviar podem chamar juntos
  PERFORM pg_advisory_xact_lock(380380);
  FOR q IN
    SELECT p.id, p.fonte, p.ref, p.enviada_em, nullif(p.ficha->>'operacao', '') AS op, nullif(p.ficha->>'tipo', '') AS tipo,
           nullif(right(regexp_replace(coalesce(p.remetente, ''), '\D', '', 'g'), 8), '') AS quem,
           privado.grupo_texto_normal(p.texto) AS nt
      FROM privado.grupo_pedido p
     WHERE p.enviada_em >= now() - make_interval(days => greatest(coalesce(p_dias, 30), 1))
       AND NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_junto j WHERE j.pedido_id = p.id)
     ORDER BY p.enviada_em, p.id
     LIMIT 5000
  LOOP
    v_card := NULL; v_motivo := 'proprio'; v_sem := NULL;
    IF q.fonte <> 'teste' AND length(q.quem) = 8 THEN
      -- outra parte da mesma mensagem, ou o mesmo texto colado de novo (o que a 371 já juntava)
      SELECT j.card, CASE WHEN j.ref = q.ref THEN 'mesma_mensagem' ELSE 'mesmo_texto' END INTO v_card, v_motivo
        FROM privado.grupo_pedido_junto j
       WHERE j.quem = q.quem AND j.fonte = q.fonte
         AND j.enviada_em BETWEEN q.enviada_em - interval '10 days' AND q.enviada_em + interval '10 days'
         AND (j.ref = q.ref OR j.nt = q.nt)
       ORDER BY (j.ref = q.ref) DESC, j.enviada_em DESC
       LIMIT 1;
      -- o mesmo pedido reescrito
      IF v_card IS NULL THEN
        SELECT j.card, s.sem INTO v_card, v_sem
          FROM privado.grupo_pedido_junto j
          CROSS JOIN LATERAL (SELECT similarity(j.nt, q.nt)::numeric AS sem) s
         WHERE j.quem = q.quem AND j.fonte = q.fonte
           AND j.enviada_em BETWEEN q.enviada_em - interval '72 hours' AND q.enviada_em + interval '72 hours'
           AND (s.sem >= 0.60
                OR (s.sem >= 0.50 AND (j.operacao IS NULL OR q.op IS NULL OR j.operacao = q.op)
                                  AND (j.tipo IS NULL OR q.tipo IS NULL OR j.tipo = q.tipo)))
         ORDER BY s.sem DESC, j.enviada_em DESC
         LIMIT 1;
        v_motivo := 'parecido';
      END IF;
    END IF;
    -- 418 (Pedro, 19/10: "a mesma busca em vários grupos apareça só uma vez"): o mesmo texto vindo de OUTRO número
    IF v_card IS NULL AND q.fonte <> 'teste' THEN
      SELECT o.card, o.sem INTO v_card, v_sem FROM privado.grupo_pedido_card_de_outro(q.id) o;
      v_motivo := 'mesmo_texto';
    END IF;
    INSERT INTO privado.grupo_pedido_junto (pedido_id, card, motivo, semelhanca, quem, nt, fonte, ref, operacao, tipo, enviada_em)
    VALUES (q.id, coalesce(v_card, q.id), CASE WHEN v_card IS NULL THEN 'proprio' ELSE v_motivo END,
            CASE WHEN v_card IS NOT NULL THEN round(v_sem, 2) END, q.quem, q.nt, q.fonte, q.ref, q.op, q.tipo, q.enviada_em)
    ON CONFLICT (pedido_id) DO NOTHING;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END
$function$;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos(p_filtro text DEFAULT 'todos'::text, p_horas integer DEFAULT NULL::integer, p_limite integer DEFAULT 80, p_nota_min numeric DEFAULT NULL::numeric, p_ordem text DEFAULT 'recentes'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  e       privado.grupo_captacao_estado;
  v_horas int;
  v_desde timestamptz;
  v_fil   text := lower(coalesce(nullif(btrim(p_filtro), ''), 'todos'));
  v_nota  numeric := CASE WHEN p_nota_min > 0 THEN least(p_nota_min, 100) END;
  v_ord   text := CASE WHEN lower(coalesce(p_ordem, '')) = 'nota' THEN 'nota' ELSE 'recentes' END;
  v_ped   jsonb;
  v_cont  jsonb;
  v_fonte jsonb;
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  -- 380: o que chegou desde a última vez entra no card certo antes de listar
  PERFORM privado.grupo_pedido_juntar_novos();
  v_horas := least(greatest(coalesce(p_horas, nullif(e.config->>'janela_h', '')::int, 48), 1), 24 * 60);
  v_desde := now() - make_interval(hours => v_horas);

  -- 371: as solicitações da janela, cada duplicata uma vez só (a cópia mais recente já pontuada representa todas)
  IF to_regclass('pg_temp._gc_sol') IS NULL THEN
    CREATE TEMP TABLE _gc_sol (k text, id bigint, n int, ids bigint[], grupos text[], primeira timestamptz,
                               ultima timestamptz, estado text, faixa text, nota numeric, pontuado_em timestamptz,
                               fonte text, versoes int) ON COMMIT DROP;
  END IF;
  TRUNCATE _gc_sol;
  INSERT INTO _gc_sol
  WITH g AS (
    -- 380: o card (o mesmo pedido do mesmo corretor: partes da mensagem, cópias e versões reescritas); sem card, a chave da 371
    SELECT q.*, coalesce('c' || jt.card, privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte)) AS k,
           coalesce(jt.nt, q.texto) AS nt
      FROM privado.grupo_pedido q LEFT JOIN privado.grupo_pedido_junto jt ON jt.pedido_id = q.id
     WHERE q.enviada_em >= v_desde
       AND NOT privado.grupo_e_nosso(q.grupo_id, q.grupo_nome)          -- 418: os nossos grupos não são o mercado
  ), junta AS (
    -- 'vezes' conta MENSAGENS (a mesma mensagem em 3 partes é 1 vez), 'versoes' os textos diferentes
    SELECT k, count(DISTINCT fonte || ':' || ref)::int AS n, array_agg(id ORDER BY enviada_em, id) AS ids,
           count(DISTINCT nt)::int AS versoes,
           array_agg(DISTINCT grupo_nome) FILTER (WHERE nullif(btrim(grupo_nome), '') IS NOT NULL) AS grupos,
           min(enviada_em) AS primeira, max(enviada_em) AS ultima,
           CASE WHEN bool_or(estado = 'enviado') THEN 'enviado' WHEN bool_or(estado = 'rejeitado') THEN 'rejeitado'
                WHEN bool_or(estado = 'aprovado') THEN 'aprovado' ELSE 'novo' END AS estado
      FROM g GROUP BY k
  ), rep AS (
    -- 380: a versão mais recente, e dela a parte de melhor nota
    SELECT DISTINCT ON (k) k, id, faixa, nota, pontuado_em, fonte FROM g
     ORDER BY k, (pontuado_em IS NULL), enviada_em DESC, nota DESC NULLS LAST, parte, id DESC
  )
  SELECT j.k, r.id, j.n, j.ids, coalesce(j.grupos, '{}'), j.primeira, j.ultima, j.estado, r.faixa, r.nota, r.pontuado_em, r.fonte,
         j.versoes
    FROM junta j JOIN rep r USING (k);

  SELECT jsonb_build_object(
           'todos',     count(*),
           'verde',     count(*) FILTER (WHERE s.faixa = 'verde'),
           'amarelo',   count(*) FILTER (WHERE s.faixa = 'amarelo'),
           'registro',  count(*) FILTER (WHERE s.faixa = 'registro'),
           'sem_match', count(*) FILTER (WHERE s.faixa = 'sem_match'),
           'a_pontuar', count(*) FILTER (WHERE s.pontuado_em IS NULL),
           'teste',     count(*) FILTER (WHERE s.fonte = 'teste'),
           'mensagens', coalesce(sum(s.n), 0),                         -- 371: com as cópias
           'juntadas',  count(*) FILTER (WHERE s.n > 1),
           'nota_min',  v_nota,
           'com_a_nota', count(*) FILTER (WHERE v_nota IS NULL OR s.nota >= v_nota))
    INTO v_cont FROM _gc_sol s;

  -- o que chega dos grupos (para a tela dizer quando a fonte está muda)
  SELECT jsonb_build_object(
           'mensagens',  count(*),
           'com_texto',  count(*) FILTER (WHERE nullif(btrim(c.texto), '') IS NOT NULL),
           'grupos',     count(DISTINCT c.grupo_id),
           'ultima_com_texto', max(c.enviada_em) FILTER (WHERE nullif(btrim(c.texto), '') IS NOT NULL),
           'lidas',      (SELECT count(*) FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.lida_em >= v_desde))
    INTO v_fonte FROM privado.grupo_conversa c WHERE c.enviada_em >= v_desde AND NOT c.de_mim;

  -- 337: o que veio de conversa exportada, e o que ainda está na fila do leitor (grupo, importada e teste)
  v_fonte := v_fonte || jsonb_build_object(
    'importadas', (SELECT count(*) FROM privado.grupo_importada g WHERE g.enviada_em >= v_desde),
    'grupos_importados', (SELECT count(DISTINCT g.grupo_nome) FROM privado.grupo_importada g WHERE g.enviada_em >= v_desde),
    'na_fila', (SELECT count(*) FROM privado.grupo_importada g WHERE g.enviada_em >= v_desde
                   AND NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.ref = g.ref))
             + (SELECT count(*) FROM privado.grupo_conversa c WHERE c.enviada_em >= v_desde AND NOT c.de_mim
                   AND nullif(btrim(c.texto), '') IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.ref = c.message_id))
             + (SELECT count(*) FROM privado.grupo_pedido_teste t
                 WHERE NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'teste' AND l.ref = t.id::text)),
    'nao_eram_pedido', (SELECT count(*) FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.lida_em >= v_desde
                           AND l.pedidos = 0 AND l.erro IS NULL),
    'com_erro', (SELECT count(*) FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.lida_em >= v_desde AND l.erro IS NOT NULL));

  SELECT coalesce(jsonb_agg(x.j ORDER BY x.o1 DESC NULLS LAST, x.ultima DESC, x.id DESC), '[]'::jsonb) INTO v_ped
    FROM (
      SELECT s.id, s.ultima, CASE WHEN v_ord = 'nota' THEN s.nota END AS o1,
             jsonb_build_object(
               'id', q.id, 'fonte', q.fonte, 'parte', q.parte,
               'grupo', q.grupo_nome, 'nome', q.remetente_nome, 'telefone', q.remetente,
               'enviada_em', s.ultima, 'texto', q.texto,
               -- 371: as cópias juntadas
               'vezes', s.n, 'grupos', to_jsonb(s.grupos), 'primeira_em', s.primeira, 'ids', to_jsonb(s.ids),
               -- 380: as outras partes da mesma mensagem ("casa OU apartamento", "aluguel OU venda") e os outros textos
               'outras_partes', coalesce((SELECT jsonb_agg(jsonb_build_object('id', pp.id, 'parte', pp.parte, 'ficha', pp.ficha,
                                                                              'nota', pp.nota, 'faixa', pp.faixa) ORDER BY pp.parte)
                                            FROM privado.grupo_pedido pp
                                           WHERE pp.id = ANY (s.ids) AND pp.id <> q.id AND pp.fonte = q.fonte AND pp.ref = q.ref), '[]'::jsonb),
               'versoes', s.versoes,
               'outras_versoes', coalesce((SELECT jsonb_agg(jsonb_build_object('texto', v.texto, 'quando', v.enviada_em, 'grupo', v.grupo_nome)
                                                            ORDER BY v.enviada_em DESC)
                                             FROM (SELECT DISTINCT ON (jv.nt) pv.texto, pv.enviada_em, pv.grupo_nome
                                                     FROM privado.grupo_pedido pv JOIN privado.grupo_pedido_junto jv ON jv.pedido_id = pv.id
                                                    WHERE pv.id = ANY (s.ids)
                                                      AND jv.nt IS DISTINCT FROM (SELECT jr.nt FROM privado.grupo_pedido_junto jr WHERE jr.pedido_id = q.id)
                                                    ORDER BY jv.nt, pv.enviada_em DESC) v), '[]'::jsonb),
               'ficha', q.ficha, 'duvidosos', to_jsonb(q.duvidosos), 'local', q.local,
               'estado', s.estado, 'nota', q.nota, 'faixa', q.faixa, 'sem_match_motivo', q.sem_match_motivo,
               'funil', q.funil, 'pontuado', q.pontuado_em IS NOT NULL,
               -- 380: os imóveis desta parte na ordem dela; depois os que só as outras partes da mensagem acharam
               'pares', coalesce((SELECT jsonb_agg(x.o ORDER BY x.minha DESC, x.posicao, x.nota DESC)
                                    FROM (SELECT DISTINCT ON (p.codigo) p.codigo, (p.pedido_id = q.id) AS minha, p.posicao, p.nota,
                                                 jsonb_build_object('codigo', p.codigo, 'posicao', p.posicao, 'nota', p.nota,
                                                                    'detalhe', p.detalhe, 'acima_do_teto', p.acima_do_teto, 'imovel', p.imovel,
                                                                    'parte', pp.parte) AS o
                                            FROM privado.grupo_pedido pp JOIN privado.grupo_pedido_par p ON p.pedido_id = pp.id
                                           WHERE pp.id = q.id
                                              OR (pp.id = ANY (s.ids) AND pp.fonte = q.fonte AND pp.ref = q.ref)
                                           ORDER BY p.codigo, (p.pedido_id = q.id) DESC, p.nota DESC) x), '[]'::jsonb),
               'ofertas', coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', o.codigo, 'quando', o.enviado_em,
                                                                        'com_card', o.com_card, 'resumo', o.resumo) ORDER BY o.enviado_em)
                                      FROM privado.grupo_pedido_oferta o WHERE o.pedido_id = ANY (s.ids)), '[]'::jsonb),   -- 339
               -- 372: as mensagens de negociação digitadas na tela e mandadas no PV dele
               'negociacao', coalesce((SELECT jsonb_agg(jsonb_build_object('texto', m.texto, 'quando', m.enviado_em,
                                                                           'quem', m.quem, 'resumo', m.resumo) ORDER BY m.enviado_em)
                                         FROM privado.grupo_pedido_mensagem m WHERE m.pedido_id = ANY (s.ids)), '[]'::jsonb),
               'julgamento', (SELECT jsonb_build_object('leitura', j.leitura, 'o_que_errou', j.o_que_errou, 'quando', j.criado_em)
                                FROM privado.grupo_pedido_julgamento j WHERE j.pedido_id = ANY (s.ids) ORDER BY j.id DESC LIMIT 1)) AS j
        FROM _gc_sol s JOIN privado.grupo_pedido q ON q.id = s.id
       WHERE CASE v_fil WHEN 'verde'     THEN s.faixa = 'verde'
                        WHEN 'amarelo'   THEN s.faixa = 'amarelo'
                        WHEN 'sem_match' THEN s.faixa = 'sem_match'
                        WHEN 'teste'     THEN s.fonte = 'teste'
                        ELSE true END
         AND (v_nota IS NULL OR s.nota >= v_nota)
       ORDER BY CASE WHEN v_ord = 'nota' THEN s.nota END DESC NULLS LAST, s.ultima DESC, s.id DESC
       LIMIT least(greatest(coalesce(p_limite, 80), 1), 300)) x;

  RETURN jsonb_build_object(
    'modo',      coalesce(e.config->>'modo', 'treino'),
    'config',    e.config,
    'aviso',     e.aviso,
    'batimento', e.batimento,
    'servico_vivo', coalesce(e.batimento > now() - interval '3 minutes', false),
    'horas',     v_horas,
    'ordem',     v_ord,
    'fonte',     v_fonte,
    'contagem',  v_cont,
    'acerto',    (SELECT jsonb_build_object(
                           'julgados', count(*),
                           'corretas', count(*) FILTER (WHERE u.leitura = 'correta'),
                           'erradas',  count(*) FILTER (WHERE u.leitura = 'errada'))
                    FROM (SELECT DISTINCT ON (j.pedido_id) j.leitura
                            FROM privado.grupo_pedido_julgamento j ORDER BY j.pedido_id, j.id DESC) u),
    'pedidos',   v_ped);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_demanda(p_dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH base AS (
    SELECT coalesce((SELECT j.card FROM privado.grupo_pedido_junto j WHERE j.pedido_id = q.id), q.id) AS id, q.faixa,
           coalesce(q.local->>'operacao', q.ficha->>'operacao') AS operacao,
           nullif(q.ficha->>'quartos', '')::int AS quartos,
           nullif(q.ficha->>'preco_max', '')::numeric AS teto,
           coalesce((SELECT array_agg(DISTINCT z) FROM (
                       SELECT jsonb_array_elements_text(coalesce(q.local->'bairros', '[]'::jsonb)) AS z
                       UNION SELECT jsonb_array_elements_text(coalesce(q.local->'condominios', '[]'::jsonb))) s), ARRAY['(sem lugar)']) AS lugares
      FROM privado.grupo_pedido q
     WHERE q.fonte = 'grupo' AND NOT privado.grupo_e_nosso(q.grupo_id, q.grupo_nome)          -- 418
       AND q.enviada_em >= now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 365))
  ), linhas AS (
    SELECT b.id, b.faixa, coalesce(b.operacao, '(não disse)') AS operacao, lugar, b.quartos,
           CASE WHEN b.teto IS NULL THEN '(sem valor)'
                WHEN coalesce(b.operacao, CASE WHEN b.teto < 30000 THEN 'aluguel' ELSE 'venda' END) = 'aluguel' THEN
                  CASE WHEN b.teto <= 1500 THEN 'até 1.500' WHEN b.teto <= 2500 THEN '1.500 a 2.500' WHEN b.teto <= 4000 THEN '2.500 a 4.000'
                       WHEN b.teto <= 6000 THEN '4.000 a 6.000' ELSE 'acima de 6.000' END
                ELSE CASE WHEN b.teto <= 300000 THEN 'até 300 mil' WHEN b.teto <= 500000 THEN '300 a 500 mil' WHEN b.teto <= 800000 THEN '500 a 800 mil'
                          WHEN b.teto <= 1500000 THEN '800 mil a 1,5 mi' ELSE 'acima de 1,5 mi' END END AS faixa_de_preco
      FROM base b, unnest(b.lugares) AS lugar
  )
  SELECT jsonb_build_object(
    'dias', least(greatest(coalesce(p_dias, 30), 1), 365),
    'pedidos', (SELECT count(DISTINCT id) FROM base),
    'sem_imovel', (SELECT count(DISTINCT id) FROM base WHERE faixa = 'sem_match'),
    'linhas', coalesce((SELECT jsonb_agg(jsonb_build_object('operacao', g.operacao, 'lugar', g.lugar, 'quartos', g.quartos,
                                                             'preco', g.faixa_de_preco, 'pedidos', g.n, 'sem_imovel', g.sem)
                                         ORDER BY g.sem DESC, g.n DESC, g.lugar)
                          FROM (SELECT l.operacao, l.lugar, l.quartos, l.faixa_de_preco, count(DISTINCT l.id) AS n,
                                       count(DISTINCT l.id) FILTER (WHERE l.faixa = 'sem_match') AS sem
                                  FROM linhas l GROUP BY 1, 2, 3, 4 ORDER BY 6 DESC, 5 DESC LIMIT 60) g), '[]'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.site_painel_metricas(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_grao text DEFAULT 'dia'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_grao text := CASE lower(coalesce(p_grao, 'dia')) WHEN 'semana' THEN 'week' WHEN 'mes' THEN 'month' ELSE 'day' END;
  v_hoje date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_ate  date := least(coalesce(p_ate, v_hoje), v_hoje);
  v_de   date := greatest(least(coalesce(p_de, v_ate - 29), v_ate), v_ate - 400);
  v_ini  timestamptz;
  v_fim  timestamptz;
  v_int  text[] := site_painel_internos();
  v_nomes text[] := ARRAY[
    'visitas', 'visitas_nay', 'visitas_crm', 'visitas_confirmadas', 'visitas_marcadas_para',
    'visitas_olx', 'visitas_olx_confirmadas',
    'visitas_realizadas', 'visitas_desistiu', 'visitas_fechou', 'visitas_sem_resultado',
    'enviados', 'enviados_nay', 'enviados_equipe', 'destinatarios', 'enviados_captacao', 'destinatarios_captacao',
    'grupo_posts', 'grupo_imoveis',
    'imoveis_novos', 'imoveis_novos_site', 'imoveis_novos_olx', 'imoveis_novos_crm', 'imoveis_novos_outros',
    'fech_iniciados', 'fech_concluidos',
    'olx_leads', 'olx_whatsapp', 'organicos', 'olx_anuncios', 'olx_chats_donos',
    'disparos', 'disparos_oficial', 'disparos_zapi', 'responderam', 'responderam_oficial', 'responderam_zapi',
    'status_mudou', 'status_confirmado', 'status_oficial', 'status_zapi', 'status_outros',
    'pedidos_grupo', 'pedidos_grupo_atendidos', 'perguntas', 'perguntas_respondidas'];
  v jsonb;
BEGIN
  -- semana começa na segunda e mês no dia 1: o primeiro período não sai pela metade
  v_de  := date_trunc(v_grao, v_de::timestamp)::date;
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := (v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus';

  WITH ev(m, t, k) AS MATERIALIZED (
  -- PARCERIA: as visitas (a conversão da Parceria); quem marcou: a Nay ou alguém pelo CRM
  SELECT x.m, x.t, 'v' || v.id
    FROM nai_visita v
   CROSS JOIN LATERAL (VALUES ('visitas', v.criado_em),
                              (CASE WHEN v.criada_no_crm_por IS NULL THEN 'visitas_nay' ELSE 'visitas_crm' END, v.criado_em),
                              -- confirmada: pelo corretor, aprovada pela equipe ou confirmada no fim do fluxo
                              ('visitas_confirmadas', coalesce(v.confirmada_em, v.confirmada_corretor_em, v.aprovada_em)),
                              ('visitas_marcadas_para', CASE WHEN v.estado NOT IN ('cancelada', 'expirada') THEN v.quando END)) x(m, t)
   WHERE v.excluida_em IS NULL AND x.t >= v_ini AND x.t < v_fim
  -- 404: o resultado que a equipe marcou, pelo dia da VISITA (as que já passaram); fechou também é realizada
  UNION ALL
  SELECT x.m, vv.quando, vv.k
    FROM (SELECT 'parceria' AS origem, id, quando FROM nai_visita WHERE excluida_em IS NULL AND quando IS NOT NULL
          UNION ALL SELECT 'olx', id, quando FROM privado.olx_visita WHERE quando IS NOT NULL) vv0
   CROSS JOIN LATERAL (SELECT vv0.quando, vv0.origem || vv0.id AS k) vv
    LEFT JOIN privado.visita_resultado r ON r.origem = vv0.origem AND r.visita_id = vv0.id
   CROSS JOIN LATERAL (VALUES (CASE WHEN r.resultado IN ('realizada', 'fechou') THEN 'visitas_realizadas' END),
                              (CASE WHEN r.resultado = 'fechou' THEN 'visitas_fechou' END),
                              (CASE WHEN r.resultado = 'desistiu' THEN 'visitas_desistiu' END),
                              (CASE WHEN r.resultado IS NULL THEN 'visitas_sem_resultado' END)) x(m)
   WHERE x.m IS NOT NULL AND vv.quando >= v_ini AND vv.quando < least(v_fim, now())
  -- PARCERIA: imóvel que saiu (card ou foto) para alguém: pela Nay (nay-core e a NAI velha) ou pela equipe
  UNION ALL
  SELECT x.m, s.enviado_em, x.k
    FROM (SELECT CASE WHEN papel_destino = 'entrega' THEN 'enviados_equipe' ELSE 'enviados_nay' END AS quem,
                 chave_destino, codigo, enviado_em
            FROM nai_saida
           WHERE estado = 'enviado' AND codigo IS NOT NULL AND enviado_em >= v_ini AND enviado_em < v_fim
          UNION ALL
          SELECT 'enviados_nay', chave_destino, codigo, enviado_em
            FROM core_saida
           WHERE estado = 'enviado' AND codigo IS NOT NULL AND enviado_em >= v_ini AND enviado_em < v_fim) s
   CROSS JOIN LATERAL (VALUES (s.quem, s.chave_destino || '|' || s.codigo),
                              ('enviados', s.chave_destino || '|' || s.codigo),
                              ('destinatarios', s.chave_destino)) x(m, k)
   WHERE right(regexp_replace(s.chave_destino, '\D', '', 'g'), 8) <> ALL (v_int)
  -- CAPTAÇÃO (8595): imóvel que a Nay do WhatsApp mandou para cliente da OLX/orgânico
  UNION ALL
  SELECT x.m, e.enviado_em, x.k
    FROM privado.olx_cliente_enviada e
    JOIN privado.olx_lead_whatsapp w ON w.id = e.lead
   CROSS JOIN LATERAL (VALUES ('enviados_captacao', e.lead || '|' || e.codigo),
                              ('destinatarios_captacao', e.lead::text)) x(m, k)
   WHERE e.tipo = 'card' AND e.codigo IS NOT NULL AND e.enviado_em >= v_ini AND e.enviado_em < v_fim
     AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  -- GRUPOS: os posts de imóvel nos grupos de corretores
  UNION ALL
  SELECT x.m, e.enviado_em, x.k
    FROM envios e
   CROSS JOIN LATERAL (VALUES ('grupo_posts', 'e' || e.id), ('grupo_imoveis', e.codigo::text)) x(m, k)
   WHERE e.destino = 'grupo' AND e.enviado_em >= v_ini AND e.enviado_em < v_fim
  -- IMÓVEIS NOVOS no cadastro (a carga da planilha do site antigo de 26/09 não é imóvel novo)
  UNION ALL
  SELECT x.m, i.criado_em, i.codigo::text
    FROM imoveis i
   CROSS JOIN LATERAL (VALUES ('imoveis_novos'),
                              ('imoveis_novos_' || CASE WHEN i.origem IN ('site', 'olx', 'crm') THEN i.origem ELSE 'outros' END)) x(m)
   WHERE i.origem IS DISTINCT FROM 'planilha_site_antigo_20260926' AND i.criado_em >= v_ini AND i.criado_em < v_fim
  -- FECHAMENTO: os da aba Fechamento
  UNION ALL
  SELECT x.m, x.t, 'f' || f.id
    FROM nai_fechamento f
   CROSS JOIN LATERAL (VALUES ('fech_iniciados', f.iniciado_em), ('fech_concluidos', f.concluido_em)) x(m, t)
   WHERE x.t >= v_ini AND x.t < v_fim
  -- OLX: os leads que a OLX manda, os que chegaram ao WhatsApp (e os orgânicos), as visitas, os anúncios e os
  -- chats com proprietários
  UNION ALL
  SELECT 'olx_leads', o.recebido_em, coalesce(nullif(right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8), ''), 'ol' || o.id)
    FROM privado.olx_lead o
   WHERE o.recebido_em >= v_ini AND o.recebido_em < v_fim
     AND right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT CASE WHEN w.origem = 'organico' THEN 'organicos' ELSE 'olx_whatsapp' END, w.criado_em, 'w' || w.id
    FROM privado.olx_lead_whatsapp w
   WHERE w.criado_em >= v_ini AND w.criado_em < v_fim
     AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT x.m, x.t, 'ov' || ov.id
    FROM privado.olx_visita ov
    JOIN privado.olx_lead_whatsapp w ON w.id = ov.lead
   CROSS JOIN LATERAL (VALUES ('visitas_olx', ov.criado_em), ('visitas_olx_confirmadas', ov.confirmada_em)) x(m, t)
   WHERE x.t >= v_ini AND x.t < v_fim
     AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT 'olx_anuncios', a.publicado_em, 'a' || a.id
    FROM privado.olx_anuncio a WHERE a.publicado_em >= v_ini AND a.publicado_em < v_fim
  UNION ALL
  SELECT 'olx_chats_donos', c.criado_em, 'c' || c.id
    FROM privado.olx_chat c WHERE c.criado_em >= v_ini AND c.criado_em < v_fim
  -- DISPAROS para proprietários: o que saiu (pela oficial ou pela Z-API), quem respondeu e quem mudou/confirmou o status
  UNION ALL
  SELECT x.m, m.criada_em, 'cm' || m.id
    FROM captacao_mensagens m
   CROSS JOIN LATERAL (VALUES ('disparos'),
                              (CASE WHEN m.message_id LIKE 'wamid.%' THEN 'disparos_oficial' ELSE 'disparos_zapi' END)) x(m)
   WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND coalesce(m.status, '') !~* '^(falhou|nao entregue|não entregue)'
     AND m.criada_em >= v_ini AND m.criada_em < v_fim
  UNION ALL
  -- por número: o canal de hoje do dono (oficial ou Z-API); a mudança sem dono ligado fica em "outros"
  SELECT x.m, l.respondeu_em, 'cl' || l.id
    FROM captacao_leads l
   CROSS JOIN LATERAL (VALUES ('responderam'),
                              (CASE WHEN l.canal = 'oficial' THEN 'responderam_oficial' ELSE 'responderam_zapi' END)) x(m)
   WHERE l.respondeu_em >= v_ini AND l.respondeu_em < v_fim
     AND right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
  UNION ALL
  SELECT x.m, mu.criado_em, 'im' || mu.id
    FROM privado.imovel_mudanca mu
    LEFT JOIN captacao_leads l ON l.id = mu.lead_id
   CROSS JOIN LATERAL (VALUES (CASE WHEN mu.tipo = 'mudanca' THEN 'status_mudou' ELSE 'status_confirmado' END),
                              (CASE WHEN l.id IS NULL THEN 'status_outros' WHEN l.canal = 'oficial' THEN 'status_oficial'
                                    ELSE 'status_zapi' END)) x(m)
   WHERE mu.tipo IN ('mudanca', 'confirmacao') AND mu.desfeito_em IS NULL
     AND mu.criado_em >= v_ini AND mu.criado_em < v_fim
  -- GRUPOS: os pedidos de imóvel que os corretores fazem nos grupos (o mesmo pedido em vários grupos conta uma vez)
  UNION ALL
  SELECT x.m, g.enviada_em, x.k
    FROM privado.grupo_pedido g
    LEFT JOIN LATERAL (SELECT j.card FROM privado.grupo_pedido_junto j WHERE j.pedido_id = g.id LIMIT 1) j ON true
   CROSS JOIN LATERAL (VALUES ('pedidos_grupo', 'gp' || coalesce(j.card, g.id)),
                              ('pedidos_grupo_atendidos', CASE WHEN g.estado = 'enviado' THEN 'gp' || coalesce(j.card, g.id) END)) x(m, k)
   WHERE g.fonte = 'grupo' AND g.enviada_em >= v_ini AND g.enviada_em < v_fim AND x.k IS NOT NULL
     AND NOT privado.grupo_e_nosso(g.grupo_id, g.grupo_nome)                                     -- 418
  -- A FILA DE PERGUNTAS ao Tel (a limpeza que ele fez em 16/10, "zerada pelo Tel", não conta)
  UNION ALL
  SELECT x.m, x.t, 'pf' || p.id
    FROM pergunta_fila p
   CROSS JOIN LATERAL (VALUES ('perguntas', p.criada_em), ('perguntas_respondidas', p.respondida_em)) x(m, t)
   WHERE coalesce(p.detalhe, '') !~* '^zerada' AND x.t >= v_ini AND x.t < v_fim
  ), per AS (
    SELECT generate_series(v_de::timestamp, v_ate::timestamp, ('1 ' || v_grao)::interval)::date AS p
  ), agg AS (
    SELECT m, date_trunc(v_grao, t AT TIME ZONE 'America/Manaus')::date AS p, count(DISTINCT k) AS n
      FROM ev GROUP BY 1, 2
  ), nomes AS (
    SELECT unnest(v_nomes) AS m UNION SELECT DISTINCT m FROM ev
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate,
    'grao', CASE v_grao WHEN 'week' THEN 'semana' WHEN 'month' THEN 'mes' ELSE 'dia' END,
    'gerado_em', now(),
    'periodos', (SELECT jsonb_agg(p ORDER BY p) FROM per),
    'internos', to_jsonb(v_int),
    'serie', (SELECT jsonb_object_agg(n.m, (SELECT jsonb_agg(coalesce(a.n, 0) ORDER BY per.p)
                                              FROM per LEFT JOIN agg a ON a.m = n.m AND a.p = per.p))
                FROM nomes n),
    'totais', (SELECT jsonb_object_agg(n.m, coalesce(t.n, 0))
                 FROM nomes n LEFT JOIN (SELECT m, count(DISTINCT k) AS n FROM ev GROUP BY m) t ON t.m = n.m),
    -- os códigos que mais saíram (Parceria e Captação), com o que o imóvel é
    'top_imoveis', (
    SELECT coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'vezes', c.vezes, 'tipo', i.tipo, 'bairro', i.bairro,
                                                 'condominio', i.condominio_nome, 'venda', i.valor_venda, 'aluguel', i.valor_aluguel)
                              ORDER BY c.vezes DESC, c.codigo), '[]'::jsonb)
      FROM (SELECT split_part(k, '|', 2)::int AS codigo, count(DISTINCT k) AS vezes   -- vezes = pessoas que receberam
              FROM ev WHERE m IN ('enviados', 'enviados_captacao') AND split_part(k, '|', 2) ~ '^\d+$'
             GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 10) c
      LEFT JOIN imoveis i ON i.codigo = c.codigo)
  ) INTO v;

  -- cada DIA de disparo, por linha, seguido: quem recebeu naquele dia, quem respondeu em até 7 dias depois daquele
  -- disparo e quem mudou ou confirmou o status do imóvel depois dele (o dono que recebeu em dois dias conta nos dois)
  v := v || jsonb_build_object('coortes_disparo', (
    WITH d AS (
      SELECT m.lead_id, (m.criada_em AT TIME ZONE 'America/Manaus')::date AS dia, min(m.criada_em) AS quando,
             bool_or(m.message_id LIKE 'wamid.%') AS oficial
        FROM captacao_mensagens m
       WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.lead_id IS NOT NULL
         AND coalesce(m.status, '') !~* '^(falhou|nao entregue|não entregue)'
         AND m.criada_em >= v_ini AND m.criada_em < v_fim
       GROUP BY 1, 2
    ), d2 AS (
      SELECT d.*, right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) AS p8
        FROM d JOIN captacao_leads l ON l.id = d.lead_id
    ), r AS MATERIALIZED (       -- o que os donos escreveram (o telefone limpo uma vez só)
      SELECT lead_id, right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) AS p8, criada_em
        FROM captacao_mensagens
       WHERE direcao = 'recebida' AND criada_em >= v_ini AND criada_em < v_fim + interval '7 days'
    )
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.dia DESC, c.linha), '[]'::jsonb)
      FROM (SELECT d2.dia, CASE WHEN d2.oficial THEN 'oficial' ELSE 'captacao' END AS linha,
                   count(*) AS enviados,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM r
                                                   WHERE (r.lead_id = d2.lead_id OR r.p8 = d2.p8)
                                                     AND r.criada_em > d2.quando AND r.criada_em < d2.quando + interval '7 days')) AS responderam,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.imovel_mudanca mu
                                                   WHERE mu.lead_id = d2.lead_id AND mu.tipo = 'mudanca'
                                                     AND mu.desfeito_em IS NULL AND mu.criado_em >= d2.quando)) AS mudaram,
                   count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.imovel_mudanca mu
                                                   WHERE mu.lead_id = d2.lead_id AND mu.tipo IN ('mudanca', 'confirmacao')
                                                     AND mu.desfeito_em IS NULL AND mu.criado_em >= d2.quando)) AS atualizaram
              FROM d2
             WHERE d2.p8 <> ALL (v_int)
             GROUP BY 1, 2) c));

  -- OLX: dos clientes que a OLX trouxe ao WhatsApp no intervalo, quantos chegaram a cada passo
  v := v || jsonb_build_object('funil_olx', (
    WITH w AS (
      SELECT w.id, w.origem
        FROM privado.olx_lead_whatsapp w
       WHERE w.criado_em >= v_ini AND w.criado_em < v_fim
         AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)
    )
    SELECT jsonb_build_object(
      'leads_olx', (SELECT count(DISTINCT coalesce(nullif(right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8), ''), 'ol' || o.id))
                      FROM privado.olx_lead o WHERE o.recebido_em >= v_ini AND o.recebido_em < v_fim
                       AND right(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), 8) <> ALL (v_int)),
      'no_whatsapp', count(*) FILTER (WHERE w.origem <> 'organico'),
      'organicos', count(*) FILTER (WHERE w.origem = 'organico'),
      'receberam_imovel', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.lead = w.id AND e.tipo = 'card')),
      'pediram_visita', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_visita ov WHERE ov.lead = w.id)),
      'visita_confirmada', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_visita ov WHERE ov.lead = w.id
                                                            AND (ov.confirmada_em IS NOT NULL OR ov.estado = 'confirmada'))),
      'visitaram', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.olx_visita ov WHERE ov.lead = w.id
                                                    AND (ov.confirmada_em IS NOT NULL OR ov.estado = 'confirmada') AND ov.quando < now())))
      FROM w));

  -- a aba Fechamento: os que começaram ou terminaram no intervalo (só o primeiro nome do cliente)
  v := v || jsonb_build_object('fechamentos', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id', f.id, 'tipo', f.tipo, 'iniciado_em', f.iniciado_em, 'concluido_em', f.concluido_em,
             'nome', nullif(split_part(btrim(coalesce(c.nome_completo, c.nome_whatsapp, '')), ' ', 1), ''),
             'dias', CASE WHEN f.concluido_em IS NOT NULL THEN round(extract(epoch FROM f.concluido_em - f.iniciado_em) / 86400.0, 1) END)
           ORDER BY coalesce(f.concluido_em, f.iniciado_em) DESC), '[]'::jsonb)
      FROM nai_fechamento f
      LEFT JOIN nai_contato c ON c.id = f.contato_id
     WHERE (f.iniciado_em >= v_ini AND f.iniciado_em < v_fim) OR (f.concluido_em >= v_ini AND f.concluido_em < v_fim)));

  RETURN v;
END
$function$;

-- os cards dos últimos 10 dias: o mais novo entra no mais antigo de outro número com o mesmo texto (em ordem, para a
-- corrente A <- B <- C terminar toda em A)
DO $$
DECLARE r record; v_alvo bigint; v_sem numeric; v_n int := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(380380);
  FOR r IN SELECT j.card, min(j.enviada_em) AS quando FROM privado.grupo_pedido_junto j
            WHERE j.fonte = 'grupo' AND j.enviada_em > now() - interval '10 days'
            GROUP BY j.card ORDER BY 2, 1
  LOOP
    SELECT o.card, o.sem INTO v_alvo, v_sem FROM privado.grupo_pedido_card_de_outro(r.card) o;
    IF v_alvo IS NOT NULL AND v_alvo <> r.card THEN
      UPDATE privado.grupo_pedido_junto SET card = v_alvo,
             motivo = CASE WHEN pedido_id = r.card THEN 'mesmo_texto' ELSE motivo END,
             semelhanca = CASE WHEN pedido_id = r.card THEN v_sem ELSE semelhanca END
       WHERE card = r.card;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RAISE NOTICE '418: % card(s) juntados a um de outro número', v_n;
END $$;
COMMIT;
