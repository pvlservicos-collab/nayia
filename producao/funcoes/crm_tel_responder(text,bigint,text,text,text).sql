CREATE OR REPLACE FUNCTION public.crm_tel_responder(p_fonte text, p_id bigint, p_acao text, p_texto text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  f      pergunta_fila;
  d      privado.duvida;
  s      text := btrim(coalesce(p_texto, ''));
  v_quem text := coalesce(nullif(btrim(p_quem), ''), 'o Tel pelo CRM');
  v_dest bigint;
  v_turno bigint;
  v_era_pv boolean;
  v_ass  text;
  v_msg  text;
BEGIN
  IF p_acao NOT IN ('responder', 'descartar') THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Ação inválida.');
  END IF;
  IF p_acao = 'responder' AND s = '' THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Escreva a resposta antes de enviar.');
  END IF;

  IF p_fonte = 'fila' THEN
    SELECT * INTO f FROM pergunta_fila WHERE id = p_id AND estado IN ('fila', 'perguntada', 'agente') FOR UPDATE;
    IF f.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'mensagem', 'Essa dúvida já foi respondida ou descartada.');
    END IF;
    v_era_pv := f.estado = 'perguntada';
    IF p_acao = 'descartar' THEN
      UPDATE pergunta_fila SET estado = 'descartada', respondida_em = now(),
             detalhe = concat_ws(' · ', nullif(detalhe, ''), 'descartada no CRM por ' || v_quem)
       WHERE id = f.id;
      IF f.origem = 'pendencias' THEN
        UPDATE pendencias SET status = 'descartada', respondida_em = now() WHERE id = f.origem_id;
      END IF;
      v_msg := 'Descartada.';
    ELSE
      UPDATE pergunta_fila SET estado = 'respondida', resposta = s, respondida_em = now(),
             detalhe = concat_ws(' · ', nullif(detalhe, ''), 'respondida no CRM por ' || v_quem)
       WHERE id = f.id;
      IF f.linha = 'parceria' THEN
        SELECT id INTO v_dest FROM nai_contato WHERE chave = nai_chave(f.chave) LIMIT 1;
        IF v_dest IS NULL THEN
          SELECT id INTO v_dest FROM nai_contato
           WHERE right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) = right(f.chave, 8) ORDER BY id LIMIT 1;
        END IF;
        IF v_dest IS NULL THEN
          UPDATE pergunta_fila SET entrega_erro = 'a conversa do cliente não foi achada' WHERE id = f.id;
          v_msg := 'Guardei a resposta, mas não achei a conversa do cliente na Parceria para entregar.';
        ELSE
          -- o mesmo caminho do DEVOLVER: 'entrega' a partir de um turno do Tel, motivo resposta_do_tel
          INSERT INTO nai_turno (contato_id, papel, texto)
          VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
                  left('Respostas Tel no CRM (' || v_quem || '): pergunta ' || f.id, 500))
          RETURNING id INTO v_turno;
          PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega',
            'Sobre ' || CASE WHEN f.codigo IS NOT NULL
                             THEN 'o #' || f.codigo || coalesce(' (' || nullif(btrim(f.imovel), '') || ')', '')
                             ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(pergunta_fila_fala_do_tel(s)),
            'resposta_do_tel', 2);
          UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
          UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
          UPDATE pergunta_fila SET entregue_em = now() WHERE id = f.id;
          v_msg := 'Resposta enviada ao corretor pela Parceria.';
        END IF;
      ELSE
        v_msg := 'Resposta guardada: a Nay manda ao cliente pelo WhatsApp Leads em até 1 minuto.';
      END IF;
      IF f.origem = 'pendencias' THEN
        UPDATE pendencias SET status = 'respondida', resposta = s, respondida_em = now() WHERE id = f.origem_id;
      END IF;
      -- a memória do imóvel, como no PV (sem número de unidade, que é de um apartamento só)
      IF f.codigo IS NOT NULL AND lower(unaccent(s)) !~ '\m(apto|ap|apartamento|bloco|torre|unidade)\s*\.?\s*\d' THEN
        v_ass := coalesce(nay_assunto_do_imovel(f.pergunta),
                          'pergunta: ' || left(lower(unaccent(btrim(regexp_replace(f.pergunta, '\s+', ' ', 'g')))), 120));
        PERFORM nay_gravar_conhecimento(f.codigo::text, v_ass, s, 'tel (Respostas Tel no CRM)');
      END IF;
    END IF;
    -- a do PV do Tel saiu: o PV passa para a próxima da fila
    IF v_era_pv THEN
      PERFORM pergunta_fila_perguntar_proxima();
    END IF;
    RETURN jsonb_build_object('ok', true, 'mensagem', v_msg);
  END IF;

  IF p_fonte = 'duvida' THEN
    SELECT * INTO d FROM privado.duvida WHERE id = p_id AND estado = 'com_o_tel' FOR UPDATE;
    IF d.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'mensagem', 'Essa dúvida já foi respondida ou encerrada.');
    END IF;
    IF p_acao = 'descartar' THEN
      UPDATE privado.duvida SET estado = 'encerrada', situacao = 'descartada_pelo_tel', atualizada_em = now(),
             historico = historico || jsonb_build_array(jsonb_build_object('em', now(), 'feito', 'descartada no CRM por ' || v_quem))
       WHERE id = d.id;
      RETURN jsonb_build_object('ok', true, 'mensagem', 'Descartada.');
    END IF;
    PERFORM nay_duvida_mandar_pela_parceria(d.cliente_tel,
      'Sobre ' || CASE WHEN d.codigo IS NOT NULL THEN 'o #' || d.codigo ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(pergunta_fila_fala_do_tel(s)),
      NULL, d.codigo);
    UPDATE privado.duvida SET estado = 'respondida', situacao = 'tel_respondeu', resposta = s, respondida_em = now(),
           atualizada_em = now(),
           historico = historico || jsonb_build_array(jsonb_build_object('em', now(), 'feito', 'respondida no CRM por ' || v_quem))
     WHERE id = d.id;
    RETURN jsonb_build_object('ok', true, 'mensagem', 'Resposta enviada ao corretor pela Parceria.');
  END IF;

  RETURN jsonb_build_object('ok', false, 'mensagem', 'Dúvida não encontrada.');
END $function$;
