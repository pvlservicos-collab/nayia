CREATE OR REPLACE FUNCTION public.nai_negocio_pelo_valor(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- Só valor com cara de dinheiro: "de 7mil", "até 3.500", "R$ 700 mil",
  -- "média de 5mil". "3 quartos", "apto 1601" e "bloco 13" não contam.
  SELECT CASE WHEN x.v IS NULL OR x.v < 300 THEN NULL
              WHEN x.v <= 30000 THEN 'locacao'
              WHEN x.v >= 100000 THEN 'venda' END
    FROM (SELECT coalesce(nay_maior_valor(coalesce(p_texto, '')), nay_valor_em_reais(coalesce(p_texto, ''))) AS v) x
   WHERE lower(unaccent(coalesce(p_texto, ''))) ~
         '(r\$|\d\s*(mil|k)\M|\mmil\M|reais|\mate\s+(r\$\s*)?\d|\mvalor|orcamento|\mmedia\s+de|\mfaixa\s+de|\mpaga\s)';
$function$;
