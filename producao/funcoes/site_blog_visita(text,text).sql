CREATE OR REPLACE FUNCTION public.site_blog_visita(p_slug text, p_origem text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM blog_artigo WHERE slug = p_slug AND publicado;
  IF v_id IS NULL THEN RETURN false; END IF;
  INSERT INTO blog_visita (artigo_id, dia, origem, n)
  VALUES (v_id, (now() AT TIME ZONE 'America/Manaus')::date, left(coalesce(nullif(btrim(p_origem), ''), 'direto'), 40), 1)
  ON CONFLICT (artigo_id, dia, origem) DO UPDATE SET n = blog_visita.n + 1;
  RETURN true;
END
$function$;
