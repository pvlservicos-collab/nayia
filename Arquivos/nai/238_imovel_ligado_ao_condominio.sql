-- 238 (30/09/2026): IMÓVEL OFERECIDO LIGADO AO CADASTRO DO CONDOMÍNIO.
-- Da revisão pedida pelo Pedro ("tá faltando informação, tanto dos imóveis quanto dos
-- condomínios"). 82 dos 277 imóveis que a Nay oferece tinham o nome do condomínio
-- escrito mas sem ligação (condo_id) com o cadastro de condomínios -- e sem a ligação
-- o imóvel não herda a ficha do condomínio, não entra no filtro por condomínio do site
-- e não aparece na contagem dele.
--   1. nome igual ao de um condomínio cadastrado (sem acento, sem caixa): liga.
--   2. condomínio de verdade que ainda não estava no cadastro: cadastra (nome e bairro
--      do próprio imóvel) e liga. "Casa", "Apartamento", "Sala/Andar" e afins são o
--      TIPO escrito no lugar do nome (imóvel de rua): esses ficam sem condomínio.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE alvo ON COMMIT DROP AS
SELECT i.codigo, btrim(i.condominio_nome) AS nome, lower(unaccent(btrim(i.condominio_nome))) AS chave, nullif(btrim(i.bairro), '') AS bairro
  FROM imoveis i
 WHERE NOT coalesce(i.e_parceiro, false) AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
   AND i.condo_id IS NULL AND coalesce(btrim(i.condominio_nome), '') <> ''
   AND lower(unaccent(btrim(i.condominio_nome))) !~ '^(casa|casa de condominio|apartamento|apartamento em via publica|sala/andar|sala|loja|loja/ponto|galpao/deposito|lote|lote em condominio|flat|cobertura|predio|terreno|condominio nao identificado)$';

-- 2. os que faltam no cadastro
WITH novos AS (
  SELECT min(a.nome) AS nome, a.chave, mode() WITHIN GROUP (ORDER BY a.bairro) AS bairro,
         row_number() OVER (ORDER BY a.chave) AS n
    FROM alvo a
   WHERE NOT EXISTS (SELECT 1 FROM condominios c WHERE lower(unaccent(btrim(c.nome))) = a.chave)
   GROUP BY a.chave
)
INSERT INTO condominios (id, nome, bairro)
SELECT (SELECT max(id) FROM condominios) + n, nome, bairro FROM novos;

-- 1. liga pelo nome
UPDATE imoveis i
   SET condo_id = (SELECT min(c.id) FROM condominios c WHERE lower(unaccent(btrim(c.nome))) = a.chave)
  FROM alvo a
 WHERE a.codigo = i.codigo
   AND EXISTS (SELECT 1 FROM condominios c WHERE lower(unaccent(btrim(c.nome))) = a.chave);
COMMIT;
