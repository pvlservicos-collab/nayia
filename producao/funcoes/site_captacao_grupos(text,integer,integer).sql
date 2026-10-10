CREATE OR REPLACE FUNCTION public.site_captacao_grupos(p_filtro text DEFAULT 'todos'::text, p_horas integer DEFAULT NULL::integer, p_limite integer DEFAULT 80)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  e       privado.grupo_captacao_estado;
  v_horas int;
  v_desde timestamptz;
  v_fil   text := lower(coalesce(nullif(btrim(p_filtro), ''), 'todos'));
  v_ped   jsonb;
  v_cont  jsonb;
  v_fonte jsonb;
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  v_horas := least(greatest(coalesce(p_horas, nullif(e.config->>'janela_h', '')::int, 48), 1), 24 * 60);
  v_desde := now() - make_interval(hours => v_horas);

  SELECT jsonb_build_object(
           'todos',     count(*),
           'verde',     count(*) FILTER (WHERE q.faixa = 'verde'),
           'amarelo',   count(*) FILTER (WHERE q.faixa = 'amarelo'),
           'registro',  count(*) FILTER (WHERE q.faixa = 'registro'),
           'sem_match', count(*) FILTER (WHERE q.faixa = 'sem_match'),
           'a_pontuar', count(*) FILTER (WHERE q.pontuado_em IS NULL),
           'teste',     count(*) FILTER (WHERE q.fonte = 'teste'))
    INTO v_cont FROM privado.grupo_pedido q WHERE q.enviada_em >= v_desde;

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

  SELECT coalesce(jsonb_agg(x.j ORDER BY x.enviada_em DESC, x.id DESC), '[]'::jsonb) INTO v_ped
    FROM (
      SELECT q.id, q.enviada_em,
             jsonb_build_object(
               'id', q.id, 'fonte', q.fonte, 'parte', q.parte,
               'grupo', q.grupo_nome, 'nome', q.remetente_nome, 'telefone', q.remetente,
               'enviada_em', q.enviada_em, 'texto', q.texto,
               'ficha', q.ficha, 'duvidosos', to_jsonb(q.duvidosos), 'local', q.local,
               'estado', q.estado, 'nota', q.nota, 'faixa', q.faixa, 'sem_match_motivo', q.sem_match_motivo,
               'funil', q.funil, 'pontuado', q.pontuado_em IS NOT NULL,
               'pares', coalesce((SELECT jsonb_agg(jsonb_build_object(
                                           'codigo', p.codigo, 'posicao', p.posicao, 'nota', p.nota,
                                           'detalhe', p.detalhe, 'acima_do_teto', p.acima_do_teto, 'imovel', p.imovel)
                                         ORDER BY p.posicao)
                                    FROM privado.grupo_pedido_par p WHERE p.pedido_id = q.id), '[]'::jsonb),
               'julgamento', (SELECT jsonb_build_object('leitura', j.leitura, 'o_que_errou', j.o_que_errou, 'quando', j.criado_em)
                                FROM privado.grupo_pedido_julgamento j WHERE j.pedido_id = q.id ORDER BY j.id DESC LIMIT 1)) AS j
        FROM privado.grupo_pedido q
       WHERE q.enviada_em >= v_desde
         AND CASE v_fil WHEN 'verde'     THEN q.faixa = 'verde'
                        WHEN 'amarelo'   THEN q.faixa = 'amarelo'
                        WHEN 'sem_match' THEN q.faixa = 'sem_match'
                        WHEN 'teste'     THEN q.fonte = 'teste'
                        ELSE true END
       ORDER BY q.enviada_em DESC, q.id DESC
       LIMIT least(greatest(coalesce(p_limite, 80), 1), 300)) x;

  RETURN jsonb_build_object(
    'modo',      coalesce(e.config->>'modo', 'treino'),
    'config',    e.config,
    'aviso',     e.aviso,
    'batimento', e.batimento,
    'servico_vivo', coalesce(e.batimento > now() - interval '3 minutes', false),
    'horas',     v_horas,
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
