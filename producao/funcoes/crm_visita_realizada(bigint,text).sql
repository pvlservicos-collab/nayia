CREATE OR REPLACE FUNCTION public.crm_visita_realizada(p_visita bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v nai_visita;
  c nai_contato;
  v_nome text;
  v_extra text := '';
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN;
  END IF;
  IF v.estado IN ('realizada', 'encerrada', 'cancelada', 'expirada', 'coletando') THEN
    RETURN QUERY SELECT false, 'Essa visita já está ' || v.estado || '.'; RETURN;
  END IF;
  IF v.quando IS NULL OR v.quando > now() THEN
    RETURN QUERY SELECT false, 'A visita ainda não aconteceu (é ' || coalesce(to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24:MI'), 'sem data') || ').'; RETURN;
  END IF;

  -- a mesma rotina do nai_agenda_tick, 1h depois da visita
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));
  PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
    'E aí' || coalesce(', ' || v_nome, '') || ', como foi a visita no ' || nai_ref_imovel(v.codigo) || '? O cliente gostou?',
    'pos_visita', 1);
  IF v.acesso = 'buscar_chave' AND v.motoboy_id IS NOT NULL AND v.devolver_chave_em IS NULL THEN
    PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
      '' || nai_acompanhante() || ', não esquece de devolver a chave do ' || nai_ref_imovel(v.codigo) || ' ao proprietário.', 'devolver_chave', 2);
    UPDATE nai_visita SET devolver_chave_em = now() WHERE id = v.id;
    v_extra := ' e lembrei o ' || nai_acompanhante() || ' de devolver a chave';
  END IF;
  UPDATE nai_visita SET pos_visita_em = now(), estado = 'realizada', aguardando = NULL, senha = NULL, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'realizada', 'marcada no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém'));
  PERFORM nai_liberar_chats_da_visita(v.id);
  RETURN QUERY SELECT true, 'Marcada como realizada. A Nay perguntou ao corretor como foi' || v_extra || '.';
END $function$;
