CREATE OR REPLACE FUNCTION public.nay_bairro_parecido(p_bairro text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT i.bairro
    FROM imoveis i
   WHERE coalesce(i.disponivel, true)
     AND coalesce(i.bairro,'') <> ''
     AND similarity(nay_normalizar_lugar(i.bairro, true),
                    nay_normalizar_lugar(p_bairro, true)) > 0.4
   GROUP BY i.bairro
   ORDER BY max(similarity(nay_normalizar_lugar(i.bairro, true),
                           nay_normalizar_lugar(p_bairro, true))) DESC,
            count(*) DESC
   LIMIT 1;
$function$;
