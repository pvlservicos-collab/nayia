CREATE OR REPLACE FUNCTION public.nai_imoveis_pedidos(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE COST 5000
AS $function$
  WITH t AS (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s),

  -- A CHAMADA CARA, UMA VEZ SO. Era isto que rodava 141 vezes.
  alvo AS MATERIALIZED (
    SELECT nai_imovel_pelo_condominio(p_texto, p_telefone) AS cods
  ),

  -- os codigos que ele escreveu, e que existem no catalogo
  por_codigo AS (
    SELECT x::int AS c, strpos(coalesce(p_texto, ''), x) AS pos
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
     WHERE x ~ '^[0-9]{3,5}$'
       AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = x)
  ),

  -- e os que ele chamou pelo nome do condominio
  por_nome AS (
    SELECT unnest(v.codigos) AS c,
           coalesce(nullif(strpos(t.s, lower(unaccent(v.nucleo))), 0), 9999) AS pos
      FROM vw_condominio_som v, t, alvo a
     WHERE a.cods IS NOT NULL
       AND v.codigos && a.cods
  )

  SELECT coalesce((
    SELECT array_agg(c ORDER BY pos, c)
      FROM (SELECT c, min(pos) AS pos
              FROM (SELECT * FROM por_codigo UNION ALL SELECT * FROM por_nome) u
             GROUP BY c) z), '{}');
$function$
;
