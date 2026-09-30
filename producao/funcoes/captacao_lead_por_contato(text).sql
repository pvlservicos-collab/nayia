CREATE OR REPLACE FUNCTION public.captacao_lead_por_contato(p_tel text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_tel)
      AND coalesce(p_tel, '') !~* '@lid' AND length(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')) BETWEEN 12 AND 13
      AND regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') ~ '^55' LIMIT 1),
    (SELECT id FROM captacao_leads WHERE chat_lid = regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')
      AND regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') <> '' ORDER BY id DESC LIMIT 1));
$function$;
