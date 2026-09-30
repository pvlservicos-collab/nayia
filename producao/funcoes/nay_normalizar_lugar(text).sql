CREATE OR REPLACE FUNCTION public.nay_normalizar_lugar(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t text;
  a record;
BEGIN
  t := btrim(regexp_replace(
         regexp_replace(
           regexp_replace(
             regexp_replace(lower(unaccent(coalesce(p_texto,''))),
                            '[^a-z0-9]+', ' ', 'g'),
             '\m(pq|pque)\M', 'parque', 'g'),
           '\m(dez)\M', '10', 'g'),
         '\s+', ' ', 'g'));

  -- AREA -> BAIRRO (Tel, 18/09). "vieiralves" vira "nossa senhora das gracas",
  -- e dai em diante tudo o que compara bairro enxerga os dois como um so.
  -- A tabela e pequena; o IF evita ler ela quando o texto nao cita area nenhuma.
  IF t <> '' THEN
    FOR a IN
      SELECT btrim(regexp_replace(lower(unaccent(area)),   '[^a-z0-9]+', ' ', 'g')) AS de,
             btrim(regexp_replace(lower(unaccent(bairro)), '[^a-z0-9]+', ' ', 'g')) AS para
        FROM bairro_area
    LOOP
      IF position(a.de IN t) > 0 THEN
        t := regexp_replace(t, '\m' || a.de || '\M', a.para, 'g');
      END IF;
    END LOOP;
  END IF;

  RETURN t;
END;
$function$;
