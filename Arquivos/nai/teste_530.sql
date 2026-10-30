SELECT (crm_olx_scrap_busca('{"finalidade":"venda","tipos":["apartamento"],"quartos":[3],"preco_max":700000,"bairros":["Ponta Negra"],"por":3}'))->>'total' AS total_ponta_negra;
SELECT jsonb_array_length(crm_olx_scrap_busca('{"por":6,"pagina":2}')->'itens') AS pag2;
SELECT (crm_olx_scrap_busca('{"finalidade":"locacao","com_telefone":true,"ordem":"menor_preco","por":2}')) -> 'itens' -> 0 ->> 'preco' AS menor_aluguel;
SELECT crm_olx_scrap_opcoes()->>'total' AS total, jsonb_array_length(crm_olx_scrap_opcoes()->'bairros') AS bairros;
SELECT jsonb_array_length(crm_olx_scrap_leads('Alê', '{}')) AS leads_ale;
