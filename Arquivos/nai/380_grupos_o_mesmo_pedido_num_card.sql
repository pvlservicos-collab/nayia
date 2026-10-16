-- 380: captação ativa por grupos -- O MESMO PEDIDO DO MESMO CORRETOR VIRA UM CARD SÓ
--
-- Pedro, 16/10/2026: "verifica lá na captação ativa dos pedidos dos grupos se não tem pedidos repetidos, o mesmo
-- corretor faz o pedido em vários grupos, se tiver devem ser todos juntados em um só card lá".
--
-- A 371 já juntava a cópia IGUAL (mesmo remetente, mesmo texto, mesma parte). Medido hoje (48 h): 653 pedidos, 208 cards,
-- e ainda 127 cards de corretores com mais de um. Sobravam:
--   1. a mesma mensagem lida em PARTES ("casa ou apartamento", "aluguel ou venda"): a Aira Araújo tinha 4 cards de 1 mensagem;
--   2. o pedido REESCRITO e colado de novo: a G Silva com 400, 350 e 450 mil; "preferência no Vista do Parque" acrescentado;
--      "2 quarta" corrigido para "2 quartos"; "em condomínio" trocado por "no condomínio" no dia seguinte.
--
-- O CARD (privado.grupo_pedido_junto, uma linha por pedido): o pedido entra no card de outro do MESMO corretor quando
--   · é outra parte da mesma mensagem, ou o mesmo texto (sem acento, pontuação, emoji e espaço) em até 10 dias; ou
--   · o texto se parece (pg_trgm, similarity) em até 72 h: 0,60 ou mais; ou 0,50 a 0,60 com o mesmo negócio e o mesmo tipo.
--     Medido nos 3 dias: juntou as versões de G Silva, Juliana, Iraci, Karla, Marcio, Steffanie, Gilson, Eduardo; deixou
--     separados os pedidos diferentes do mesmo corretor (Marcelo 0,58: alugar apto x comprar casa; Everton 0,46: lotes em
--     dois condomínios; Paula 0,49; Maiko 0,49).
-- Nada é apagado nem reescrito em grupo_pedido: quem junta é a leitura. Quem preenche a tabela é a própria tela (a lista,
-- o rejeitar e o enviar chamam privado.grupo_pedido_juntar_novos), sem gatilho em grupo_pedido: o serviço nay-grupos grava
-- nela a cada 10 s e uma trava de DDL o pararia.
--   · site_captacao_grupos: um card por pedido; 'vezes' conta mensagens (não partes); a versão mais recente representa, e
--     dela a parte de melhor nota; 'pares' soma os imóveis das outras partes da mensagem; novos 'outras_partes',
--     'versoes' e 'outras_versoes' (os outros textos, para a tela mostrar).
--   · site_captacao_grupos_estado: rejeitar / desfazer vale para o card inteiro.
--   · site_captacao_grupos_enviar: aceita o imóvel achado por outra parte da mensagem; enviado num pedido do card vale
--     para todos; o card inteiro fica 'enviado'.
-- Backup das três em /root/backups-funcoes/*-antes-380.sql.

BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.grupo_pedido_junto (
  -- sem chave estrangeira de propósito: ela travaria privado.grupo_pedido, que o nay-grupos usa a cada 10 s (pedido não é apagado)
  pedido_id  bigint PRIMARY KEY,
  card       bigint NOT NULL,
  motivo     text   NOT NULL CHECK (motivo IN ('proprio', 'mesma_mensagem', 'mesmo_texto', 'parecido')),
  semelhanca numeric(4,2),
  -- a cópia do que a comparação usa, para não refazer acento e regex de cada pedido a cada novo
  quem       text,
  nt         text   NOT NULL,
  fonte      text   NOT NULL,
  ref        text   NOT NULL,
  operacao   text,
  tipo       text,
  enviada_em timestamptz NOT NULL,
  juntado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS grupo_pedido_junto_card ON privado.grupo_pedido_junto (card);
CREATE INDEX IF NOT EXISTS grupo_pedido_junto_quem ON privado.grupo_pedido_junto (quem, enviada_em);
COMMENT ON TABLE privado.grupo_pedido_junto IS
  '380: o card de cada pedido dos grupos. card = o primeiro pedido do card. Preenchida por privado.grupo_pedido_juntar_novos().';

CREATE OR REPLACE FUNCTION privado.grupo_texto_normal(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT btrim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g'))
$function$;

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
    INSERT INTO privado.grupo_pedido_junto (pedido_id, card, motivo, semelhanca, quem, nt, fonte, ref, operacao, tipo, enviada_em)
    VALUES (q.id, coalesce(v_card, q.id), CASE WHEN v_card IS NULL THEN 'proprio' ELSE v_motivo END,
            CASE WHEN v_card IS NOT NULL THEN round(v_sem, 2) END, q.quem, q.nt, q.fonte, q.ref, q.op, q.tipo, q.enviada_em)
    ON CONFLICT (pedido_id) DO NOTHING;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END
$function$;
COMMENT ON FUNCTION privado.grupo_pedido_juntar_novos(integer) IS
  '380: põe no card certo os pedidos dos grupos que ainda não têm card (os dos últimos p_dias dias), em ordem de chegada.';

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

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_estado(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_estado text := lower(coalesce(p_estado, '')); v_k text; v_n int; v_card bigint;
BEGIN
  IF v_estado IN ('aprovado', 'enviado') THEN
    RETURN jsonb_build_object('erro', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui.');
  END IF;
  IF v_estado NOT IN ('novo', 'rejeitado') THEN
    RETURN jsonb_build_object('erro', 'Estado desconhecido.');
  END IF;
  SELECT privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) INTO v_k FROM privado.grupo_pedido WHERE id = p_id;
  IF v_k IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  -- 380: vale para o card inteiro (partes, cópias e versões do mesmo pedido); sem card, as cópias da 371
  PERFORM privado.grupo_pedido_juntar_novos();
  SELECT card INTO v_card FROM privado.grupo_pedido_junto WHERE pedido_id = p_id;
  IF v_card IS NOT NULL THEN
    UPDATE privado.grupo_pedido SET estado = v_estado
     WHERE id IN (SELECT pedido_id FROM privado.grupo_pedido_junto WHERE card = v_card) AND estado IN ('novo', 'rejeitado');
  ELSE
    UPDATE privado.grupo_pedido SET estado = v_estado
     WHERE privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) = v_k AND estado IN ('novo', 'rejeitado');
  END IF;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  RETURN jsonb_build_object('ok', true, 'estado', v_estado, 'copias', v_n);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_enviar(p_id bigint, p_codigo integer, p_abertura text DEFAULT NULL::text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q       privado.grupo_pedido;
  e       privado.grupo_captacao_estado;
  v_fone  text;
  v_abert text;
  v_card  boolean;
  v_min   int;
  v_ult   timestamptz;
  v_turno bigint;
  v_dest  bigint;
  v_msg   text;
  v_fila  record;
  v_resumo text;
  v_k     text;
  v_ids   bigint[];
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  IF coalesce(e.config->>'envio_manual', 'false') <> 'true' THEN
    RETURN jsonb_build_object('erro', 'O envio manual está desligado na configuração (envio_manual).');
  END IF;
  SELECT * INTO q FROM privado.grupo_pedido WHERE id = p_id FOR UPDATE;
  IF q.id IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  IF q.fonte = 'teste' THEN
    RETURN jsonb_build_object('erro', 'Isto é um teste colado na tela: não tem corretor para receber.');
  END IF;
  IF q.estado = 'rejeitado' THEN
    RETURN jsonb_build_object('erro', 'Esta solicitação está rejeitada. Desfaça a rejeição antes de enviar.');
  END IF;
  IF q.enviada_em < now() - make_interval(hours => coalesce(nullif(e.config->>'janela_h', '')::numeric::int, 48)) THEN
    RETURN jsonb_build_object('erro', 'Este pedido já passou de ' || coalesce(nullif(e.config->>'janela_h', ''), '48') || ' h: não envio.');
  END IF;
  v_fone := regexp_replace(coalesce(q.remetente, ''), '\D', '', 'g');
  IF length(v_fone) NOT BETWEEN 10 AND 13 OR nai_chave(v_fone) IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não tenho o telefone de quem escreveu (a mensagem veio sem número). Fale com a pessoa pelo grupo.');
  END IF;
  -- 380: o card inteiro (partes da mensagem, cópias em outros grupos e versões reescritas); sem card, as cópias da 371
  PERFORM privado.grupo_pedido_juntar_novos();
  v_k := privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte);
  SELECT array_agg(j.pedido_id) INTO v_ids
    FROM privado.grupo_pedido_junto j WHERE j.card = (SELECT card FROM privado.grupo_pedido_junto WHERE pedido_id = q.id);
  IF v_ids IS NULL THEN
    SELECT array_agg(c.id) INTO v_ids FROM privado.grupo_pedido c
     WHERE privado.grupo_pedido_chave(c.fonte, c.id, c.remetente, c.texto, c.parte) = v_k;
  END IF;
  v_ids := array_append(coalesce(v_ids, '{}'), q.id);
  -- o imóvel pode ter casado com OUTRA parte da mesma mensagem ("casa ou apartamento"): o card mostra os de todas
  IF NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_par p JOIN privado.grupo_pedido c ON c.id = p.pedido_id
                  WHERE p.codigo = p_codigo AND (c.id = q.id OR (c.id = ANY (v_ids) AND c.fonte = q.fonte AND c.ref = q.ref))) THEN
    RETURN jsonb_build_object('erro', 'Esse imóvel não está entre os que casaram com este pedido.');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta o WHERE o.codigo = p_codigo AND o.pedido_id = ANY (v_ids)) THEN
    RETURN jsonb_build_object('erro', 'Esse imóvel já foi enviado para este pedido.');
  END IF;
  -- duas mensagens ao mesmo corretor, só com o intervalo (para não parecer spam nem arriscar o número)
  v_min := greatest(coalesce(nullif(e.config->>'intervalo_min_entre_envios', '')::numeric::int, 30), 0);
  SELECT max(o.enviado_em) INTO v_ult FROM privado.grupo_pedido_oferta o WHERE nai_chave(o.telefone) = nai_chave(v_fone);
  IF v_ult IS NOT NULL AND v_ult > now() - make_interval(mins => v_min) THEN
    RETURN jsonb_build_object('erro', 'Esse corretor já recebeu uma mensagem daqui às ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'HH24:MI')
                                      || '. O intervalo é de ' || v_min || ' min: dá para mandar de novo às '
                                      || to_char((v_ult + make_interval(mins => v_min)) AT TIME ZONE 'America/Manaus', 'HH24:MI') || '.');
  END IF;
  v_abert := left(btrim(coalesce(nullif(btrim(p_abertura), ''), e.config->>'mensagem_de_abertura', '')), 700);
  IF v_abert = '' THEN RETURN jsonb_build_object('erro', 'A mensagem de abertura está vazia.'); END IF;
  v_card := coalesce(e.config->>'enviar_dados_e_fotos', 'true') = 'true';

  -- daqui para baixo é tudo ou nada: se o imóvel não puder ir, nem a abertura fica na caixa
  BEGIN
    INSERT INTO nai_turno (contato_id, papel, texto)
    VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
            left('captação ativa pelo painel (' || coalesce(nullif(btrim(p_quem), ''), 'site') || '): ' || p_codigo
                 || ' para ' || v_fone || ', pedido ' || q.id, 500))
    RETURNING id INTO v_turno;
    v_dest := nai_contato_do_cadastro(v_fone, q.remetente_nome);
    -- a abertura entra ANTES do card: a caixa entrega na ordem em que as linhas nascem
    PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_abert, 'captacao_ativa_abertura', 1);
    IF v_card THEN
      v_msg := nai_enviar_imoveis_para(v_turno, ARRAY[p_codigo], v_fone);
      IF v_msg NOT LIKE 'Mandei para %' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = v_msg;
      END IF;
    END IF;
    -- sai no próximo ciclo do enviador (como a aba Enviar imóvel)
    UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    RETURN jsonb_build_object('erro', regexp_replace(SQLERRM, '^Não mandei nada para [^:]*:\s*', 'Não enviei: '));
  END;

  SELECT count(*) FILTER (WHERE s.tipo = 'imagem' AND s.estado = 'pendente') AS fotos,
         count(*) FILTER (WHERE s.estado = 'bloqueado') AS barradas,
         string_agg(DISTINCT s.bloqueio, '; ') FILTER (WHERE s.estado = 'bloqueado') AS motivos
    INTO v_fila FROM nai_saida s WHERE s.turno_id = v_turno;
  v_resumo := 'Na fila de envio: a abertura'
              || CASE WHEN v_card THEN ', o card e ' || v_fila.fotos || CASE WHEN v_fila.fotos = 1 THEN ' foto' ELSE ' fotos' END ELSE ' (só ela)' END
              || CASE WHEN v_fila.barradas > 0 THEN '. ' || v_fila.barradas || ' mensagem(ns) barrada(s): ' || coalesce(v_fila.motivos, '?') ELSE '' END || '.';

  INSERT INTO privado.grupo_pedido_oferta (pedido_id, codigo, telefone, abertura, com_card, turno_id, resumo, quem)
  VALUES (q.id, p_codigo, v_fone, v_abert, v_card, v_turno, v_resumo, nullif(btrim(coalesce(p_quem, '')), ''));
  UPDATE privado.grupo_pedido SET estado = 'enviado' WHERE id = ANY (v_ids);
  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;

-- os pedidos dos últimos 30 dias entram nos cards agora
SELECT privado.grupo_pedido_juntar_novos(30) AS juntados;

COMMIT;
