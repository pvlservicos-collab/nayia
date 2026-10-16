CREATE OR REPLACE FUNCTION public.site_captacao_grupos_enviar_varios(p_id bigint, p_codigos integer[], p_abertura text DEFAULT NULL::text, p_card boolean DEFAULT true, p_fotos boolean DEFAULT false, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q        privado.grupo_pedido;
  e        privado.grupo_captacao_estado;
  v_fone   text;
  v_chave  text;
  v_abert  text := left(btrim(coalesce(p_abertura, ''), ' ' || chr(9) || chr(10) || chr(13)), 700);
  v_card   boolean := coalesce(p_card, false);
  v_fotos  boolean := coalesce(p_fotos, false);
  v_cods   int[];
  v_ids    bigint[];
  v_k      text;
  v_min    int;
  v_ult    timestamptz;
  v_turno  bigint;
  v_dest   bigint;
  v_ja     timestamptz;
  v_vao    int[] := '{}';
  v_fora   text[] := '{}';
  v_feitos text[] := '{}';
  v_ordem  int := 1;
  v_n      int;
  v_texto  text;
  v_fila   record;
  v_resumo text;
  c        int;
  i        record;
  f        record;
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
  v_chave := nai_chave(v_fone);
  IF length(v_fone) NOT BETWEEN 10 AND 13 OR v_chave IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não tenho o telefone de quem escreveu (a mensagem veio sem número). Fale com a pessoa pelo grupo.');
  END IF;

  -- a lista: sem repetir, na ordem em que ele montou
  SELECT array_agg(d.x ORDER BY d.o) INTO v_cods
    FROM (SELECT DISTINCT ON (u.x) u.x, u.o FROM unnest(p_codigos) WITH ORDINALITY u(x, o) WHERE u.x > 0 ORDER BY u.x, u.o) d;
  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN jsonb_build_object('erro', 'Escolha pelo menos um imóvel.'); END IF;
  IF array_length(v_cods, 1) > 10 THEN RETURN jsonb_build_object('erro', 'No máximo 10 imóveis por envio.'); END IF;
  IF NOT v_card AND NOT v_fotos THEN RETURN jsonb_build_object('erro', 'Marque o card, as fotos ou os dois.'); END IF;

  -- o card inteiro do pedido (380): o que já foi para uma cópia, versão ou parte não vai de novo
  PERFORM privado.grupo_pedido_juntar_novos();
  SELECT array_agg(j.pedido_id) INTO v_ids
    FROM privado.grupo_pedido_junto j WHERE j.card = (SELECT card FROM privado.grupo_pedido_junto WHERE pedido_id = q.id);
  IF v_ids IS NULL THEN
    v_k := privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte);
    SELECT array_agg(x.id) INTO v_ids FROM privado.grupo_pedido x
     WHERE privado.grupo_pedido_chave(x.fonte, x.id, x.remetente, x.texto, x.parte) = v_k;
  END IF;
  v_ids := array_append(coalesce(v_ids, '{}'), q.id);

  -- o intervalo entre mensagens daqui ao mesmo corretor (o mesmo do envio de um imóvel)
  v_min := greatest(coalesce(nullif(e.config->>'intervalo_min_entre_envios', '')::numeric::int, 30), 0);
  SELECT max(o.enviado_em) INTO v_ult FROM privado.grupo_pedido_oferta o WHERE nai_chave(o.telefone) = v_chave;
  IF v_ult IS NOT NULL AND v_ult > now() - make_interval(mins => v_min) THEN
    RETURN jsonb_build_object('erro', 'Esse corretor já recebeu uma mensagem daqui às ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'HH24:MI')
                                      || '. O intervalo é de ' || v_min || ' min: dá para mandar de novo às '
                                      || to_char((v_ult + make_interval(mins => v_min)) AT TIME ZONE 'America/Manaus', 'HH24:MI') || '.');
  END IF;

  -- daqui para baixo é tudo ou nada: se nenhum imóvel puder ir, nem a mensagem inicial fica na caixa
  BEGIN
    INSERT INTO nai_turno (contato_id, papel, texto)
    VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
            left('captação ativa pelo painel, vários imóveis (' || coalesce(nullif(btrim(p_quem), ''), 'site') || '): '
                 || array_to_string(v_cods, ', ') || ' para ' || v_fone || ', pedido ' || q.id, 500))
    RETURNING id INTO v_turno;

    FOREACH c IN ARRAY v_cods LOOP
      i := NULL;
      SELECT x.codigo, coalesce(x.e_parceiro, false) AS parceiro,
             nay_esta_no_mercado(x.disponivel, x.bloqueado, x.publicado_no_site) AS no_mercado
        INTO i FROM imoveis x WHERE x.codigo = c;
      IF i.codigo IS NULL OR (SELECT texto_pronto FROM nai_card_do_imovel(c)) IS NULL THEN
        v_fora := v_fora || (c || ': não achei esse código');
      ELSIF i.parceiro THEN
        v_fora := v_fora || (c || ': é imóvel de parceiro (parceria não sai)');
      ELSIF NOT coalesce(i.no_mercado, false) THEN
        v_fora := v_fora || (c || ': está indisponível');
      ELSIF EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta o WHERE o.codigo = c AND o.pedido_id = ANY (v_ids)) THEN
        v_fora := v_fora || (c || ': já foi enviado para este pedido');
      ELSE
        v_ja := nay_reservar_imovel_do_dia(v_chave, c, 'nai', v_turno);
        IF v_ja IS NOT NULL THEN
          v_fora := v_fora || (c || ': já foi para esse número ' || nay_quando_foi(v_ja)
                               || ' (libera ' || nay_quando_foi(v_ja + interval '24 hours') || ')');
        ELSE
          v_vao := v_vao || c;
        END IF;
      END IF;
    END LOOP;
    IF coalesce(array_length(v_vao, 1), 0) = 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Nenhum imóvel pode ir: ' || array_to_string(v_fora, '; ') || '.';
    END IF;

    v_dest := nai_contato_do_cadastro(v_fone, q.remetente_nome);
    -- a mensagem inicial entra ANTES dos cards: a caixa entrega na ordem em que as linhas nascem
    IF v_abert <> '' THEN
      PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_abert, 'captacao_ativa_abertura', 1);
    END IF;
    -- um imóvel de cada vez, na ordem da lista: o card e as fotos dele
    FOREACH c IN ARRAY v_vao LOOP
      IF v_card THEN
        SELECT texto_pronto INTO v_texto FROM nai_card_do_imovel(c);
        v_ordem := v_ordem + 1;
        PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_texto, 'envia_comando', v_ordem);
      END IF;
      v_n := 0;
      IF v_fotos THEN
        FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
          CONTINUE WHEN f.e_colagem;          -- a colagem de 4 fotos é só dos grupos (Tel, 14/09)
          v_ordem := v_ordem + 1;
          INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
          VALUES (v_turno, v_dest, 'entrega', v_chave, 'imagem', f.url, c, v_ordem, 'foto');
          v_n := v_n + 1;
        END LOOP;
      END IF;
      v_feitos := v_feitos || (c || CASE WHEN v_card AND v_fotos THEN ' (card e ' || v_n || ' foto' || CASE WHEN v_n = 1 THEN ')' ELSE 's)' END
                                         WHEN v_card THEN ' (card)'
                                         ELSE ' (' || v_n || ' foto' || CASE WHEN v_n = 1 THEN ')' ELSE 's)' END END);
    END LOOP;
    -- sai no próximo ciclo do enviador (como a aba Enviar imóvel)
    UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    RETURN jsonb_build_object('erro', SQLERRM);
  END;

  SELECT count(*) FILTER (WHERE s.estado = 'bloqueado') AS barradas,
         string_agg(DISTINCT s.bloqueio, '; ') FILTER (WHERE s.estado = 'bloqueado') AS motivos
    INTO v_fila FROM nai_saida s WHERE s.turno_id = v_turno;
  v_resumo := 'Na fila de envio, pelo número da Parceria: ' || CASE WHEN v_abert <> '' THEN 'a mensagem inicial e ' ELSE '' END
              || array_to_string(v_feitos, ', ')
              || CASE WHEN coalesce(array_length(v_fora, 1), 0) > 0 THEN '. Não foram: ' || array_to_string(v_fora, '; ') ELSE '' END
              || CASE WHEN v_fila.barradas > 0 THEN '. ' || v_fila.barradas || ' mensagem(ns) barrada(s): ' || coalesce(v_fila.motivos, '?') ELSE '' END || '.';

  INSERT INTO privado.grupo_pedido_oferta (pedido_id, codigo, telefone, abertura, com_card, turno_id, resumo, quem)
  SELECT q.id, x, v_fone, v_abert, v_card, v_turno, v_resumo, nullif(btrim(coalesce(p_quem, '')), '')
    FROM unnest(v_vao) x
  ON CONFLICT (pedido_id, codigo) DO NOTHING;
  UPDATE privado.grupo_pedido SET estado = 'enviado' WHERE id = ANY (v_ids);
  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'turno', v_turno, 'foram', to_jsonb(v_vao), 'nao_foram', to_jsonb(v_fora));
END
$function$;
