CREATE OR REPLACE FUNCTION public.captacao_honorarios_valor(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.codigo, nullif(btrim(coalesce(c.valor_venda_pedido, '')), '') AS pedido
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), num AS (
    -- o número que ele escreveu: "R$ 350 mil" -> 350000; "570.000" -> 570000; "1.350.000,00" -> 1350000; "2,5" -> 2500000 (milhões)
    SELECT l.pedido,
           (regexp_match(l.pedido, '(\d[\d\.]*(?:,\d+)?)'))[1] AS bruto,
           l.pedido ~* '\mmil\M' AS em_mil,
           l.pedido ~* 'milh' AS em_milhao
      FROM l
  ), v AS (
    SELECT CASE
             WHEN num.bruto IS NULL THEN NULL
             WHEN num.em_milhao THEN replace(replace(num.bruto, '.', ''), ',', '.')::numeric * 1000000
             WHEN num.em_mil THEN replace(replace(num.bruto, '.', ''), ',', '.')::numeric * 1000
             -- "2,5" sem unidade: só pode ser milhão; "350" sem unidade: mil
             WHEN num.bruto ~ '^\d{1,2}(,\d+)?$' THEN replace(num.bruto, ',', '.')::numeric * 1000000
             WHEN num.bruto ~ '^\d{3}$' THEN num.bruto::numeric * 1000
             ELSE replace(split_part(num.bruto, ',', 1), '.', '')::numeric
           END AS pedido_num
      FROM num
  )
  SELECT 'R$ ' || replace(to_char(x.valor, 'FM999,999,999'), ',', '.')
    FROM (
      SELECT coalesce((SELECT v.pedido_num FROM v WHERE v.pedido_num >= 10000),
                      (SELECT i.valor_venda FROM l JOIN imoveis i ON i.codigo::text = l.codigo
                        WHERE coalesce(i.valor_venda, 0) > 0 LIMIT 1)) AS valor
    ) x
   WHERE x.valor IS NOT NULL;
$function$;
