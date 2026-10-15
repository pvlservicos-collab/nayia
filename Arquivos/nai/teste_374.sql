-- testes da 374 (dentro do ensaio, que termina em ROLLBACK)
-- a Rebecca responde (simulado): ainda calada pela resposta de gente das 08:06
UPDATE privado.olx_chat SET ultima_de = 'comprador', ultima_em = now() - interval '1 minute' WHERE id = 7;
SELECT count(*) = 0 AS calada_antes_de_devolver FROM olx_nay_fila(50) WHERE chat = 7;
SELECT olx_nay_devolver(7);
SELECT count(*) = 1 AS na_fila_depois_de_devolver FROM olx_nay_fila(50) WHERE chat = 7;
-- gente responde DEPOIS da devolução: cala de novo
INSERT INTO privado.olx_chat_mensagem (chat, message_id, de, texto, quando) VALUES (7, 'teste-374', 'nos', 'oi', now() + interval '1 second');
SELECT count(*) = 0 AS calada_por_gente_depois FROM olx_nay_fila(50) WHERE chat = 7;
