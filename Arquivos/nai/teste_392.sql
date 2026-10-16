-- 392: a busca comercial, o Diego, a fila com as antigas
SELECT 'galpao locacao' AS caso, count(*) FROM olx_cliente_buscar('{"finalidade": "locacao", "tipo": "galpao", "mobilia": "mobiliado", "quartos": 3}'::jsonb, '{}', 10)
UNION ALL SELECT 'predio venda', count(*) FROM olx_cliente_buscar('{"finalidade": "venda", "tipo": "predio"}'::jsonb, '{}', 10)
UNION ALL SELECT 'comercial locacao', count(*) FROM olx_cliente_buscar('{"finalidade": "locacao", "tipo": "comercial"}'::jsonb, '{}', 10)
UNION ALL SELECT 'sala locacao', count(*) FROM olx_cliente_buscar('{"finalidade": "locacao", "tipo": "sala", "mobilia": "semi"}'::jsonb, '{}', 10)
UNION ALL SELECT 'apto 2q ate 2500 (igual antes)', count(*) FROM olx_cliente_buscar('{"finalidade": "locacao", "tipo": "apartamento", "teto": 2500, "quartos": 2}'::jsonb, '{}', 10);
SELECT b.codigo, i.tipo, b.bairro, b.preco FROM olx_cliente_buscar('{"finalidade": "locacao", "tipo": "galpao"}'::jsonb, '{}', 5) b JOIN imoveis i ON i.codigo = b.codigo;
SELECT telefone, nome, papel FROM equipe WHERE telefone = '5592982092845';
SELECT chave, valor FROM privado.olx_config WHERE chave IN ('visita_locacao', 'seguimento_min');
SELECT estado, linha, origem, count(*) FROM pergunta_fila GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
SELECT status, count(*) FROM pendencias GROUP BY 1;
SELECT position('pendencias' IN pg_get_functiondef('pergunta_fila_responder(bigint,bigint,text,text)'::regprocedure)) > 0 AS remendo;
