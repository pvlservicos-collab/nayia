CREATE OR REPLACE FUNCTION public.crm_nay_voltar(p_telefone text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_ids bigint[];
BEGIN
  SELECT p.ids INTO v_ids FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RETURN QUERY SELECT true, 'A Nay já atende esta conversa.'; RETURN;
  END IF;
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
  RETURN QUERY SELECT true, 'A Nay voltou a atender esta conversa.';
END $function$;
