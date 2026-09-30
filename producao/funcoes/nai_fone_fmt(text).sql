CREATE OR REPLACE FUNCTION public.nai_fone_fmt(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN d ~ '^55[0-9]{2}9[0-9]{8}$' THEN '(' || substr(d,3,2) || ') ' || substr(d,5,5) || '-' || substr(d,10,4)
    -- Celular que o WhatsApp entrega SEM o 9 (12 digitos, comeca com 6-9):
    -- o numero de verdade tem o 9. Nos avisos ao Tel saia "[telefone …2835]" (13/09).
    WHEN d ~ '^55[0-9]{2}[6-9][0-9]{7}$' THEN '(' || substr(d,3,2) || ') 9' || substr(d,5,4) || '-' || substr(d,9,4)
    WHEN d ~ '^55[0-9]{2}[0-9]{8}$'  THEN '(' || substr(d,3,2) || ') ' || substr(d,5,4) || '-' || substr(d,9,4)
    ELSE p
  END
  FROM (SELECT nai_fone_br(p) AS d) t;
$function$;
