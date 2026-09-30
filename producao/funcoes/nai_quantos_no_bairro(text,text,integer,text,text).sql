CREATE OR REPLACE FUNCTION public.nai_quantos_no_bairro(p_bairro text, p_telefone text, p_quartos integer, p_negocio text, p_tipo text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT count(*)::int FROM imoveis i
   WHERE (nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(coalesce(p_bairro, ''), true) || '%'
          -- 206: conjunto e avenida contam os bairros deles
          OR i.bairro IN (SELECT unnest(nai_bairros_do_lugar(p_bairro))))
     AND nai_oferta_serve(i, coalesce(p_telefone, ''), NULL, p_quartos, false, false, p_negocio, p_tipo);
$function$;
