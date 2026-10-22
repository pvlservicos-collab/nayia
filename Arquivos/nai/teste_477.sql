-- teste da 477: uma dúvida da OLX entra com o agente, ele responde; outra ele devolve ao Tel; a da Parceria não muda
SELECT pergunta_fila_entrar('captacao', '5592999990001', 'Teste OLX', NULL, NULL, 'Tem vaga coberta?', 'olx_whatsapp', NULL) AS id_olx \gset
SELECT id, linha, estado FROM pergunta_fila WHERE id = :id_olx;
SELECT pergunta_fila_agente_responder(:id_olx, 'Tem sim, 1 vaga coberta.', 'ensaio');
SELECT id, estado, resposta, detalhe FROM pergunta_fila WHERE id = :id_olx;
SELECT pergunta_fila_entrar('captacao', '5592999990002', 'Teste OLX 2', NULL, NULL, 'Aceita pet?', 'olx_whatsapp', NULL) AS id_olx2 \gset
SELECT pergunta_fila_agente_devolver(:id_olx2, 'nem a ficha nem o dono sabem');
SELECT id, estado, detalhe FROM pergunta_fila WHERE id = :id_olx2;
SELECT pergunta_fila_entrar('parceria', '5592999990003', 'Teste Parceria', NULL, NULL, 'Qual o andar?', 'teste', NULL) AS id_par \gset
SELECT id, linha, estado FROM pergunta_fila WHERE id = :id_par;
