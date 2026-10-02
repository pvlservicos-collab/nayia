CREATE OR REPLACE FUNCTION public.crm_anuncio_numero(v jsonb)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE jsonb_typeof(v)
    WHEN 'number' THEN (v #>> '{}')::numeric
    WHEN 'string' THEN CASE
      WHEN (v #>> '{}') ~ '^\s*[0-9]+(\.[0-9]{1,2})?\s*$' THEN btrim(v #>> '{}')::numeric
      WHEN regexp_replace(v #>> '{}', '[^0-9.,]', '', 'g') ~ '^([0-9]{1,3}(\.[0-9]{3})+|[0-9]+)(,[0-9]{1,2})?$'
        THEN replace(replace(regexp_replace(v #>> '{}', '[^0-9.,]', '', 'g'), '.', ''), ',', '.')::numeric
      END
    END;
$function$;
