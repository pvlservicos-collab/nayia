CREATE OR REPLACE FUNCTION public.captacao_guardar_lid_do_eco(p_tel text, p_lid text)
 RETURNS integer
 LANGUAGE sql
AS $function$
  WITH u AS (
    UPDATE captacao_leads SET chat_lid = regexp_replace(p_lid, '\D', '', 'g')
     WHERE telefone_chave = nay_fone_chave(p_tel)
       AND regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') ~ '^55'
       AND regexp_replace(coalesce(p_lid, ''), '\D', '', 'g') <> ''
       AND chat_lid IS DISTINCT FROM regexp_replace(p_lid, '\D', '', 'g')
    RETURNING 1)
  SELECT count(*)::int FROM u;
$function$;
