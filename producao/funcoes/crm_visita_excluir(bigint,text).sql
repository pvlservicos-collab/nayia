CREATE OR REPLACE FUNCTION public.crm_visita_excluir(p_visita bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v nai_visita;
  v_barradas int;
  quem text := coalesce(nullif(btrim(p_quem), ''), 'CRM');
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN; END IF;
  IF v.excluida_em IS NOT NULL THEN RETURN QUERY SELECT true, 'Essa visita já tinha sido excluída.'; RETURN; END IF;

  UPDATE nai_visita
     SET excluida_em = now(), excluida_por = quem,
         estado = CASE WHEN estado IN ('encerrada', 'cancelada', 'expirada') THEN estado ELSE 'cancelada' END,
         aguardando = NULL, senha = NULL,
         encerrada_em = coalesce(encerrada_em, now()),
         motivo = coalesce(motivo, 'Excluída no CRM por ' || quem),
         atualizado_em = now()
   WHERE id = v.id;
  -- o que a Nay ainda ia mandar sobre ela não sai mais ("sem avisar ninguém")
  WITH b AS (
    UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'visita excluída no CRM'
     WHERE visita_id = v.id AND estado = 'pendente' RETURNING 1)
  SELECT count(*) INTO v_barradas FROM b;
  PERFORM nai_evento(v.id, 'excluida_no_crm', 'por ' || quem);
  PERFORM nai_liberar_chats_da_visita(v.id);
  RETURN QUERY SELECT true, 'Visita excluída. Ninguém foi avisado' ||
    CASE WHEN v_barradas > 0 THEN ' (' || v_barradas || ' mensagem da fila não sai mais)' ELSE '' END || '.';
END $function$;
