CREATE OR REPLACE FUNCTION public.site_fotos_renumerar(p_codigo integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  UPDATE imovel_fotos f SET ordem = x.n, e_capa = (x.n = 1)
    FROM (SELECT id, row_number() OVER (ORDER BY ordem NULLS LAST, id) AS n FROM imovel_fotos WHERE codigo = p_codigo) x
   WHERE f.id = x.id AND (f.ordem IS DISTINCT FROM x.n OR f.e_capa IS DISTINCT FROM (x.n = 1));
$function$;
