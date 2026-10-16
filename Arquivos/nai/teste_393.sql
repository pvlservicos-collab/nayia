-- 393: o mesmo telefone em outro anúncio vira o mesmo lead; a Josy volta para Visita
SELECT id, etapa FROM privado.olx_lead_whatsapp WHERE id = 6;
-- a Ellen (lead 5, chat 17) pergunta noutro anúncio (o chat 13, da Claudia, só para o ensaio): o mesmo lead, reaberto
SELECT olx_nay_lead_whatsapp(13, 'Ellen martinez da silva', '5592995234069', false, '{"teste": "393"}'::jsonb) AS lead;
SELECT id, chat, codigo, etapa, assumido_em IS NULL AS reabre, perfil ? 'teste' AS somou FROM privado.olx_lead_whatsapp WHERE id = 5;
SELECT count(*) AS linhas_do_telefone FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '95234069';
-- o mesmo anúncio de novo (o mesmo chat): nada reabre
SELECT olx_nay_lead_whatsapp(13, NULL, '92995234069', true, '{}'::jsonb) AS lead;
SELECT id, etapa, quer_visita FROM privado.olx_lead_whatsapp WHERE id = 5;
-- telefone novo: lead novo como antes
SELECT olx_nay_lead_whatsapp(26, 'Teste 393', '92900000393', false, '{}'::jsonb) IS NOT NULL AS novo;
SELECT chave, valor FROM privado.olx_config WHERE chave LIKE 'visita_%' ORDER BY 1;
