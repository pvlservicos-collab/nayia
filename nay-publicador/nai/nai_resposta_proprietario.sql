CREATE OR REPLACE FUNCTION public.nai_resposta_proprietario(p_turno bigint, p_decisao text, p_quando text, p_acesso text, p_detalhe text, p_senha text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t      nai_turno;
  v      nai_visita;
  k      nai_contato;
  dec    text := lower(coalesce(p_decisao, ''));
  q      timestamptz := nai_ler_quando(p_quando);
  v_ac   text := nai_acesso_normalizar(p_acesso);
  v_txt  text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'proprietario' THEN
    RETURN QUERY SELECT NULL::text, 'esta ferramenta e so para quando quem escreve e o PROPRIETARIO.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  IF t.visita_id IS NULL THEN
    -- Sem visita definida: nada se decide; o Tel fica sabendo.
    PERFORM nai_avisar_tel(p_turno, NULL, 'Tel, o proprietário ' || coalesce(k.nome_whatsapp, '') || ' (' ||
      nai_fone_fmt(k.telefone) || ') escreveu e não sei de qual visita é: "' || left(coalesce(t.texto, ''), 300) ||
      E'"\nParei de responder esse contato. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.', 'proprietario_sem_visita');
    PERFORM nai_parar_chat(k.id, 'proprietario sem visita definida');
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = t.visita_id FOR UPDATE;
  IF NOT nai_visita_aberta(v.estado) THEN
    RETURN QUERY SELECT 'Obrigada! Essa visita já foi encerrada, qualquer coisa te aviso por aqui.'::text, NULL::text; RETURN;
  END IF;

  -- Aprende o acesso (sem senha) para a proxima visita deste imovel.
  IF v_ac IS NOT NULL THEN
    UPDATE nai_visita SET acesso = v_ac, acesso_detalhe = coalesce(NULLIF(btrim(coalesce(p_detalhe, '')), ''), acesso_detalhe)
     WHERE id = v.id RETURNING * INTO v;
    INSERT INTO nai_acesso_imovel (codigo, acesso, detalhe, fonte)
         VALUES (v.codigo, v_ac, NULLIF(btrim(coalesce(p_detalhe, '')), ''), 'proprietario')
    ON CONFLICT (codigo) DO UPDATE SET acesso = EXCLUDED.acesso,
      detalhe = coalesce(EXCLUDED.detalhe, nai_acesso_imovel.detalhe), fonte = 'proprietario', atualizado_em = now();
  ELSIF p_detalhe IS NOT NULL AND btrim(p_detalhe) <> '' AND v.acesso = 'buscar_chave' THEN
    UPDATE nai_visita SET acesso_detalhe = btrim(p_detalhe) WHERE id = v.id RETURNING * INTO v;
    UPDATE nai_acesso_imovel SET detalhe = btrim(p_detalhe), atualizado_em = now() WHERE codigo = v.codigo;
  END IF;
  IF nullif(btrim(coalesce(p_senha, '')), '') IS NOT NULL THEN
    UPDATE nai_visita SET senha = btrim(p_senha), acesso = coalesce(acesso, 'fechadura') WHERE id = v.id RETURNING * INTO v;
  END IF;

  IF dec IN ('aceita', 'sim', 'confirma') THEN
    IF v.estado NOT IN ('aguardando_proprietario', 'negociando', 'aguardando_acesso') THEN
      RETURN QUERY SELECT 'Obrigada!'::text, 'nao havia nada esperando confirmacao dele; so agradeca.'::text; RETURN;
    END IF;
    UPDATE nai_visita SET prop_ok_em = coalesce(prop_ok_em, now()), aguardando = NULL, atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_aceitou', NULL);
    v_txt := nai_prosseguir_acesso(v.id, p_turno, true);
    RETURN QUERY SELECT v_txt, 'diga o texto_pronto como veio, sem acrescentar pergunta.'::text; RETURN;
  END IF;

  IF dec = 'acesso' THEN
    IF v.prop_ok_em IS NULL THEN
      UPDATE nai_visita SET prop_ok_em = now() WHERE id = v.id;
    END IF;
    v_txt := nai_prosseguir_acesso(v.id, p_turno, true);
    RETURN QUERY SELECT v_txt, 'diga o texto_pronto como veio.'::text; RETURN;
  END IF;

  IF dec IN ('outro_horario', 'recusa', 'nao') THEN
    IF q IS NULL THEN
      UPDATE nai_visita SET estado = 'negociando', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'proprietario_recusou', NULL);
      RETURN QUERY SELECT 'Sem problemas! Qual outro horário fica bom pra você receber a visita?'::text,
        'quando ele disser, chame resposta_do_proprietario com decisao outro_horario e o horario.'::text; RETURN;
    END IF;
    IF q <= now() + interval '10 minutes' THEN
      RETURN QUERY SELECT 'Esse horário já passou. Qual outro fica bom?'::text, NULL::text; RETURN;
    END IF;
    UPDATE nai_visita SET quando_sugerido = q, estado = 'negociando', aguardando = 'corretor', atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_sugeriu', nai_hora_exata(q));
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
      coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
      'o proprietário não consegue ' || nai_quando_humano(v.quando) || ', mas sugeriu ' || nai_quando_humano(q) ||
      '. Funciona pro seu cliente?', 'proprietario_sugeriu', 400);
    -- sem "vou ver e te retorno" (Tel, 13/09): o proprietario ouve de novo quando houver resposta.
    RETURN QUERY SELECT NULL::text, 'levei o horario ao corretor. responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  IF dec = 'cancela' THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_nao_quer', p_detalhe);
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o proprietário do ' || nai_ref_imovel(v.codigo) ||
      ' não quer (ou não pode) a visita #' || v.id || ' (' || nai_hora_exata(v.quando) || '): "' || left(coalesce(t.texto, ''), 300) ||
      E'"\nParei com o proprietário e com o corretor até você responder.\nMe responda VISITA ' || v.id || ' CANCELA ou VISITA ' || v.id || ' HORARIO <novo horário>.', 'proprietario_nao_quer');
    PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': proprietario nao quer');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': proprietario nao quer');
    -- CALADA (Tel, 12/09): foi para o Tel, o corretor nao e avisado.
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;

  -- duvida ou qualquer outra coisa: e com o Tel (proprietario fora de agenda).
  PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o proprietário do ' || nai_ref_imovel(v.codigo) || ' (visita #' || v.id ||
    ') perguntou: "' || left(coalesce(nullif(p_detalhe, ''), t.texto, ''), 300) ||
    E'"\nParei de responder o proprietário. Qualquer comando VISITA ' || v.id || ' seu me devolve a conversa.', 'proprietario_duvida');
  PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': pergunta do proprietario');
  RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text;
END;
$function$
;
