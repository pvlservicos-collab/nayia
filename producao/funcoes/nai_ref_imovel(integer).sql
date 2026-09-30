CREATE OR REPLACE FUNCTION public.nai_ref_imovel(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(nai_condominio_ok(i.condominio_nome),
                  coalesce(i.tipo, 'imóvel') || CASE WHEN coalesce(i.bairro,'') <> '' THEN ' no ' || i.bairro ELSE '' END)
         || ', código ' || i.codigo
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$;
