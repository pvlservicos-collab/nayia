SELECT crm_olx_cliente_etapa('+55 (92) 90000-0411', 'visita') AS criou, (SELECT etapa||'/'||origem||'/'||telefone FROM privado.olx_lead_whatsapp WHERE telefone='92900000411') AS linha;
SELECT crm_olx_cliente_etapa('5592900000411', 'fechamento') AS atualizou, (SELECT etapa FROM privado.olx_lead_whatsapp WHERE telefone='92900000411') AS etapa, (SELECT count(*) FROM privado.olx_lead_whatsapp WHERE right(telefone,8)='00000411') AS linhas;
SELECT crm_olx_cliente_etapa('123', 'visita') AS curto, crm_olx_cliente_etapa('92900000411', 'xpto') AS etapa_invalida;
SELECT count(*) FILTER (WHERE origem='manual') manuais_na_lista FROM crm_olx_clientes_etapas();
DELETE FROM privado.olx_lead_whatsapp WHERE telefone='92900000411';
