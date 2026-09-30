CREATE OR REPLACE FUNCTION public.nai_numeros_por_extenso(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 225: "dois quartos" -> "2 quartos"; "um ou dois" -> "1 ou 2"
  SELECT regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           lower(unaccent(coalesce(p, ''))),
           '\m(um|uma)\M', '1', 'g'), '\m(dois|duas)\M', '2', 'g'), '\mtres\M', '3', 'g'),
           '\mquatro\M', '4', 'g'), '\mcinco\M', '5', 'g'), '\mseis\M', '6', 'g');
$function$;
