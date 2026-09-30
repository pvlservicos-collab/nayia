CREATE OR REPLACE FUNCTION public.nai_ficha_caracteristicas(p_codigo integer)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(array_agg(DISTINCT btrim(c)) FILTER (WHERE btrim(c) <> ''), '{}')
    FROM imoveis i
    LEFT JOIN imovel_ficha f ON f.codigo = i.codigo AND f.encontrado
    CROSS JOIN LATERAL unnest(
      coalesce(i.caracteristicas, '{}')
      || coalesce(string_to_array(i.extras->>'caracteristicas', ','), '{}')
      || coalesce(f.caracteristicas_imovel, '{}')
      || coalesce(f.caracteristicas_condominio, '{}')) c
   WHERE i.codigo = p_codigo;
$function$
;
