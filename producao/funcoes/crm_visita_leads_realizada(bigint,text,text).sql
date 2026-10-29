CREATE OR REPLACE FUNCTION public.crm_visita_leads_realizada(p_visita bigint, p_para text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v privado.olx_visita;
BEGIN
  SELECT * INTO v FROM privado.olx_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita da Nay Leads.'; RETURN;
  END IF;
  IF p_para NOT IN ('cliente', 'corretor') THEN
    RETURN QUERY SELECT false, 'Escolha se a Nay pergunta ao cliente ou ao corretor.'; RETURN;
  END IF;
  IF v.estado = 'realizada' THEN
    RETURN QUERY SELECT false, 'Essa visita já foi marcada como realizada'
                               || coalesce(' por ' || v.realizada_por, '') || '.'; RETURN;
  END IF;
  IF v.estado <> 'confirmada' THEN
    RETURN QUERY SELECT false, 'Só a visita confirmada pode ser marcada como realizada (esta está "' || v.estado || '").'; RETURN;
  END IF;
  IF v.quando > now() THEN
    RETURN QUERY SELECT false, 'A visita ainda não aconteceu (é ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24:MI') || ').'; RETURN;
  END IF;
  IF p_para = 'corretor' AND coalesce(regexp_replace(v.corretor_telefone, '\D', '', 'g'), '') = '' THEN
    RETURN QUERY SELECT false, 'Essa visita não tem o número do corretor: pergunte ao cliente.'; RETURN;
  END IF;
  -- depois_em volta a vazio: o pedido da equipe vale mesmo se o automático antigo já tinha perguntado
  UPDATE privado.olx_visita
     SET estado = 'realizada', feedback_para = p_para, realizada_em = now(),
         realizada_por = nullif(btrim(coalesce(p_quem, '')), ''), depois_em = NULL, atualizado_em = now()
   WHERE id = v.id;
  RETURN QUERY SELECT true, 'Marcada como realizada. A Nay vai perguntar ao '
                            || CASE WHEN p_para = 'cliente' THEN 'cliente' ELSE 'corretor' END
                            || ' como foi a visita (sai em até 1 minuto, pelo número Leads).';
END $function$;
