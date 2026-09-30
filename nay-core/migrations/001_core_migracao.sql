-- 001: a tabela de controle das migrações do nay-core.
-- Cada arquivo migrations/NNN_*.sql aplicado vira uma linha aqui, com o md5 do
-- conteúdo. scripts/migrar.py não reaplica o que já está na tabela e RECUSA
-- arquivo já aplicado cujo md5 mudou: migração aplicada não se edita, se
-- escreve outra. É o que faltava no sistema velho (entrevista, pergunta 50).
CREATE TABLE IF NOT EXISTS core_migracao (
  arquivo     text PRIMARY KEY,
  md5         text NOT NULL,
  aplicado_em timestamptz NOT NULL DEFAULT now()
);
