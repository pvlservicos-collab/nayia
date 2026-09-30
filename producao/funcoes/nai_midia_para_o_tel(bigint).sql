CREATE OR REPLACE FUNCTION public.nai_midia_para_o_tel(p_turno bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t nai_turno; k nai_contato;
  v_mid jsonb; n_img int; n_doc int; n_vid int; itens text[] := '{}';
  v_nome text; v_fone text; v_texto text; v_cod int; v_links text; v_horas int;
  v_aviso text; v_conting text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- a. Tel, equipe e acompanhante não geram aviso (turno 12465: o Tel avisado sobre
  --    ele mesmo); fora da lista continua calado como hoje
  IF t.papel IN ('tel', 'equipe', 'motoboy') OR nai_e_da_equipe_contato(t.contato_id)
     OR coalesce(t.porta, '') LIKE 'fora da lista%' THEN
    PERFORM nai_anotar(p_turno, 3, 'midia_para_o_tel', 'passou', 'sem aviso: ' || coalesce(t.papel, '') || ' / ' || coalesce(t.porta, ''));
    RETURN jsonb_build_object('ok', true, 'aviso', false, 'motivo', 'papel_ou_porta');
  END IF;
  IF EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = p_turno AND s.motivo = 'midia_para_o_tel') THEN
    RETURN jsonb_build_object('ok', true, 'aviso', false, 'motivo', 'ja_avisado');
  END IF;

  v_mid := nai_midias_do_turno(p_turno);
  IF jsonb_array_length(v_mid) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'aviso', false, 'motivo', 'sem_midia');
  END IF;
  SELECT count(*) FILTER (WHERE x->>'tipo' = 'imagem'), count(*) FILTER (WHERE x->>'tipo' = 'documento'),
         count(*) FILTER (WHERE x->>'tipo' = 'video')
    INTO n_img, n_doc, n_vid FROM jsonb_array_elements(v_mid) x;
  IF n_img > 0 THEN itens := itens || (CASE WHEN n_img = 1 THEN 'uma imagem' ELSE n_img || ' imagens' END); END IF;
  IF n_doc > 0 THEN itens := itens || (CASE WHEN n_doc = 1 THEN 'um arquivo' ELSE n_doc || ' arquivos' END); END IF;
  IF n_vid > 0 THEN itens := itens || (CASE WHEN n_vid = 1 THEN 'um vídeo' ELSE n_vid || ' vídeos' END); END IF;

  v_nome  := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  v_fone  := nai_fone_fmt(k.telefone);
  -- o texto que veio junto (a legenda das mídias e as mensagens de texto do turno), com CPF mascarado
  v_texto := nai_mascarar_texto(left(btrim(coalesce(t.texto, '')), 400));
  v_cod   := nai_imovel_da_conversa(t.contato_id, t.texto);
  SELECT string_agg(x->>'url', E'\n' ORDER BY o) INTO v_links FROM jsonb_array_elements(v_mid) WITH ORDINALITY z(x, o);
  v_horas := nai_cfg_int('escalacao_expira_horas', 0);

  v_aviso := 'Tel, ' || v_nome || ' (' || v_fone || ') me mandou ' || nai_lista_pt(itens)
    || CASE WHEN v_texto <> '' THEN ' e escreveu: "' || v_texto || '"' ELSE ', sem escrever nada junto' END
    || CASE WHEN v_cod IS NOT NULL THEN '. Imóvel da conversa: ' || nai_ref_imovel(v_cod) ELSE '' END
    || '.' || E'\n' || 'Não abro imagem nem arquivo: dá uma olhada aí.' || E'\n' || v_links || E'\n'
    || 'Respondi "Recebi, já te respondo por aqui" e parei de responder esse chat'
    || CASE WHEN v_horas > 0 THEN ' por até ' || v_horas || ' horas' ELSE '' END
    || '. Para eu voltar antes: DEVOLVER ' || v_fone || ' [resposta]';
  PERFORM nai_avisar_tel(p_turno, NULL, v_aviso, 'midia_para_o_tel');

  -- c. a contingência ao corretor: a mesma frase que nai_escalar usa hoje para mídia
  v_conting := 'Recebi' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '') || '! Já te respondo por aqui.';
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_conting, 'midia_contingencia', 1);

  -- d. a pausa com prazo (195)
  PERFORM nai_parar_chat(t.contato_id, 'midia: ' || nai_lista_pt(itens) || ' em ' || to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'));
  -- e. o painel enxerga
  PERFORM nai_anotar(p_turno, 3, 'midia_para_o_tel', 'parou', nai_lista_pt(itens) || ': aviso ao Tel, contingência, chat pausado');
  UPDATE nai_turno SET ferramentas = array_append(coalesce(ferramentas, '{}'), 'midia_para_o_tel'), fechado_em = now() WHERE id = p_turno;
  RETURN jsonb_build_object('ok', true, 'aviso', true, 'itens', nai_lista_pt(itens), 'imovel', v_cod);
END;
$function$;
