-- =====================================================================
-- NAI -- 108: as caracteristicas saem do porao (Tel, 23/09/2026)
--
-- Ele: "la onde abre o imovel nao tem todas as informacoes no nosso site,
-- preciso disso bem organizado para a nay nao errar, o tipo de imovel se e
-- casa ou apartamento, semi ou mobiliado, o que tem EXATAMENTE" e "preciso de
-- uma revisao completa nos imoveis buscando preencher buracos".
--
-- O QUE ACHEI: a lista "Caracteristicas do Imovel" do site antigo ESTA no
-- nosso banco -- 1.172 imoveis tem ela em `extras->>'caracteristicas'`
-- ("Semi-Mobiliado", "Mobiliado, Climatizado", "Fechadura eletronica"). So que
-- ninguem le de la: a coluna `caracteristicas`, que e a que o card e a busca
-- leem, esta vazia. O dado estava guardado no porao.
--
-- DUAS COISAS, entao:
--   1. a lista vai para a COLUNA `caracteristicas`, onde o card ja sabe ler;
--   2. onde a coluna `mobilia` esta vazia e a lista diz "Mobiliado" ou
--      "Semi-Mobiliado", a mobilia e preenchida a partir dela.
--
-- NADA E SOBRESCRITO: so entra onde esta vazio.
--
-- O QUE CONTINUA SEM RESPOSTA: 99 imoveis no mercado nao tem caracteristica
-- nenhuma nem no site antigo. Para esses, ninguem sabe se e mobiliado -- e
-- inventar seria pior do que nao saber.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1. a lista sai do extras e vai para a coluna
UPDATE imoveis i
   SET caracteristicas = (
         SELECT array_agg(btrim(x)) FROM unnest(string_to_array(i.extras->>'caracteristicas', ',')) x
          WHERE btrim(x) <> '')
 WHERE coalesce(array_length(i.caracteristicas, 1), 0) = 0
   AND coalesce(i.extras->>'caracteristicas', '') <> '';

-- 2. a mobilia sai da lista, quando a coluna esta vazia
UPDATE imoveis i
   SET mobilia = CASE
         WHEN array_to_string(i.caracteristicas, ', ') ~* 'semi.?mobiliad' THEN 'semi-mobiliado'
         WHEN array_to_string(i.caracteristicas, ', ') ~* 'mobiliad'       THEN 'mobiliado'
         WHEN array_to_string(i.caracteristicas, ', ') ~* '(climatizad|ar.condicionado)' THEN 'so ar-condicionado'
       END
 WHERE coalesce(i.mobilia, '') = ''
   AND array_to_string(i.caracteristicas, ', ') ~* '(mobiliad|climatizad|ar.condicionado)';

COMMIT;

WITH n AS (SELECT * FROM imoveis
            WHERE nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)
              AND NOT coalesce(e_parceiro, false))
SELECT 'dos que a Nay oferece' AS o,
       count(*) FILTER (WHERE coalesce(array_length(caracteristicas, 1), 0) > 0)::text AS com_caracteristicas,
       count(*) FILTER (WHERE coalesce(mobilia, '') <> '')::text AS com_mobilia,
       count(*)::text AS total
  FROM n;
