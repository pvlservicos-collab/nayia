CREATE OR REPLACE FUNCTION public.nai_motoboy()
 RETURNS TABLE(contato_id bigint, nome text, telefone text)
 LANGUAGE plpgsql
AS $function$
DECLARE e record; v_id bigint;
BEGIN
  SELECT * INTO e FROM equipe WHERE papel = 'acompanhante' AND ativo ORDER BY criado_em LIMIT 1;
  IF e IS NULL OR nai_chave(e.telefone) IS NULL THEN RETURN; END IF;
  v_id := nai_contato_de(e.telefone, e.nome);
  RETURN QUERY SELECT v_id, e.nome::text, e.telefone::text;
END;
$function$;
