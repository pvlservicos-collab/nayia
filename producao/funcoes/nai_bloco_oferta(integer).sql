CREATE OR REPLACE FUNCTION public.nai_bloco_oferta(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nai_bloco_oferta(p_codigo, 'ambos');
$function$;
