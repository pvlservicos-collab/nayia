-- teste da 459 (dentro do ensaio, antes do ROLLBACK): dois leads da mesma pessoa viram uma conversa
SELECT cnm_lead_receber('{"id":"T1","name":"Maria","phone":"92999990000","message":"Tenho interesse","createdAt":"2026-10-21 10:00:00","proposeTypeName":"Contato Site","ad":{"reference":"99","title":"Apto 5 quartos","purpose":"Venda","value":3000000,"url":"https://www.chavesnamao.com.br/imovel/1"}}'::jsonb, '', '', 'chavesnamao-leads-api');
SELECT cnm_lead_receber('{"id":"T2","name":"Maria S.","phone":"5592999990000","message":null,"createdAt":"2026-10-21 11:00:00","proposeTypeName":"Formulário WhatsApp","ad":{"reference":"150","purpose":"Venda","value":2100000}}'::jsonb, '', '', 'chavesnamao-leads-api');
SELECT cnm_lead_receber('{"id":"T3","name":"João","email":"joao@x.com","message":"Aceita financiamento?","ad":{"reference":"abc"}}'::jsonb, '', '', 'chavesnamao-leads-api');
SELECT jsonb_pretty(crm_cnm_chats());
SELECT jsonb_pretty(crm_cnm_conversa('t99990000'));
SELECT crm_cnm_ler('t99990000') AS lidos;
SELECT (crm_cnm_painel() - 'anuncios') AS painel, jsonb_array_length(crm_cnm_painel()->'anuncios') AS anuncios;
