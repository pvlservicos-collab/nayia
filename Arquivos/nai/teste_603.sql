-- 603: quantos ficam na lista, e nenhum abaixo do valor ou fora de condomínio
SELECT jsonb_array_length(crm_olx_captar()->'itens') AS na_lista, crm_olx_captar()->'fora' AS fora;
SELECT count(*) AS furou FROM jsonb_array_elements(crm_olx_captar()->'itens') i
 WHERE (i->>'tipo_negocio' ILIKE 'Aluguel%' AND (i->>'preco')::numeric < 2500) OR (i->>'tipo_negocio' ILIKE 'Venda%' AND (i->>'preco')::numeric < 200000)
    OR NOT (i->>'categoria' = 'Apartamentos' OR i->>'tipo_negocio' ILIKE '%condomin%');
