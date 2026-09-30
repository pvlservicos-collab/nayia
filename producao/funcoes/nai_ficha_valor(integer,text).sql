CREATE OR REPLACE FUNCTION public.nai_ficha_valor(p_codigo integer, p_chave text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- A chave é o rótulo do anúncio normalizado (minúscula, sem acento, sem
  -- "?"): 'aceita financiamento', 'aceita permuta', 'incluso no aluguel',
  -- 'garantia de aluguel', 'taxa de condominio', 'iptu', 'lances de escada'.
  -- É a mesma forma das chaves de `imoveis.extras` (site antigo). O anúncio de
  -- hoje manda; o `extras` só completa.
  SELECT coalesce(
    nullif(btrim((SELECT f.campos->>p_chave FROM imovel_ficha f
                   WHERE f.codigo = p_codigo AND f.encontrado AND f.lido_em IS NOT NULL)), ''),
    nullif(btrim((SELECT i.extras->>p_chave FROM imoveis i WHERE i.codigo = p_codigo)), ''));
$function$;
