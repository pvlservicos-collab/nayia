SELECT count(*) AS quer_vender_dos_12, count(*) FILTER (WHERE status = 'concluido') AS concluidos,
       count(*) FILTER (WHERE status IN ('novo','erro')) AS entrariam_no_disparo
  FROM captacao_leads
 WHERE telefone_chave IN (SELECT nay_fone_chave(t) FROM unnest(ARRAY['5521981691076','559281197777','559281455686','559284151942','559293001033','559296051615','5511972260211','559281150213','559291093142','559292015390','559295333754']) t)
   AND quer_vender;
SELECT count(*) AS na_fila_do_disparo FROM captacao_py_fila_do_disparo() f
 WHERE f IN (SELECT id FROM captacao_leads WHERE telefone_chave IN (SELECT nay_fone_chave(t) FROM unnest(ARRAY['5511972260211','559281150213','559291093142','559292015390','559295333754']) t));
