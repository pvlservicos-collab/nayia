-- Testes da 343 (rodam dentro do ensaio, antes do ROLLBACK). Nada é enviado: o ensaio desfaz a entrada dos leads.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

INSERT INTO _t SELECT 'entraram os seis da lista 23', '2262, 2647, 4443, 4770, 5439, 5607',
  (SELECT string_agg(codigo, ', ' ORDER BY codigo) FROM captacao_leads WHERE lista_id = 23);
INSERT INTO _t SELECT 'todos novos, sem envio, sem resposta, sem gente', '6',
  (SELECT count(*)::text FROM captacao_leads WHERE lista_id = 23 AND status = 'novo' AND etapa = 'novo' AND tentativas = 0
      AND ultimo_envio_em IS NULL AND respondeu_em IS NULL AND humano_assumiu_em IS NULL AND NOT opt_out);
INSERT INTO _t SELECT 'a fila do disparo é exatamente esses seis', '6/6',
  (SELECT count(*)::text || '/' || count(*) FILTER (WHERE l.lista_id = 23)::text
     FROM captacao_py_fila_do_disparo() f(id) JOIN captacao_leads l ON l.id = f.id);
INSERT INTO _t SELECT 'nenhum deles já recebeu mensagem da captação', '0',
  (SELECT count(*)::text FROM captacao_leads l WHERE l.lista_id = 23
      AND EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada'));
INSERT INTO _t SELECT 'nenhum está na lista de não disparar nem é de fora da campanha', '0',
  (SELECT count(*)::text FROM captacao_leads l WHERE l.lista_id = 23
      AND (EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
           OR captacao_fora_da_campanha(l.id) IS NOT NULL));
INSERT INTO _t SELECT 'todos têm nome para o "Olá, {{1}}!" e telefone no formato da Meta', '6',
  (SELECT count(*)::text FROM captacao_leads l WHERE l.lista_id = 23 AND coalesce(btrim(l.nome), '') <> ''
      AND l.telefone ~ '^55[0-9]{10,11}$' AND l.imovel_desc IS NOT NULL);
INSERT INTO _t SELECT 'um lead por telefone e por dono', '6/6',
  (SELECT count(DISTINCT telefone_chave)::text || '/' || count(DISTINCT proprietario_id)::text FROM captacao_leads WHERE lista_id = 23);
INSERT INTO _t SELECT 'quem já estava na campanha não foi tocado', '343',
  (SELECT count(*)::text FROM captacao_nao_disparar);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

-- como cada um vai ser chamado (o {{1}} do modelo) e de qual imóvel a conversa trata; telefone só com os 4 finais
SELECT l.codigo, l.imovel_desc AS imovel, l.tipo_imovel AS tipo, right(l.telefone, 4) AS fim,
       concat_ws(' ', l.tratamento, split_part(regexp_replace(btrim(l.nome), '^(sr|sra|dr|dra|dona|exmo|exma)\.?\s+', '', 'i'), ' ', 1)) AS "Olá, ...",
       jsonb_array_length(l.imoveis_prop) AS imoveis_do_dono,
       (SELECT c.vencimento FROM contratos_locacao c WHERE c.codigo = l.codigo ORDER BY c.vencimento DESC NULLS LAST LIMIT 1) AS vence
  FROM captacao_leads l WHERE l.lista_id = 23 ORDER BY 7, 1;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '343: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '343: % testes, todos certos', m;
END $$;
