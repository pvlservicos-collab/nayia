CREATE OR REPLACE FUNCTION public.ia_uso_registrar(p_no text, p_modelo text, p_entrada integer, p_cache integer, p_saida integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO privado.ia_uso (no, modelo, tokens_entrada, tokens_cache, tokens_saida, custo_usd)
  SELECT left(p_no, 60), left(p_modelo, 80), p_entrada, p_cache, p_saida,
         CASE WHEN p.modelo IS NULL OR p.entrada IS NULL THEN NULL
              ELSE (greatest(coalesce(p_entrada, 0) - coalesce(p_cache, 0), 0) * p.entrada
                    + coalesce(p_cache, 0) * coalesce(p.entrada_cache, p.entrada)
                    + coalesce(p_saida, 0) * coalesce(p.saida, 0)) / 1000000.0 END
    FROM (SELECT 1) x LEFT JOIN privado.ia_preco p ON p.modelo = p_modelo
$function$;
