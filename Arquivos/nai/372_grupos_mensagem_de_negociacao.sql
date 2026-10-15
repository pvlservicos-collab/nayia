-- 372: captação ativa por grupos -- MENSAGEM DE NEGOCIAÇÃO
--
-- Pedro, 15/10/2026: "cria mais um campo ali ao lado de enviar imóvel, Mensagem de negociação, abre um campo lá, e eu
-- digito uma mensagem para enviar para esse cara e nosso sistema já chama ele no PV com minha msg".
--
-- O botão abre um campo; o texto vai, do jeito que foi digitado, para o PV de quem fez o pedido, pelo número da
-- Parceria: o mesmo caminho da abertura do "Enviar ao corretor" (turno 'tel' + nai_enfileirar_texto, papel
-- 'entrega', entregue pelo nay-enviador-manual). Sem card nem foto.
-- Travas: envio manual ligado; não é teste colado; tem o telefone de quem escreveu; texto de 1 a 1.500 caracteres;
-- o MESMO texto ao mesmo corretor não sai duas vezes em 10 minutos (clique duplo). O intervalo de 30 min do
-- "Enviar ao corretor" NÃO vale aqui: é conversa digitada por gente.
-- Fica gravada em privado.grupo_pedido_mensagem e aparece no card (todas as cópias da 371 enxergam).

BEGIN;

