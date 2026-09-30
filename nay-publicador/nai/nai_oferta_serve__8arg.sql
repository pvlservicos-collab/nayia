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
     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR (coalesce(i.mobilia, '') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
                        OR coalesce(i.descricao, '') ~* '(mobiliad|modulad|planejad)'))
     AND NOT EXISTS (SELECT 1 FROM envios e
                      WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                        AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8));
$function$
;
