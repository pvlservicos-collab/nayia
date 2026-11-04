CREATE OR REPLACE FUNCTION public.campanha_condominio(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN length(c) >= 3 AND EXISTS (
                     SELECT 1 FROM regexp_split_to_table(lower(unaccent(c)), '[^a-z0-9]+') w
                      WHERE w <> '' AND w NOT IN ('casa', 'casas', 'apartamento', 'apto', 'ap', 'sala', 'loja', 'terreno', 'lote',
                                                  'kitnet', 'flat', 'cobertura', 'condominio', 'residencial', 'edificio',
                                                  'predio', 'galpao', 'ponto', 'imovel', 'sem', 'nao', 'na', 'n', 'a', 'de',
                                                  'do', 'da', 'em', 'comercial', 'outro', 'outros'))
              THEN CASE WHEN c = lower(c) THEN initcap(c) ELSE c END END
    FROM (SELECT btrim(regexp_replace(coalesce(condominio_nome, ''), '\s+', ' ', 'g')) AS c FROM imoveis WHERE codigo = p_codigo) x
$function$;
