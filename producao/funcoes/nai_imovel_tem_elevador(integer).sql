CREATE OR REPLACE FUNCTION public.nai_imovel_tem_elevador(p_codigo integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM imovel_ficha f WHERE f.codigo = i.codigo
                  AND (array_to_string(f.caracteristicas_condominio, ' ') ~* 'elevador'
                       OR coalesce(f.campos->>'elevadores', '') ~ '[1-9]'))
      OR array_to_string(i.caracteristicas, ' ') ~* 'elevador' THEN true
    WHEN coalesce(nullif(i.extras->>'lances de escada', ''), '0') ~ '^[1-9]' THEN false
    WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN false
    ELSE NULL END
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$;
