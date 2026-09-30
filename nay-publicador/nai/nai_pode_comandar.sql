CREATE OR REPLACE FUNCTION public.nai_pode_comandar(p_chave text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM regexp_split_to_table(coalesce(nai_cfg('comando_telefones'), ''), '\s*,\s*') AS n
     WHERE nullif(btrim(n), '') IS NOT NULL AND nai_chave(n) = p_chave);
$function$
;
