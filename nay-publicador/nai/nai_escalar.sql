CREATE OR REPLACE FUNCTION public.nai_escalar(p_turno bigint, p_codigo text, p_assunto text, p_disse text)
 RETURNS TABLE(texto_pronto text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; e record; v_nome text; v_cod text; v_base text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  -- PARCERIA NAO SOBE AO TEL (138): a resposta e fixa.
  IF nai_pergunta_parceria(coalesce(nullif(p_disse, ''), t.texto, ''))
     AND nai_so_parceria(coalesce(nullif(p_disse, ''), t.texto, '')) THEN
    RETURN QUERY SELECT nai_cfg('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!');
    RETURN;
  END IF;
  -- ANTES DE ESCALAR, A BASE (Tel, 13/09): "olá o imovel é mobiliado?" subiu ao
  -- Tel com a resposta na ficha. O codigo precisa ser dele (escrito, card que
  -- mandamos, ou o card que ele MARCOU neste turno) -- nunca da cabeca do modelo.
  v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  IF length(v_cod) BETWEEN 3 AND 5
     AND (coalesce(nay_codigo_confirmado(k.telefone, v_cod, 72), 'nao') <> 'nao'
          OR EXISTS (SELECT 1 FROM mensagens m WHERE m.id = ANY (coalesce(t.msg_ids, '{}'))
                      AND nay_imovel_da_citacao(m.citado_id) = v_cod)) THEN
    v_base := coalesce(nai_resposta_da_base(v_cod::int, p_disse), nai_resposta_da_base(v_cod::int, p_assunto));
    IF v_base IS NOT NULL THEN
      RETURN QUERY SELECT v_base;
      RETURN;
    END IF;
  END IF;
  -- PAREDE: BUSCA NAO SOBE AO TEL (Tel, 15/09). Instrucao no cabecalho o
  -- modelo pode ignorar -- e ignorou, no teste de 15/09, escalando "voce tem
  -- apartamento de 2 quartos?" em vez de procurar. Aqui a busca volta como a
  -- pergunta certa da sequencia, e o Tel nao recebe nada.
  DECLARE v_ped jsonb; r_perfil record;
  BEGIN
    v_ped := nai_pedido_de_perfil(coalesce(nullif(p_disse, ''), t.texto));
    IF (v_ped->>'e_pedido')::boolean THEN
      SELECT * INTO r_perfil FROM nai_buscar_por_perfil(
        p_turno, v_ped->>'bairro', v_ped->>'teto', v_ped->>'quartos', NULL);
      IF r_perfil.texto_pronto IS NOT NULL THEN
        RETURN QUERY SELECT r_perfil.texto_pronto;
        RETURN;
      END IF;
    END IF;
  END;

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  -- MIDIA VAI PARA O TEL (Tel, 16/09): "ela NUNCA deve falar que nao le
  -- imagem; se nao conseguir, manda a imagem ao Tel". O aviso padrao diria que
  -- ele "perguntou sobre o imovel: ''" -- com aspas vazias, porque nao veio
  -- texto nenhum. Quando o turno traz midia, o Tel recebe o recado certo: ele
  -- ve as fotos no proprio WhatsApp, na conversa daquela pessoa.
  DECLARE v_mid text;
  BEGIN
    v_mid := nai_midia_do_turno(p_turno);
    IF v_mid IS NOT NULL THEN
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') me mandou ' || v_mid ||
        CASE WHEN btrim(coalesce(nullif(p_disse, ''), t.texto, '')) <> ''
             THEN ' e escreveu: "' || left(coalesce(nullif(p_disse, ''), t.texto), 300) || '"'
             ELSE ', sem escrever nada junto' END ||
        '. Não abro imagem nem áudio: dá uma olhada aí na conversa dele?' ||
        E'\nFalei só que recebi e que já respondo. Parei de responder esse chat: quem segue é você. Para eu voltar: DEVOLVER '
        || nai_fone_fmt(k.telefone) || '.',
        'midia_para_o_tel');
      PERFORM nai_parar_chat(k.id, 'midia: ' || v_mid);
      -- UMA LINHA, E O TEL ASSUME (Tel, 16/09). O escalar normal cala, e esta
      -- certo: ali ela nao sabe a resposta e nao promete nada. Aqui e outra
      -- coisa -- o corretor acabou de mandar treze fotos e fica olhando para a
      -- tela. Calar depois disso e o mesmo "teve um que mandou boa noite e ela
      -- n respondeu" de que ele reclamou em 15/09.
      --
      -- A frase nao diz que viu, nao diz que nao consegue abrir, e nao promete
      -- prazo: diz que chegou e que a resposta vem. Quem responde e o Tel, que
      -- ja recebeu o aviso acima.
      RETURN QUERY SELECT ('Recebi'
        || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
        || '! Já te respondo por aqui.')::text;
      RETURN;
    END IF;
  END;
  SELECT * INTO e FROM nay_escalar(k.telefone, v_nome, p_codigo, p_assunto, p_disse);
  IF e.acao IN ('escalar', 'esperar') THEN
    v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou sobre o ' ||
      coalesce(CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ref_imovel(v_cod::int) END, 'imóvel') || ': "' ||
      left(coalesce(nullif(p_disse, ''), p_assunto, ''), 300) || '". Não achei na base, você sabe?' ||
      E'\nNão falei nada com ele e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'duvida_fora_da_base');
    PERFORM nai_parar_chat(k.id, 'duvida fora da base: ' || coalesce(p_assunto, ''));
    RETURN QUERY SELECT 'SILENCIO'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT e.texto_pronto;
END;
$function$
;
