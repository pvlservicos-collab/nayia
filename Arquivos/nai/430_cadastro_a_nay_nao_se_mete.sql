-- 430 (Pedro, 20/10/2026): "Quero que quando a Nay de cadastro estiver falando com o corretor, a Nay de Parceria não
-- se meta." A RESPOSTA dele já ia só para o cadastro (428, a porta). Faltava o que a Nay manda SEM ser chamada:
--   - o follow-up do dia seguinte ("Oi, seu cliente tem interesse?"), nai_followup_rodar: pula, com o motivo;
--   - o radar / captação ativa (envio automático e o botão do painel), site_captacao_grupos_perguntar e _enviar:
--     recusa com a explicação.
-- "Falando" = a ficha dele está em 'perguntando' (cadastro_whats_da_parceria, que olha também as linhas irmãs).
BEGIN;

CREATE OR REPLACE FUNCTION public.nai_followup_rodar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_hoje   date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_hora   time := (now() AT TIME ZONE 'America/Manaus')::time;
  r        record;
  v_ct     bigint;
  v_ids    bigint[];
  v_chaves text[];
  v_nome   text;
  v_pula   text;
  v_feitos int := 0;
  v_lim    int := greatest(nai_cfg_int('followup_por_minuto', 2), 1);
  v_dias   date[];
BEGIN
  IF nai_cfg('followup_ligado', 'nao') <> 'sim' THEN RETURN 0; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' OR nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 0; END IF;
  IF extract(isodow FROM now() AT TIME ZONE 'America/Manaus') = 7 THEN RETURN 0; END IF;   -- domingo
  IF v_hora < nai_cfg('followup_inicio', '09:00')::time OR v_hora > nai_cfg('followup_fim', '18:00')::time THEN RETURN 0; END IF;

  -- 415: na segunda, o sábado também (domingo ela não roda; antes o sábado nunca ganhava follow-up). O dia gravado é o
  -- último em que recebeu; quem recebeu no sábado E no domingo ganha um só.
  v_dias := CASE WHEN extract(isodow FROM v_hoje) = 1 THEN ARRAY[v_hoje - 2, v_hoje - 1] ELSE ARRAY[v_hoje - 1] END;
  FOR r IN
    SELECT e.chave, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos, min(e.primeiro_em) AS primeiro,
           max((e.primeiro_em AT TIME ZONE 'America/Manaus')::date) AS dia
      FROM imovel_enviado_no_dia e
     WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = ANY (v_dias)
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave AND f.dia_recebeu = ANY (v_dias))
     GROUP BY e.chave
     ORDER BY min(e.primeiro_em)
  LOOP
    EXIT WHEN v_feitos >= v_lim;
    v_pula := NULL;
    SELECT id INTO v_ct FROM nai_contato WHERE chave = r.chave;
    IF v_ct IS NULL THEN v_ct := nai_contato_do_cadastro(r.chave, NULL); END IF;
    v_ids := nai_contato_irmaos(v_ct);
    SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);

    IF nay_fora_da_regra_do_dia(r.chave) THEN
      v_pula := 'equipe ou teste';
    ELSIF EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (v_chaves) AND f.dia_recebeu = ANY (v_dias)) THEN
      v_pula := 'a outra linha dele já recebeu';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND m.criada_em > r.primeiro AND nai_recusou(m.texto)) THEN
      v_pula := 'recusou';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado)) THEN
      v_pula := 'visita em andamento';
    ELSIF nai_tel_com_a_conversa(v_ct) THEN
      v_pula := 'o Tel está com a conversa';
    ELSIF cadastro_whats_da_parceria(r.chave, v_ct) IS NOT NULL THEN
      v_pula := 'a Nay do cadastro está falando com ele';      -- 430
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = v_hoje) THEN
      v_pula := 'já conversou hoje';
    ELSIF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = ANY (v_chaves) AND q.decisao = 'nao') THEN
      v_pula := 'o Tel disse que não é corretor';
    ELSIF btrim(nai_cfg('so_estes_numeros', '')) <> '' AND NOT nai_na_lista_curta(v_ct, r.chave) THEN
      v_pula := 'fora da lista curta';
    END IF;

    IF v_pula IS NOT NULL THEN
      INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado, motivo)
      VALUES (r.chave, r.dia, v_ct, r.codigos, 'pulado', v_pula) ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) INTO v_nome FROM nai_contato k WHERE k.id = v_ct;
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            'Oi' || coalesce(' ' || v_nome, '') || ', seu cliente tem interesse?', 1, 'followup', now());
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            coalesce(v_nome || ', q', 'Q') || 'ualquer coisa temos muitas opções de imóveis para locação e venda, '
            || 'o que está procurando para seus clientes?', 2, 'followup', now() + interval '8 seconds');
    INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado)
    VALUES (r.chave, r.dia, v_ct, r.codigos, 'enviado') ON CONFLICT DO NOTHING;
    v_feitos := v_feitos + 1;
  END LOOP;
  RETURN v_feitos;
END;
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
  -- 430: a Nay do cadastro está perguntando a ele sobre um imóvel: nada mais sai até ela terminar
  IF cadastro_whats_da_parceria(v_fone) IS NOT NULL THEN
    RETURN jsonb_build_object('erro', 'A Nay do cadastro está falando com esse corretor agora (cadastro de imóvel). Espere ela terminar.');
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
  -- 430: a Nay do cadastro está perguntando a ele sobre um imóvel: nada mais sai até ela terminar
  IF cadastro_whats_da_parceria(v_fone) IS NOT NULL THEN
    RETURN jsonb_build_object('erro', 'A Nay do cadastro está falando com esse corretor agora (cadastro de imóvel). Espere ela terminar.');
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

COMMIT;
