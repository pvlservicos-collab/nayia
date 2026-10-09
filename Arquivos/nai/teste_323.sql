-- testes da 323, dentro da transação do ensaio (sem BEGIN/COMMIT)
SELECT 'na retomada' AS o_que, count(*) FROM captacao_retomada_oficial;
SELECT 'fila: novos' AS o_que, count(*) FROM captacao_py_fila_do_disparo() f JOIN captacao_leads l ON l.id = f WHERE l.status IN ('novo','erro');
SELECT 'fila: retomada' AS o_que, count(*) FROM captacao_py_fila_do_disparo() f JOIN captacao_leads l ON l.id = f WHERE l.status = 'enviado';
-- ninguém da fila já falou com a gente, é corretor, está com humano ou já recebeu o modelo oficial
SELECT 'fila com algo errado (tem de ser 0)' AS o_que, count(*) FROM captacao_py_fila_do_disparo() f JOIN captacao_leads l ON l.id = f
 WHERE l.respondeu_em IS NOT NULL OR l.humano_assumiu_em IS NOT NULL OR l.opt_out OR captacao_fora_da_campanha(l.id) IS NOT NULL
    OR EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id)
    OR EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'recebida');
-- os novos vêm antes da retomada
SELECT 'primeiro da fila' AS o_que, l.id, l.status FROM captacao_py_fila_do_disparo() f JOIN captacao_leads l ON l.id = f LIMIT 1;
-- o Marcio Rabelo (584) e os corretores nunca entram
SELECT 'Marcio 584 na fila (tem de ser 0)' AS o_que, count(*) FROM captacao_py_fila_do_disparo() f WHERE f = 584;
-- a reserva de um lead da retomada: liga o interruptor só aqui dentro (vai ser desfeito), tira os novos da frente
UPDATE captacao_config SET valor = 'sim' WHERE chave = 'python_disparo';
DELETE FROM captacao_config WHERE chave = '_py_disparo_em';
UPDATE captacao_leads SET status = 'reservado', atualizado_em = now() WHERE status = 'reservado';
CREATE TEMP TABLE novos_de_lado AS SELECT id FROM captacao_leads WHERE status IN ('novo','erro');
UPDATE captacao_leads SET status = 'concluido' WHERE id IN (SELECT id FROM novos_de_lado);
SELECT 'motivo de não sair (tem de ser vazio)' AS o_que, coalesce(captacao_py_disparo_motivo(), '') AS motivo;
-- em dois comandos: no mesmo SELECT da função, as subconsultas enxergam o banco de ANTES dela escrever
CREATE TEMP TABLE reservado AS SELECT * FROM captacao_py_reservar_disparo();
SELECT 'reservou da retomada' AS o_que, r.lead_id, r.nome IS NOT NULL AS tem_nome,
       (SELECT status FROM captacao_leads WHERE id = r.lead_id) AS status_agora,
       EXISTS (SELECT 1 FROM captacao_motor WHERE lead_id = r.lead_id) AS no_motor,
       EXISTS (SELECT 1 FROM captacao_retomada_oficial WHERE lead_id = r.lead_id) AS era_da_retomada
  FROM reservado r;
-- o reservado da retomada não aparece mais na fila
SELECT 'fila depois da reserva (um a menos)' AS o_que, count(*) FROM captacao_py_fila_do_disparo();
-- sem duplicata: nenhum telefone nem dono aparece duas vezes na fila (Pedro, 09/10: "só não vai mandar msg duplicada para o mesmo contato")
SELECT 'telefone repetido na fila (tem de ser 0)' AS o_que, count(*) - count(DISTINCT l.telefone_chave) AS repetidos FROM captacao_py_fila_do_disparo() f JOIN captacao_leads l ON l.id = f;
SELECT 'dono repetido na fila (tem de ser 0)' AS o_que, count(*) FILTER (WHERE l.proprietario_id IS NOT NULL) - count(DISTINCT l.proprietario_id) AS repetidos FROM captacao_py_fila_do_disparo() f JOIN captacao_leads l ON l.id = f;
SELECT 'na fila com o modelo oficial já enviado (tem de ser 0)' AS o_que, count(*) FROM captacao_py_fila_do_disparo() f JOIN captacao_mensagens m ON m.lead_id = f AND m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou' JOIN captacao_motor mt ON mt.lead_id = f;
