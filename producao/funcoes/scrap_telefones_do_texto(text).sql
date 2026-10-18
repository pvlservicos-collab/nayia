CREATE OR REPLACE FUNCTION public.scrap_telefones_do_texto(p text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE t text; m text[]; achados text[] := '{}'; tel text; i int;
BEGIN
  t := coalesce(p, '');
  FOR i IN 1..3 LOOP
    t := regexp_replace(t, '(\d)[Il|]', '\11', 'g');
    t := regexp_replace(t, '[Il|](\d)', '1\1', 'g');
    t := regexp_replace(t, '(\d)[Oo](?=\d)', '\10', 'g');
  END LOOP;
  FOR m IN SELECT regexp_matches(t, '((?:\(?\d{2}\)?[\s.-]*)?\d{4,5}[\s.-]?\d{4})(?!\d)', 'g') LOOP
    tel := scrap_telefone_normalizar(m[1]);
    IF tel IS NOT NULL AND NOT (tel = ANY (achados)) THEN achados := achados || tel; END IF;
  END LOOP;
  RETURN achados;
END
$function$;
