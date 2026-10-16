SELECT 'felipe venda mobiliada' c, count(*) FROM olx_cliente_buscar('{"finalidade":"venda","tipo":"casa_condominio","teto":900000,"bairros":["Flores"],"quartos":3,"mobilia":"mobiliado"}'::jsonb, '{3883}', 10)
UNION ALL SELECT 'qualquer bairro', count(*) FROM olx_cliente_buscar('{"finalidade":"venda","tipo":"casa_condominio","teto":900000,"bairros":["Flores"],"qualquer_bairro":true,"quartos":3}'::jsonb, '{}', 10)
UNION ALL SELECT 'sem escada apto venda 450k', count(*) FROM olx_cliente_buscar('{"finalidade":"venda","tipo":"apartamento","teto":450000,"aceita_escada":false}'::jsonb, '{}', 10)
UNION ALL SELECT 'com escada apto venda 450k', count(*) FROM olx_cliente_buscar('{"finalidade":"venda","tipo":"apartamento","teto":450000}'::jsonb, '{}', 10)
UNION ALL SELECT 'locacao mobiliado (igual)', count(*) FROM olx_cliente_buscar('{"finalidade":"locacao","tipo":"apartamento","teto":3000,"mobilia":"mobiliado"}'::jsonb, '{}', 10);
