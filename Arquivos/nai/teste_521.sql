-- teste da 521: a Susi (7640) e a Karis (busca 52, lead 60), lidas pelo papel do CRM
SELECT telefone AS karis FROM privado.olx_lead_whatsapp WHERE id = 60 \gset
SET LOCAL ROLE nay_disparo;
\echo '--- Susi'
SELECT j->>'estado' AS estado, j->'filtros'->>'teto' AS teto, jsonb_array_length(j->'grupos') AS grupos,
       jsonb_array_length(j->'passos') AS passos, j->'passos'->0->>'texto' AS ultimo_passo
  FROM (SELECT crm_lead_busca_ativa('5592982517640') AS j) x;
\echo '--- Karis (a que repetia nos grupos)'
SELECT j->>'estado' AS estado, jsonb_array_length(j->'grupos') AS pedidos_nos_grupos,
       jsonb_array_length(j->'olx') AS olx, jsonb_array_length(j->'corretores') AS corretores,
       left(j->'passos'->0->>'texto', 90) AS ultimo_passo
  FROM (SELECT crm_lead_busca_ativa(:'karis') AS j) x;
\echo '--- telefone que não é lead: nulo'
SELECT crm_lead_busca_ativa('5592900000000') IS NULL AS vazio;
RESET ROLE;
