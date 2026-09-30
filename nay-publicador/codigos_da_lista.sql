-- QUAIS IMÓVEIS ENTRAM NUMA LISTA -- a regra, extraída para uma função
--
-- POR QUE (Tel, 27/09): "coloca para atualizar sempre a lista quando atualizar
-- os valores do site também". Para reler no site o valor dos imóveis de uma
-- lista, o publicador precisa saber QUAIS são -- e `nay_lista_de_imoveis`
-- devolve só o texto pronto.
--
-- A REGRA NÃO PODE SER COPIADA. Ela tem seis condições (no mercado, não é
-- parceiro, a categoria, ter valor no negócio pedido, o piso do grupo, o
-- condomínio de verdade), e uma segunda cópia divergiria na primeira edição
-- -- é o padrão 4.3 do HISTORICO, o mais caro deste projeto. Então ela sai de
-- dentro do `nay_lista_de_imoveis` e as duas passam a ler daqui, igual ao que
-- já se fez com `nay_condominios_candidatos` em 11/09.
--
-- A rede que segura isto é o teste que compara as duas: o que
-- `nay_codigos_da_lista` devolve tem que ser exatamente o que aparece no
-- texto de `nay_lista_de_imoveis`, em toda categoria e nos dois negócios.

-- Os DEFAULTS são os mesmos do `nay_lista_de_imoveis` -- inclusive
-- `p_negocio DEFAULT 'locacao'`. Assinaturas que diferem em default fazem o
-- Postgres recusar o CREATE OR REPLACE ("cannot remove parameter defaults"),
-- e o CLAUDE.md já registra o parente disto: assinatura diferente não
-- substitui, cria uma SOBRECARGA, e a antiga continua chamável.
CREATE OR REPLACE FUNCTION nay_codigos_da_lista(
    p_categoria     text,
    p_negocio       text    DEFAULT 'locacao',
    p_valor_minimo  numeric DEFAULT NULL,
    p_so_condominio boolean DEFAULT false)
RETURNS TABLE(codigo text)
LANGUAGE sql STABLE AS $$
  SELECT i.codigo::text
    FROM imoveis i
   WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND nay_categoria_do_imovel(i.tipo, i.condominio_nome) = p_categoria
     AND (CASE WHEN (lower(coalesce(p_negocio,'')) LIKE 'vend%'
                  OR lower(coalesce(p_negocio,'')) LIKE 'compr%')
               THEN coalesce(i.valor_venda,0)
               ELSE coalesce(i.valor_aluguel,0) END) > 0
     AND (p_valor_minimo IS NULL
          OR (CASE WHEN (lower(coalesce(p_negocio,'')) LIKE 'vend%'
                      OR lower(coalesce(p_negocio,'')) LIKE 'compr%')
                   THEN coalesce(i.valor_venda,0)
                   ELSE coalesce(i.valor_aluguel,0) END) >= p_valor_minimo)
     AND (NOT p_so_condominio
          OR nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL)
$$;

-- E `nay_lista_de_imoveis` passa a CHAMAR a função, em vez de repetir o WHERE.
CREATE OR REPLACE FUNCTION nay_lista_de_imoveis(
    p_categoria     text,
    p_negocio       text    DEFAULT 'locacao',
    p_valor_minimo  numeric DEFAULT NULL,
    p_so_condominio boolean DEFAULT false)
RETURNS TABLE(texto_pronto text, quantos integer)
LANGUAGE plpgsql STABLE AS $$
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
    SELECT c.codigo AS cod,
           nay_custo_cheio(c.codigo, v_neg) AS custo,
           nay_linha_da_lista(c.codigo, p_categoria, v_neg) AS linha
      FROM nay_codigos_da_lista(p_categoria, p_negocio, p_valor_minimo,
                                p_so_condominio) c
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
$$;
