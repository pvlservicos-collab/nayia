CREATE OR REPLACE FUNCTION public.scrap_bloqueado(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (SELECT 1 FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
                  WHERE l.tipo = 'blacklist' AND scrap_chave(c.telefone) = scrap_chave(p_telefone))
$function$;
