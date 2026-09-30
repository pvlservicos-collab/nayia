-- Mudança 3: rastreia "código já postado no Easy, quando".
-- Não rodar ainda -- revisar antes.

CREATE TABLE easy_publicacoes (
  codigo TEXT PRIMARY KEY,
  publicado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
