-- Doc 28, passo 7: schema da tabela de vagas (grade de horários).
-- Não rodar ainda -- revisar antes.

CREATE TABLE vagas (
  id SERIAL PRIMARY KEY,
  horario TIME NOT NULL,

  -- 'diaria': todo dia, sem dias_semana nem data_unica.
  -- 'semanal': recorrente em dias específicos da semana (dias_semana
  --            obrigatório). Convenção igual ao EXTRACT(DOW) do Postgres:
  --            0=domingo, 1=segunda, ..., 6=sábado.
  -- 'unica': dispara uma vez só, na data_unica (o caso "só hoje", ou
  --          qualquer data futura específica marcada de propósito).
  tipo_recorrencia TEXT NOT NULL CHECK (tipo_recorrencia IN ('diaria', 'semanal', 'unica')),
  dias_semana INTEGER[],
  data_unica DATE,

  -- até 3 códigos; array vazio = vaga livre, esperando o Tel preencher
  -- (doc 28: quando o imóvel sai de circulação, a vaga fica livre e
  -- espera, a Nay não escolhe sozinha o próximo).
  codigos TEXT[] NOT NULL DEFAULT '{}',

  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),

  CHECK (
    (tipo_recorrencia = 'diaria' AND dias_semana IS NULL AND data_unica IS NULL)
    OR (tipo_recorrencia = 'semanal' AND dias_semana IS NOT NULL AND data_unica IS NULL)
    OR (tipo_recorrencia = 'unica' AND dias_semana IS NULL AND data_unica IS NOT NULL)
  ),
  CHECK (dias_semana IS NULL OR dias_semana <@ ARRAY[0,1,2,3,4,5,6]),
  CHECK (array_length(codigos, 1) IS NULL OR array_length(codigos, 1) <= 3)
);
