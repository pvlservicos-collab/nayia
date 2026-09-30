CREATE OR REPLACE FUNCTION public.nay_valor_escrito(p_token text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t     text := lower(btrim(coalesce(p_token,'')));
  corpo text;
  n     numeric;
BEGIN
  IF t = '' THEN RETURN NULL; END IF;

  -- POR EXTENSO, do jeito que ele escreve o pedido: "600 mil", "3 milhões",
  -- "1.2 mi". AQUI e não no Python: quem lê dinheiro escrito é UMA função só,
  -- senão a linha colada e o pedido descrito dariam números diferentes.
  --
  -- MEDIDO em 15/09, e por isso existe: "até 3 milhões" caía no ramo do
  -- número solto, e como 3 < 1000 virava R$ 3.000 -- o pedido de venda até
  -- três milhões voltava os imóveis de ALUGUEL até três mil, calado.
  IF t ~ '^[0-9]+([.,][0-9]+)?\s*(milh|mi$)' THEN
    corpo := (regexp_match(t, '^([0-9]+(?:[.,][0-9]+)?)'))[1];
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000000);
  END IF;

  IF t ~ '^[0-9]+([.,][0-9]+)?\s*mil$' THEN
    corpo := (regexp_match(t, '^([0-9]+(?:[.,][0-9]+)?)'))[1];
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000);
  END IF;

  -- milhão: "1.2M", "2.1m"
  IF t ~ '^[0-9]+([.,][0-9]+)?\s*m$' THEN
    corpo := regexp_replace(t, '\s*m$', '');
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000000);
  END IF;

  -- milhar explícito: "2.5k", "280k", "5k"
  IF t ~ '^[0-9]+([.,][0-9]+)?\s*k$' THEN
    corpo := regexp_replace(t, '\s*k$', '');
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000);
  END IF;

  IF t !~ '^[0-9]+([.,][0-9]+)?$' THEN RETURN NULL; END IF;

  -- "2.500" / "2,500": separador de milhar. TRÊS casas depois do ponto é a
  -- marca -- "2.50" não é isso, e "2.5" também não.
  IF t ~ '^[0-9]+[.,][0-9]{3}$' THEN
    RETURN trim_scale(regexp_replace(t, '[.,]', '', 'g')::numeric);
  END IF;

  n := replace(t, ',', '.')::numeric;
  -- "2.6" e "2.5" são dois mil e seiscentos / quinhentos. Nenhum imóvel
  -- deste catálogo custa R$ 2,60.
  IF n < 1000 THEN RETURN trim_scale(n * 1000); END IF;
  RETURN trim_scale(n);
END;
$function$;
