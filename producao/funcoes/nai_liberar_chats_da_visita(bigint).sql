CREATE OR REPLACE FUNCTION public.nai_liberar_chats_da_visita(p_visita bigint)
 RETURNS integer
 LANGUAGE sql
AS $function$
  WITH u AS (UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL
              WHERE humano_motivo LIKE 'visita #' || p_visita || ':%' RETURNING 1)
  SELECT count(*)::int FROM u;
$function$;
