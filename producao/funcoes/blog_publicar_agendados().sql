CREATE OR REPLACE FUNCTION public.blog_publicar_agendados()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int;
BEGIN
  UPDATE blog_artigo SET publicado = true, publicado_em = agendado_para, agendado_para = NULL, atualizado_em = now()
   WHERE NOT publicado AND agendado_para IS NOT NULL AND agendado_para <= now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$function$;
