CREATE OR REPLACE FUNCTION public.captacao_valor_venda_num(p_texto text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- "277k" -> 277000; "R$ 350 mil" -> 350000; "1.400.000" -> 1400000; "165.000,00" -> 165000; "2,5" -> 2500000.
  -- Mais de um número no texto ("160 ou 170") não vira valor.
  SELECT CASE
           WHEN (SELECT count(*) FROM regexp_matches(coalesce(p_texto, ''), '\d[\d.,]*', 'g')) <> 1 THEN NULL
           WHEN n.bruto IS NULL THEN NULL
           WHEN p_texto ~* 'milh' THEN replace(replace(n.bruto, '.', ''), ',', '.')::numeric * 1000000
           WHEN p_texto ~* '\mmil\M' OR p_texto ~* '\d\s*k\M' THEN replace(replace(n.bruto, '.', ''), ',', '.')::numeric * 1000
           WHEN n.bruto ~ '^\d{1,2}(,\d+)?$' THEN replace(n.bruto, ',', '.')::numeric * 1000000
           WHEN n.bruto ~ '^\d{3}$' THEN n.bruto::numeric * 1000
           ELSE replace(split_part(n.bruto, ',', 1), '.', '')::numeric
         END
    FROM (SELECT (regexp_match(coalesce(p_texto, ''), '(\d[\d\.]*(?:,\d+)?)'))[1] AS bruto) n;
$function$;
