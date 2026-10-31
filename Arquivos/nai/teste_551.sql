-- 551: as tabelas da porta existem, a mesma mensagem não entra duas vezes e a sombra compara com o que o n8n gravou
INSERT INTO core_porta_evento (linha, corpo, message_id, modo) VALUES ('captacao', '{"type":"ReceivedCallback"}', 'TESTE551', 'sombra');
INSERT INTO core_porta_evento (linha, corpo, message_id, modo) VALUES ('captacao', '{"type":"ReceivedCallback"}', 'TESTE551', 'sombra')
  ON CONFLICT (linha, message_id) WHERE message_id IS NOT NULL DO NOTHING;
INSERT INTO core_porta_evento (linha, corpo, message_id, modo) VALUES ('status', '{"type":"MessageStatusCallback"}', NULL, 'sombra');
INSERT INTO core_porta_evento (linha, corpo, message_id, modo) VALUES ('status', '{"type":"MessageStatusCallback"}', NULL, 'sombra');
SELECT 'eventos (esperado 3)' AS caso, count(*) FROM core_porta_evento WHERE message_id = 'TESTE551' OR corpo->>'type' = 'MessageStatusCallback';
INSERT INTO core_porta_sombra (linha, evento_id, message_id, telefone, direcao, origem, texto, acao)
SELECT 'captacao', id, message_id, '5592999990001', 'recebida', 'texto', 'oi', 'gravaria_fila' FROM core_porta_evento WHERE message_id = 'TESTE551';
SELECT 'sombra (esperado 1)' AS caso, count(*) FROM core_porta_sombra WHERE message_id = 'TESTE551';
SELECT 'pendentes pelo índice' AS caso, count(*) FROM core_porta_evento WHERE processado_em IS NULL;
