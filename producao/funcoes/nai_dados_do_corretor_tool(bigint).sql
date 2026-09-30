CREATE OR REPLACE FUNCTION public.nai_dados_do_corretor_tool(p_turno bigint)
 RETURNS TABLE(instrucao_para_voce text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN d.completo
    THEN 'voce ja tem nome completo, CPF e CRECI deste corretor (' || coalesce(d.nome_completo, '') || '). NAO peca de novo.'
    ELSE 'falta do corretor: ' || array_to_string(ARRAY_REMOVE(ARRAY[
           CASE WHEN d.nome_completo IS NULL THEN 'nome completo' END,
           CASE WHEN d.cpf IS NULL THEN 'CPF' END,
           CASE WHEN d.creci IS NULL THEN 'CRECI' END], NULL), ', ') || '. so peca quando for marcar visita.'
  END
  FROM nai_turno t, nai_dados_corretor(t.contato_id) d WHERE t.id = p_turno;
$function$;
