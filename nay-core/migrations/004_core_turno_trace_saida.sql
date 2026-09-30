-- 004: o turno, o trace e a caixa de saída.

-- Um turno = uma rajada de uma pessoa processada. `caminho` diz se ele passou
-- pelo modelo; é o número que mostra quantas mensagens não precisaram dele.
CREATE TABLE IF NOT EXISTS core_turno (
  id             bigserial PRIMARY KEY,
  chave          text NOT NULL,
  papel          text,
  texto          text NOT NULL,
  estado_antes   text,
  estado_depois  text,
  intencao       text,
  caminho        text CHECK (caminho IN ('pre_roteador', 'classificador', 'fallback', 'fora_do_escopo')),
  usou_modelo    boolean NOT NULL DEFAULT false,
  versao_regras  text,
  versao_prompt  text,
  exec_id        text,
  ms_total       int,
  erro           text,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  fechado_em     timestamptz
);
CREATE INDEX IF NOT EXISTS core_turno_chave ON core_turno (chave, criado_em);

-- Uma linha por etapa por turno. Guarda o que a pergunta 53 diz que hoje não
-- dá para reconstruir: texto cru do modelo, argumentos e retorno de cada
-- ferramenta, versão do prompt, modelo e tempo.
CREATE TABLE IF NOT EXISTS core_trace (
  id            bigserial PRIMARY KEY,
  turno_id      bigint NOT NULL REFERENCES core_turno(id),
  seq           int NOT NULL,
  setor         text NOT NULL,
  etapa         text NOT NULL,
  entrada       jsonb,
  saida         jsonb,
  ms            int,
  modelo        text,
  versao_prompt text,
  erro          text,
  criado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS core_trace_turno ON core_trace (turno_id, seq);

-- A caixa de saída. NESTA ENTREGA O NAY-CORE NUNCA ENVIA: o CHECK em `estado`
-- só aceita 'simulado'. Falha fechada no banco, não promessa no código --
-- liberar o envio real vai exigir uma migração nova, de propósito.
CREATE TABLE IF NOT EXISTS core_saida (
  id           bigserial PRIMARY KEY,
  turno_id     bigint NOT NULL REFERENCES core_turno(id),
  chave        text NOT NULL,
  ordem        int NOT NULL,
  tipo         text NOT NULL CHECK (tipo IN ('texto', 'imagem')),
  texto        text,
  imagem_url   text,
  codigo       int,
  motivo       text,
  enviar_apos  timestamptz NOT NULL DEFAULT now(),
  estado       text NOT NULL DEFAULT 'simulado' CHECK (estado = 'simulado'),
  criado_em    timestamptz NOT NULL DEFAULT now(),
  CHECK (tipo = 'texto' AND texto IS NOT NULL OR tipo = 'imagem' AND imagem_url IS NOT NULL AND codigo IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS core_saida_turno ON core_saida (turno_id, ordem);
