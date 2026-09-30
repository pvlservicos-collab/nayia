CREATE OR REPLACE FUNCTION public.nai_mascarar(p_j jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  IF p_j IS NULL THEN RETURN NULL; END IF;
  RETURN CASE jsonb_typeof(p_j)
    WHEN 'string' THEN to_jsonb(nai_mascarar_texto(p_j #>> '{}'))
    WHEN 'object' THEN (SELECT coalesce(jsonb_object_agg(e.k, nai_mascarar(e.v)), '{}'::jsonb)
                          FROM jsonb_each(p_j) AS e(k, v))
    WHEN 'array'  THEN (SELECT coalesce(jsonb_agg(nai_mascarar(a.v) ORDER BY a.i), '[]'::jsonb)
                          FROM jsonb_array_elements(p_j) WITH ORDINALITY AS a(v, i))
    ELSE p_j END;
EXCEPTION WHEN others THEN
  -- Mascarar é proteção, não função de negócio: se falhar, devolve o original
  -- em vez de perder o trace. O risco é dado sensível no painel, não perda.
  RETURN p_j;
END;
$function$;
