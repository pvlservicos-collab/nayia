CREATE OR REPLACE FUNCTION public.captacao_honorarios_frase(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.tratamento, nay_primeiro_nome(c.nome) AS n
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), d AS (
    SELECT l.tratamento,
           CASE WHEN l.n = upper(l.n) OR l.n = lower(l.n) THEN initcap(l.n) ELSE l.n END AS nome,
           captacao_honorarios_valor(p_telefone) AS valor
      FROM l
  )
  SELECT CASE WHEN d.tratamento IN ('Sr.', 'Sra.') THEN d.tratamento || coalesce(' ' || d.nome, '') || ', só'
              WHEN d.nome IS NOT NULL THEN d.nome || ', só'
              ELSE 'Só' END
         || ' para eu anotar certinho: no valor de ' || d.valor
         || ' já estão inclusos os 6% de honorários de corretagem, ou '
         || CASE d.tratamento WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END
         || ' quer esse valor líquido?'
    FROM d
   WHERE d.valor IS NOT NULL;
$function$;
