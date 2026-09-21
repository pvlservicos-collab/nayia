-- Gatilhos de funil para as fontes de lead (tela /leads) e um tipo de bloco novo
-- que move o lead de etapa no pipeline.
--
-- ALTER TYPE ... ADD VALUE não pode rodar dentro de transação junto com um uso do
-- valor novo, por isso este arquivo é aplicado statement a statement, sem BEGIN
-- (ver scripts/apply-migration.mjs, que decide isso olhando o conteúdo).

-- Disparam quando um lead novo entra por /api/ingest/leads.
ALTER TYPE "funnel_trigger" ADD VALUE IF NOT EXISTS 'lead_site_evento';
ALTER TYPE "funnel_trigger" ADD VALUE IF NOT EXISTS 'lead_agenda_ascensao';

-- Bloco "Mover de etapa": config = { "stageId": "<uuid>" }. É o que leva o lead
-- para "Atendimento por humano" assim que ele responde.
ALTER TYPE "funnel_block_type" ADD VALUE IF NOT EXISTS 'move_stage';
