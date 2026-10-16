CREATE OR REPLACE FUNCTION public.olx_cliente_buscar(p_filtros jsonb, p_excluir integer[] DEFAULT '{}'::integer[], p_limite integer DEFAULT 5)
 RETURNS TABLE(codigo integer, bairro text, condominio text, tipo text, quartos integer, preco numeric, perto boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH f AS (
    SELECT CASE WHEN lower(coalesce(p_filtros->>'finalidade', '')) LIKE 'vend%' THEN 'venda' ELSE 'locacao' END AS fin,
           lower(coalesce(p_filtros->>'tipo', '')) AS tipo,
           CASE WHEN coalesce(p_filtros->>'teto', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p_filtros->>'teto')::numeric END AS teto,
           CASE WHEN coalesce(p_filtros->>'quartos', '') ~ '^[0-9]+$' THEN (p_filtros->>'quartos')::int END AS quartos,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           lower(coalesce(p_filtros->>'mobilia', '')) AS mob,
           lower(coalesce(p_filtros->>'financiamento', '')) ~ '(financ|simula|aprovad)' AS financia
  ), pedidos AS (     -- os bairros que ela disse, no nome do cadastro ("pq 10" -> parque 10 de novembro)
    SELECT DISTINCT nay_normalizar_lugar(coalesce(nay_bairro_parecido(b), b), true) AS n
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros' ELSE '[]'::jsonb END) b
     WHERE btrim(b) <> ''
  ), perto AS (
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      FROM unnest(nai_bairros_ao_redor(ARRAY(SELECT n FROM pedidos))) x
     WHERE nay_normalizar_lugar(x, true) NOT IN (SELECT n FROM pedidos)
  ), c AS (
    SELECT i.codigo, i.bairro, i.condominio_nome, i.tipo, i.quartos, nay_normalizar_lugar(i.bairro, true) AS bn,
           CASE WHEN f.fin = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END AS p
      FROM core_imovel_busca i CROSS JOIN f
     WHERE i.ofertavel AND NOT coalesce(i.e_parceiro, false)
       AND CASE WHEN f.fin = 'venda' THEN i.de_venda ELSE i.de_locacao END
       AND CASE WHEN f.tipo IN ('', 'tanto_faz') THEN i.tipo IN ('apartamento', 'casa', 'casa_condominio', 'flat', 'cobertura')
                WHEN f.tipo = 'casa' THEN i.tipo IN ('casa', 'casa_condominio')
                ELSE i.tipo = f.tipo END
       AND (f.quartos IS NULL OR coalesce(i.quartos, 0) >= f.quartos - CASE WHEN f.menos THEN 1 ELSE 0 END)
       AND (f.mob NOT IN ('mobiliado', 'semi') OR i.mobilia = f.mob)
       AND NOT (i.codigo = ANY (coalesce(p_excluir, '{}')))
       -- quem vai financiar não recebe imóvel que não aceita financiamento (a regra dos pedidos dos grupos, 371)
       AND NOT (f.fin = 'venda' AND f.financia AND EXISTS (
             SELECT 1 FROM imoveis x WHERE x.codigo = i.codigo AND lower(coalesce(x.extras->>'aceita financiamento', '')) LIKE 'n%'))
  )
  SELECT c.codigo, c.bairro, c.condominio_nome, c.tipo, c.quartos, c.p, (c.bn IN (SELECT n FROM perto))
    FROM c CROSS JOIN f
   WHERE c.p > 0
     AND (f.teto IS NULL OR c.p BETWEEN f.teto * 0.75 AND f.teto * 1.10)
     AND (NOT EXISTS (SELECT 1 FROM pedidos) OR c.bn IN (SELECT n FROM pedidos) OR c.bn IN (SELECT n FROM perto))
   ORDER BY (c.bn IN (SELECT n FROM perto)), abs(c.p - coalesce(f.teto, c.p)), c.codigo
   LIMIT least(greatest(coalesce(p_limite, 5), 1), 10)
$function$;
