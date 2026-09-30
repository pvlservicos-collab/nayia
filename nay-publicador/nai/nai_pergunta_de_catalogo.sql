CREATE OR REPLACE FUNCTION public.nai_pergunta_de_catalogo(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  WITH s AS (SELECT lower(unaccent(coalesce(p_texto,''))) AS t)
  SELECT coalesce(array_length(nai_imoveis_pedidos(p_texto, ''), 1), 0) > 0
      OR nai_pede_os_valores(p_texto)
      OR (SELECT t FROM s) ~ '\m(visita|visitar|visitamos|remarcar|cancelar|agendar)\M'
      -- "Tem smille mundi pra locacao?", "Vai ter a casa para locacao?"
      -- O segundo termo e so de BUSCA (locacao, venda, opcao, disponivel).
      -- Fora dele de proposito: quarto, casa, apartamento -- que e o
      -- vocabulario com que ele RESPONDE o cadastro ("tem 3 quartos").
      OR ((SELECT t FROM s) ~ '\m(tem|tens|teria|vai ter|voce tem|vc tem|possui|envia|enviar|manda|mandar|mostra|procuro|busco)\M'
          AND (SELECT t FROM s) ~ '\m(loca|alug|venda|vender|comprar|opc|disponiv)');
$function$
;