CREATE TABLE IF NOT EXISTS privado.grupo_pedido_mensagem (
  id         bigserial PRIMARY KEY,
  pedido_id  bigint NOT NULL,
  telefone   text NOT NULL,
  texto      text NOT NULL,
  turno_id   bigint,
  resumo     text,
  quem       text,
  enviado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS grupo_pedido_mensagem_pedido ON privado.grupo_pedido_mensagem (pedido_id);
COMMENT ON TABLE privado.grupo_pedido_mensagem IS
  '372: mensagem de negociação digitada na Captação ativa (Grupos) e mandada no PV de quem fez o pedido.';

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_mensagem(p_id bigint, p_texto text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q       privado.grupo_pedido;
  e       privado.grupo_captacao_estado;
  v_fone  text;
  v_texto text := btrim(coalesce(p_texto, ''), ' ' || chr(9) || chr(10) || chr(13));
  v_turno bigint;
  v_dest  bigint;
  v_said  bigint;
  v_fila  record;
  v_resumo text;
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  IF coalesce(e.config->>'envio_manual', 'false') <> 'true' THEN
    RETURN jsonb_build_object('erro', 'O envio manual está desligado na configuração (envio_manual).');
  END IF;
  SELECT * INTO q FROM privado.grupo_pedido WHERE id = p_id;
  IF q.id IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  IF q.fonte = 'teste' THEN
    RETURN jsonb_build_object('erro', 'Isto é um teste colado na tela: não tem corretor para receber.');
  END IF;
  IF v_texto = '' THEN RETURN jsonb_build_object('erro', 'Escreva a mensagem.'); END IF;
  IF length(v_texto) > 1500 THEN RETURN jsonb_build_object('erro', 'A mensagem passou de 1.500 caracteres.'); END IF;
  v_fone := regexp_replace(coalesce(q.remetente, ''), '\D', '', 'g');
  IF length(v_fone) NOT BETWEEN 10 AND 13 OR nai_chave(v_fone) IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não tenho o telefone de quem escreveu (a mensagem veio sem número). Fale com a pessoa pelo grupo.');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.grupo_pedido_mensagem m
              WHERE nai_chave(m.telefone) = nai_chave(v_fone) AND m.texto = v_texto AND m.enviado_em > now() - interval '10 minutes') THEN
    RETURN jsonb_build_object('erro', 'Essa mesma mensagem já foi para ele há menos de 10 minutos.');
  END IF;

  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
          left('captação ativa, mensagem de negociação (' || coalesce(nullif(btrim(p_quem), ''), 'site') || ') para '
               || v_fone || ', pedido ' || q.id, 500))
  RETURNING id INTO v_turno;
  v_dest := nai_contato_do_cadastro(v_fone, q.remetente_nome);
  v_said := nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_texto, 'captacao_ativa_negociacao', 1);
  IF v_said IS NULL THEN
    RAISE EXCEPTION 'não consegui pôr a mensagem na fila (contato %)', v_dest;
  END IF;
  UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
  UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;

  SELECT count(*) FILTER (WHERE s.estado = 'bloqueado') AS barradas,
         string_agg(DISTINCT s.bloqueio, '; ') FILTER (WHERE s.estado = 'bloqueado') AS motivos
    INTO v_fila FROM nai_saida s WHERE s.turno_id = v_turno;
  v_resumo := CASE WHEN v_fila.barradas > 0 THEN 'Barrada: ' || coalesce(v_fila.motivos, '?')
                   ELSE 'Na fila de envio, pelo número da Parceria.' END;
  INSERT INTO privado.grupo_pedido_mensagem (pedido_id, telefone, texto, turno_id, resumo, quem)
  VALUES (q.id, v_fone, v_texto, v_turno, v_resumo, nullif(btrim(coalesce(p_quem, '')), ''));
  RETURN jsonb_build_object('ok', v_fila.barradas = 0, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;
REVOKE ALL ON FUNCTION public.site_captacao_grupos_mensagem(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos_mensagem(bigint, text, text) TO nay_site_escrita;

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
  v_horas := least(greatest(coalesce(p_horas, nullif(e.config->>'janela_h', '')::int, 48), 1), 24 * 60);
  v_desde := now() - make_interval(hours => v_horas);

  -- 371: as solicitações da janela, cada duplicata uma vez só (a cópia mais recente já pontuada representa todas)
  IF to_regclass('pg_temp._gc_sol') IS NULL THEN
    CREATE TEMP TABLE _gc_sol (k text, id bigint, n int, ids bigint[], grupos text[], primeira timestamptz,
                               ultima timestamptz, estado text, faixa text, nota numeric, pontuado_em timestamptz,
                               fonte text) ON COMMIT DROP;
  END IF;
  TRUNCATE _gc_sol;
  INSERT INTO _gc_sol
  WITH g AS (
    SELECT q.*, privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte) AS k
      FROM privado.grupo_pedido q WHERE q.enviada_em >= v_desde
  ), junta AS (
    SELECT k, count(*)::int AS n, array_agg(id ORDER BY enviada_em, id) AS ids,
           array_agg(DISTINCT grupo_nome) FILTER (WHERE nullif(btrim(grupo_nome), '') IS NOT NULL) AS grupos,
           min(enviada_em) AS primeira, max(enviada_em) AS ultima,
           CASE WHEN bool_or(estado = 'enviado') THEN 'enviado' WHEN bool_or(estado = 'rejeitado') THEN 'rejeitado'
                WHEN bool_or(estado = 'aprovado') THEN 'aprovado' ELSE 'novo' END AS estado
      FROM g GROUP BY k
  ), rep AS (
    SELECT DISTINCT ON (k) k, id, faixa, nota, pontuado_em, fonte FROM g ORDER BY k, (pontuado_em IS NULL), enviada_em DESC, id DESC
  )
  SELECT j.k, r.id, j.n, j.ids, coalesce(j.grupos, '{}'), j.primeira, j.ultima, j.estado, r.faixa, r.nota, r.pontuado_em, r.fonte
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
               'ficha', q.ficha, 'duvidosos', to_jsonb(q.duvidosos), 'local', q.local,
               'estado', s.estado, 'nota', q.nota, 'faixa', q.faixa, 'sem_match_motivo', q.sem_match_motivo,
               'funil', q.funil, 'pontuado', q.pontuado_em IS NOT NULL,
               'pares', coalesce((SELECT jsonb_agg(jsonb_build_object(
                                           'codigo', p.codigo, 'posicao', p.posicao, 'nota', p.nota,
                                           'detalhe', p.detalhe, 'acima_do_teto', p.acima_do_teto, 'imovel', p.imovel)
                                         ORDER BY p.posicao)
                                    FROM privado.grupo_pedido_par p WHERE p.pedido_id = q.id), '[]'::jsonb),
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

COMMIT;
