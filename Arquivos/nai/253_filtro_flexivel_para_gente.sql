-- 253 (01/10/2026): O FILTRO DE GENTE É FLEXÍVEL; O DA NAY, NÃO.
-- Pedro: "quero flexibilidade na hora de buscar imóveis manualmente, só não
-- quando a Nay for buscar... em todos os lugares onde podemos buscar
-- manualmente hoje".
--
-- O QUE MOSTROU O PROBLEMA: o Solar da Praia de locação a R$ 8.000 (3647) não
-- aparecia na tela Enviar imóvel com "Mobiliado" marcado, porque o campo
-- mobília dele está VAZIO -- e o filtro exigia a palavra no campo. Ao mesmo
-- tempo, a busca da NAY oferecia o mesmo imóvel como mobiliado, porque ela
-- adivinhava pela descrição ("armários planejados"). As duas discordavam, e
-- quem causava isso era a falta do dado.
--
-- A REGRA NOVA, nas duas pontas:
--
--   GENTE buscando (nai_disparo_buscar, a tela Enviar imóvel do site e do CRM)
--   -> o filtro NUNCA ESCONDE O QUE NÃO SABEMOS. Marcar "Mobiliado" passa a
--      trazer também o imóvel sem mobília informada (e o que a descrição sugere)
--      -- quem está olhando vê a coluna vazia e decide. O mesmo para quartos e
--      tipo: imóvel sem o dado não é descartado. "Onde" passa a entender
--      conjunto e avenida, como a aba Imóveis já entende.
--      O VALOR continua firme: imóvel sem preço não cabe numa faixa de preço, e
--      trazê-lo só sujaria a tela.
--
--   A NAY buscando (nai_oferta_serve, as duas assinaturas)
--   -> fica ESTRITA. Ela só chama de mobiliado o que o campo mobília diz. Antes
--      "armários planejados" e "ar-condicionado" na descrição faziam dela
--      mobiliado, e ela prometia ao corretor uma coisa que não sabemos. Armário
--      planejado não é móvel.
--      Medido hoje: dos 42 imóveis de locação que ela oferece, 10 estão com a
--      mobília em branco, e exatamente 1 (o 3647) entrava pela descrição.
--
-- Nada aqui muda o que a Nay oferece por preço, bairro, tipo ou quartos.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ---------------------------------------------------------------- GENTE
CREATE OR REPLACE FUNCTION public.nai_disparo_buscar(p_finalidade text, p_vmin numeric, p_vmax numeric, p_bairros text[], p_mobilias text[], p_tipos text[], p_quartos integer[], p_limite integer DEFAULT 60)
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
   WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND nai_imovel_disponivel(i.codigo)
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
          OR ('mobiliado' = ANY (f.mobs) AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'mobiliad%')
          OR ('semi' = ANY (f.mobs) AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'semi%'))
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
COMMENT ON FUNCTION nai_disparo_buscar(text, numeric, numeric, text[], text[], text[], integer[], integer) IS
  '253: a busca de GENTE (tela Enviar imóvel). Flexível: não esconde imóvel por falta do dado filtrado (mobília, tipo, quartos) e entende conjunto/avenida. O preço continua firme.';

-- ---------------------------------------------------------------- A NAY
-- as duas assinaturas: só o campo mobília conta, nunca a descrição
CREATE OR REPLACE FUNCTION public.nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric, p_quartos integer, p_sem boolean, p_com boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nai_oferta_serve(i, p_telefone, p_teto, p_quartos, p_sem, p_com, NULL::text, NULL::text);
$function$;

CREATE OR REPLACE FUNCTION public.nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric, p_quartos integer, p_sem boolean, p_com boolean, p_negocio text, p_tipo text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND (p_tipo IS NULL OR i.tipo ILIKE p_tipo)
     -- A FINALIDADE manda no preco que vale. 'venda' olha valor_venda,
     -- 'locacao' olha valor_aluguel, e sem saber vale qualquer um dos dois --
     -- o card mostra os dois preços de qualquer jeito.
     AND CASE coalesce(p_negocio, 'ambos')
           WHEN 'venda'   THEN coalesce(i.valor_venda, 0) > 0
                           AND (p_teto IS NULL OR i.valor_venda BETWEEN
                                  p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                              AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
           WHEN 'locacao' THEN coalesce(i.valor_aluguel, 0) > 0
                           AND (p_teto IS NULL OR i.valor_aluguel BETWEEN
                                  p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                              AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
           ELSE (coalesce(i.valor_aluguel, 0) > 0
                 AND (p_teto IS NULL OR i.valor_aluguel BETWEEN
                        p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                    AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)))
             OR (coalesce(i.valor_venda, 0) > 0
                 AND (p_teto IS NULL OR i.valor_venda BETWEEN
                        p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                    AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)))
         END
     AND (p_quartos IS NULL OR p_quartos = 0 OR i.quartos = p_quartos)
     -- 253: SÓ O CAMPO MOBÍLIA. A Nay não adivinha pela descrição: "armários
     -- planejados" não é mobiliado, e prometer isso ao corretor é pior do que
     -- não oferecer. Quem quer o benefício da dúvida é gente, na tela de
     -- Enviar imóvel (nai_disparo_buscar).
     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR coalesce(i.mobilia, '') ~* 'mobiliad')
     AND NOT EXISTS (SELECT 1 FROM envios e
                      WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                        AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8));
$function$;
COMMENT ON FUNCTION nai_oferta_serve(imoveis, text, numeric, integer, boolean, boolean, text, text) IS
  '253: a porta da oferta da NAY. Estrita: mobiliado é o que o campo mobília diz, nunca a descrição.';
COMMIT;
