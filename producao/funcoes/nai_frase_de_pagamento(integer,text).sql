CREATE OR REPLACE FUNCTION public.nai_frase_de_pagamento(p_codigo integer, p_afirmacao text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- A frase CERTA, quando a dela contradiz a ficha.
  SELECT 'O ' || coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''), coalesce(i.tipo, 'imóvel'))
         || ' (' || i.codigo || ') '
         || CASE WHEN p_afirmacao IN ('so_a_vista', 'financia') THEN
                   CASE WHEN nai_ficha_valor(i.codigo, 'aceita financiamento') ~* '^s' THEN 'aceita financiamento.'
                        ELSE 'não aceita financiamento: é só à vista.' END
                 ELSE
                   CASE WHEN nai_ficha_valor(i.codigo, 'aceita permuta') ~* '^s' THEN 'aceita permuta.'
                        ELSE 'não aceita permuta.' END END
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$;
