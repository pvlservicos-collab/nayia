-- 141a: o esquema da visita nova, das etapas e do follow-up. So acrescenta
-- (estados, papeis, colunas, tabelas): o codigo antigo continua valendo.
-- Curto e com lock_timeout: se nao pegar a trava em 5 s, desiste -- nunca
-- deixa a Nay esperando atras (o ensaio de 28/09 11h40 travou 2 min).
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';
-- ---------------------------------------------------------------- esquema
ALTER TABLE nai_visita DROP CONSTRAINT nai_visita_estado_check;
ALTER TABLE nai_visita ADD CONSTRAINT nai_visita_estado_check CHECK (estado = ANY (ARRAY[
  'coletando', 'confirmando', 'aguardando_rayssa', 'aguardando_proprietario', 'negociando', 'aguardando_acesso',
  'aguardando_motoboy', 'confirmada', 'com_tel', 'realizada', 'encerrada', 'cancelada', 'expirada']));
ALTER TABLE nai_visita DROP CONSTRAINT nai_visita_aguardando_check;
ALTER TABLE nai_visita ADD CONSTRAINT nai_visita_aguardando_check CHECK (aguardando = ANY (ARRAY[
  'corretor', 'proprietario', 'motoboy', 'tel', 'equipe']));
ALTER TABLE nai_visita
  ADD COLUMN IF NOT EXISTS confirmada_corretor_em timestamptz,
  ADD COLUMN IF NOT EXISTS rayssa_msg_em          timestamptz,
  ADD COLUMN IF NOT EXISTS rayssa_lembretes       integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS aprovada_em            timestamptz,
  ADD COLUMN IF NOT EXISTS aprovada_por           text,
  ADD COLUMN IF NOT EXISTS prop_telefone_manual   text;

ALTER TABLE nai_saida DROP CONSTRAINT nai_saida_papel_destino_check;
ALTER TABLE nai_saida ADD CONSTRAINT nai_saida_papel_destino_check CHECK (papel_destino = ANY (ARRAY[
  'turno', 'corretor', 'proprietario', 'motoboy', 'tel', 'entrega', 'equipe', 'seguimento']));

CREATE TABLE IF NOT EXISTS nai_etapa_contato (
  contato_id    bigint PRIMARY KEY REFERENCES nai_contato(id),
  etapa         text NOT NULL CHECK (etapa IN ('identificacao', 'recebeu_imovel', 'agendamento_visita')),
  desde         timestamptz NOT NULL DEFAULT now(),
  motivo        text,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  crm_em        timestamptz
);
CREATE TABLE IF NOT EXISTS nai_etapa_evento (
  id bigserial PRIMARY KEY, contato_id bigint NOT NULL, de text, para text NOT NULL, motivo text,
  em timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS nai_followup (
  id          bigserial PRIMARY KEY,
  chave       text NOT NULL,
  dia_recebeu date NOT NULL,
  contato_id  bigint,
  codigos     integer[],
  estado      text NOT NULL CHECK (estado IN ('enviado', 'pulado')),
  motivo      text,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (chave, dia_recebeu));

INSERT INTO nai_config (chave, valor) VALUES
  ('aprovador_visita_telefone', '5596991511557'),
  ('aprovador_visita_nome', 'Rayssa'),
  ('aprovacao_lembrete_min', '30'),
  ('followup_ligado', 'nao'),
  ('followup_inicio', '09:00'),
  ('followup_fim', '18:00'),
  ('followup_por_minuto', '2')
ON CONFLICT (chave) DO NOTHING;

COMMIT;
