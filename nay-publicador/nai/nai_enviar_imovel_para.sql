CREATE OR REPLACE FUNCTION public.nai_enviar_imovel_para(p_turno bigint, p_codigo integer, p_telefone text)
 RETURNS text
 LANGUAGE sql
AS $function$
  SELECT nai_enviar_imoveis_para(p_turno, ARRAY[p_codigo], p_telefone);
$function$
;
