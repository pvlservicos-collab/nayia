-- =====================================================================
-- 148 — O DISPARO POR FAIXA (28/09/2026)
--
-- Tel: "quero mais uma função lá no enviar imóveis, enviar intervalo de
-- imóveis, aí eu posso selecionar uma faixa de renda, bairro ou imobiliário e
-- o sistema vai achar e marcar os imóveis para mim confirmar visualmente e aí
-- clico em enviar e ele envia".
--
-- A BUSCA MORA AQUI, NÃO NA LISTA DO SITE: a mobília só existe em `imoveis`,
-- que o usuário de leitura do site não enxerga. E aqui ela sai com as mesmas
-- paredes do envio: só imóvel nosso, disponível e no mercado -- o que a tela
-- marca é o que a caixa de saída aceita mandar.
--
-- Quem chama é o `nay_disparo` (o CRM), que só EXECUTA as funções do disparo.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION nai_disparo_buscar(
  p_finalidade text,     -- 'aluguel' | 'venda' | NULL (tanto faz)
  p_vmin       numeric,
  p_vmax       numeric,
  p_bairro     text,
  p_mobilia    text,     -- 'mobiliado' | 'semi' | NULL
  p_tipo       text,     -- começo do tipo: 'Apartamento', 'Casa'... | NULL
  p_quartos    integer,  -- no mínimo | NULL
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
           nullif(btrim(coalesce(p_bairro, '')), '') AS bairro,
           nullif(btrim(lower(coalesce(p_mobilia, ''))), '') AS mob,
           nullif(btrim(coalesce(p_tipo, '')), '') AS tipo
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
     -- a finalidade, e a faixa de valor NA COLUNA DELA (sem finalidade: um dos
     -- dois preços cabe inteiro na faixa)
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
     -- o bairro do jeito que a Nay compara ("pq dez" acha Parque 10 de Novembro)
     AND (f.bairro IS NULL
          OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(f.bairro, true) || '%')
     AND (f.mob IS NULL
          OR (f.mob = 'mobiliado' AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'mobiliad%')
          OR (f.mob = 'semi' AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'semi%'))
     AND (f.tipo IS NULL OR i.tipo ILIKE f.tipo || '%')
     AND (p_quartos IS NULL OR coalesce(i.quartos, 0) >= p_quartos)
   ORDER BY CASE WHEN f.fin = 'venda' THEN i.valor_venda
                 ELSE coalesce(nullif(i.valor_aluguel, 0), i.valor_venda) END ASC NULLS LAST,
            i.codigo DESC
   LIMIT least(greatest(coalesce(p_limite, 60), 1), 100);
$fn$;

REVOKE EXECUTE ON FUNCTION nai_disparo_buscar(text, numeric, numeric, text, text, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_disparo_buscar(text, numeric, numeric, text, text, text, integer, integer) TO nay_disparo;

COMMIT;
