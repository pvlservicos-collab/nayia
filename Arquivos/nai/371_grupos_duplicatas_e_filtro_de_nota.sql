-- 371: captação ativa por grupos -- as DUPLICATAS viram uma solicitação só, e o filtro por NOTA
--
-- Pedro, 15/10/2026: "pega as solicitações lá da captação ativa das abas grupos, quando o cara joga em vários grupos
-- ele cria várias, junta todas as duplicatas em uma, e deixa lá em cima um filtro para a gente filtrar por nota".
--
-- Medido antes (7 dias): 1.108 pedidos, 376 diferentes. O mesmo corretor cola o MESMO texto em 10, 13 grupos, e
-- de novo nos dias seguintes (um texto apareceu 49 vezes).
--
-- DUPLICATA = mesmo remetente + mesmo texto (sem diferença de maiúscula, pontuação, espaço e emoji) + mesma parte da
-- mensagem. Nada é apagado: as linhas de privado.grupo_pedido continuam todas; quem junta é a LEITURA.
--   · site_captacao_grupos: uma linha por duplicata, com 'vezes', 'grupos' (todos os nomes), 'primeira_em' e 'ids'.
--     A que aparece é a mais recente já pontuada. Contagens das abas = solicitações diferentes. Novos parâmetros:
--     p_nota_min (nota mínima) e p_ordem ('recentes' | 'nota').
--   · site_captacao_grupos_estado: rejeitar / desfazer vale para todas as cópias.
--   · site_captacao_grupos_enviar: imóvel enviado numa cópia conta como enviado em todas, e todas ficam 'enviado'.
-- Backup das três em /root/backups-funcoes/*-antes-371.sql.

BEGIN;

CREATE OR REPLACE FUNCTION privado.grupo_pedido_chave(p_fonte text, p_id bigint, p_remetente text, p_texto text, p_parte integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- teste colado na tela nunca junta com nada; sem remetente, também não
  SELECT CASE WHEN p_fonte = 'teste' OR nullif(regexp_replace(coalesce(p_remetente, ''), '\D', '', 'g'), '') IS NULL
              THEN 'id:' || p_id
              ELSE right(regexp_replace(p_remetente, '\D', '', 'g'), 8) || ':'
                   || md5(regexp_replace(lower(coalesce(p_texto, '')), '[^a-z0-9à-úç]+', '', 'g')) || ':' || coalesce(p_parte, 1)
         END
$function$;
COMMENT ON FUNCTION privado.grupo_pedido_chave(text, bigint, text, text, integer) IS
  '371: a mesma solicitação colada em vários grupos (mesmo remetente, mesmo texto, mesma parte) tem a mesma chave.';

DROP FUNCTION public.site_captacao_grupos(text, integer, integer);

CREATE FUNCTION public.site_captacao_grupos(p_filtro text DEFAULT 'todos'::text, p_horas integer DEFAULT NULL::integer,
                                            p_limite integer DEFAULT 80, p_nota_min numeric DEFAULT NULL::numeric,
                                            p_ordem text DEFAULT 'recentes'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER   -- 371: VOLATILE (monta a tabela temporária das solicitações)
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
REVOKE ALL ON FUNCTION public.site_captacao_grupos(text, integer, integer, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos(text, integer, integer, numeric, text) TO nay_site_escrita;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_estado(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_estado text := lower(coalesce(p_estado, '')); v_k text; v_n int;
BEGIN
  IF v_estado IN ('aprovado', 'enviado') THEN
    RETURN jsonb_build_object('erro', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui.');
  END IF;
  IF v_estado NOT IN ('novo', 'rejeitado') THEN
    RETURN jsonb_build_object('erro', 'Estado desconhecido.');
  END IF;
  SELECT privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) INTO v_k FROM privado.grupo_pedido WHERE id = p_id;
  IF v_k IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  -- 371: vale para todas as cópias da mesma solicitação (o mesmo texto colado em vários grupos)
  UPDATE privado.grupo_pedido SET estado = v_estado
   WHERE privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) = v_k AND estado IN ('novo', 'rejeitado');
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
  IF NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_par p WHERE p.pedido_id = q.id AND p.codigo = p_codigo) THEN
    RETURN jsonb_build_object('erro', 'Esse imóvel não está entre os que casaram com este pedido.');
  END IF;
  -- 371: a mesma solicitação colada em vários grupos é uma só: o imóvel enviado numa cópia vale para todas
  v_k := privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte);
  IF EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta o JOIN privado.grupo_pedido c ON c.id = o.pedido_id
              WHERE o.codigo = p_codigo AND privado.grupo_pedido_chave(c.fonte, c.id, c.remetente, c.texto, c.parte) = v_k) THEN
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
  UPDATE privado.grupo_pedido SET estado = 'enviado'
   WHERE id = q.id OR privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) = v_k;
  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;

-- conferência
DO $$
DECLARE v jsonb;
BEGIN
  v := site_captacao_grupos('todos', 168, 300);
  RAISE NOTICE '7 dias: % solicitações diferentes, % mensagens, % juntadas', v->'contagem'->>'todos', v->'contagem'->>'mensagens', v->'contagem'->>'juntadas';
END $$;

COMMIT;
