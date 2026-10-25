-- teste da 494 (dentro da transação do ensaio, antes do ROLLBACK)
SELECT 'sem' AS mob, count(*) AS achados, count(*) FILTER (WHERE m.mobilia = 'mobiliado') AS mobiliados
  FROM olx_cliente_buscar('{"finalidade": "locacao", "mobilia": "sem"}'::jsonb, '{}', 10) b
  JOIN core_imovel_busca m ON m.codigo = b.codigo;
SELECT 'tanto_faz' AS mob, count(*) AS achados, count(*) FILTER (WHERE m.mobilia = 'mobiliado') AS mobiliados
  FROM olx_cliente_buscar('{"finalidade": "locacao", "mobilia": "tanto_faz"}'::jsonb, '{}', 10) b
  JOIN core_imovel_busca m ON m.codigo = b.codigo;
SELECT 'mobiliado' AS mob, count(*) AS achados, count(*) FILTER (WHERE m.mobilia <> 'mobiliado') AS outros
  FROM olx_cliente_buscar('{"finalidade": "locacao", "mobilia": "mobiliado"}'::jsonb, '{}', 10) b
  JOIN core_imovel_busca m ON m.codigo = b.codigo;
