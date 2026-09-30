CREATE OR REPLACE FUNCTION public.nai_card_do_imovel(p_codigo integer)
 RETURNS TABLE(texto_pronto text, qtd_fotos integer)
 LANGUAGE sql
 STABLE
AS $function$
  -- 191: O CARD DOS GRUPOS (Pedro, 29/09: "o card precisa ser ajustado"). O card
  -- dos grupos e montado pelo publicador lendo o anuncio -- traz lances de
  -- escada, caracteristicas, "aceita financiamento" e a OBS do Tel. O da Nay era
  -- remontado do banco, que nao tem nada disso. Agora a Nay manda o MESMO card,
  -- lido na ficha (ficha_do_anuncio.py), enquanto ele for recente e o preco
  -- bater com o banco. Senao, o card do banco, como sempre.
  SELECT coalesce(
           (SELECT f.card FROM imovel_ficha f JOIN imoveis i ON i.codigo = f.codigo
             WHERE f.codigo = p_codigo AND f.encontrado AND f.erro IS NULL AND f.card IS NOT NULL
               AND f.lido_em > now() - interval '26 hours'
               AND NOT coalesce(i.e_parceiro, false)
               AND coalesce(f.valor_venda, 0) = coalesce(i.valor_venda, 0)
               AND coalesce(f.valor_aluguel, 0) = coalesce(i.valor_aluguel, 0)
               AND f.card ~ ('C[óo]digo:\s*' || p_codigo || '\s*$')),
           b.texto_pronto),
         b.qtd_fotos
    FROM nai_card_do_banco(p_codigo) b;
$function$
;
