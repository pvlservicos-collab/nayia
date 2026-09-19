-- `imovel_fotos.id` ganha sequência própria.
--
-- O CASO (01/09): o varredor de fotos falhou com "null value in column id
-- violates not-null constraint". A coluna é `integer NOT NULL` sem
-- default -- o import original preenchia o id à mão, e nada mais nunca
-- inseriu ali desde então.
--
-- A sequência começa acima do maior id existente, então não colide com
-- nada. É mudança ADITIVA: quem já insere passando o id explicitamente
-- continua funcionando igual.
--
--   docker cp imovel_fotos_id.sql nay-postgres:/tmp/fid.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/fid.sql

CREATE SEQUENCE IF NOT EXISTS imovel_fotos_id_seq;

-- Acima do maior que existe. `setval` com `is_called = true` faz o
-- próximo `nextval` devolver max+1.
SELECT setval('imovel_fotos_id_seq',
              coalesce((SELECT max(id) FROM imovel_fotos), 0) + 1, false);

ALTER TABLE imovel_fotos ALTER COLUMN id SET DEFAULT nextval('imovel_fotos_id_seq');
ALTER SEQUENCE imovel_fotos_id_seq OWNED BY imovel_fotos.id;

SELECT 'proximo id sera:' AS r, nextval('imovel_fotos_id_seq')::text AS v;
SELECT setval('imovel_fotos_id_seq',
              coalesce((SELECT max(id) FROM imovel_fotos), 0) + 1, false);
