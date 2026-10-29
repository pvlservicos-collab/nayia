-- 522: O PIPELINE DOS LEADS SÓ COM OS LEADS (Pedro, 29/10/2026): "lá na pipeline não faz sentido ter todo mundo, corretor
-- ou proprietário; agora que vamos criar os leads relacionados, lá no pipeline fica só os leads; proprietários ou pessoas
-- que ele tirou dúvida fica em uma opção lá em cima desmarcada, só aparece quando clicamos, e em uma pipeline invisível só
-- deles que só aparece quando marco a caixinha".
--
-- crm_leads_pipeline (491) devolve todo mundo que escreveu no 8595. Esta função diz, no mesmo período, quem NÃO é cliente:
--   corretor     está em `corretores`, respondeu uma busca (privado.busca_corretor) ou o motivo da parada diz corretor,
--                CRECI, imobiliária ou parceria (o agente "humano" da Nay Leads escreve isso: "Corretor oferecendo parceria");
--   proprietario o motivo diz que ele é o dono ("Quer vender o próprio imóvel", "Tem um imóvel no Acquarelle"). A ETAPA
--                'proprietarios' NÃO conta: é a fase em que a Nay fala com os donos para a visita do cliente (o 70, que quer
--                comprar o Kopenhagen, está nela);
--   outro        empresa ou fornecedor (construtora, plataforma, "contato comercial", vídeo com IA);
--   consultado   quem a Nay procurou pelo 8595 para tirar a dúvida de um lead (crm_contatos_relacionados, 517).
-- Na dúvida, fica como lead: só sai do pipeline quem a regra reconhece.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_leads_pipeline_outros(p_de date, p_ate date)
 RETURNS TABLE(fone8 text, telefone text, nome text, tipo text, motivo text, em timestamp with time zone, cliente8 text,
               codigos integer[])
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

REVOKE ALL ON FUNCTION public.crm_leads_pipeline_outros(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_leads_pipeline_outros(date, date) TO nay_disparo, nay;

COMMIT;
