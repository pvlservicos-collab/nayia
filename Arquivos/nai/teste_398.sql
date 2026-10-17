-- 398: parar e voltar a Nay do WhatsApp pelo botão do CRM (o lead 3, Claudia, só no ensaio)
SELECT * FROM crm_captacao_etapa_manual('5592991761866', 'com_o_tel', 'ensaio');
SELECT id, humano_em IS NOT NULL AS parada, parada_motivo FROM privado.olx_lead_whatsapp WHERE id = 3;
SELECT * FROM crm_captacao_etapa_manual('5592991761866', 'todos', 'ensaio');
SELECT id, humano_em IS NULL AS solta, assumido_em > now() - interval '1 minute' AS reassumida,
       ultima_lida = (SELECT max(id) FROM captacao_mensagens WHERE direcao = 'recebida'
                       AND right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) = '91761866') AS pulou_o_atraso
  FROM privado.olx_lead_whatsapp WHERE id = 3;
-- quem é da campanha continua como antes
SELECT * FROM crm_captacao_etapa_manual('5592000000000', 'com_o_tel', 'ensaio');
