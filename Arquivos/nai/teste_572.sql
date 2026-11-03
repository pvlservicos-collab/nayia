-- 572: o lead autenticado do ZAP vira cliente da Nay do 8595 (origem zap); o sem chave, não; repetido não duplica
DO $$
DECLARE
  k text := 'chave-de-ensaio-572';
  p jsonb := '{"leadOrigin": "VivaReal", "timestamp": "2026-11-03T10:00:00Z", "originLeadId": "ENSAIO-572",
              "originListingId": "2700000000", "clientListingId": "2944", "name": "Cliente Ensaio",
              "email": "ensaio@email.com", "ddd": "92", "phone": "981230572", "message": "Tenho interesse",
              "temperature": "Alta", "transactionType": "SELL"}';
  r jsonb; l record;
BEGIN
  UPDATE privado.zap_config SET valor = k WHERE chave = 'lead_segredo';
  r := zap_lead_receber(p, k);
  SELECT * INTO l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '81230572';
  IF l.id IS NULL OR l.origem <> 'zap' OR l.codigo <> 2944 OR l.negocio <> 'venda' OR l.telefone <> '92981230572' THEN
    RAISE EXCEPTION 'não virou cliente da Nay: % %', r, row_to_json(l);
  END IF;
  r := zap_lead_receber(p, k);
  IF r->>'status' <> 'repetido' OR (SELECT count(*) FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '81230572') <> 1 THEN
    RAISE EXCEPTION 'repetido duplicou: %', r;
  END IF;
  r := zap_lead_receber(jsonb_set(jsonb_set(p, '{originLeadId}', '"ENSAIO-572b"'), '{phone}', '"981230573"'), 'errada');
  IF r->>'status' <> 'negado' OR EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '81230573') THEN
    RAISE EXCEPTION 'chave errada passou: %', r;
  END IF;
  -- sem a chave gravada (antes da homologação): o lead sem chave entra, menos o de teste deles
  UPDATE privado.zap_config SET valor = NULL WHERE chave = 'lead_segredo';
  r := zap_lead_receber(jsonb_set(jsonb_set(p, '{originLeadId}', '"ENSAIO-572c"'), '{phone}', '"981230574"'), NULL);
  IF NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '81230574' AND origem = 'zap') THEN
    RAISE EXCEPTION 'sem chave gravada, o lead real não entrou: %', r;
  END IF;
  r := zap_lead_receber('{"originLeadId": "ENSAIO-572d", "clientListingId": "2944", "name": "Nome Consumidor", "ddd": "11",
                          "phone": "999999999", "transactionType": "SELL"}', NULL);
  IF EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE telefone = '11999999999') THEN
    RAISE EXCEPTION 'o lead de teste deles chamou alguém';
  END IF;
  RAISE NOTICE '572 ok: lead % etapa %', l.id, l.etapa;
END $$;
