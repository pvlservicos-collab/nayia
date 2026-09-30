CREATE OR REPLACE FUNCTION public.nay_codigos_da_saida(p_message_id text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nay_codigos_citados(coalesce(s.texto,''))
    FROM mensagem_saida s
   WHERE s.message_id = NULLIF(btrim(coalesce(p_message_id,'')), '')
   LIMIT 1;
$function$;
