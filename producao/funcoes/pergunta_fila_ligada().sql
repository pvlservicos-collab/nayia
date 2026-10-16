CREATE OR REPLACE FUNCTION public.pergunta_fila_ligada()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$ SELECT lower(coalesce(nai_cfg('pergunta_fila', 'nao'), 'nao')) = 'sim' $function$;
