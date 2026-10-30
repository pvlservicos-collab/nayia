CREATE OR REPLACE FUNCTION public.nai_disparo_buscar(p_finalidade text, p_vmin numeric, p_vmax numeric, p_bairros text[], p_mobilias text[], p_tipos text[], p_quartos integer[], p_limite integer DEFAULT 60, p_parceiros_novos boolean DEFAULT false)
 RETURNS TABLE(codigo integer, titulo text, tipo text, bairro text, quartos integer, mobilia text, valor_venda numeric, valor_aluguel numeric, fotos integer, capa text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH f AS (
    SELECT nullif(btrim(lower(coalesce(p_finalidade, ''))), '') AS fin,
           (SELECT array_agg(nay_normalizar_lugar(x, true)) FROM unnest(p_bairros) x WHERE btrim(x) <> '') AS bairros,
           (SELECT array_agg(btrim(x)) FROM unnest(p_bairros) x WHERE btrim(x) <> '') AS lugares,
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
   WHERE ((nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
           AND NOT coalesce(i.e_parceiro, false)
           AND nai_imovel_disponivel(i.codigo))
          -- 531: o parceiro NOVO (não o antigo do site antigo), só quando a tela pede (o Enviar imóvel do 8595)
          OR (coalesce(p_parceiros_novos, false)
              AND i.e_parceiro AND i.status = 'Disponível'
              AND coalesce(i.disponivel, true) AND NOT coalesce(i.bloqueado, false)
              AND (coalesce(i.valor_aluguel, 0) > 0 OR coalesce(i.valor_venda, 0) > 0)
              AND coalesce(i.extras->>'parceiro_antigo', '') <> 'sim'))
     AND (f.fin IS NULL
          OR (f.fin = 'aluguel' AND coalesce(i.valor_aluguel, 0) > 0)
          OR (f.fin = 'venda' AND coalesce(i.valor_venda, 0) > 0))
     -- o preço continua firme: sem preço não cabe em faixa de preço
     AND (CASE f.fin
            WHEN 'aluguel' THEN (p_vmin IS NULL OR i.valor_aluguel >= p_vmin) AND (p_vmax IS NULL OR i.valor_aluguel <= p_vmax)
            WHEN 'venda'   THEN (p_vmin IS NULL OR i.valor_venda >= p_vmin) AND (p_vmax IS NULL OR i.valor_venda <= p_vmax)
            ELSE (p_vmin IS NULL AND p_vmax IS NULL)
              OR (nullif(i.valor_aluguel, 0) >= coalesce(p_vmin, 0) AND nullif(i.valor_aluguel, 0) <= coalesce(p_vmax, 1e12))
              OR (nullif(i.valor_venda, 0) >= coalesce(p_vmin, 0) AND nullif(i.valor_venda, 0) <= coalesce(p_vmax, 1e12))
          END)
     -- ONDE: bairro, e também conjunto e avenida (o mesmo da aba Imóveis, 229/231)
     AND (f.bairros IS NULL OR EXISTS (
            SELECT 1 FROM unnest(f.bairros) b WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || b || '%')
          OR i.bairro IN (SELECT unnest(nai_bairros_do_conjunto(x)) FROM unnest(f.lugares) x)
          OR EXISTS (SELECT 1 FROM imovel_lugar l
                      WHERE l.codigo = i.codigo AND (l.conjuntos && f.lugares OR l.avenidas && f.lugares)))
     -- MOBÍLIA: o que não sabemos não é escondido (Pedro, 01/10). O campo
     -- PREENCHIDO manda: quem pede "Mobiliado" não recebe o que o cadastro diz
     -- ser semi -- isso não é flexibilidade, é o filtro deixar de filtrar. A
     -- dúvida só entra quando o campo está VAZIO; aí quem olha a tela decide
     -- (a coluna mobília aparece vazia na lista).
     AND (f.mobs IS NULL
          OR coalesce(btrim(i.mobilia), '') = ''
          OR ('mobiliado' = ANY (f.mobs) AND nay_mobilia_nivel(i.mobilia) = 'mobiliado')
          OR ('semi' = ANY (f.mobs) AND nay_mobilia_nivel(i.mobilia) = 'semi'))
     -- TIPO e QUARTOS: idem, sem o dado não descarta
     AND (f.tipos IS NULL OR coalesce(btrim(i.tipo), '') = ''
          OR EXISTS (SELECT 1 FROM unnest(f.tipos) t WHERE i.tipo ILIKE t || '%'))
     AND (f.qts IS NULL OR i.quartos IS NULL
          OR coalesce(i.quartos, 0) = ANY (f.qts)
          OR (4 = ANY (f.qts) AND coalesce(i.quartos, 0) >= 4))
   ORDER BY CASE WHEN f.fin = 'venda' THEN i.valor_venda
                 ELSE coalesce(nullif(i.valor_aluguel, 0), i.valor_venda) END ASC NULLS LAST,
            i.codigo DESC
   LIMIT least(greatest(coalesce(p_limite, 60), 1), 100);
$function$;
