CREATE OR REPLACE FUNCTION public.captacao_olx_pronome(p_tratamento text, p_maiuscula boolean)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_tratamento = 'Sr.' THEN CASE WHEN p_maiuscula THEN 'O Sr.' ELSE 'o Sr.' END
              WHEN p_tratamento = 'Sra.' THEN CASE WHEN p_maiuscula THEN 'A Sra.' ELSE 'a Sra.' END
              ELSE CASE WHEN p_maiuscula THEN 'Você' ELSE 'você' END END;
$function$;
