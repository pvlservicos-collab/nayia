CREATE OR REPLACE FUNCTION public.olx_cliente_buscar(p_filtros jsonb, p_excluir integer[] DEFAULT '{}'::integer[], p_limite integer DEFAULT 5)
 RETURNS TABLE(codigo integer, bairro text, condominio text, tipo text, quartos integer, preco numeric, perto boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH f0 AS (
    SELECT CASE WHEN lower(coalesce(p_filtros->>'finalidade', '')) LIKE 'vend%' THEN 'venda' ELSE 'locacao' END AS fin,
           lower(unaccent(coalesce(p_filtros->>'tipo', ''))) AS tipo,
           CASE WHEN coalesce(p_filtros->>'teto', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p_filtros->>'teto')::numeric END AS teto,
           CASE WHEN coalesce(p_filtros->>'quartos', '') ~ '^[0-9]+$' THEN (p_filtros->>'quartos')::int END AS quartos,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           lower(coalesce(p_filtros->>'mobilia', '')) AS mob,
           lower(coalesce(p_filtros->>'financiamento', '')) ~ '(financ|simula|aprovad)' AS financia,
           -- 394: "não serve escada" (a pergunta da venda até 500 mil)
           coalesce(p_filtros->>'aceita_escada', '') = 'false' AS sem_escada
  ), f AS (
    SELECT f0.*, f0.tipo IN ('galpao', 'predio', 'sala', 'loja', 'terreno', 'comercial') AS comercial FROM f0
  ), pedidos AS (     -- os bairros que ela disse, no nome do cadastro ("pq 10" -> parque 10 de novembro)
    -- 388: o nome do cadastro parecido; senão o bairro do conjunto/lugar (nai_bairros_do_lugar: "Vieiralves")
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      -- 394: "qualquer bairro" vale (antes os bairros ditos antes continuavam mandando)
      FROM jsonb_array_elements_text(CASE WHEN coalesce(p_filtros->>'qualquer_bairro', '') = 'true' THEN '[]'::jsonb
                                          WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros'
                                          ELSE '[]'::jsonb END) b
      CROSS JOIN LATERAL unnest(coalesce(CASE WHEN nay_bairro_parecido(b) IS NOT NULL THEN ARRAY[nay_bairro_parecido(b)] END,
                                         nullif(nai_bairros_do_lugar('no ' || b), '{}'), ARRAY[b])) x
     WHERE btrim(b) <> ''
  ), perto AS (
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      FROM unnest(nai_bairros_ao_redor(ARRAY(SELECT n FROM pedidos))) x
     WHERE nay_normalizar_lugar(x, true) NOT IN (SELECT n FROM pedidos)
  ), c AS (
    SELECT i.codigo, i.bairro, i.condominio_nome, i.tipo, i.quartos, nay_normalizar_lugar(i.bairro, true) AS bn,
           CASE WHEN f.fin = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END AS p
      FROM core_imovel_busca i CROSS JOIN f
      LEFT JOIN imoveis x ON x.codigo = i.codigo
     -- 400: o imóvel de parceiro Disponível vai ao cliente final (o nay-olx só manda aceita_parceiro a quem não é corretor)
     WHERE (i.ofertavel
            OR (coalesce(p_filtros->>'aceita_parceiro', '') = 'true' AND coalesce(i.e_parceiro, false)
                AND x.status = 'Disponível' AND coalesce(x.disponivel, true) AND NOT coalesce(x.bloqueado, false)))
       AND CASE WHEN f.fin = 'venda' THEN i.de_venda ELSE i.de_locacao END
       AND CASE WHEN f.tipo IN ('', 'tanto_faz') THEN i.tipo IN ('apartamento', 'casa', 'casa_condominio', 'flat', 'cobertura')
                WHEN f.tipo = 'casa' THEN i.tipo IN ('casa', 'casa_condominio')
                -- 392: galpão e prédio moram em 'outro' na busca; o cadastro diz qual
                WHEN f.tipo = 'galpao' THEN i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) LIKE 'galp%'
                WHEN f.tipo = 'predio' THEN i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) LIKE 'predio%'
                WHEN f.tipo = 'comercial' THEN i.tipo IN ('sala', 'loja')
                                          OR (i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) ~ '^(galp|predio)')
                ELSE i.tipo = f.tipo END
       AND (f.comercial OR f.quartos IS NULL OR coalesce(i.quartos, 0) >= f.quartos - CASE WHEN f.menos THEN 1 ELSE 0 END)
       -- 388: "modulados e ar" (semi) também aceita o mobiliado; mobiliado é só mobiliado. 392: no comercial não conta
       -- 394: mobília é coisa de LOCAÇÃO (o Felipe, venda até 900 mil "mobiliada": a busca voltava vazia)
       AND (f.comercial OR f.fin = 'venda' OR f.mob NOT IN ('mobiliado', 'semi') OR i.mobilia = f.mob
            OR (f.mob = 'semi' AND i.mobilia = 'mobiliado'))
       AND NOT (f.sem_escada AND i.tipo IN ('apartamento', 'cobertura', 'flat') AND nai_imovel_tem_elevador(i.codigo) IS FALSE)
       AND NOT (i.codigo = ANY (coalesce(p_excluir, '{}')))
       -- quem vai financiar não recebe imóvel que não aceita financiamento (a regra dos pedidos dos grupos, 371)
       AND NOT (f.fin = 'venda' AND f.financia AND lower(coalesce(x.extras->>'aceita financiamento', '')) LIKE 'n%')
  )
  SELECT c.codigo, c.bairro, c.condominio_nome, c.tipo, c.quartos, c.p, (c.bn IN (SELECT n FROM perto))
    FROM c CROSS JOIN f
   WHERE c.p > 0
     -- 394: a faixa firme da Parceria (225): 20% abaixo, 10% acima
     AND (f.teto IS NULL OR c.p BETWEEN f.teto * 0.80 AND f.teto * 1.10)
     AND (NOT EXISTS (SELECT 1 FROM pedidos) OR c.bn IN (SELECT n FROM pedidos) OR c.bn IN (SELECT n FROM perto))
   ORDER BY (c.bn IN (SELECT n FROM perto)), abs(c.p - coalesce(f.teto, c.p)), c.codigo
   LIMIT least(greatest(coalesce(p_limite, 5), 1), 10)
$function$;
