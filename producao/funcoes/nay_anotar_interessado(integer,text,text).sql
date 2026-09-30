CREATE OR REPLACE FUNCTION public.nay_anotar_interessado(p_pendencia_id integer, p_telefone text, p_nome text)
 RETURNS void
 LANGUAGE sql
AS $function$
  INSERT INTO pendencia_interessado (pendencia_id, telefone, nome)
  SELECT p_pendencia_id, p_telefone, NULLIF(btrim(coalesce(p_nome,'')),'')
   WHERE p_pendencia_id IS NOT NULL
     AND NULLIF(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),'') IS NOT NULL
  ON CONFLICT DO NOTHING;
$function$;
