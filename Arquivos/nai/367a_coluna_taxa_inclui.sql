-- 367a -- A coluna do que está incluso na taxa de condomínio (só o esquema; os dados e a função vêm na 367)
--
-- Pedro, 14/10/2026: "mexe lá na parte dos componentes do condomínio um campo O que está incluso na taxa de
-- condomínio. geralmente é: segurança 24 horas, água, gás, energia (só alguns flats)".
-- DDL num arquivo curto e à parte (ver o ALTER TABLE que travou a Nay em 28/09): ADD COLUMN com padrão constante
-- não reescreve a tabela, e o lock_timeout desiste em vez de ficar na fila na frente da Nay.
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE condominio_ficha ADD COLUMN IF NOT EXISTS taxa_inclui text[] NOT NULL DEFAULT '{}';
COMMENT ON COLUMN condominio_ficha.taxa_inclui IS
  '367: o que está incluso na taxa de condomínio (Segurança 24 horas, Água, Gás, Energia...). Vale para todo imóvel do condomínio; a Nay nova lê junto da taxa.';
COMMIT;
