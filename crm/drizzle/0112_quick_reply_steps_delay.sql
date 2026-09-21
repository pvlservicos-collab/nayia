-- Espera (em segundos) depois de mandar um passo da sequência, antes do próximo.
-- 0 = sem pausa (comportamento atual, sem mudança pra quem já tem passos cadastrados).
ALTER TABLE "quick_reply_steps" ADD COLUMN "delay_seconds" integer NOT NULL DEFAULT 0;
