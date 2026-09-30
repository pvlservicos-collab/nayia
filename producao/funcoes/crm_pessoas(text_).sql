CREATE OR REPLACE FUNCTION public.crm_pessoas(p_telefones text[])
 RETURNS TABLE(telefone text, contato_id bigint, ids bigint[], chaves text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH entrada AS (
    SELECT DISTINCT t AS telefone FROM unnest(coalesce(p_telefones, ARRAY[]::text[])) AS t
     WHERE coalesce(t, '') <> '' LIMIT 3000
  ),
  lid_map AS MATERIALIZED (
    SELECT 'lid:' || regexp_replace(i.lid, '\D', '', 'g') AS lid_chave, nai_chave(i.telefone) AS fone_chave
      FROM identidade_lid i WHERE coalesce(i.telefone, '') <> ''
  ),
  cand AS (
    SELECT e.telefone, x.chave
      FROM entrada e
      CROSS JOIN LATERAL (SELECT regexp_replace(e.telefone, '\D', '', 'g') AS dig) d
      CROSS JOIN LATERAL unnest(ARRAY[
        CASE WHEN d.dig ~ '^55[0-9]{10,11}$' OR length(d.dig) IN (10, 11) THEN nai_chave(d.dig) END,
        CASE WHEN d.dig !~ '^55[0-9]{10,11}$' AND length(d.dig) BETWEEN 12 AND 20 THEN 'lid:' || d.dig END
      ]) AS x(chave)
     WHERE x.chave IS NOT NULL
  ),
  chaves AS MATERIALIZED (      -- o telefone e o @lid da mesma pessoa
    SELECT c.telefone, c.chave FROM cand c
    UNION SELECT c.telefone, m.fone_chave FROM cand c JOIN lid_map m ON m.lid_chave = c.chave
    UNION SELECT c.telefone, m.lid_chave  FROM cand c JOIN lid_map m ON m.fone_chave = c.chave
  ),
  contatos AS MATERIALIZED (
    SELECT ch.telefone, nc.id FROM chaves ch JOIN nai_contato nc ON nc.chave = ch.chave
  )
  SELECT e.telefone,
         (SELECT min(c.id) FROM contatos c WHERE c.telefone = e.telefone),
         ARRAY(SELECT DISTINCT c.id FROM contatos c WHERE c.telefone = e.telefone),
         ARRAY(SELECT ch.chave FROM chaves ch WHERE ch.telefone = e.telefone ORDER BY ch.chave)
    FROM entrada e
$function$;
