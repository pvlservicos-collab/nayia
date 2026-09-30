CREATE OR REPLACE FUNCTION public.nai_lugar_rotulo(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (SELECT * FROM nai_lugar_citado(p_texto)),
  n AS (SELECT count(*) AS q FROM l)
  SELECT CASE
    WHEN n.q = 0 THEN NULL
    WHEN n.q = 1 AND (SELECT tipo FROM l) = 'conjunto' THEN
      (SELECT bairros[1] || ' (bairro ' || CASE WHEN lower(unaccent(nome)) ~ '^(vila|morada)' THEN 'da ' ELSE 'do ' END
              || nome || ')' FROM l)
    -- 229: a zona diz os bairros dela
    WHEN n.q = 1 AND (SELECT tipo FROM l) = 'zona' THEN (SELECT nome || ' (' || nai_lista_pt(bairros) || ')' FROM l)
    WHEN n.q = 1 THEN (SELECT 'entorno da ' || nome || ' (' || nai_lista_pt(bairros) || ')' FROM l)
    ELSE nai_lista_pt(nai_bairros_do_lugar(p_texto)) || ' (' || (SELECT nai_lista_pt(array_agg(nome ORDER BY nome)) FROM l) || ')'
  END FROM n;
$function$;
