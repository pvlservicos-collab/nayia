-- =====================================================================
-- 150 — O DISPARO POR FAIXA COM VÁRIOS VALORES EM CADA FILTRO (28/09/2026)
--
-- Tel: "lá no enviar imóveis lá em cima eu quero poder selecionar mais de um
-- bairro, mais de uma informação de tudo, e quando eu começo a digitar desce a
-- lista também do nosso banco para só selecionar sem precisar digitar
-- certinho".
--
--   nai_disparo_buscar (nova assinatura): bairros, tipos, mobílias e quartos
--     viram LISTAS -- vale o imóvel que bate com qualquer um da lista. As
--     paredes são as mesmas da 148 (nosso, disponível, no mercado).
--   nai_disparo_opcoes(): o que existe no NOSSO banco para cada filtro, só do
--     que pode sair, com a contagem -- é a lista que desce enquanto ele digita.
--
-- A assinatura antiga (148, valores únicos) é APAGADA no fim: função com
-- assinatura nova no Postgres não substitui, cria outra ao lado.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION nai_disparo_buscar(
  p_finalidade text,       -- 'aluguel' | 'venda' | NULL (tanto faz)
  p_vmin       numeric,
  p_vmax       numeric,
  p_bairros    text[],     -- qualquer um deles | NULL/vazio = todos
  p_mobilias   text[],     -- 'mobiliado', 'semi' | NULL/vazio
  p_tipos      text[],     -- começo do tipo: 'Apartamento', 'Casa'... | NULL/vazio
  p_quartos    integer[],  -- exatos; 4 = 4 ou mais | NULL/vazio
  p_limite     integer DEFAULT 60)
RETURNS TABLE (codigo integer, titulo text, tipo text, bairro text, quartos integer, mobilia text,
               valor_venda numeric, valor_aluguel numeric, fotos integer, capa text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  WITH f AS (
    SELECT nullif(btrim(lower(coalesce(p_finalidade, ''))), '') AS fin,
           (SELECT array_agg(nay_normalizar_lugar(x, true)) FROM unnest(p_bairros) x WHERE btrim(x) <> '') AS bairros,
           (SELECT array_agg(lower(btrim(x))) FROM unnest(p_mobilias) x WHERE btrim(x) <> '') AS mobs,
           (SELECT array_agg(btrim(x)) FROM unnest(p_tipos) x WHERE btrim(x) <> '') AS tipos,
           (SELECT array_agg(x) FROM unnest(p_quartos) x WHERE x IS NOT NULL) AS qts
  )
  SELECT i.codigo,
         coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo, 'Imóvel ' || i.codigo),
         i.tipo, i.bairro, i.quartos, i.mobilia, i.valor_venda, i.valor_aluguel,
         (SELECT count(*) FROM imovel_fotos x WHERE x.codigo = i.codigo)::int,
         (SELECT x.url FROM imovel_fotos x WHERE x.codigo = i.codigo AND coalesce(x.url, '') <> ''
           ORDER BY x.e_capa DESC NULLS LAST, x.ordem NULLS LAST LIMIT 1)
    FROM imoveis i, f
   WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND nai_imovel_disponivel(i.codigo)
     AND (f.fin IS NULL
          OR (f.fin = 'aluguel' AND coalesce(i.valor_aluguel, 0) > 0)
          OR (f.fin = 'venda' AND coalesce(i.valor_venda, 0) > 0))
     AND (CASE f.fin
            WHEN 'aluguel' THEN (p_vmin IS NULL OR i.valor_aluguel >= p_vmin) AND (p_vmax IS NULL OR i.valor_aluguel <= p_vmax)
            WHEN 'venda'   THEN (p_vmin IS NULL OR i.valor_venda >= p_vmin) AND (p_vmax IS NULL OR i.valor_venda <= p_vmax)
            ELSE (p_vmin IS NULL AND p_vmax IS NULL)
              OR (nullif(i.valor_aluguel, 0) >= coalesce(p_vmin, 0) AND nullif(i.valor_aluguel, 0) <= coalesce(p_vmax, 1e12))
              OR (nullif(i.valor_venda, 0) >= coalesce(p_vmin, 0) AND nullif(i.valor_venda, 0) <= coalesce(p_vmax, 1e12))
          END)
     AND (f.bairros IS NULL OR EXISTS (
            SELECT 1 FROM unnest(f.bairros) b WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || b || '%'))
     AND (f.mobs IS NULL
          OR ('mobiliado' = ANY (f.mobs) AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'mobiliad%')
          OR ('semi' = ANY (f.mobs) AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'semi%'))
     AND (f.tipos IS NULL OR EXISTS (SELECT 1 FROM unnest(f.tipos) t WHERE i.tipo ILIKE t || '%'))
     AND (f.qts IS NULL OR coalesce(i.quartos, 0) = ANY (f.qts)
          OR (4 = ANY (f.qts) AND coalesce(i.quartos, 0) >= 4))
   ORDER BY CASE WHEN f.fin = 'venda' THEN i.valor_venda
                 ELSE coalesce(nullif(i.valor_aluguel, 0), i.valor_venda) END ASC NULLS LAST,
            i.codigo DESC
   LIMIT least(greatest(coalesce(p_limite, 60), 1), 100);
$fn$;

-- O que existe no nosso banco para cada filtro -- só do que pode sair.
CREATE OR REPLACE FUNCTION nai_disparo_opcoes()
RETURNS TABLE (campo text, valor text, n integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  WITH ok AS (
    SELECT i.* FROM imoveis i
     WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND nai_imovel_disponivel(i.codigo)
  )
  SELECT 'bairro', btrim(bairro), count(*)::int FROM ok WHERE coalesce(btrim(bairro), '') <> '' GROUP BY 2
  UNION ALL
  SELECT 'tipo', btrim(tipo), count(*)::int FROM ok WHERE coalesce(btrim(tipo), '') <> '' GROUP BY 2
  ORDER BY 1, 3 DESC, 2;
$fn$;

REVOKE EXECUTE ON FUNCTION nai_disparo_buscar(text, numeric, numeric, text[], text[], text[], integer[], integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_disparo_buscar(text, numeric, numeric, text[], text[], text[], integer[], integer) TO nay_disparo;
REVOKE EXECUTE ON FUNCTION nai_disparo_opcoes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_disparo_opcoes() TO nay_disparo;

COMMIT;

-- Depois do CRM novo no ar (ele chama a assinatura nova), a antiga sai:
--   DROP FUNCTION IF EXISTS nai_disparo_buscar(text, numeric, numeric, text, text, text, integer, integer);
