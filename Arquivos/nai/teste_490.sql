-- teste da 490 (dentro da transação do ensaio, antes do ROLLBACK)
INSERT INTO privado.agente_evento (lead_id, chave8, agente, acao, turno, decisao, ms, modo) VALUES
  (NULL, '99999999', 'fluxo', 'chegou', 'tz1', '{"resumo": "2 mensagens novas"}', NULL, 'real'),
  (NULL, '99999999', 'mestre', 'rotear', 'tz1', '{"rotas": ["imoveis"], "resumo": "imoveis"}', 310, 'real'),
  (NULL, '99999999', 'atendimento', 'respondeu', 'tz1', '{"resumo": "Quantos quartos?"}', 4200, 'real'),
  (NULL, '99999999', 'fluxo', 'falou', 'tz1', '{"resumo": "1 balão"}', NULL, 'real');
SELECT jsonb_array_length(crm_agentes_tracos(5, NULL, '5592999999999')->'turnos') AS turnos_do_teste;
SELECT string_agg(p->>'agente' || ':' || (p->>'acao'), ' > ' ORDER BY (p->>'id')::bigint) AS passos
  FROM jsonb_array_elements(crm_agentes_tracos(1, NULL, '5592999999999')->'turnos'->0->'passos') p;
SELECT count(*) AS fluxo_no_card FROM crm_agentes_do_lead('5592999999999') WHERE agente = 'fluxo';
SELECT jsonb_array_length(crm_agentes_tracos(40)->'turnos') AS turnos_30d;
