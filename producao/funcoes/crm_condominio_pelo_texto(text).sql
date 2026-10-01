CREATE OR REPLACE FUNCTION public.crm_condominio_pelo_texto(p_texto text)
 RETURNS TABLE(id integer, nome text, bairro text, forca numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH t AS (SELECT ' ' || nay_sem_acento(lower(coalesce(p_texto, ''))) || ' ' AS s),
  n AS (
    SELECT c.id, c.nome, c.bairro,
           nay_sem_acento(lower(nai_condominio_nucleo(c.nome))) AS nucleo
      FROM condominios c
  )
  SELECT n.id, n.nome, n.bairro, (length(n.nucleo))::numeric AS forca
    FROM n, t
   WHERE length(n.nucleo) >= 4
     AND t.s ~ ('(^|[^a-z0-9])' || regexp_replace(n.nucleo, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '([^a-z0-9]|$)')
   ORDER BY 4 DESC, n.nome
   LIMIT 5
$function$;
