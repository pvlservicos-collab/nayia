CREATE OR REPLACE FUNCTION public.nai_nome_so_do_bairro(p_texto text, p_codigo integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  WITH t AS (SELECT ' ' || nay_normalizar_lugar(coalesce(p_texto, ''), true) || ' ' AS n),
  citados AS (
    SELECT DISTINCT b.nb
      FROM (SELECT DISTINCT nay_normalizar_lugar(x.bairro, true) AS nb
              FROM (SELECT DISTINCT bairro FROM imoveis WHERE coalesce(btrim(bairro), '') <> ''
                    UNION SELECT bairro FROM bairro_zona) x) b, t
     WHERE length(b.nb) >= 4 AND t.n LIKE '% ' || b.nb || ' %'
    -- 206: o conjunto que ele citou ("eldorado" nao e o Eldorado Park)
    UNION
    SELECT btrim((regexp_match(t.n, '(' || c.expressao || ')'))[1])
      FROM nai_lugar_conjunto c, t
     WHERE c.ativo AND t.n ~ c.expressao),
  palavras AS (
    SELECT DISTINCT w
      FROM imoveis i, t,
           regexp_split_to_table(nay_normalizar_lugar(coalesce(i.condominio_nome, ''), true), '\s+') w
     WHERE i.codigo = p_codigo AND length(w) >= 3 AND t.n LIKE '% ' || w || ' %')
  SELECT EXISTS (SELECT 1 FROM citados) AND EXISTS (SELECT 1 FROM palavras)
     AND NOT EXISTS (SELECT 1 FROM palavras p
                      WHERE NOT EXISTS (SELECT 1 FROM citados c WHERE ' ' || c.nb || ' ' LIKE '% ' || p.w || ' %'));
$function$;
