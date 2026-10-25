-- teste da 489 (dentro da transação do ensaio, antes do ROLLBACK)
SELECT 'agentes: ' || jsonb_array_length(crm_agentes()->'agentes') || ' modo ' || (crm_agentes()->>'modo') AS legenda;
INSERT INTO privado.agente_evento (lead_id, chave8, agente, acao, turno, decisao, confianca, ms, modo)
VALUES (1, '99999999', 'mestre', 'rotear', 't1', '{"rotas": ["imoveis", "duvida"], "resumo": "imoveis, duvida"}', 0.81, 310, 'real');
SELECT count(*) AS eventos_teste FROM crm_agentes_do_lead('5592999999999');
SELECT jsonb_pretty(crm_agentes_painel(48)->'caminhos') AS caminhos;
SELECT a->>'chave' AS agente, a->>'ativacoes' AS ativacoes_48h, a->>'conversas' AS conversas
  FROM jsonb_array_elements(crm_agentes_painel(48)->'agentes') a;
SELECT count(*) AS linha_do_tempo_7d FROM privado.agente_linha_do_tempo(now() - interval '7 days');
