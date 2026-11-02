-- teste da 558 (dentro do ensaio)
DO $t$
DECLARE v_b bigint; v_tel text; v_antes int;
BEGIN
  ASSERT jsonb_array_length(crm_grupos_da_busca()) >= 1, 'grupos';
  SELECT w.telefone, c.id, jsonb_array_length(coalesce(c.grupos, '[]'::jsonb)) INTO v_tel, v_b, v_antes
    FROM privado.busca_cliente c JOIN privado.olx_lead_whatsapp w ON w.id = c.lead ORDER BY c.id DESC LIMIT 1;
  ASSERT crm_lead_pedido_nos_grupos(v_tel, 'Preciso de apto 2q no Parque 10 até 3 mil', '[{"grupo":"x-group","nome":"Grupo X","mid":"M1"}]', 'teste') = v_b, 'busca';
  ASSERT (SELECT jsonb_array_length(grupos) FROM privado.busca_cliente WHERE id = v_b) = v_antes + 1, 'item';
  ASSERT (SELECT (grupos -> -1 ->> 'manual')::boolean FROM privado.busca_cliente WHERE id = v_b), 'manual';
  ASSERT EXISTS (SELECT 1 FROM privado.busca_cliente_passo WHERE busca = v_b AND texto LIKE 'Pedido à mão no CRM (teste)%'), 'passo';
  ASSERT crm_lead_pedido_nos_grupos('000', 'x', '[{"grupo":"x-group"}]', 'teste') IS NULL, 'sem lead';
  ASSERT crm_lead_pedido_nos_grupos(v_tel, 'x', '[]', 'teste') IS NULL, 'sem envio';
  RAISE NOTICE 'teste_558: ok';
END
$t$;
