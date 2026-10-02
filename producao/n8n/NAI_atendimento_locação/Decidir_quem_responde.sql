-- A ROTA de hoje continua igual. O que muda: a INTENCAO passa a ser
-- GRAVADA, com quem decidiu e com quanta certeza. A partir daqui existe
-- um lugar onde a decisao do turno esta escrita, e depurar vira SELECT.
--
-- MATERIALIZED nao e enfeite: sem ele o Postgres pode inlinar a CTE e
-- rodar as funcoes fora de ordem. Mesmo assim nada quebra (tudo tem
-- padrao seguro), mas os campos viriam errados.
WITH d AS MATERIALIZED (
  SELECT nai_decidir_com_jev($1::bigint, $2::jsonb) AS atendente
), i AS MATERIALIZED (
  SELECT nai_decidir_v2(
           $1::bigint,
           $2::jsonb #>> '{intencao,choice}',
           ($2::jsonb #>> '{intencao,confidence}')::real,
           'jev',
           CASE WHEN $2::jsonb #>> '{codigo_quer,choice}' ~ '^[0-9]{3,5}$'
                THEN ARRAY[($2::jsonb #>> '{codigo_quer,choice}')::int] ELSE '{}'::int[] END,
           CASE WHEN $2::jsonb #>> '{codigo_rejeita,choice}' ~ '^[0-9]{3,5}$'
                THEN ARRAY[($2::jsonb #>> '{codigo_rejeita,choice}')::int] ELSE '{}'::int[] END,
           $2::jsonb) AS intencao
)
SELECT d.atendente,
       i.intencao,
       nai_pediu_imovel($1::bigint) AS pediu_imovel,
       (SELECT texto FROM nai_prompt WHERE papel = 'secretaria') AS prompt_secretaria
  FROM d, i;
