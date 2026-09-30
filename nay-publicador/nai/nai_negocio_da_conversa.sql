CREATE OR REPLACE FUNCTION public.nai_negocio_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 190: a conversa guarda o negócio por 3 dias. Ordem: o que ele disse
  -- AGORA (palavra, depois valor), o que ele disse antes (idem), e por
  -- último a finalidade do que ele já recebeu. Muda só com pedido claro:
  -- "venda", "comprar", "R$ 700 mil".
  SELECT coalesce(
    nai_negocio_das_falas(array[coalesce(p_texto, '')]),
    nai_negocio_das_falas(coalesce((SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
         SELECT t.id, t.texto FROM nai_turno t
          WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
            AND t.criado_em > greatest(now() - interval '3 days',
                                       coalesce((SELECT k.zerado_em FROM nai_contato k WHERE k.id = p_contato), '-infinity'))
          ORDER BY t.id DESC LIMIT 40) x), '{}'::text[])),
    nai_negocio_do_que_recebeu(p_contato));
$function$
;
