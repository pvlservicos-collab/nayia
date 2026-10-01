CREATE OR REPLACE FUNCTION public.nai_bairro_normal_refazer()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  WITH b AS (
    SELECT btrim(i.bairro) AS bairro, nay_normalizar_lugar(i.bairro, true) AS normal, count(*) AS imoveis
      FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL GROUP BY 1, 2
  ), ins AS (
    INSERT INTO bairro_normal (bairro, normal, dois, imoveis)
    SELECT b.bairro, b.normal,
           CASE WHEN array_length(string_to_array(b.normal, ' '), 1) >= 3
                THEN array_to_string((string_to_array(b.normal, ' '))[1:2], ' ') END,
           b.imoveis
      FROM b
    ON CONFLICT (bairro) DO UPDATE SET normal = EXCLUDED.normal, dois = EXCLUDED.dois, imoveis = EXCLUDED.imoveis
    RETURNING 1
  )
  SELECT count(*) INTO n FROM ins;
  DELETE FROM bairro_normal x WHERE NOT EXISTS (SELECT 1 FROM imoveis i WHERE btrim(i.bairro) = x.bairro);
  RETURN n;
END;
$function$;
