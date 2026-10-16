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
