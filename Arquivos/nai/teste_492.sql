-- um dono que já escreveu na Parceria e um que não
WITH d AS (SELECT DISTINCT ON (b.chave) b.chave FROM nay_proprietario_bloqueio b
            WHERE EXISTS (SELECT 1 FROM mensagens m WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = b.chave) LIMIT 1)
SELECT 'com conversa na Parceria' AS caso, nay_leads_linha_do_dono(chave) FROM d;
SELECT 'numero novo' AS caso, nay_leads_linha_do_dono('92987123456');
SELECT 'oficial nao conta' AS caso, nay_leads_linha_do_dono('');
-- mandar pela Parceria: fila do núcleo + marca do CRM (tudo desfeito no ROLLBACK do ensaio)
WITH d AS (SELECT c.chave FROM nai_contato c
            WHERE EXISTS (SELECT 1 FROM mensagens m WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = c.chave) LIMIT 1)
SELECT nay_leads_mandar_pela_parceria(chave, 'teste 492', 'Fulano', 'dúvida: aceita pet?', 1) IS NOT NULL AS saiu FROM d;
SELECT estado, papel_destino, motivo, bloqueio FROM core_saida WHERE texto = 'teste 492';
SELECT count(*) AS marcas FROM crm_nay_leads_com_dono();
SET ROLE nay_disparo;
SELECT count(*) AS como_o_crm FROM crm_nay_leads_com_dono();
RESET ROLE;
SELECT nay_leads_mandar_pela_parceria('92987123456', 'x', NULL, NULL, NULL) IS NULL AS sem_contato_nao_manda;
