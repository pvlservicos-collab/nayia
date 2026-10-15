-- testes da 375 (no ensaio, que termina em ROLLBACK)
SELECT site_lembrete_criar('Ligar para o dono do 3050', (now() AT TIME ZONE 'America/Manaus')::date) AS hoje,
       site_lembrete_criar('Conferir o contrato', (now() AT TIME ZONE 'America/Manaus')::date - 2) AS atrasado,
       site_lembrete_criar('Renovar o plano da OLX', (now() AT TIME ZONE 'America/Manaus')::date + 5) AS futuro,
       site_lembrete_criar('   ', current_date) AS vazio, site_lembrete_criar('x', NULL) AS sem_dia;
SELECT jsonb_array_length(l->'agora') agora, jsonb_array_length(l->'proximos') proximos, l->'agora'->0->>'atrasado' primeiro_atrasado
  FROM site_lembretes() l;
SELECT site_lembrete_feito((SELECT max(id) FROM privado.lembrete_equipe WHERE texto = 'Ligar para o dono do 3050')) AS feito;
SELECT jsonb_array_length(l->'agora') agora_depois, jsonb_array_length(l->'feitos') feitos FROM site_lembretes() l;
SELECT site_lembrete_feito((SELECT max(id) FROM privado.lembrete_equipe WHERE texto = 'Ligar para o dono do 3050'), false) AS desfeito,
       site_lembrete_apagar((SELECT max(id) FROM privado.lembrete_equipe WHERE texto = 'Conferir o contrato')) AS apagado;
SELECT jsonb_array_length(l->'agora') agora_final FROM site_lembretes() l;
SET ROLE nay_site_escrita;
SELECT jsonb_array_length(site_lembretes()->'agora') AS pelo_papel_do_site;
SELECT count(*) FROM privado.lembrete_equipe;  -- tem de falhar: o papel do site não toca a tabela
