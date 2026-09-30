CREATE OR REPLACE FUNCTION public.nai_usou_ferramenta(p_turno bigint, p_nome text)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE nai_turno SET ferramentas = array_append(ferramentas, p_nome)
   WHERE id = p_turno AND NOT (p_nome = ANY(ferramentas));
$function$;
