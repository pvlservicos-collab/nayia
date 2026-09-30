CREATE OR REPLACE FUNCTION public.nai_prosseguir_acesso(p_visita bigint, p_turno bigint, p_devolver boolean)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  c       nai_contato;
  ac      nai_acesso_imovel;
  v_texto text;
  v_moto  text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;

  IF v.acesso IS NULL THEN
    SELECT * INTO ac FROM nai_acesso_imovel WHERE codigo = v.codigo;
    IF ac.codigo IS NOT NULL THEN
      UPDATE nai_visita SET acesso = ac.acesso, acesso_detalhe = coalesce(acesso_detalhe, ac.detalhe) WHERE id = v.id
      RETURNING * INTO v;
    ELSIF EXISTS (SELECT 1 FROM imovel_privado p WHERE p.codigo = v.codigo AND p.proprietario_acompanha) THEN
      UPDATE nai_visita SET acesso = 'proprietario_acompanha' WHERE id = v.id RETURNING * INTO v;
    END IF;
  END IF;

  IF v.acesso IS NULL THEN
    -- Pergunta curta (Tel, 13/09: "ela so pergunta: E como e para entrar? precisa de chave?").
    v_texto := 'E como é para entrar? precisa de chave?';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSIF v.acesso = 'fechadura' AND v.senha IS NULL THEN
    v_texto := 'Obrigada! Pode me passar a senha da fechadura? Ela fica só com o ' || nai_acompanhante() || ', que acompanha a visita.';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSIF v.acesso = 'buscar_chave' AND v.acesso_detalhe IS NULL THEN
    v_texto := 'Obrigada! Onde e a partir de que horas o ' || nai_acompanhante() || ' pode pegar a chave?';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSE
    -- Tudo certo com o proprietario: confirma com ele e chama o Fernando.
    -- Cards c_prop ("Visita confirmada ... de forma humanizada") e, com a
    -- chave conosco, novo_5 ("so passando para avisar que vamos fazer uma visita").
    v_texto := CASE WHEN v.acesso = 'chave_conosco'
      THEN 'Obrigada! Só passando para avisar que a visita fica ' || nai_quando_humano(v.quando) || '. '
      ELSE 'Combinado, então: visita confirmada ' || nai_quando_humano(v.quando) || '. ' END ||
      -- sem nome/CPF do visitante: no fluxo v17 eles chegam DEPOIS da confirmacao
      'O ' || nai_acompanhante() || ', da nossa equipe, acompanha a visita. Qualquer novidade eu aviso por aqui.';
    -- Card "Avisar motoboy", literal (revisao de 13/09): sem o acesso aqui -- o
    -- acesso vai no "Fechado, Fernando, agendei aqui", depois que ele confirma (card novo_8).
    v_moto := 'Olá, reservamos uma visita ao imóvel ' || nai_endereco_interno(v.codigo) ||
      coalesce(' do proprietário ' || v.proprietario_nome, '') || ', ' || nai_hora_exata(v.quando) ||
      ', pelo corretor ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' || nai_fone_fmt(c.telefone) || ').' ||
      ' Posso confirmar que você vai acompanhar?';
    UPDATE nai_visita SET estado = 'aguardando_motoboy', aguardando = 'motoboy', ult_msg_moto_em = now(),
                          reenvios_moto = 0, atualizado_em = now() WHERE id = v.id;
    IF v.motoboy_id IS NULL THEN
      UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel' WHERE id = v.id;
      PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || ') foi aceita pelo proprietário, mas não tenho o ' || nai_acompanhante() || ' cadastrado na equipe.', 'sem_motoboy');
    ELSE
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy', v_moto, 'flag_fernando', 600);
    END IF;
    PERFORM nai_evento(v.id, 'proprietario_ok', v.acesso);
  END IF;

  IF p_devolver THEN RETURN v_texto; END IF;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', v_texto, 'acesso_ou_confirmacao', 500);
  RETURN NULL;
END;
$function$
;
