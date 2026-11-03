-- teste da 571: roda dentro do ensaio (a migração já foi aplicada na mesma transação)
SELECT jsonb_array_length(crm_cadastros_incompletos()) AS cadastros_incompletos;
SELECT x->>'cadastro_id' AS cad, x->>'nome' AS nome, x->>'canal' AS canal, x->>'humano' AS humano,
       x->'ja_cadastrado' AS ja_cadastrado, x->'falou_parceria' AS falou_parceria, x->'cadastro_whats_aberto' AS whats_aberto
  FROM jsonb_array_elements(crm_cadastros_incompletos()) x
 WHERE x->'ja_cadastrado' IS NOT NULL AND x->'ja_cadastrado' <> 'null'::jsonb
    OR x->'falou_parceria' IS NOT NULL AND x->'falou_parceria' <> 'null'::jsonb
    OR x->'cadastro_whats_aberto' IS NOT NULL AND x->'cadastro_whats_aberto' <> 'null'::jsonb;
-- o papel do CRM só EXECUTA a função (o ensaio como superusuário não pega permissão negada)
SET LOCAL ROLE nay_disparo;
SELECT jsonb_array_length(crm_cadastros_incompletos()) AS como_nay_disparo;
RESET ROLE;
