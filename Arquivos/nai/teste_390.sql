SELECT * FROM olx_organicos_novos(600);
UPDATE privado.olx_config SET valor = (now() - interval '10 hours')::text WHERE chave = 'organico_desde';
SELECT * FROM olx_organicos_novos(600) LIMIT 20;
SELECT id, telefone, origem, etapa, ultima_lida FROM privado.olx_lead_whatsapp WHERE origem = 'organico';
SELECT telefone, etapa, origem FROM crm_olx_clientes_etapas() WHERE origem = 'organico';
