CREATE OR REPLACE FUNCTION public.nai_ferramentas_v2(p_turno bigint, p_ferramentas text[])
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE nai_turno_decisao
     SET ferramentas = ARRAY(SELECT DISTINCT unnest(coalesce(p_ferramentas,'{}')))
   WHERE turno_id = p_turno;
$function$
;
