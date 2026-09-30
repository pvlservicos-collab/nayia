CREATE OR REPLACE FUNCTION public.nai_fala_e_dele(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (nai_cfg('pedido_ignora_oferta', 'sim') = 'sim' AND nai_oferece_imovel(coalesce(p_texto, '')))
      OR (nai_cfg('pedido_ignora_anuncio', 'sim') = 'sim' AND nai_e_anuncio_dele(p_texto));
$function$;
