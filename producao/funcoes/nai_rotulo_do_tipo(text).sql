CREATE OR REPLACE FUNCTION public.nai_rotulo_do_tipo(p_tipo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_tipo
    WHEN 'Casa%'        THEN 'casa'      WHEN 'Apartamento%' THEN 'apartamento'
    WHEN 'Cobertura%'   THEN 'cobertura' WHEN 'Flat%'        THEN 'flat'
    WHEN 'Sala%'        THEN 'sala'      WHEN 'Loja%'        THEN 'ponto'
    WHEN 'Galp%'        THEN 'galpão'    WHEN 'Lote%'        THEN 'terreno'
    WHEN 'Ch%'          THEN 'chácara'   WHEN 'Pr%dio%'      THEN 'prédio'
  END;
$function$;
