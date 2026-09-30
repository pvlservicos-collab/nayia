CREATE OR REPLACE FUNCTION public.nai_tracar_cabecalho(p_turno bigint, p_papel text, p_prompt text, p_contexto text, p_exec text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_ver int; v_vazio boolean;
BEGIN
  v_vazio := coalesce(length(btrim(coalesce(p_prompt, ''))), 0) < 500;
  SELECT versao INTO v_ver FROM nai_prompt WHERE papel = p_papel;

  UPDATE nai_turno
     SET prompt_versao = v_ver,
         exec_id = coalesce(nullif(btrim(coalesce(p_exec,'')),''), exec_id)
   WHERE id = p_turno;

  RETURN nai_tracar(
    p_turno, 'cabecalho', 'prompt_e_contexto',
    -- Prompt curto ou ausente é ERRO, não aviso: significa que o agente está
    -- rodando com o texto de reserva de dentro do nó -- uma cópia velha, que
    -- ninguém versionou. É o achado de 19/09.
    CASE WHEN v_vazio THEN 'erro' ELSE 'ok' END,
    NULL,
    jsonb_build_object(
      'papel',            p_papel,
      'prompt_versao',    v_ver,
      'prompt_caracteres', length(coalesce(p_prompt, '')),
      'contexto',         p_contexto),
    CASE WHEN v_vazio
         THEN 'PROMPT VAZIO OU CURTO: o agente pode estar usando o texto de reserva do no'
         ELSE 'prompt v' || coalesce(v_ver::text, '?') || ', ' ||
              length(coalesce(p_prompt,'')) || ' chars' END,
    NULL, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$function$;
