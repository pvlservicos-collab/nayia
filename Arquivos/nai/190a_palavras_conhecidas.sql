-- 190a -- as palavras que o pessoal usa de verdade nas conversas (29/09/2026).
-- O corretor de nomes (nai_corrigir_nomes) trocava palavra comum por nome de
-- bairro/condomínio parecido: "cômodo" virou "Coroado" (Sulivam: "Ela precisa
-- de mais um cômodo" -> "No Coroado não tenho nenhuma casa"), "dentro" virou
-- "Centro" (7x em 14 dias), "vista" virou "vistas", "terreno" virou "estilo",
-- "portal" virou "portugal". A lista protege o que aparece em 3 ou mais
-- mensagens recebidas (180 dias): palavra de gente não é erro de digitação de
-- nome, e o nome escrito errado é raro. Tabela nova: não trava nada existente.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS nai_palavra_conhecida (
  palavra       text PRIMARY KEY,
  mensagens     int NOT NULL,
  atualizada_em timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION nai_atualizar_palavras_conhecidas()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  TRUNCATE nai_palavra_conhecida;
  INSERT INTO nai_palavra_conhecida (palavra, mensagens)
  SELECT w, count(DISTINCT id)
    FROM (SELECT m.id, regexp_split_to_table(lower(unaccent(coalesce(m.texto, ''))), '[^a-z0-9]+') AS w
            FROM mensagens m
           WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '180 days'
             AND length(coalesce(m.texto, '')) < 2000) x
   WHERE length(w) >= 3 AND w ~ '^[a-z]+$'
   GROUP BY w
  HAVING count(DISTINCT id) >= 3;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION nai_palavra_conhecida(p text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM nai_palavra_conhecida
                  WHERE palavra = lower(unaccent(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g'))));
$$;

SELECT nai_atualizar_palavras_conhecidas();

COMMIT;
