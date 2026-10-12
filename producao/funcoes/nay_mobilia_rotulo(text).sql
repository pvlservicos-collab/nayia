CREATE OR REPLACE FUNCTION public.nay_mobilia_rotulo(p_nivel text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_nivel
           WHEN 'nada'        THEN 'sem móveis'          -- "pelado" nunca sai para o cliente
           WHEN 'climatizado' THEN 'só climatizado'
           WHEN 'semi'        THEN 'com modulados e ar'
           WHEN 'mobiliado'   THEN 'mobiliado'
         END
$function$;
