CREATE OR REPLACE FUNCTION public.nai_cpf_valido(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Tira tudo que nao e numero e devolve os 11 digitos. Qualquer outra
  -- quantidade devolve NULL, e ai ela pede de novo -- que e o caso do
  -- corretor que mandou o CPF pela metade.
  SELECT nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '')
   WHERE regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^[0-9]{11}$';
$function$
;
