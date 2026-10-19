-- 414: um que recebeu follow-up hoje (enviado), um pulado e quem recebeu imóvel hoje (previsto amanhã 09:00)
SET ROLE nay_disparo;
SELECT 'enviado' AS caso, estado, to_char(quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando, left(mensagem, 60) AS msg, motivo, codigos
  FROM crm_parceria_followup_nay('559291885070');
SELECT 'pulado' AS caso, estado, to_char(quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando, motivo, codigos
  FROM crm_parceria_followup_nay('559299071484');
RESET ROLE;
SELECT e.chave AS recebeu_hoje FROM imovel_enviado_no_dia e
 WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
 ORDER BY e.primeiro_em DESC LIMIT 1 \gset
SET ROLE nay_disparo;
SELECT 'previsto' AS caso, estado, to_char(quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando, left(mensagem, 50) AS msg, codigos
  FROM crm_parceria_followup_nay(:'recebeu_hoje') WHERE estado = 'previsto';
SELECT count(*) AS sem_ninguem FROM crm_parceria_followup_nay('5599000000000');
RESET ROLE;
