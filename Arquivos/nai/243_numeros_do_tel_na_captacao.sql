-- 243 (30/09/2026): os 28 números que o Pedro mandou vão para a aba "Com o Tel" da captação.
-- Pedro: "pega toda essa lista de números e coloca no de captação na tag com o Tel". São os
-- contatos que o Tel marcou à mão no WhatsApp da captação (etiquetas dele: captação,
-- confirmar se está disponível, contactar em breve) e que NÃO estão na campanha: nenhum dos
-- 28 existe em captacao_leads. A etapa manual (242) os traz para a aba sem mexer na fila de
-- disparo -- ninguém vira 'novo' por aqui, então a campanha não dispara para eles.
BEGIN;
SET LOCAL lock_timeout = '3s';
SELECT crm_captacao_etapa_manual('559292737713', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('554784910353', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559292015390', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559291663090', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559295200982', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281209919', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559291804557', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281289286', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281180015', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281570857', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559292679825', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559293090782', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559284560043', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559292841101', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559293559567', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559296080654', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281412713', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281334245', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559291335500', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559282210321', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('554192263069', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559295333754', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559291362256', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559281930194', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559288544670', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559291006311', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559282241099', 'com_o_tel', 'Pedro (lista de 30/09)');
SELECT crm_captacao_etapa_manual('559291634742', 'com_o_tel', 'Pedro (lista de 30/09)');
COMMIT;
SELECT count(*) AS marcados FROM captacao_etapa_manual WHERE etapa = 'com_o_tel';
