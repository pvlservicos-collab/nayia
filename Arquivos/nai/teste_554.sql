-- teste da 554 (dentro do ensaio; tudo some no ROLLBACK). A senha de mentira só vale aqui dentro.
\set ON_ERROR_STOP 1
INSERT INTO privado.cnm_config (chave, valor) VALUES ('lead_email', 'teste@exemplo.com'), ('lead_token', 'abc123')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

-- senha errada: negado
SELECT 'errada' AS caso, cnm_lead_receber('{"id":"T1","name":"Fulana","phone":"92900000001"}', 'teste@exemplo.com', 'xxx', 'chavesnamao-leads-api');
-- o token do painel inteiro (base64 de email:token) também vale
SELECT 'painel' AS caso, cnm_lead_receber('{"id":"T0","name":"Beltrana Souza","phone":"(92) 90000-0009","message":"Tenho interesse","ad":{"reference":"999999"}}',
       'teste@exemplo.com', translate(encode(convert_to('teste@exemplo.com:abc123', 'UTF8'), 'base64'), E'\n', ''), 'x');
-- certo: entra no CRM e vira cliente da Nay (com o código e a finalidade pelo portal)
SELECT 'novo' AS caso, cnm_lead_receber('{"id":"T2","name":"Maria Teste","phone":"5592900000002","message":"Quero visitar","proposeTypeName":"Alugar","ad":{"reference":"9045","title":"Apto","value":"2500"}}',
       'teste@exemplo.com', 'abc123', 'chavesnamao-leads-api');
-- repetido: não duplica nem chama de novo
SELECT 'repetido' AS caso, cnm_lead_receber('{"id":"T2","name":"Maria Teste","phone":"5592900000002"}', 'teste@exemplo.com', 'abc123', 'chavesnamao-leads-api');
SELECT telefone, origem, etapa, codigo, negocio, nome, perfil FROM privado.olx_lead_whatsapp
 WHERE right(telefone, 8) IN ('00000002', '00000009') ORDER BY id;

-- quem já é cliente (orgânico) e chega por outro imóvel: o mesmo lead, reaberto com o código novo
INSERT INTO privado.olx_lead_whatsapp (telefone, origem, etapa, assumido_em, perfil)
VALUES ('92900000003', 'organico', 'filtrar', now(), '{}');
SELECT 'organico' AS caso, cnm_lead_receber('{"id":"T3","name":"Joana","phone":"92900000003","ad":{"reference":"9045","value":"650000"}}',
       'teste@exemplo.com', 'abc123', 'x');
SELECT telefone, origem, etapa, assumido_em IS NULL AS reaberto, codigo, negocio FROM privado.olx_lead_whatsapp
 WHERE right(telefone, 8) = '00000003';

-- a chave desligada: o lead fica só no CRM
UPDATE privado.cnm_config SET valor = 'nao' WHERE chave = 'nay_atende';
SELECT 'desligada' AS caso, cnm_lead_receber('{"id":"T4","phone":"92900000004"}', 'teste@exemplo.com', 'abc123', 'x');
SELECT count(*) AS deve_ser_0 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '00000004';

-- o papel do site (quem chama a rota) consegue receber
UPDATE privado.cnm_config SET valor = 'sim' WHERE chave = 'nay_atende';
SET ROLE nay_site_escrita;
SELECT 'papel do site' AS caso, cnm_lead_receber('{"id":"T5","phone":"92900000005"}', 'teste@exemplo.com', 'abc123', 'x');
RESET ROLE;
SELECT count(*) AS deve_ser_1 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '00000005';
