CREATE OR REPLACE FUNCTION public.nai_negocio_das_falas(p_falas text[])
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- Primeiro a PALAVRA (a fala mais nova que disse locação ou venda); se
  -- nenhuma disse, o VALOR (190). A fala em que ele oferece o imóvel DELE
  -- ("vendo meu apartamento por 450 mil") não diz o que o cliente procura.
  SELECT coalesce(
    (SELECT nay_negocio_pedido(f.fala) FROM unnest(p_falas) WITH ORDINALITY f(fala, pos)
      WHERE nay_negocio_pedido(f.fala) IS NOT NULL AND NOT nai_fala_e_dele(f.fala)
      ORDER BY f.pos LIMIT 1),
    (SELECT nai_negocio_pelo_valor(f.fala) FROM unnest(p_falas) WITH ORDINALITY f(fala, pos)
      WHERE nai_negocio_pelo_valor(f.fala) IS NOT NULL AND NOT nai_fala_e_dele(f.fala)
      ORDER BY f.pos LIMIT 1));
$function$
;
