CREATE OR REPLACE FUNCTION public.nai_imovel_disponivel(p_codigo integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                     FROM imoveis i WHERE i.codigo = p_codigo), false);
$function$
;
