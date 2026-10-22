-- 475e: com a raspagem DIÁRIA da OLX (scripts/raspar_olx_diario.sh, 22/10/2026), a busca do cliente só usa o anúncio
-- visto nos últimos 10 dias (era 30): o anúncio que saiu da OLX para de ser atualizado e some da busca.

BEGIN;

CREATE OR REPLACE FUNCTION public.busca_olx_candidatos(p_filtros jsonb, p_excluir bigint[] DEFAULT '{}'::bigint[], p_limite integer DEFAULT 5)
 RETURNS TABLE(olx_id bigint, titulo text, url text, preco numeric, preco_texto text, bairro text, quartos integer, subtipo text, tipo_negocio text, anunciante text, telefones text[], fotos text[], descricao text, nota integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH f AS (
    SELECT lower(coalesce(p_filtros->>'finalidade', '')) AS fin, lower(coalesce(p_filtros->>'tipo', '')) AS tipo,
           nullif(p_filtros->>'teto', '')::numeric AS teto, nullif(p_filtros->>'quartos', '')::int AS q,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           coalesce(p_filtros->>'qualquer_bairro', '') = 'true' AS qualquer
  ), pedidos AS (
    SELECT DISTINCT nay_normalizar_lugar(coalesce(nay_bairro_parecido(b), b), true) AS n
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros' ELSE '[]'::jsonb END) b
  ), cand AS (
    SELECT DISTINCT ON (a.olx_id) a.*
      FROM scrap_anuncio a, f
     WHERE cardinality(a.telefones) > 0
       AND a.coletado_em > now() - interval '10 days'   -- 475e: a raspagem é diária; o que sumiu da OLX deixa de vir
       AND NOT (a.olx_id = ANY (p_excluir))
       AND (f.fin = '' OR (f.fin LIKE 'loca%' AND a.tipo_negocio ILIKE 'Aluguel%') OR (f.fin LIKE 'vend%' AND a.tipo_negocio ILIKE 'Venda%'))
       AND (f.tipo = ''
            OR (f.tipo ~ 'condom' AND a.tipo_negocio ILIKE '%condom%')
            OR (f.tipo !~ 'condom' AND f.tipo ~ 'casa' AND a.categoria = 'Casas')
            OR (f.tipo ~ 'apart' AND a.categoria = 'Apartamentos'))
       AND (f.teto IS NULL OR a.preco BETWEEN f.teto * 0.8 AND f.teto * 1.1)
       AND (f.q IS NULL OR a.quartos BETWEEN f.q - CASE WHEN f.menos THEN 1 ELSE 0 END AND f.q + 1)
       AND (f.qualquer OR NOT EXISTS (SELECT 1 FROM pedidos)
            OR nay_normalizar_lugar(a.bairro, true) IN (SELECT n FROM pedidos))
       AND coalesce(a.anunciante, '') !~* '(imob ?easy|f ?v sobreira)'
     ORDER BY a.olx_id, a.coletado_em DESC
  )
  SELECT c.olx_id, c.titulo, c.url, c.preco, c.preco_texto, c.bairro, c.quartos, c.subtipo, c.tipo_negocio, c.anunciante,
         c.telefones, c.fotos, left(c.descricao, 1500),
         (100 - CASE WHEN f.teto IS NULL THEN 0 ELSE least(30, round(abs(c.preco - f.teto) / f.teto * 100)::int) END
              - CASE WHEN f.q IS NOT NULL AND c.quartos <> f.q THEN 10 ELSE 0 END)::int AS nota
    FROM cand c, f
   ORDER BY 14 DESC, c.data_olx DESC NULLS LAST
   LIMIT greatest(p_limite, 1);
$function$;;

COMMIT;
