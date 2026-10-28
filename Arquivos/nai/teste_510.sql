-- teste da 510: grava uma busca de mentira para a lead 41 e lê pelo card do CRM
INSERT INTO privado.lead_busca (lead_id, telefone, titulo, disse, situacao, ja_enviados)
VALUES (41, '9293006380', 'VENDA · Apartamento · 3 quartos · até R$ 1.000.000 · Adrianópolis', 'teste', 'com_opcoes', '{3841}');
INSERT INTO privado.lead_busca_imovel (busca_id, posicao, codigo, nota, detalhe)
SELECT currval('privado.lead_busca_id_seq'), 1, 3841, 94, '[{"criterio": "preco", "texto": "x"}]';
SELECT jsonb_array_length(crm_lead_buscas('5592993006380')) AS buscas,
       crm_lead_buscas('92993006380')->0->'imoveis'->0->>'codigo' AS codigo,
       crm_lead_buscas('92993006380')->0->'imoveis'->0->>'enviado' AS enviado,
       jsonb_array_length(crm_lead_buscas('')) AS vazio;
SET ROLE nay_disparo;
SELECT jsonb_array_length(crm_lead_buscas('92993006380')) AS pelo_crm;
RESET ROLE;
