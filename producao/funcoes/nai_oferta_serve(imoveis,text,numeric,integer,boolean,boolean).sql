CREATE OR REPLACE FUNCTION public.nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric, p_quartos integer, p_sem boolean, p_com boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND coalesce(i.valor_aluguel, 0) > 0
     -- A FAIXA EM VOLTA DO TETO (Tel, 16/09): "ele deu o teto de 4.200 e ela
     -- tinha que seguir aquela regra de enviar 15% a menos e 10% a mais em
     -- cima do teto que ele passou".
     --
     -- Ate aqui o teto era so um limite para cima, e a lista sai ordenada pelo
     -- mais barato: para um cliente de 4.200 ela ofereceu 2.500, 2.500 e
     -- 2.600. Nao era erro de codigo -- era o que estava escrito --, mas
     -- mostra imovel de outro padrao.
     --
     -- Medido no catalogo: com teto 4.200 havia 21 candidatos ate o teto e
     -- ficam 8 na faixa; e entram os de ate 4.620, que antes nao apareciam.
     -- Os percentuais estao em `nai_config`: faixa_abaixo_pct e faixa_acima_pct.
     AND (p_teto IS NULL
          OR i.valor_aluguel BETWEEN p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                                 AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
     AND (p_quartos IS NULL OR p_quartos = 0 OR i.quartos = p_quartos)
     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR (coalesce(i.mobilia, '') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
                        OR coalesce(i.descricao, '') ~* '(mobiliad|modulad|planejad)'))
     AND NOT EXISTS (SELECT 1 FROM envios e
                      WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                        AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8));
$function$;
