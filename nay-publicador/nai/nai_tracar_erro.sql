CREATE OR REPLACE FUNCTION public.nai_tracar_erro(p_turno bigint, p_setor text, p_etapa text, p_erro text, p_exec text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN nai_tracar(p_turno, p_setor, p_etapa, 'erro', NULL, NULL,
                    left(coalesce(p_erro, 'erro sem mensagem'), 2000), NULL, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$function$
;
