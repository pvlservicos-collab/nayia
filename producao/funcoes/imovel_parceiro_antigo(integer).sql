CREATE OR REPLACE FUNCTION public.imovel_parceiro_antigo(p_codigo integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 413: parceiro do site antigo, ainda sem o status atualizado pelo disparo: a Nay de captação não oferece
  SELECT coalesce((SELECT coalesce(i.extras->>'parceiro_antigo', '') = 'sim' FROM imoveis i WHERE i.codigo = p_codigo), false)
$function$;
