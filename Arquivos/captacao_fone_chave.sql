-- Casamento de telefone que sobrevive ao NONO DIGITO.
--
-- O problema, medido em 09/09/2026 com uma resposta real do Tel: o lead
-- estava gravado como 5596991712835 (13 digitos, com o 9), mas a Z-API
-- entregou a mensagem recebida como 559691712835 (12 digitos, sem o 9).
-- O fluxo casa lead por igualdade exata de telefone, entao o lead nao foi
-- encontrado, `conhecido` veio false e o 'Preparar resposta' descartou --
-- em silencio. Na campanha inteira isso significa: a Nay nunca responde
-- um proprietario de verdade.
--
-- Nao da para escolher um formato e confiar: a propria base tem os dois
-- (559284011981 com 12, 5592981272285 com 13), e o que a Z-API entrega
-- depende do DDD e de como o contato salvou o numero.
--
-- A chave e o que NAO muda: DDI + DDD + os 8 digitos finais. O nono
-- digito e sempre um '9' colado na frente desses 8, entao ignora-lo
-- casa as duas formas sem juntar pessoas diferentes -- dois numeros so
-- colidem se DDD e os 8 finais forem iguais, que e o mesmo telefone.

BEGIN;

CREATE OR REPLACE FUNCTION nay_fone_chave(fone text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    -- Brasileiro com DDI: 55 + DDD(2) + 8 ou 9 digitos.
    WHEN d ~ '^55[0-9]{10,11}$' THEN substring(d, 1, 4) || right(d, 8)
    -- Qualquer outra coisa (internacional, numero curto) fica como veio.
    ELSE d
  END
  FROM (SELECT regexp_replace(coalesce(fone, ''), '\D', '', 'g') AS d) t;
$$;

-- Coluna gerada: nunca sai de sincronia com o telefone, e o Postgres
-- recalcula sozinho em todo INSERT e UPDATE.
ALTER TABLE captacao_leads
  ADD COLUMN IF NOT EXISTS telefone_chave text
  GENERATED ALWAYS AS (nay_fone_chave(telefone)) STORED;

-- UNIQUE na chave, nao so no telefone: sem isto o mesmo proprietario
-- entraria duas vezes na campanha se a lista trouxesse ele escrito das
-- duas formas -- e receberia a mesma pergunta duas vezes.
CREATE UNIQUE INDEX IF NOT EXISTS captacao_leads_fone_chave_uk
  ON captacao_leads (telefone_chave);

-- O webhook busca o lead por aqui a cada mensagem que chega.
CREATE INDEX IF NOT EXISTS captacao_mensagens_chave_idx
  ON captacao_mensagens (nay_fone_chave(telefone), direcao, status);

COMMIT;
