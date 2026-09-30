CREATE OR REPLACE FUNCTION public.nai_ficha_imovel(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT '🏠 ' || coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''),
                           coalesce(i.tipo, 'Imóvel') || coalesce(' no ' || nullif(btrim(i.bairro), ''), ''))
      || E'\n📍 ' || concat_ws(', ', nullif(btrim(i.logradouro), ''), nullif(btrim(i.numero::text), ''), nullif(btrim(i.bairro), ''))
      || CASE WHEN coalesce(i.valor_aluguel, 0) > 0
              THEN E'\n💰 Aluguel: R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.')
                   || CASE WHEN coalesce(i.extras->>'incluso no aluguel', '') ~* 'condom' THEN ' (incluso a tx)' ELSE '' END
              ELSE '' END
      || CASE WHEN coalesce(i.valor_venda, 0) > 0
              THEN E'\n💰 Venda: R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.') ELSE '' END
      || E'\n#' || i.codigo
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$
;
