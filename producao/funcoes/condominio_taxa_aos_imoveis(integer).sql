CREATE OR REPLACE FUNCTION public.condominio_taxa_aos_imoveis(p_ficha integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int := 0;
BEGIN
  WITH cf AS (
    SELECT f.id, f.condominio_id, f.taxas,
           array_remove(ARRAY[lower(btrim(f.nome)), lower(btrim(c.nome))]
                        || coalesce((SELECT array_agg(lower(btrim(x))) FROM unnest(f.nomes_no_imovel) x), '{}'), NULL) AS nomes
      FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id
     WHERE f.id = p_ficha
  ), linha AS (   -- uma linha por número de quartos (a primeira, se repetir)
    SELECT DISTINCT ON ((t->>'quartos')::int) (t->>'quartos')::int AS quartos,
           (t->>'condominio')::numeric AS condominio, (t->>'iptu')::numeric AS iptu,
           t ? 'fonte' AS deduzida   -- a linha que uma migração tirou dos próprios imóveis, não digitada
      FROM cf, jsonb_array_elements(cf.taxas) WITH ORDINALITY x(t, o)
     WHERE t->>'quartos' ~ '^\d+$' AND coalesce(t->>'condominio', t->>'iptu') IS NOT NULL
     ORDER BY (t->>'quartos')::int, o
  ), alvo AS (
    -- a taxa DIGITADA no condomínio manda; a deduzida só preenche quem está sem
    SELECT i.codigo,
           CASE WHEN l.deduzida AND i.taxa_condominio IS NOT NULL THEN i.taxa_condominio
                ELSE coalesce(l.condominio, i.taxa_condominio) END AS taxa,
           CASE WHEN l.deduzida AND i.iptu IS NOT NULL THEN i.iptu ELSE coalesce(l.iptu, i.iptu) END AS iptu
      FROM imoveis i, cf, linha l
     WHERE i.quartos = l.quartos AND coalesce(i.status, '') <> 'Excluído'
       AND (i.condo_id = cf.condominio_id
            OR (i.condo_id IS NULL AND lower(btrim(coalesce(i.condominio_nome, ''))) = ANY (cf.nomes)))
  )
  UPDATE imoveis i SET taxa_condominio = a.taxa, iptu = a.iptu
    FROM alvo a WHERE i.codigo = a.codigo AND (i.taxa_condominio IS DISTINCT FROM a.taxa OR i.iptu IS DISTINCT FROM a.iptu);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $function$;
