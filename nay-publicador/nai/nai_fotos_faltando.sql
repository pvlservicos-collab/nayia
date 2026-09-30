CREATE OR REPLACE FUNCTION public.nai_fotos_faltando(p_codigos integer[])
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(array_agg(i.codigo ORDER BY i.codigo), '{}')
    FROM imoveis i
   WHERE i.codigo = ANY (coalesce(p_codigos, '{}'))
     AND NOT coalesce(i.e_parceiro, false)
     AND coalesce(i.publicado_no_site, false)
     AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo);
$function$
;
