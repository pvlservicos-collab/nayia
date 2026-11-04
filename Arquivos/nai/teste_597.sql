-- 597: o "sem" (não quer mobiliado) nunca recebe o mobiliado; os outros pedidos de mobília como antes.
-- Cada caso exclui todos os outros imóveis (p_excluir), para o alvo ser o único que pode voltar.
WITH mob AS (
  SELECT c.codigo, c.bairro, c.valor_aluguel FROM core_imovel_busca c
   WHERE c.ofertavel AND c.de_locacao AND c.mobilia = 'mobiliado' AND c.tipo = 'apartamento' AND c.valor_aluguel > 0
     AND coalesce(c.bairro, '') <> ''
   ORDER BY c.codigo LIMIT 1),
semi AS (
  SELECT c.codigo, c.bairro, c.valor_aluguel FROM core_imovel_busca c
   WHERE c.ofertavel AND c.de_locacao AND c.mobilia = 'semi' AND c.tipo = 'apartamento' AND c.valor_aluguel > 0
     AND coalesce(c.bairro, '') <> ''
   ORDER BY c.codigo LIMIT 1),
casos AS (
  SELECT 'mobiliado, pedido sem dizer a mobília' AS caso, m.codigo, m.bairro, m.valor_aluguel, '' AS pede, true AS espera FROM mob m
  UNION ALL SELECT 'mobiliado, pedido "sem" (o 597)', m.codigo, m.bairro, m.valor_aluguel, 'sem', false FROM mob m
  UNION ALL SELECT 'mobiliado, pedido mobiliado', m.codigo, m.bairro, m.valor_aluguel, 'mobiliado', true FROM mob m
  UNION ALL SELECT 'mobiliado, pedido semi (o semi aceita mobiliado)', m.codigo, m.bairro, m.valor_aluguel, 'semi', true FROM mob m
  UNION ALL SELECT 'semi, pedido "sem" (modulados servem)', s.codigo, s.bairro, s.valor_aluguel, 'sem', true FROM semi s
  UNION ALL SELECT 'semi, pedido mobiliado', s.codigo, s.bairro, s.valor_aluguel, 'mobiliado', false FROM semi s),
r AS MATERIALIZED (
  SELECT k.*, EXISTS (SELECT 1 FROM olx_cliente_buscar(
                 jsonb_build_object('finalidade', 'locacao', 'tipo', 'apartamento', 'teto', k.valor_aluguel,
                                    'bairros', jsonb_build_array(k.bairro), 'mobilia', k.pede),
                 ARRAY(SELECT c.codigo FROM core_imovel_busca c WHERE c.codigo <> k.codigo), 10) x
                WHERE x.codigo = k.codigo) AS voltou
    FROM casos k)
SELECT caso, codigo, pede, voltou, espera, CASE WHEN voltou = espera THEN 'OK' ELSE 'FALHOU' END AS resultado
  FROM r ORDER BY caso;
