CREATE OR REPLACE FUNCTION public.nay_captacao_tem_valor(p_campos jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Sem interpretar moeda: "R$ 390.000", "390000" e "3.500,00" passam;
  -- "R$ 0,00", "a combinar" e "" não. Converter "1.500" em número é
  -- exatamente onde a OLX engana, e aqui a pergunta é só "tem preço?".
  SELECT bool_or(regexp_replace(coalesce(p_campos ->> k, ''), '[^0-9]', '', 'g') ~ '[1-9]')
    FROM unnest(ARRAY['valor_venda', 'valor_aluguel']) AS k;
$function$;
