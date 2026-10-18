CREATE OR REPLACE FUNCTION public.site_blog_apagar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  DELETE FROM blog_artigo WHERE id = p_id;
  RETURN jsonb_build_object('ok', FOUND);
END
$function$;
