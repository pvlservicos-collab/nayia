CREATE OR REPLACE FUNCTION public.site_link_organico_clique(p_codigo text, p_utm jsonb, p_referer text, p_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE l privado.link_organico;
BEGIN
  SELECT * INTO l FROM privado.link_organico WHERE codigo = lower(btrim(p_codigo)) AND ativo;
  IF l.codigo IS NULL THEN RETURN NULL; END IF;
  INSERT INTO privado.link_organico_clique (codigo, utm, referer, ip_hash)
  VALUES (l.codigo, coalesce(p_utm, '{}'::jsonb), left(p_referer, 300),
          CASE WHEN coalesce(p_ip, '') <> '' THEN left(md5(p_ip || to_char(now(), 'YYYY-MM-DD')), 16) END);
  RETURN jsonb_build_object('mensagem', l.mensagem);
END
$function$;
