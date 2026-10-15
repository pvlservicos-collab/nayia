-- testes da 369 (dentro da transação do ensaio)
\echo '== um lead chega (segredo certo e errado) =='
SELECT crm_olx_lead_receber('proprietarios', 'errado-errado-errado-errado-errado', '{"source":"whatsapp"}', NULL) AS segredo_errado;
SELECT crm_olx_lead_receber('proprietarios', (SELECT segredo FROM privado.olx_conta WHERE conta = 'proprietarios'),
       '{"source":"whatsapp","listId":"1544146133","linkAd":"https://www.olx.com.br/vi/1544146133","name":"Teste","email":"t@x.com","phone":"92999990000","message":"oi","createdAt":"2026-10-14T20:00:00.000Z","externalId":"ext-1"}', NULL) AS lead1,
       crm_olx_lead_receber('proprietarios', (SELECT segredo FROM privado.olx_conta WHERE conta = 'proprietarios'),
       '{"source":"whatsapp","listId":"1544146133","externalId":"ext-1"}', NULL) AS repetido;
\echo '== as métricas, pelo papel do CRM =='
SET ROLE nay_disparo;
SELECT jsonb_array_length(m->'linhas') AS anuncios, m->'linhas'->0 AS primeira FROM crm_olx_metricas() m;
RESET ROLE;
