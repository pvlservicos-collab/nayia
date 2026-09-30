CREATE OR REPLACE FUNCTION public.nai_dia_por_extenso(p_dia date, p_hoje date)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_dia = p_hoje THEN 'Hoje, '
              WHEN p_dia = p_hoje + 1 THEN 'Amanhã, '
              ELSE '' END
      || CASE extract(isodow FROM p_dia)
           WHEN 1 THEN 'segunda' WHEN 2 THEN 'terça' WHEN 3 THEN 'quarta'
           WHEN 4 THEN 'quinta'  WHEN 5 THEN 'sexta' WHEN 6 THEN 'sábado'
           ELSE 'domingo' END
      || ' ' || to_char(p_dia, 'DD/MM');
$function$
;
