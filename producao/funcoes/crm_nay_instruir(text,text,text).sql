CREATE OR REPLACE FUNCTION public.crm_nay_instruir(p_telefone text, p_texto text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE v_ids bigint[]; v_contato bigint; v_texto text := left(btrim(coalesce(p_texto, '')), 4000); r record;
BEGIN
  IF v_texto = '' THEN RETURN QUERY SELECT false, 'Escreva a instrução antes.'; RETURN; END IF;
  SELECT p.ids, p.contato_id INTO v_ids, v_contato FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    v_contato := nai_contato_do_cadastro(p_telefone, NULL);
    v_ids := ARRAY[v_contato];
  END IF;
  v_contato := coalesce(v_contato, v_ids[1]);
  INSERT INTO nai_instrucao (contato_id, texto, criado_por) VALUES (v_contato, v_texto, left(coalesce(p_quem, 'CRM'), 80));
  -- solta a Nay do mesmo jeito do "voltar a atender" (228)
  SELECT * INTO r FROM crm_nay_voltar(p_telefone, p_quem);
  RETURN QUERY SELECT true, 'Instrução guardada por 48 h. ' || coalesce(r.mensagem, '');
END $function$;
