CREATE OR REPLACE FUNCTION public.nai_pediu_imovel(p_turno bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN nai_so_cumprimentou(t.texto)
                OR lower(btrim(coalesce(t.texto, ''))) ~ '^(muito )?(obrigad[oa]s?|obg|vlw|valeu|agrade[cç]o)( nay)?[\s!.,🙏👍😊]*$'
              THEN false
              ELSE coalesce(nai_jev_pedido(p_turno), true) END
    FROM nai_turno t WHERE t.id = p_turno;
$function$;
