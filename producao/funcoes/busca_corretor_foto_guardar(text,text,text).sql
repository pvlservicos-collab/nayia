CREATE OR REPLACE FUNCTION public.busca_corretor_foto_guardar(p_telefone text, p_url text, p_message_id text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO privado.busca_corretor_foto (telefone8, url, message_id)
  SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8), p_url, nullif(p_message_id, '')
   WHERE busca_corretor_e(p_telefone)
  ON CONFLICT (message_id) DO NOTHING
  RETURNING true;
$function$;
