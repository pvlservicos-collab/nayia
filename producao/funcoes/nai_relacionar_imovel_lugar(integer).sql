CREATE OR REPLACE FUNCTION public.nai_relacionar_imovel_lugar(p_codigo integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  -- 229: sem código = todos (e some quem não existe mais); com código = só ele.
  -- Cada nome é normalizado UMA vez (bz/cj/av); normalizar dentro do laço por
  -- imóvel levava 54 s para os 5.674.
  WITH bz AS MATERIALIZED (
    SELECT DISTINCT ON (nay_normalizar_lugar(z.bairro, true)) nay_normalizar_lugar(z.bairro, true) AS bn, z.zona
      FROM bairro_zona z ORDER BY nay_normalizar_lugar(z.bairro, true), z.zona
  ), cj AS MATERIALIZED (
    SELECT c.nome, c.expressao, nay_normalizar_lugar(c.bairro, true) AS bn FROM nai_lugar_conjunto c WHERE c.ativo
  ), av AS MATERIALIZED (
    SELECT a.nome, a.expressao, ARRAY(SELECT nay_normalizar_lugar(x, true) FROM unnest(a.bairros) x) AS bns
      FROM nai_lugar_avenida a WHERE a.ativo
  ), base AS MATERIALIZED (
    SELECT i.codigo, nullif(btrim(i.bairro), '') AS bairro,
           nay_normalizar_lugar(coalesce(i.bairro, ''), true) AS bn,
           nai_lugar_normal(i.logradouro) AS rua,
           nai_lugar_normal(i.condominio_nome) AS condo
      FROM imoveis i
     WHERE p_codigo IS NULL OR i.codigo = p_codigo
  )
  -- padrão por fora, imóvel por dentro: cada regex é compilada uma vez (o cache do
  -- Postgres guarda só 32, e 79 padrões alternados recompilavam a cada linha)
  , m_cj AS (
    SELECT b.codigo, array_agg(cj.nome ORDER BY cj.nome) AS nomes
      FROM cj CROSS JOIN base b
     WHERE (b.condo <> '' AND b.condo ~ cj.expressao)
        OR (b.rua <> '' AND cj.bn = b.bn AND b.rua ~ cj.expressao)
        OR (b.bn <> '' AND b.bn ~ cj.expressao)   -- 231: o bairro tem o nome do conjunto
     GROUP BY b.codigo
  ), m_av AS (
    SELECT b.codigo, array_agg(av.nome ORDER BY av.nome) AS nomes
      FROM av CROSS JOIN base b
     WHERE b.rua <> '' AND b.rua ~ av.expressao
     GROUP BY b.codigo
  ), cj_b AS (
    SELECT cj.bn, array_agg(cj.nome ORDER BY cj.nome) AS nomes FROM cj GROUP BY cj.bn
  ), av_b AS (
    SELECT x.bn, array_agg(DISTINCT av.nome ORDER BY av.nome) AS nomes FROM av, unnest(av.bns) x(bn) GROUP BY x.bn
  )
  INSERT INTO imovel_lugar AS l (codigo, bairro, zona, conjuntos, conjuntos_do_bairro, avenidas, avenidas_do_bairro, atualizado_em)
  SELECT b.codigo, b.bairro, bz.zona,
         coalesce(m_cj.nomes, '{}'), coalesce(cj_b.nomes, '{}'),
         coalesce(m_av.nomes, '{}'), coalesce(av_b.nomes, '{}'),
         now()
    FROM base b
    LEFT JOIN bz   ON b.bn <> '' AND bz.bn = b.bn
    LEFT JOIN m_cj ON m_cj.codigo = b.codigo
    LEFT JOIN m_av ON m_av.codigo = b.codigo
    LEFT JOIN cj_b ON b.bn <> '' AND cj_b.bn = b.bn
    LEFT JOIN av_b ON b.bn <> '' AND av_b.bn = b.bn
  ON CONFLICT (codigo) DO UPDATE
     SET bairro = EXCLUDED.bairro, zona = EXCLUDED.zona, conjuntos = EXCLUDED.conjuntos,
         conjuntos_do_bairro = EXCLUDED.conjuntos_do_bairro, avenidas = EXCLUDED.avenidas,
         avenidas_do_bairro = EXCLUDED.avenidas_do_bairro, atualizado_em = now();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF p_codigo IS NULL THEN
    DELETE FROM imovel_lugar l WHERE NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = l.codigo);
  END IF;
  RETURN n;
END;
$function$;
