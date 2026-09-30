CREATE OR REPLACE FUNCTION public.crm_nay_parar(p_telefone text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_ids bigint[];
  v_n int;
BEGIN
  SELECT p.ids INTO v_ids FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    -- a Nay ainda não conhece: cria pelo telefone, para a parada valer já
    PERFORM nai_contato_do_cadastro(p_telefone, NULL);
    SELECT p.ids INTO v_ids FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  END IF;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RETURN QUERY SELECT false, 'Não achei esse contato na Nay.'; RETURN;
  END IF;
  UPDATE nai_contato
     SET humano_assumiu_em = now(),
         humano_motivo = 'parada no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém')
   WHERE id = ANY (v_ids);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN QUERY SELECT true, 'A Nay parou nesta conversa. Ela não manda nada até alguém clicar em "Nay voltar a atender".';
END $function$;
