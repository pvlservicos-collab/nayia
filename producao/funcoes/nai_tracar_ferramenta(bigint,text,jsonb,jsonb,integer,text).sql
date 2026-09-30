CREATE OR REPLACE FUNCTION public.nai_tracar_ferramenta(p_turno bigint, p_ferramenta text, p_argumentos jsonb, p_resultado jsonb, p_ms integer DEFAULT NULL::integer, p_exec text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN nai_tracar(
    p_turno, 'ferramenta', p_ferramenta,
    CASE WHEN p_resultado IS NULL OR p_resultado = 'null'::jsonb THEN 'parou' ELSE 'ok' END,
    p_argumentos, p_resultado,
    CASE WHEN p_resultado IS NULL OR p_resultado = 'null'::jsonb
         THEN 'a ferramenta nao devolveu nada' END,
    p_ms, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$function$;
