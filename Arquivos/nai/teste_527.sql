-- teste da 527 (dentro da transação do ensaio; tudo volta no ROLLBACK)
\echo '--- o painel, pelo papel do CRM'
SET LOCAL ROLE nay_disparo;
SELECT x->>'fonte' AS fonte, x->>'id' AS id, x->>'linha' AS linha, x->>'estado' AS estado, x->>'cliente' AS cliente,
       left(x->>'pergunta', 60) AS pergunta, left(replace(x->>'cliente_disse', E'\n', ' / '), 80) AS cliente_disse
  FROM jsonb_array_elements(crm_tel_duvidas()) x;

\echo '--- responder a 330 (Leads, na fila): fica respondida e a Nay Leads entrega'
SELECT crm_tel_responder('fila', 330, 'responder', 'O proprietário não baixa para 5 mil; o mínimo é 6.800 com condomínio.', 'Teste');
\echo '--- responder a 309 (a do PV): o PV passa para a próxima'
SELECT crm_tel_responder('fila', 309, 'responder', 'O proprietário aceita conversar, mas não faz permuta.', 'Teste');
\echo '--- de novo a 330: recusa; descartar a 301 (agente); resposta vazia'
SELECT crm_tel_responder('fila', 330, 'responder', 'x', 'Teste');
SELECT crm_tel_responder('fila', 301, 'descartar', NULL, 'Teste');
SELECT crm_tel_responder('fila', 302, 'responder', '   ', 'Teste');
RESET ROLE;
SELECT id, estado, left(coalesce(resposta, ''), 40) AS resposta, entregue_em IS NOT NULL AS entregue, left(detalhe, 60) AS detalhe
  FROM pergunta_fila WHERE id IN (301, 309, 330) ORDER BY id;
SELECT id, estado FROM pergunta_fila WHERE estado = 'perguntada';

\echo '--- o aviso: 302 volta do agente para a fila (avisa); 302 de fila para perguntada e de volta (PULAR) não avisa'
SELECT count(*) AS avisos_antes FROM privado.aviso_equipe WHERE fonte = 'respostas-tel';
UPDATE pergunta_fila SET estado = 'fila' WHERE id = 302;
UPDATE pergunta_fila SET estado = 'perguntada' WHERE id = 302;
UPDATE pergunta_fila SET estado = 'fila' WHERE id = 302;
SELECT count(*) AS avisos_depois, max(texto) AS texto FROM privado.aviso_equipe WHERE fonte = 'respostas-tel';
