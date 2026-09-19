-- Decisão do Tel: sem cap artificial de código por vaga -- remove o
-- CHECK que limitava a 3. Não rodar daqui -- aplicar no servidor.

ALTER TABLE vagas DROP CONSTRAINT IF EXISTS vagas_codigos_check;
