CREATE OR REPLACE FUNCTION public.captacao_olx_encerrar(p_telefone text, p_motivo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lead bigint;
  v_motivo text := lower(btrim(coalesce(p_motivo, 'concluido')));
  v_prox jsonb;
BEGIN
  SELECT l.id INTO v_lead FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.telefone_chave = nay_fone_chave(p_telefone);
  IF v_lead IS NULL THEN RETURN 'ERRO: este proprietario nao e da OLX'; END IF;
  IF v_motivo NOT IN ('opt_out', 'numero_errado', 'nao_e_o_dono', 'parou_de_responder') THEN
    v_prox := captacao_olx_proxima(p_telefone);
    IF NOT coalesce((v_prox->>'fim')::boolean, false) THEN
      RETURN 'NAO encerrei: ainda falta o roteiro. Faca agora, com EXATAMENTE estas palavras, esta pergunta (campo '
             || (v_prox->>'campo') || '): "' || (v_prox->>'pergunta') || '"';
    END IF;
  END IF;
  UPDATE captacao_leads
     SET etapa = 'concluido', status = 'concluido', motivo_fim = 'olx: ' || v_motivo, fechado_em = now(),
         opt_out = opt_out OR v_motivo = 'opt_out', pergunta_pendente = NULL, atualizado_em = now()
   WHERE id = v_lead;
  RETURN 'encerrado. Nao faca mais perguntas. Se ele mandar mais um ok/obrigado depois da sua despedida, responda SILENCIO.';
END $function$;
