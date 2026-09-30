CREATE OR REPLACE FUNCTION public.nay_e_da_equipe(p_telefone text)
 RETURNS TABLE(nome text, papel text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT e.nome, e.papel
    FROM equipe e
   WHERE e.ativo
     AND right(regexp_replace(e.telefone,'[^0-9]','','g'), 8)
       = right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'), 8)
   LIMIT 1;
$function$;
