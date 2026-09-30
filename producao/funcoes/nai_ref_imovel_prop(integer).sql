CREATE OR REPLACE FUNCTION public.nai_ref_imovel_prop(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN nai_condominio_ok(i.condominio_nome) IS NOT NULL THEN 'no seu imóvel do ' || nai_condominio_ok(i.condominio_nome)
    WHEN coalesce(i.bairro, '') <> '' THEN 'no seu imóvel no ' || i.bairro
    ELSE 'no seu imóvel' END
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$;
