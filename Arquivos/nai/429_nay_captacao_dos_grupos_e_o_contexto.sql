-- 429: A NAY CAPTAÇÃO DOS GRUPOS E O CONTEXTO PARA A NAY DA PARCERIA (Pedro, 20/10/2026: "ela está me fazendo perder
-- oportunidades ... se achar uma opção de nota acima de 88 ela não manda direto, ela vai lá no corretor e pergunta se
-- serve para ele com modulados e ar, ou serve para ele mobiliado ... quando o novo mecanismo for ser ativado precisa
-- passar o contexto para a Nay Parceria que vai seguir atendendo").
--
-- O que deu errado (19-20/10): o radar mandou ao Júlio (5516) o 9003 MOBILIADO para "modulados e climatizado"; ele
-- respondeu "N serve totalmente mobiliado, só quer modulados e climatização" e a Nay da Parceria (nay-core), que não
-- sabia do pedido, perguntou a região e mandou casas À VENDA (o pedido velho dele, "casa até 900 mil"). Com a Cristina
-- (0221) ela disse "na região que você pediu não tenho" sem saber a região.
--
--   nay_contexto_do_grupo   o pedido do grupo (nos filtros do nay-core), o imóvel, e a pergunta se ela perguntou;
--                           o nay-core lê antes do turno (nay/contexto/do_grupo.py) e começa um pedido NOVO com ele.
--   site_captacao_grupos_perguntar   o envio automático: só a pergunta "serve para o seu cliente?" (o "sim" dele faz
--                           o nay-core mandar o card e as fotos; o "não" recusa e a busca segue com o pedido do grupo).
--   site_captacao_grupos_enviar      o botão manual (card e fotos) também deixa o contexto.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.nay_contexto_do_grupo (
  id           bigserial PRIMARY KEY,
  final8       text NOT NULL,
  telefone     text,
  pedido_id    bigint,
  codigo       integer,
  pergunta     text,
  filtros      jsonb NOT NULL DEFAULT '{}'::jsonb,
  pedido_texto text,
  origem       text NOT NULL DEFAULT 'captacao_grupos',
  criado_em    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nay_contexto_do_grupo_quem ON public.nay_contexto_do_grupo (final8, criado_em DESC);
COMMENT ON TABLE public.nay_contexto_do_grupo IS '429: o que a Nay Captação dos Grupos passou à Nay da Parceria (nay-core lê antes do turno).';
GRANT SELECT ON public.nay_contexto_do_grupo TO nay_core;

-- o pedido do grupo nos filtros do nay-core (finalidade, tipo, teto, bairros, quartos, mobília). A mobília pela
-- FRASE (a mesma regra do radar, grupos/texto.py mobilia_pedida): modulado/planejado/semi = semi.
CREATE OR REPLACE FUNCTION privado.grupo_pedido_filtros_para_nay(p_id bigint)
RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'finalidade', CASE q.ficha->>'operacao' WHEN 'aluguel' THEN 'locacao' WHEN 'venda' THEN 'venda' END,
    'tipo', CASE WHEN q.ficha->>'tipo' IN ('apartamento', 'casa') THEN q.ficha->>'tipo' END,
    'teto', nullif(q.ficha->>'preco_max', '')::numeric,
    'quartos', nullif(q.ficha->>'quartos', '')::int,
    'bairros', CASE WHEN jsonb_array_length(coalesce(q.local->'bairros', '[]')) > 0 THEN q.local->'bairros'
                    WHEN jsonb_array_length(coalesce(q.ficha->'bairros', '[]')) > 0 THEN q.ficha->'bairros' END,
    'condominios', CASE WHEN jsonb_array_length(coalesce(q.local->'condominios', '[]')) > 0 THEN q.local->'condominios' END,
    'mobilia', CASE WHEN t ~* '(modulad|planejad|semi.?mobil)' THEN 'semi'
                    WHEN t ~* '(sem mob[ií]lia|sem m[oó]veis|n[aã]o mobiliad|vazio)' THEN NULL
                    WHEN t ~* '(mobiliad|porteira fechada)' THEN 'mobiliado'
                    WHEN t ~* '(climatizad|ar.condicionado)' THEN 'climatizado'
                    WHEN q.ficha->>'mobiliado' = 'true' THEN 'mobiliado' END))
    FROM privado.grupo_pedido q,
         LATERAL (SELECT coalesce(nullif(q.ficha->>'trecho', ''), q.texto) AS t) x
   WHERE q.id = p_id
$f$;

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
  -- 429: o contexto para a Nay da Parceria (nay-core): o pedido do grupo e o card que saiu
  INSERT INTO nay_contexto_do_grupo (final8, telefone, pedido_id, codigo, pergunta, filtros, pedido_texto)
  VALUES (right(v_fone, 8), v_fone, q.id, p_codigo, NULL, privado.grupo_pedido_filtros_para_nay(q.id), q.texto);
  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_perguntar(p_id bigint, p_codigo integer, p_abertura text DEFAULT NULL::text, p_quem text DEFAULT NULL::text)
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
  v_card := false;        -- 429: a pergunta vai sozinha; o card e as fotos saem quando ele disser que serve

  -- daqui para baixo é tudo ou nada: se o imóvel não puder ir, nem a abertura fica na caixa
  BEGIN
    INSERT INTO nai_turno (contato_id, papel, texto)
    VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
            left('Nay Captação dos Grupos (' || coalesce(nullif(btrim(p_quem), ''), 'site') || '): pergunta se o ' || p_codigo || ' serve'
                 || ' para ' || v_fone || ', pedido ' || q.id, 500))
    RETURNING id INTO v_turno;
    v_dest := nai_contato_do_cadastro(v_fone, q.remetente_nome);
    -- a abertura entra ANTES do card: a caixa entrega na ordem em que as linhas nascem
    PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_abert, 'captacao_ativa_pergunta', 1);
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
  v_resumo := 'Na fila de envio: a pergunta se serve (o card e as fotos vão quando ele disser que sim)'
              || ''
              || CASE WHEN v_card THEN ', o card e ' || v_fila.fotos || CASE WHEN v_fila.fotos = 1 THEN ' foto' ELSE ' fotos' END ELSE ' (só ela)' END
              || CASE WHEN v_fila.barradas > 0 THEN '. ' || v_fila.barradas || ' mensagem(ns) barrada(s): ' || coalesce(v_fila.motivos, '?') ELSE '' END || '.';

  INSERT INTO privado.grupo_pedido_oferta (pedido_id, codigo, telefone, abertura, com_card, turno_id, resumo, quem)
  VALUES (q.id, p_codigo, v_fone, v_abert, v_card, v_turno, v_resumo, nullif(btrim(coalesce(p_quem, '')), ''));
  UPDATE privado.grupo_pedido SET estado = 'enviado' WHERE id = ANY (v_ids);
  -- 429: o contexto para a Nay da Parceria (nay-core): o pedido, o imóvel e a pergunta que ficou no ar
  INSERT INTO nay_contexto_do_grupo (final8, telefone, pedido_id, codigo, pergunta, filtros, pedido_texto)
  VALUES (right(v_fone, 8), v_fone, q.id, p_codigo, v_abert, privado.grupo_pedido_filtros_para_nay(q.id), q.texto);
  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;

REVOKE ALL ON FUNCTION public.site_captacao_grupos_perguntar(bigint, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos_perguntar(bigint, integer, text, text) TO nay_site_escrita;
COMMIT;
