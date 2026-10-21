-- teste da 461 (dentro do ensaio, antes do ROLLBACK): o lead de teste vira dono da casa 2207 (a da Sra. Conceição,
-- de venda) e de um apartamento de aluguel completo; a ficha só pede o que falta no cadastro
SELECT codigo, tipo, quartos, banheiros, vagas, area_util, area_total, iptu, taxa_condominio, mobilia, valor_venda, valor_aluguel,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos
  FROM imoveis i WHERE codigo = 2207;
UPDATE captacao_leads SET codigo = '2207', situacao = 'disponivel', tratamento = 'Sra.'
 WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'));
DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')));
SELECT captacao_ficha((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), 'este', '{}'::jsonb, false) AS ao_abrir;
SELECT captacao_ficha((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), 'este', '{"area": "uns 200 metros"}'::jsonb, true) AS depois_da_area;
-- um imóvel de aluguel com tudo preenchido: nada a perguntar
WITH x AS (SELECT i.codigo FROM imoveis i
            WHERE coalesce(i.valor_aluguel, 0) > 0 AND i.quartos IS NOT NULL AND i.banheiros IS NOT NULL AND i.vagas IS NOT NULL
              AND coalesce(i.area_util, i.area_total) IS NOT NULL AND i.iptu > 0 AND i.mobilia IS NOT NULL
              AND (i.condominio_nome IS NULL OR i.taxa_condominio > 0)
              AND EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo) LIMIT 1)
UPDATE captacao_leads SET codigo = (SELECT codigo::text FROM x)
 WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')) RETURNING codigo AS completo;
DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')));
SELECT captacao_ficha((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), 'este', '{}'::jsonb, false) AS completo_ao_abrir;
