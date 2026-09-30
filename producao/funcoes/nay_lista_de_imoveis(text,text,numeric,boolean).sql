CREATE OR REPLACE FUNCTION public.nay_lista_de_imoveis(p_categoria text, p_negocio text DEFAULT 'locacao'::text, p_valor_minimo numeric DEFAULT NULL::numeric, p_so_condominio boolean DEFAULT false)
 RETURNS TABLE(texto_pronto text, quantos integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_neg text := CASE WHEN lower(coalesce(p_negocio,'')) LIKE 'vend%'
                       OR lower(coalesce(p_negocio,'')) LIKE 'compr%'
                     THEN 'venda' ELSE 'locacao' END;
  v_linhas text;
  v_n int;
  v_min numeric;
  v_max numeric;
BEGIN
  WITH achados AS (
    SELECT i.codigo::text AS cod,
           nay_custo_cheio(i.codigo::text, v_neg) AS custo,
           nay_linha_da_lista(i.codigo::text, p_categoria, v_neg) AS linha
      FROM imoveis i
     WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND nay_categoria_do_imovel(i.tipo, i.condominio_nome) = p_categoria
       AND (CASE WHEN v_neg = 'venda' THEN coalesce(i.valor_venda,0)
                 ELSE coalesce(i.valor_aluguel,0) END) > 0
       -- O PISO DO GRUPO (15/09). Compara o valor que a linha mostra, não o
       -- custo cheio do título. Nulo é sem piso: a lista de sempre.
       AND (p_valor_minimo IS NULL
            OR (CASE WHEN v_neg = 'venda' THEN coalesce(i.valor_venda,0)
                     ELSE coalesce(i.valor_aluguel,0) END) >= p_valor_minimo)
       -- Condomínio DE VERDADE: a importação pôs "Casa" e "Loja/Ponto" no campo
       -- do condomínio de imóvel de rua, e nome de rótulo não pode passar.
       AND (NOT p_so_condominio
            OR nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL)
  )
  -- O ✅ COLADO NA FRENTE DE CADA IMÓVEL, sem espaço, é o formato que o Tel
  -- escreveu em 15/09. Ele vai AQUI, na montagem, e não dentro de
  -- `nay_linha_da_lista`: aquela função é a identidade da linha, e o
  -- `nay_imoveis_da_linha` a gera de novo para casar o que ele cola. Emoji
  -- dentro dela seria mais uma coisa para as duas pontas concordarem.
  SELECT count(*), min(custo), max(custo),
         string_agg('✅' || linha, chr(10) ORDER BY custo, linha)
    INTO v_n, v_min, v_max, v_linhas
    FROM achados;

  IF coalesce(v_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('não tenho nenhum imóvel nessa categoria para '
       || CASE WHEN v_neg = 'venda' THEN 'venda' ELSE 'locação' END
       || ' no momento.')::text, 0;
    RETURN;
  END IF;

  -- O TÍTULO ENTRE 🔥, com uma linha em branco antes dos imóveis (Tel, 15/09,
  -- com o exemplo dele). Até 14/09 o ✅ ficava no título e as linhas saíam
  -- cruas; ele inverteu: ✅ marca o imóvel, 🔥 marca o título.
  RETURN QUERY SELECT
    ('🔥 ' || nay_titulo_da_categoria(p_categoria, v_neg)
     || CASE WHEN v_min = v_max THEN ' — ' || nay_valor_curto(v_min)
             ELSE ' DE ' || nay_valor_curto(v_min) || ' A ' || nay_valor_curto(v_max) END
     || ' 🔥' || chr(10) || chr(10) || v_linhas)::text,
    v_n;
END;
$function$;
