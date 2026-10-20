CREATE OR REPLACE FUNCTION public.cadastro_whats_condominio(p_texto text, p_bairro text DEFAULT NULL::text)
 RETURNS TABLE(id integer, nome text, bairro text, faixa integer, parecenca numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'privado'
AS $function$
  WITH alvo AS (
    SELECT condominio_nome_nucleo(p_texto) AS n,
           nullif(lower(nay_sem_acento(btrim(coalesce(p_bairro, '')))), '') AS b
  ), c AS (
    SELECT x.id, x.nome, x.bairro, condominio_nome_nucleo(x.nome) AS n,
           lower(nay_sem_acento(coalesce(x.bairro, ''))) AS b
      FROM condominios x
  ), f AS (
    SELECT c.id, c.nome, c.bairro,
           CASE WHEN c.n = a.n THEN 1
                WHEN (' ' || a.n || ' ') LIKE ('% ' || c.n || ' %') AND length(c.n) >= 4 THEN 2
                WHEN (' ' || c.n || ' ') LIKE ('% ' || a.n || ' %') AND length(a.n) >= 5 THEN 2
                WHEN similarity(c.n, a.n) >= 0.55 OR (word_similarity(a.n, c.n) >= 0.75 AND length(a.n) >= 5) THEN 3
                WHEN similarity(c.n, a.n) >= 0.35 OR word_similarity(a.n, c.n) >= 0.6 THEN 4 END AS faixa,
           round(greatest(similarity(c.n, a.n), word_similarity(a.n, c.n))::numeric, 2) AS parecenca,
           (a.b IS NOT NULL AND c.b = a.b) AS mesmo_bairro
      FROM c CROSS JOIN alvo a
     WHERE a.n IS NOT NULL AND c.n IS NOT NULL AND length(a.n) >= 3
  )
  SELECT f.id, f.nome, f.bairro, f.faixa, f.parecenca FROM f
   WHERE f.faixa IS NOT NULL
   ORDER BY f.faixa, f.mesmo_bairro DESC, f.parecenca DESC, f.id
   LIMIT 5
$function$;
