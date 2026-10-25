CREATE OR REPLACE FUNCTION public.site_biblioteca(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'privado', 'public'
AS $function$
  WITH f AS (
    SELECT nullif(p->>'nay', '') AS nay, nullif(p->>'resultado', '') AS res, nullif(p->>'confianca', '') AS conf,
           nullif(p->>'fonte', '') AS fonte, nullif(p->>'tipo', '') AS tipo,
           nullif(btrim(coalesce(p->>'busca', '')), '') AS busca,
           nullif(p->>'de', '')::date AS de, nullif(p->>'ate', '')::date AS ate,
           greatest(1, least(coalesce((p->>'limite')::int, 50), 200)) AS lim,
           greatest(0, coalesce((p->>'pagina')::int, 0)) AS pag),
  b AS (
    SELECT x.* FROM privado.conversa_biblioteca x, f
     WHERE (f.nay IS NULL OR x.nay = f.nay) AND (f.res IS NULL OR x.resultado = f.res)
       AND (f.conf IS NULL OR x.confianca = f.conf) AND (f.fonte IS NULL OR f.fonte = ANY (x.fontes))
       AND (f.tipo IS NULL OR f.tipo = ANY (x.tipos))
       AND (f.de IS NULL OR x.dia >= f.de) AND (f.ate IS NULL OR x.dia <= f.ate)
       AND (f.busca IS NULL OR x.tel4 = f.busca OR x.resumo ILIKE '%' || f.busca || '%' OR x.texto ILIKE '%' || f.busca || '%'
            OR x.pessoa ILIKE '%' || f.busca || '%'))
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM b),
    'por_nay', (SELECT coalesce(jsonb_object_agg(nay, j), '{}'::jsonb) FROM (
                  SELECT nay, jsonb_build_object('certo', count(*) FILTER (WHERE resultado = 'certo'),
                                                 'erro', count(*) FILTER (WHERE resultado = 'erro')) j
                    FROM privado.conversa_biblioteca GROUP BY nay) z),
    'por_tipo', (SELECT coalesce(jsonb_object_agg(t, n), '{}'::jsonb) FROM (
                  SELECT t, count(*) n FROM b, unnest(b.tipos) t GROUP BY t ORDER BY n DESC) z),
    'por_confianca', (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb) FROM (
                  SELECT confianca || ' · ' || resultado AS k, count(*) n FROM b GROUP BY 1) z),
    'linhas', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'nay', nay, 'ref', ref, 'dia', dia, 'tel4', tel4,
                         'pessoa', pessoa, 'resultado', resultado, 'confianca', confianca, 'nota', nota, 'fontes', fontes,
                         'tipos', tipos, 'resumo', resumo, 'tem_texto', texto IS NOT NULL) ORDER BY dia DESC NULLS LAST, id DESC)
                        FROM (SELECT * FROM b ORDER BY dia DESC NULLS LAST, id DESC
                               LIMIT (SELECT lim FROM f) OFFSET (SELECT lim * pag FROM f)) y), '[]'::jsonb))
$function$;
