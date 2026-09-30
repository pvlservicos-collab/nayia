CREATE OR REPLACE FUNCTION public.nai_tracar_modelo(p_turno bigint, p_texto_cru text, p_ferramentas text DEFAULT NULL::text, p_modelo text DEFAULT NULL::text, p_ms integer DEFAULT NULL::integer, p_exec text DEFAULT NULL::text, p_tokens_in integer DEFAULT NULL::integer, p_tokens_out integer DEFAULT NULL::integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint;
BEGIN
  UPDATE nai_turno
     SET modelo  = coalesce(p_modelo, modelo),
         exec_id = coalesce(nullif(btrim(coalesce(p_exec,'')),''), exec_id)
   WHERE id = p_turno;

  v_id := nai_tracar(
    p_turno, 'modelo', 'resposta_crua',
    CASE WHEN coalesce(btrim(p_texto_cru), '') = '' THEN 'parou' ELSE 'ok' END,
    NULL,
    jsonb_build_object(
      'texto_cru',   p_texto_cru,
      'ferramentas', string_to_array(coalesce(p_ferramentas, ''), ','),
      'tokens_entrada', p_tokens_in,
      'tokens_saida',   p_tokens_out),
    CASE WHEN coalesce(btrim(p_texto_cru), '') = ''
         THEN 'o modelo nao devolveu texto'
         ELSE length(p_texto_cru) || ' caracteres' END,
    p_ms, p_exec);
  RETURN v_id;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$function$
;
