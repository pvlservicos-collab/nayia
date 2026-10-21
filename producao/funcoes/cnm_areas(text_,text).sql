CREATE OR REPLACE FUNCTION public.cnm_areas(p_itens text[], p_lista text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH x AS (SELECT cnm_norm(t) AS k, n FROM unnest(coalesce(p_itens, '{}')) WITH ORDINALITY u(t, n)),
       m AS (SELECT a.nome, x.n FROM x JOIN privado.cnm_area a ON a.lista = p_lista AND a.chave = x.k
             UNION ALL
             SELECT p.nome, x.n FROM x JOIN privado.cnm_area_apelido p ON p.lista = p_lista AND p.chave = x.k)
  SELECT coalesce(array_agg(z.nome ORDER BY z.n, z.nome), '{}')
    FROM (SELECT nome, min(n) AS n FROM m GROUP BY nome) z
$function$;
