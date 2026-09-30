CREATE OR REPLACE FUNCTION public.nai_registrar_saida_v2(p_turno bigint, p_enviados jsonb, p_bloqueados jsonb)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE nai_turno_decisao
     SET enviados   = coalesce(p_enviados, '[]'::jsonb),
         bloqueados = coalesce(p_bloqueados, '[]'::jsonb)
   WHERE turno_id = p_turno;
$function$;
