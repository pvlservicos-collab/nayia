-- 0132 -- O LEMBRETE DA VISITA (Pedro, 01/10/2026): "posso adicionar um lembrete ali
-- mesmo, igual esse lembrete de mensagem... por padrão o lembrete já vem configurado
-- para 1 hora antes". O lembrete da visita É um follow-up agendado (0131): a mesma
-- tabela, o mesmo cron, a mesma linha de WhatsApp. O que muda é que ele sabe de que
-- visita é e quanto antes dela sai -- para seguir a visita:
--   visita excluída na agenda  -> o lembrete que ainda não saiu é cancelado;
--   visita arrastada de hora   -> o lembrete vai junto (novo horário - minutos_antes).
-- Sem isso a pessoa receberia "lembrete da visita das 15h" de uma visita que mudou.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL ROLE crm;
ALTER TABLE followups_agendados ADD COLUMN IF NOT EXISTS visita_id bigint;
ALTER TABLE followups_agendados ADD COLUMN IF NOT EXISTS minutos_antes integer;
CREATE INDEX IF NOT EXISTS followups_agendados_visita ON followups_agendados (visita_id) WHERE visita_id IS NOT NULL;
COMMIT;
