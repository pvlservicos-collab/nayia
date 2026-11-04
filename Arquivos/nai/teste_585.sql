-- teste da 585: um anúncio limpo entra, o de telefone de corretor conhecido sai, o já cadastrado sai, o "fora" conta
INSERT INTO olx_captar (olx_id, url, titulo, preco_texto, bairro, telefone, telefones, nota, sinais)
VALUES (1, 'https://am.olx.com.br/x-1', 'Casa limpa', 'R$ 300.000', 'Flores', '5592911472583', '{5592911472583}', 80, '{teste}'),
       (2, 'https://am.olx.com.br/x-2', 'Casa do corretor', 'R$ 300.000', 'Flores',
        (SELECT nay_fone_com_ddi(telefone) FROM corretores WHERE coalesce(telefone, '') <> '' LIMIT 1),
        ARRAY[(SELECT nay_fone_com_ddi(telefone) FROM corretores WHERE coalesce(telefone, '') <> '' LIMIT 1)], 80, '{}'),
       (3, 'https://am.olx.com.br/x-3', 'Sem telefone', 'R$ 2.000', 'Centro', NULL, '{}', 70, '{}');
INSERT INTO olx_captar (olx_id, url, titulo, fora) VALUES (4, 'https://am.olx.com.br/x-4', 'Pro', 'anúncio profissional');
INSERT INTO olx_captar (olx_id, url, titulo, nota)
SELECT (extras->>'olx_id')::bigint, 'https://am.olx.com.br/x', 'já cadastrado', 90 FROM imoveis
 WHERE extras->>'olx_id' ~ '^\d+$' LIMIT 1 ON CONFLICT DO NOTHING;

SELECT jsonb_path_query_array(crm_olx_captar(), '$.itens[*].olx_id') AS itens_esperado_1_e_3,
       crm_olx_captar()->'fora' AS fora;
SELECT crm_olx_captar_chamado(1, 'whatsapp', 'teste') AS chamou, crm_olx_captar_chamado(1, 'olx', 'outro') AS segunda_nao_troca;
SELECT chamado_como, chamado_por FROM olx_captar WHERE olx_id = 1;
SET ROLE nay_disparo;
SELECT jsonb_array_length(crm_olx_captar()->'itens') AS como_nay_disparo;
RESET ROLE;
