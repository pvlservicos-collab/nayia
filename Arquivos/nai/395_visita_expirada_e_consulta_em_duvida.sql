-- 395: os dois estados novos da visita da Nay do WhatsApp (revisão do fluxo, 16/10)
--   olx_visita 'expirada': passou do horário sem fechar com corretor/proprietário (a equipe é avisada no grupo);
--   olx_visita_consulta 'duvida': o corretor/dono respondeu algo que não é sim nem não (a equipe vê no grupo e o relógio
--   para: antes, a meia hora vencia e a Nay chamava o próximo por cima da conversa da equipe).
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE privado.olx_visita DROP CONSTRAINT olx_visita_estado_check;
ALTER TABLE privado.olx_visita ADD CONSTRAINT olx_visita_estado_check CHECK (estado = ANY (ARRAY['confirmar_cliente',
  'buscando_corretor', 'pedindo_proprietario', 'confirmada', 'sem_corretor', 'proprietario_nao', 'sem_proprietario',
  'cancelada', 'expirada']));
ALTER TABLE privado.olx_visita_consulta DROP CONSTRAINT olx_visita_consulta_estado_check;
ALTER TABLE privado.olx_visita_consulta ADD CONSTRAINT olx_visita_consulta_estado_check CHECK (estado = ANY (ARRAY['esperando',
  'sim', 'nao', 'sem_resposta', 'cancelada', 'duvida']));
COMMIT;
