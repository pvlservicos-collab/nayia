-- teste da 496 (dentro da transação do ensaio): uma pergunta 'perguntada' de mentira, o Tel ensina, e depois responde
SET statement_timeout = '30s';
UPDATE pergunta_fila SET estado = 'fila' WHERE estado = 'perguntada';
INSERT INTO pergunta_fila (linha, chave, cliente, codigo, pergunta, origem, estado, perguntada_em)
VALUES ('captacao', '5592987123456', 'Teste 496', 2944, 'aceita pet?', 'olx_whatsapp', 'perguntada', now());
SELECT id AS tel FROM nai_contato WHERE chave = nai_chave(nai_cfg('tel_telefone')) LIMIT 1 \gset
SELECT max(id) AS turno FROM nai_turno WHERE contato_id = :tel \gset
SELECT pergunta_fila_responder(:turno, :tel, 'Adicionar inteligência: pet: perguntar o porte do animal antes de falar com o proprietário', NULL) AS ensinou;
SELECT regra, origem, vale_para, aplicada_em FROM nay_inteligencia_geral WHERE criada_por = 'tel (fila de perguntas)';
SELECT estado FROM pergunta_fila WHERE cliente = 'Teste 496';
SELECT pergunta_fila_responder(:turno, :tel, 'Aceita pet de pequeno porte.', NULL) AS respondeu;
SELECT estado, resposta FROM pergunta_fila WHERE cliente = 'Teste 496';
SELECT right(pergunta_fila_texto((SELECT max(id) FROM pergunta_fila), false), 120) AS rodape;
