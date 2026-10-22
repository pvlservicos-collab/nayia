-- 466: o lembrete de 1 hora antes da visita, no grupo Altarquia, sai pelo SISTEMA (nay-olx, visitas_parceria.py), não mais
-- pelo agente Visitas (Pedro, 22/10/2026: o limite da conta do Claude estourou; "diminui a frequência do visita para uma vez
-- de manhã cedo, começo da tarde e fim da tarde"). O texto é o card padrão (visita_card, 464); esta tabela marca o que já
-- foi lembrado, uma vez por visita. Desligar: privado.olx_config visitas_lembrete_1h = nao.

BEGIN;

CREATE TABLE IF NOT EXISTS privado.visita_lembrete_grupo (
  visita_id bigint PRIMARY KEY,
  em        timestamptz NOT NULL DEFAULT now());
COMMENT ON TABLE privado.visita_lembrete_grupo IS '466: a visita que já teve o lembrete de 1 hora antes no grupo Altarquia.';

COMMIT;
