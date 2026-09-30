CREATE OR REPLACE FUNCTION public.nai_jev_pedido(p_turno bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (j.respostas #>> '{pedido,noul}')::real
         >= coalesce(nullif(nai_cfg('jev_piso_pedido','0.60'),''),'0.60')::real
    FROM nai_jev j
   WHERE j.turno_id = p_turno
     AND j.respostas #>> '{pedido,noul}' IS NOT NULL
   ORDER BY j.id DESC
   LIMIT 1;
$function$;
