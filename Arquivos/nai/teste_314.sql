-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;
\set seg 'SegredoDeTesteSegredoDeTesteSegredoDeTeste0123456789'
\set outro 'OutroSegredoOutroSegredoOutroSegredoOutro9876543210'

-- 1. a conta nasce com o segredo dado; pedir de novo com outro segredo NÃO troca
INSERT INTO _t (caso, esperado, veio) SELECT 'conta nova guarda o segredo', 'true', (crm_olx_conta_preparar('proprietarios', :'seg') = :'seg')::text;
INSERT INTO _t (caso, esperado, veio) SELECT 'segundo pedido não troca o segredo', 'true', (crm_olx_conta_preparar('proprietarios', :'outro') = :'seg')::text;
INSERT INTO _t (caso, esperado, veio) SELECT 'conta que não existe é recusada', 'true', (crm_olx_conta_preparar('outra', :'seg') IS NULL)::text;
INSERT INTO _t (caso, esperado, veio)
SELECT 'estado antes de conectar: desligada, sem token nem segredo na resposta', 'false/false/false',
       (e ->> 'conectada') || '/' || (e ? 'access_token')::text || '/' || (e ? 'segredo')::text FROM crm_olx_conta_estado('proprietarios') e;

-- 2. segredo errado: nada entra
INSERT INTO _t (caso, esperado, veio)
SELECT 'webhook com segredo errado', 'false/nao_autorizado/0',
       (r ->> 'ok') || '/' || (r ->> 'codigo_erro') || '/' || (SELECT count(*) FROM privado.olx_chat)
  FROM crm_olx_chat_receber('proprietarios', :'outro', '{"chatId": "c1", "messageId": "m1", "message": "oi"}', '1.2.3.4') r;

-- 3. a mensagem do comprador, no formato da OLX
INSERT INTO _t (caso, esperado, veio)
SELECT 'mensagem do comprador entra', 'true/true/comprador', (r ->> 'ok') || '/' || (r ->> 'novo') || '/' || (r ->> 'de')
  FROM crm_olx_chat_receber('proprietarios', :'seg', '{"chatId": "c1", "message": "Oi, ainda está disponível?", "senderType": "buyer",
       "email": "maria@exemplo.com", "name": "Maria Teste", "phone": "92999990000", "messageTimestamp": "2026-10-08T15:01:02.345",
       "messageId": "m1", "origin": "buyer", "listId": "1540696600"}', '54.162.151.93') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'a mesma mensagem de novo não duplica', 'true/false/1', (r ->> 'ok') || '/' || (r ->> 'novo') || '/' || (SELECT count(*) FROM privado.olx_chat_mensagem)
  FROM crm_olx_chat_receber('proprietarios', :'seg', '{"chatId": "c1", "message": "Oi, ainda está disponível?", "senderType": "buyer",
       "messageId": "m1", "origin": "buyer", "listId": "1540696600"}', '54.162.151.93') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'segunda mensagem do comprador', 'true/true', (r ->> 'ok') || '/' || (r ->> 'novo')
  FROM crm_olx_chat_receber('proprietarios', :'seg', '{"chatId": "c1", "message": "Posso visitar amanhã?", "senderType": "buyer",
       "name": "Maria Teste", "messageId": "m2", "origin": "buyer", "listId": "1540696600"}', '54.162.151.93') r;

-- 4. a mensagem da NOSSA conta que a OLX devolve (origin seller): é nossa e não troca o nome do comprador
INSERT INTO _t (caso, esperado, veio)
SELECT 'mensagem com origin seller é nossa', 'true/nos', (r ->> 'ok') || '/' || (r ->> 'de')
  FROM crm_olx_chat_receber('proprietarios', :'seg', '{"chatId": "c1", "message": "Está sim!", "senderType": "account",
       "name": "Imob Easy", "email": "conta@imobeasy.com", "messageId": "m3", "origin": "seller", "listId": "1540696600"}', '54.162.151.93') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'a conversa: comprador, anúncio, não lidas e a última', 'Maria Teste/maria@exemplo.com/92999990000/1540696600/2/nos/Está sim!/3',
       c.nome || '/' || c.email || '/' || c.telefone || '/' || c.list_id || '/' || c.nao_lidas || '/' || c.ultima_de || '/' || c.ultima_texto || '/' || c.mensagens
  FROM crm_olx_chats('proprietarios') c;
