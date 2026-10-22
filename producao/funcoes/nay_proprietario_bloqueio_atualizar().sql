CREATE OR REPLACE FUNCTION public.nay_proprietario_bloqueio_atualizar()
 RETURNS integer
 LANGUAGE sql
AS $function$
  WITH f AS (
    SELECT nai_chave(p.telefone) AS chave, btrim(p.nome) AS nome, 'cadastro' AS fonte FROM proprietarios p
     WHERE coalesce(btrim(p.telefone), '') <> ''
    UNION ALL SELECT nai_chave(a.telefone), btrim(a.nome), 'admin antigo' FROM proprietarios_admin a
     WHERE coalesce(btrim(a.telefone), '') <> ''
    UNION ALL SELECT l.telefone_chave, btrim(l.nome), 'captacao' FROM captacao_leads l WHERE l.telefone_chave IS NOT NULL
    UNION ALL SELECT c.chave, btrim(v.proprietario_nome), 'visita' FROM nai_visita v JOIN nai_contato c ON c.id = v.proprietario_id),
  corr AS (SELECT DISTINCT nai_chave(telefone) AS chave FROM corretores WHERE coalesce(btrim(telefone), '') <> ''),
  d AS (SELECT chave,
               -- o nome que é nome: o do cadastro primeiro
               (array_agg(nome ORDER BY CASE fonte WHEN 'cadastro' THEN 1 WHEN 'visita' THEN 2 WHEN 'admin antigo' THEN 3 ELSE 4 END)
                  FILTER (WHERE nome ~ '[[:alpha:]]{3}'))[1] AS nome,
               array_agg(DISTINCT fonte) AS fontes
          FROM f WHERE chave IS NOT NULL AND length(chave) >= 10 AND chave NOT IN (SELECT chave FROM corr) GROUP BY chave),
  u AS (INSERT INTO nay_proprietario_bloqueio AS b (chave, nome, fontes) SELECT chave, nome, fontes FROM d
        ON CONFLICT (chave) DO UPDATE SET nome = coalesce(b.nome, excluded.nome),
                                          fontes = (SELECT array_agg(DISTINCT x) FROM unnest(b.fontes || excluded.fontes) x),
                                          atualizado_em = now()
        RETURNING 1)
  SELECT count(*)::integer FROM u
$function$;
