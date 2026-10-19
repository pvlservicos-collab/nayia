-- 417: a regra de dias da rodada (segunda olha sábado e domingo) e a previsão do card
SELECT d::date AS hoje, to_char(d, 'Dy') AS dia,
       CASE WHEN extract(isodow FROM d::date) = 1 THEN ARRAY[d::date - 2, d::date - 1] ELSE ARRAY[d::date - 1] END AS olha
  FROM generate_series('2026-10-17'::date, '2026-10-20'::date, '1 day') d;
SELECT position('ANY (v_dias)' IN pg_get_functiondef('nai_followup_rodar()'::regprocedure)) > 0 AS rodar_olha_os_dias;
-- quem recebeu no sábado 17/10 e não ganhou follow-up: a segunda 20/10 vai pegar
SELECT count(DISTINCT e.chave) AS sabado_sem_followup
  FROM imovel_enviado_no_dia e
 WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = '2026-10-17'
   AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave AND f.dia_recebeu IN ('2026-10-17', '2026-10-18'));
SET ROLE nay_disparo;
SELECT estado, to_char(quando AT TIME ZONE 'America/Manaus', 'Dy DD/MM HH24:MI') AS quando, codigos
  FROM crm_parceria_followup_nay('559291885070');
RESET ROLE;