INSERT INTO _t (caso, esperado, veio) SELECT 'a outra conta não vê esta conversa', '0', count(*)::text FROM crm_olx_chats('corretores');

-- 5. as mensagens, na ordem; pela conta errada não sai nada
INSERT INTO _t (caso, esperado, veio)
SELECT 'mensagens na ordem', 'comprador,comprador,nos', string_agg(m.de, ',' ORDER BY m.id)
  FROM crm_olx_chat_mensagens('proprietarios', (SELECT id FROM privado.olx_chat WHERE chat_id = 'c1')) m;
INSERT INTO _t (caso, esperado, veio)
SELECT 'mensagens pela conta errada', '0', count(*)::text
  FROM crm_olx_chat_mensagens('corretores', (SELECT id FROM privado.olx_chat WHERE chat_id = 'c1'));

-- 6. abrir a conversa zera as não lidas
-- (a ação num comando e a leitura no seguinte: no mesmo comando a leitura ainda enxerga o estado de antes)
SELECT crm_olx_chat_lido('proprietarios', h.id) AS leu FROM privado.olx_chat h WHERE h.chat_id = 'c1' \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'abrir zera as não lidas', 't/0', :'leu' || '/' || h.nao_lidas FROM privado.olx_chat h WHERE h.chat_id = 'c1';

-- 7. a resposta que NÓS mandamos; o eco dela pela OLX não duplica
INSERT INTO _t (caso, esperado, veio)
SELECT 'a nossa resposta é gravada com quem mandou', 'true/c1', crm_olx_chat_enviada('proprietarios', h.id, 'crm-abc', 'Pode sim, às 10h.', 'Rayssa') || '/' || crm_olx_chat_id_da_olx('proprietarios', h.id)
  FROM privado.olx_chat h WHERE h.chat_id = 'c1';
INSERT INTO _t (caso, esperado, veio)
SELECT 'o eco da nossa resposta não duplica', 'true/false/4/Rayssa',
       (r ->> 'ok') || '/' || (r ->> 'novo') || '/' || (SELECT count(*) FROM privado.olx_chat_mensagem) || '/' || (SELECT enviada_por FROM privado.olx_chat_mensagem WHERE message_id = 'crm-abc')
  FROM crm_olx_chat_receber('proprietarios', :'seg', '{"chatId": "c1", "message": "Pode sim, às 10h.", "senderType": "account",
       "messageId": "crm-abc", "origin": "seller"}', '54.162.151.93') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'responder em conversa de outra conta é recusado', 'false', crm_olx_chat_enviada('corretores', h.id, 'crm-x', 'x', 'x')::text
  FROM privado.olx_chat h WHERE h.chat_id = 'c1';

-- 8. conectar a conta e ligar o webhook
SELECT crm_olx_conta_conectar('proprietarios', 'token-de-teste', 'Pedro', 'Conta de Teste', 'conta@exemplo.com') AS conectou \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'conectar guarda o token e quem é', 't/true/Conta de Teste/token-de-teste',
       :'conectou' || '/' || (e ->> 'conectada') || '/' || (e ->> 'olx_nome') || '/' || crm_olx_conta_token('proprietarios')
  FROM crm_olx_conta_estado('proprietarios') e;
SELECT crm_olx_conta_webhook('proprietarios', true, 'HTTP 201') AS ligou \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'webhook ligado aparece no estado', 't/true/1', :'ligou' || '/' || (e ->> 'webhook_ativo') || '/' || (e ->> 'conversas')
  FROM crm_olx_conta_estado('proprietarios') e;

-- 9. o papel do CRM executa e não entra no schema
SET LOCAL ROLE nay_disparo;
SELECT count(*) AS pelo_papel_do_crm FROM crm_olx_chats('proprietarios') \gset
RESET ROLE;
INSERT INTO _t (caso, esperado, veio) VALUES ('nay_disparo lê as conversas pela função', '1', :'pelo_papel_do_crm');
INSERT INTO _t (caso, esperado, veio) SELECT 'nay_disparo não entra no schema privado', 'false', has_schema_privilege('nay_disparo', 'privado', 'USAGE')::text;

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_314: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
