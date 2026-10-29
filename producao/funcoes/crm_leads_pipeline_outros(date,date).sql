CREATE OR REPLACE FUNCTION public.crm_leads_pipeline_outros(p_de date, p_ate date)
 RETURNS TABLE(fone8 text, telefone text, nome text, tipo text, motivo text, em timestamp with time zone, cliente8 text, codigos integer[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH l AS (
    SELECT x.*, right(regexp_replace(x.telefone, '\D', '', 'g'), 8) AS f8
      FROM privado.olx_lead_whatsapp x
     WHERE x.criado_em >= p_de::timestamp AT TIME ZONE 'America/Manaus'
       AND x.criado_em < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
  ), classe AS (
    SELECT l.f8, l.telefone, l.nome, l.parada_motivo, greatest(l.atualizado_em, l.criado_em) AS em,
           CASE
             WHEN EXISTS (SELECT 1 FROM corretores c WHERE right(regexp_replace(c.telefone, '\D', '', 'g'), 8) = l.f8)
               OR EXISTS (SELECT 1 FROM privado.busca_corretor b WHERE b.telefone8 = l.f8)
               OR l.parada_motivo ~* '(corretor|corretora|creci|imobili[aá]ria|parceria)' THEN 'corretor'
             WHEN l.parada_motivo ~* '(pr[oó]prio im[oó]vel|tem um im[oó]vel|quer vender (o|a|seu|sua|um|uma)|propriet[aá]ri[oa] (de|do|da|quer))'
               THEN 'proprietario'
             WHEN l.parada_motivo ~* '(construtora|tecnisa|plataforma|solu[cç][aã]o para|contato comercial|v[ií]deos? com ia|divulgar melhor|apresenta[cç][aã]o de|plano suspenso|fornecedor)'
               THEN 'outro'
           END AS tipo
      FROM l
  )
  SELECT c.f8, c.telefone, c.nome, c.tipo, c.parada_motivo, c.em, NULL::text, NULL::int[]
    FROM classe c WHERE c.tipo IS NOT NULL
  UNION ALL
  SELECT r.contato, r.contato, NULL::text, 'consultado', r.motivos, r.em, r.cliente, r.codigos
    FROM crm_contatos_relacionados() r
   WHERE r.em >= p_de::timestamp AT TIME ZONE 'America/Manaus'
     AND r.em < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
     AND NOT EXISTS (SELECT 1 FROM classe c WHERE c.f8 = r.contato AND c.tipo IS NOT NULL)
$function$;
