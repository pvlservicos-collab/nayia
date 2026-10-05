CREATE OR REPLACE FUNCTION public.crm_imoveis_enviados(p_telefone text)
 RETURNS TABLE(codigo integer, imovel text, ultimo_em timestamp with time zone, primeiro_em timestamp with time zone, dias integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH p AS MATERIALIZED (SELECT * FROM crm_pessoas(ARRAY[p_telefone])),
  saiu AS (
    SELECT nullif(regexp_replace(coalesce(e.codigo, ''), '\D', '', 'g'), '')::int AS codigo, e.enviado_em AS em
      FROM envios e, p
     WHERE e.destino IS DISTINCT FROM 'grupo' AND nai_chave(e.telefone) = ANY (p.chaves)
    UNION ALL
    SELECT d.codigo, d.primeiro_em FROM imovel_enviado_no_dia d, p WHERE d.chave = ANY (p.chaves)
    UNION ALL
    SELECT s.codigo, coalesce(s.enviado_em, s.criado_em)
      FROM core_saida s, p
     WHERE s.chave_destino = ANY (p.chaves) AND s.codigo IS NOT NULL AND s.motivo IN ('card', 'foto')
       AND s.papel_destino = 'turno' AND s.estado = 'enviado'
  )
  SELECT x.codigo, nai_ref_imovel(x.codigo), max(x.em), min(x.em),
         count(DISTINCT (x.em AT TIME ZONE 'America/Manaus')::date)::int
    FROM saiu x
   WHERE x.codigo IS NOT NULL AND x.em IS NOT NULL
   GROUP BY x.codigo
   ORDER BY max(x.em) DESC
   LIMIT 80
$function$;
