-- 330: a Úrsula (10524) tem a #1081 aberta no 5758 de 07/10; a Rayssa agenda hoje às 16h
SELECT 'antes' AS passo, id, estado, quando FROM nai_visita WHERE corretor_id = 10524 AND codigo = 5758 ORDER BY id;
SELECT 'agenda 16h' AS passo, ok, mensagem, visita FROM crm_visita_agendar(5758, '559291125952', 'Úrsula', '2026-10-09 16:00-04', 60, 'Teste 330');
SELECT 'depois' AS passo, id, estado, quando, motivo FROM nai_visita WHERE corretor_id = 10524 AND codigo = 5758 ORDER BY id;
SELECT 'muda p/ 17h' AS passo, ok, mensagem, visita FROM crm_visita_agendar(5758, '559291125952', 'Úrsula', '2026-10-09 17:00-04', 60, 'Teste 330');
SELECT 'repete 17h' AS passo, ok, mensagem, visita FROM crm_visita_agendar(5758, '559291125952', 'Úrsula', '2026-10-09 17:00-04', 60, 'Teste 330');
SELECT 'fim' AS passo, id, estado, quando, criada_no_crm_por FROM nai_visita WHERE corretor_id = 10524 AND codigo = 5758 ORDER BY id;
SELECT 'eventos' AS passo, visita_id, tipo, detalhe FROM nai_visita_evento WHERE visita_id IN (SELECT id FROM nai_visita WHERE corretor_id = 10524 AND codigo = 5758) AND quando > now() - interval '1 minute' ORDER BY id;
