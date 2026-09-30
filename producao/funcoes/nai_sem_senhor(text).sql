CREATE OR REPLACE FUNCTION public.nai_sem_senhor(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 138: tira "Sr." e "Sra.", deixando o nome ou "você" (com maiúscula no começo da frase).
  SELECT regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p, ''),
           '\mSra?\.?\s+(?=[[:upper:]])', '', 'g'),
           '\m(do|da)\s+Sra?\M\.?', 'de você', 'g'),
           '\m(ao|à)\s+Sra?\M\.?', 'a você', 'g'),
           '\m(pro|pra|para o|para a)\s+Sra?\M\.?', 'pra você', 'g'),
           '\m(o|a|O|A)\s+Sra?\M\.?', 'você', 'g'),
           '\mSra?\M\.', 'você', 'g'),
           '(^|[.!?]\s+|\n\s*)você', '\1Você', 'g');
$function$;
