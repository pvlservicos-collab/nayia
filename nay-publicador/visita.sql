-- Agenda de visitas.
--
-- O PEDIDO (Tel, 11/09): "quero que a Nay verifique as visitas que os
-- corretores pediram e caso fique sem resposta durante 1 hora ela me avise,
-- e logo no inicio do dia as 06:00 da manhã ela avise as visitas que já tem
-- agendada no dia."
--
-- A tabela só guarda visita FUTURA. Passou a hora: apaga. Cancelou: apaga.
-- O cron `alertar_visitas.py` cuida dos avisos e da limpeza.
--
--   docker cp visita.sql nay-postgres:/tmp/v.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/v.sql

CREATE TABLE IF NOT EXISTS visita (
    id                    serial PRIMARY KEY,
    codigo                text,
    descricao             text NOT NULL,
    corretor              text NOT NULL,
    corretor_telefone     text,
    data_hora             timestamptz NOT NULL,
    criada_em             timestamptz NOT NULL DEFAULT now(),
    confirmada            boolean NOT NULL DEFAULT false,
    alerta_pendencia_em   timestamptz,
    alerta_90min_em       timestamptz,
    -- A CONFIRMACAO DAS 07:00 (Tel, 23/09). UM POR VISITA, nao um por
    -- dia: duas visitas no mesmo dia precisam de dois pedidos, e um
    -- carimbo global em `config` mandaria so o primeiro.
    confirmacao_pedida_em timestamptz
);

CREATE INDEX IF NOT EXISTS visita_data_hora_idx ON visita (data_hora);

-- Chaves de config para os alertas agregados (manhã e véspera).
INSERT INTO config (chave, valor)
VALUES ('visita_briefing_manha_em', '')
ON CONFLICT (chave) DO NOTHING;

INSERT INTO config (chave, valor)
VALUES ('visita_alerta_vespera_em', '')
ON CONFLICT (chave) DO NOTHING;

ALTER TABLE visita
  ADD COLUMN IF NOT EXISTS confirmacao_pedida_em timestamptz;

-- HORA A DEFINIR (Tel, 23/09). O corretor confirma o DIA e nao diz a hora --
-- o Mario fez exatamente isso: "vai ser na sexta", depois de ter prometido
-- "te digo o horario". Sem esta coluna so havia duas saidas ruins: nao
-- registrar (nenhum alerta dispara) ou chutar a hora (alerta no horario
-- errado). `data_hora` guarda o dia com 12:00 de marcador; quem decide se a
-- hora vale e a FLAG, nunca o valor.
ALTER TABLE visita
  ADD COLUMN IF NOT EXISTS hora_a_definir boolean NOT NULL DEFAULT false;
