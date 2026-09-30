-- 002: a entrada. O webhook só grava o corpo cru e devolve 200 (setor entrada).
-- Tudo o que vem depois (dedupe, mídia, rajada) trabalha a partir daqui, num
-- worker, fora do caminho do webhook.

-- O corpo cru da Z-API, exatamente como chegou. O message_id repetido é
-- descartado na própria inserção (ON CONFLICT DO NOTHING): a Z-API reentrega,
-- e o velho respondeu duas vezes por isso (pergunta 44).
CREATE TABLE IF NOT EXISTS core_evento_bruto (
  id            bigserial PRIMARY KEY,
  recebido_em   timestamptz NOT NULL DEFAULT now(),
  message_id    text,
  corpo         jsonb NOT NULL,
  processado_em timestamptz,
  erro          text
);
CREATE UNIQUE INDEX IF NOT EXISTS core_evento_bruto_msg
  ON core_evento_bruto (message_id) WHERE message_id IS NOT NULL;
-- a fila do worker: só o que ainda não foi processado
CREATE INDEX IF NOT EXISTS core_evento_bruto_fila
  ON core_evento_bruto (recebido_em) WHERE processado_em IS NULL;

-- Uma linha por mensagem normalizada. `chave` é a identidade da pessoa
-- (telefone ou lid:<dígitos>, setor identidade). `transcricao` guarda o texto
-- do áudio ou a leitura da imagem de TODA mensagem da rajada (pergunta 2).
CREATE TABLE IF NOT EXISTS core_mensagem (
  id           bigserial PRIMARY KEY,
  evento_id    bigint NOT NULL REFERENCES core_evento_bruto(id),
  message_id   text NOT NULL UNIQUE,
  chave        text NOT NULL,
  direcao      text NOT NULL CHECK (direcao IN ('recebida', 'enviada')),
  tipo         text NOT NULL CHECK (tipo IN ('texto', 'audio', 'imagem', 'documento',
                                             'video', 'reacao', 'figurinha', 'outro')),
  texto        text,
  midia_url    text,
  transcricao  text,
  citado_id    text,
  recebida_em  timestamptz NOT NULL,
  turno_id     bigint
);
CREATE INDEX IF NOT EXISTS core_mensagem_chave ON core_mensagem (chave, recebida_em);
-- a rajada: mensagens recebidas ainda sem turno, por pessoa
CREATE INDEX IF NOT EXISTS core_mensagem_sem_turno
  ON core_mensagem (chave, recebida_em) WHERE turno_id IS NULL AND direcao = 'recebida';
