CREATE OR REPLACE FUNCTION public.nai_codigos_que_ele_digitou(p_contato bigint)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- Código escrito ou card colado por ELE nos últimos 3 dias. É o pedido
  -- claro: esse imóvel vai, seja de venda ou de locação.
  SELECT coalesce(array_agg(DISTINCT x::int), '{}')
    FROM nai_turno t
   CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(t.texto, '')), '{}'::text[])) x
   WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
     AND t.criado_em > now() - interval '3 days'
     AND x ~ '^[0-9]{3,5}$';
$function$
;
