CREATE OR REPLACE FUNCTION public.site_blog_admin_artigo(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT to_jsonb(a) || jsonb_build_object('categoria_nome', blog_categoria_nome(a.categoria),
           'imovel', CASE WHEN a.codigo IS NOT NULL THEN site_blog_card_imovel(a.codigo) END)
    FROM blog_artigo a WHERE a.id = p_id
$function$;
