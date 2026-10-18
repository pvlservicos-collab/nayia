CREATE OR REPLACE FUNCTION public.site_blog_newsletter_sair(p_telefone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
BEGIN
  IF length(v_tel) IN (10, 11) THEN v_tel := '55' || v_tel; END IF;
  UPDATE blog_newsletter_corretor SET ativo = false, saiu_em = now() WHERE telefone = v_tel AND ativo;
  RETURN jsonb_build_object('ok', FOUND);
END
$function$;
