-- Testes da 291: roda dentro do ensaio, depois do UPDATE, antes do ROLLBACK.
\echo '== 1. ninguém na fila já recebeu a abertura (deve ser 0)'
SELECT count(*) AS na_fila_com_disparo FROM captacao_leads l
 WHERE l.status = 'novo'
   AND EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'enviada' AND coalesce(m.status, '') <> 'Falhou');
\echo '== 2. a fila que sobra e quem é o próximo'
SELECT count(*) AS na_fila, min(id) AS proximo_id FROM captacao_leads WHERE status = 'novo' AND NOT opt_out;
\echo '== 3. os status depois'
SELECT status, count(*) FROM captacao_leads GROUP BY 1 ORDER BY 2 DESC;
\echo '== 4. os 5 próximos da fila: o que cada um já tem de mensagem'
SELECT l.id, right(l.telefone, 4) AS fim, l.tentativas,
       (SELECT count(*) FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'enviada') AS enviadas,
       (SELECT count(*) FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida') AS recebidas
  FROM captacao_leads l WHERE l.status = 'novo' AND NOT l.opt_out ORDER BY l.id LIMIT 5;
