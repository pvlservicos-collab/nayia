CREATE OR REPLACE FUNCTION public.nay_negocio_pedido(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t text := lower(unaccent(coalesce(p_texto,'')));
  -- 225: palavras parecidas (financia -> venda; inquilino, alugue -> locação)
  v boolean := t ~ '\m(venda|vendas|vender|vende|vendo|vendido|vendida|comprar|compra|compro|comprador\w*|a venda|financi\w*|adquirir|investimento|investir)\M';
  l boolean := t ~ '\m(locacao|locacoes|aluguel|alugueis|alug\w*|locar|locado|locada|locatari\w*|inquilin\w*|para morar de aluguel)\M';
  v_valor numeric;
BEGIN
  IF v AND l THEN RETURN 'ambos'; END IF;
  IF v THEN RETURN 'venda'; END IF;
  IF l THEN RETURN 'locacao'; END IF;

  -- ACIMA DE 100 MIL E VENDA (Tel, 22/09). Aluguel em Manaus nao chega perto
  -- disso; quem fala de 700 mil esta falando de compra, mesmo sem dizer a
  -- palavra. O piso fica em `nai_config` para ele mexer sem deploy.
  v_valor := nay_maior_valor(t);
  IF v_valor IS NOT NULL AND v_valor >= nai_cfg_int('piso_venda', 100000) THEN
    RETURN 'venda';
  END IF;
  RETURN NULL;
END;
$function$;
