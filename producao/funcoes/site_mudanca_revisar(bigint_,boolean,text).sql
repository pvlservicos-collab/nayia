CREATE OR REPLACE FUNCTION public.site_mudanca_revisar(p_ids bigint[], p_revisada boolean, p_quem text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  UPDATE privado.imovel_mudanca
     SET revisado_em = CASE WHEN p_revisada THEN now() END,
         revisado_por = CASE WHEN p_revisada THEN left(coalesce(nullif(btrim(p_quem), ''), 'painel'), 80) END
   WHERE id = ANY (p_ids) AND (revisado_em IS NULL) = p_revisada;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END
$function$;
