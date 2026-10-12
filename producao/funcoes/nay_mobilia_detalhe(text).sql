CREATE OR REPLACE FUNCTION public.nay_mobilia_detalhe(p_nivel text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_nivel
           WHEN 'nada'        THEN 'está sem móveis'
           WHEN 'climatizado' THEN 'tem só o ar-condicionado'
           WHEN 'semi'        THEN 'tem móveis planejados e ar-condicionado'
           WHEN 'mobiliado'   THEN 'tem móveis, cama e tudo'
         END
$function$;
