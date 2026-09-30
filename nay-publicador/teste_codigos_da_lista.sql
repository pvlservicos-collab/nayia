-- A REDE: o que `nay_codigos_da_lista` devolve tem que ser EXATAMENTE o que
-- aparece no texto de `nay_lista_de_imoveis`. Se as duas divergirem, o
-- publicador releria no site um conjunto de imóveis e mandaria outro -- e o
-- valor que ele acabou de corrigir continuaria velho na mensagem.
--
-- Roda contra o catálogo inteiro, nas seis categorias e nos dois negócios.
BEGIN;

CREATE TEMP TABLE conferencia AS
WITH combos AS (
  SELECT c, n FROM
    (SELECT unnest(ARRAY['apartamento','apartamento_via_publica',
                         'casa_condominio','casa_via_publica','sala','lote']) c) a,
    (SELECT unnest(ARRAY['venda','locacao']) n) b
)
SELECT combos.c AS categoria, combos.n AS negocio,
       (SELECT count(*) FROM nay_codigos_da_lista(combos.c, combos.n)) AS pela_funcao,
       l.quantos AS no_texto
  FROM combos, LATERAL nay_lista_de_imoveis(combos.c, combos.n) l;

SELECT CASE WHEN bool_and(pela_funcao = no_texto)
            THEN 'AS 12 COMBINACOES BATEM (codigos = texto)'
            ELSE 'FALHOU: ' || string_agg(categoria || '/' || negocio
                                          || ' funcao=' || pela_funcao
                                          || ' texto=' || no_texto, '; ')
                   FILTER (WHERE pela_funcao <> no_texto) END
  FROM conferencia;

-- E item por item, não só a contagem: cada código da função tem que ter a
-- SUA linha dentro do texto. Contagem igual com conjuntos diferentes passaria.
CREATE TEMP TABLE item_a_item AS
SELECT c.codigo,
       nay_linha_da_lista(c.codigo, 'casa_condominio', 'venda') AS linha,
       (SELECT texto_pronto FROM nay_lista_de_imoveis('casa_condominio','venda')) AS texto
  FROM nay_codigos_da_lista('casa_condominio','venda') c;

SELECT CASE WHEN bool_and(position(linha in texto) > 0)
            THEN 'TODAS AS LINHAS DE casa_condominio/venda ESTAO NO TEXTO'
            ELSE 'FALHOU: ' || string_agg(codigo, ', ')
                   FILTER (WHERE position(linha in texto) = 0) END
  FROM item_a_item;

-- O PISO e o SO_CONDOMINIO continuam valendo na função nova -- é por eles que
-- o grupo Alto Padrão recebe a lista filtrada.
SELECT CASE WHEN (SELECT count(*) FROM nay_codigos_da_lista('casa_condominio','venda',1000000))
                 <= (SELECT count(*) FROM nay_codigos_da_lista('casa_condominio','venda'))
            THEN 'O PISO FILTRA' ELSE 'FALHOU: o piso nao filtrou' END;

DO $$ DECLARE n int; BEGIN
    SELECT count(*) INTO n FROM conferencia WHERE pela_funcao <> no_texto;
    IF n > 0 THEN RAISE EXCEPTION '% combinacoes divergem', n; END IF;
    SELECT count(*) INTO n FROM item_a_item WHERE position(linha in texto) = 0;
    IF n > 0 THEN RAISE EXCEPTION '% linhas fora do texto', n; END IF;
END $$;

ROLLBACK;
