CREATE OR REPLACE FUNCTION public.nai_tipo_das_falas(p_falas text[])
 RETURNS text
 LANGUAGE sql
 STABLE COST 2000
AS $function$
  SELECT nai_tipo_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nai_tipo_pedido(f.fala) IS NOT NULL
     AND NOT nai_fala_e_dele(f.fala)
   ORDER BY f.pos LIMIT 1;
$function$
;
