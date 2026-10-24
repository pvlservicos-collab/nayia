-- dentro do ensaio (ROLLBACK): só o tipo veio / só o bairro veio
SELECT telefone AS t1 FROM captacao_leads WHERE quem_importou LIKE 'Pedro (lista 4%' AND status='novo' ORDER BY id LIMIT 1 \gset
SELECT captacao_ficha(:'t1', 'outro', '{"negocio":"venda","tipo":"casa"}'::jsonb, false) AS so_tipo_veio;
SELECT telefone AS t2 FROM captacao_leads WHERE quem_importou LIKE 'Pedro (lista 4%' AND status='novo' AND telefone <> :'t1' ORDER BY id LIMIT 1 \gset
SELECT captacao_ficha(:'t2', 'outro', '{"negocio":"venda","bairro":"Aleixo"}'::jsonb, false) AS so_bairro_veio;
