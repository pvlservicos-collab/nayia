CREATE OR REPLACE FUNCTION public.nay_bairros_proximos(p_bairro text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  WITH alvo AS (
    SELECT z.bairro, z.zona
      FROM bairro_zona z
     WHERE nay_normalizar_lugar(z.bairro, true)
         = nay_normalizar_lugar(coalesce(p_bairro,''), true)
     LIMIT 1
  )
  SELECT array_agg(DISTINCT b ORDER BY b) FROM (
    SELECT bairro AS b FROM alvo
    UNION SELECT v.vizinho FROM bairro_vizinho v JOIN alvo a ON v.bairro = a.bairro
    UNION SELECT v.bairro  FROM bairro_vizinho v JOIN alvo a ON v.vizinho = a.bairro
    UNION SELECT z.bairro  FROM bairro_zona z JOIN alvo a ON z.zona = a.zona
  ) s;
$function$;
