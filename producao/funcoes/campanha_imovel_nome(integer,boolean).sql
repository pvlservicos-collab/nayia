CREATE OR REPLACE FUNCTION public.campanha_imovel_nome(p_codigo integer, p_seu boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN split_part(tipo, ' ', 1) IN ('casa', 'cobertura', 'sala', 'loja', 'kitnet', 'quitinete', 'chácara', 'chacara',
                                                'área', 'area', 'fazenda', 'granja')
              THEN CASE WHEN p_seu THEN 'a sua ' ELSE 'a ' END ELSE CASE WHEN p_seu THEN 'o seu ' ELSE 'o ' END END
         || tipo || coalesce(' no ' || campanha_condominio(p_codigo), CASE WHEN campanha_no_bairro(p_codigo) <> '' THEN ' ' || campanha_no_bairro(p_codigo) ELSE '' END)
    FROM (SELECT lower(coalesce(nullif(btrim(tipo), ''), 'imóvel')) AS tipo FROM imoveis WHERE codigo = p_codigo) i
$function$;
