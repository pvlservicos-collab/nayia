CREATE OR REPLACE FUNCTION public.nay_cond(q text)
 RETURNS TABLE(nome text)
 LANGUAGE sql
 STABLE
AS $function$
WITH s AS (SELECT DISTINCT condominio_nome n, word_similarity(unaccent(lower(q)),unaccent(lower(condominio_nome))) v, position(lower(q) in lower(condominio_nome))>0 e FROM imoveis WHERE condominio_nome IS NOT NULL)
SELECT n FROM s WHERE e UNION SELECT n FROM s WHERE NOT EXISTS(SELECT 1 FROM s WHERE e) AND v>=0.4 AND v>=(SELECT max(v) FROM s)-0.05 $function$;
