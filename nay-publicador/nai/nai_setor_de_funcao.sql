CREATE OR REPLACE FUNCTION public.nai_setor_de_funcao(p_nome text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT r.setor FROM nai_setor_regra r
   WHERE p_nome ~ r.padrao
   ORDER BY r.ordem LIMIT 1;
$function$
;
