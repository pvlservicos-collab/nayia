-- teste da 522: quem sai do pipeline nos últimos 30 dias, pelo papel do CRM
SET LOCAL ROLE nay_disparo;
\echo '--- por tipo'
SELECT tipo, count(*) FROM crm_leads_pipeline_outros(current_date - 30, current_date) GROUP BY 1 ORDER BY 1;
\echo '--- os que sairiam (os leads), com o motivo'
SELECT tipo, right(telefone, 4) AS fim, coalesce(nome, '-') AS nome, left(coalesce(motivo, ''), 70) AS motivo
  FROM crm_leads_pipeline_outros(current_date - 30, current_date) WHERE tipo <> 'consultado' ORDER BY tipo, fim;
\echo '--- os compradores na etapa "proprietarios" (70 e 35) e o 50 continuam leads'
SELECT p.id, right(p.telefone, 4) AS fim, p.foi_ate,
       EXISTS (SELECT 1 FROM crm_leads_pipeline_outros(current_date - 30, current_date) o
                WHERE o.fone8 = right(regexp_replace(p.telefone, '\D', '', 'g'), 8)) AS saiu
  FROM crm_leads_pipeline(current_date - 30, current_date) p WHERE p.id IN (35, 50, 70, 46, 47, 34) ORDER BY p.id;
RESET ROLE;
