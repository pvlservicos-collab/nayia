CREATE OR REPLACE FUNCTION public.nai_imovel_barrado(p_codigo integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = p_codigo
                    AND (coalesce(i.e_parceiro, false)
                         OR NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)));
$function$
;
